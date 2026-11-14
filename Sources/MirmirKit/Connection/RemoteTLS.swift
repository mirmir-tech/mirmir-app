import Crypto
import Foundation
import GRPCNIOTransportHTTP2
import NIOCore
import NIOPosix
import NIOSSL
import Synchronization

/// SHA-256 of a certificate's DER form, shown and compared exactly as mirmir
/// prints it: colon-separated uppercase hex.
public struct CertificateFingerprint: Hashable, Sendable, Codable, CustomStringConvertible {
    public let hex: String

    public init(der: [UInt8]) {
        hex = SHA256.hash(data: der).map { String(format: "%02X", $0) }.joined(separator: ":")
    }

    /// Accepts the displayed form, plain hex, any case and an optional
    /// `SHA256:` prefix.
    public init?(_ text: String) {
        var body = text.trimmingCharacters(in: .whitespaces)
        if body.uppercased().hasPrefix("SHA256:") { body.removeFirst(7) }
        let digits = body.filter { $0.isHexDigit }.uppercased()
        guard digits.count == 64, body.allSatisfy({ $0.isHexDigit || ":- ".contains($0) }) else { return nil }
        var pairs: [String] = []
        var index = digits.startIndex
        while index < digits.endIndex {
            let next = digits.index(index, offsetBy: 2)
            pairs.append(String(digits[index..<next]))
            index = next
        }
        hex = pairs.joined(separator: ":")
    }

    public var description: String { hex }
}

/// The certificate a server presented during the last handshake, recorded by
/// the pinning callback so a mismatch can be reported with both values.
final class PresentedCertificate: Sendable {
    private let value = Mutex<CertificateFingerprint?>(nil)

    var fingerprint: CertificateFingerprint? { value.withLock { $0 } }

    func record(_ chain: [NIOSSLCertificate]) -> CertificateFingerprint? {
        let fingerprint = chain.first.flatMap { try? $0.toDERBytes() }.map(CertificateFingerprint.init(der:))
        value.withLock { $0 = fingerprint }
        return fingerprint
    }
}

enum RemoteTLS {
    /// TLS that accepts exactly the pinned certificate. BoringSSL still
    /// verifies the handshake signature, so the server must hold its key.
    static func pinned(
        _ pinned: CertificateFingerprint, presented: PresentedCertificate
    ) -> HTTP2ClientTransport.Posix.TransportSecurity {
        var tls = HTTP2ClientTransport.Posix.TransportSecurity.TLS.defaults
        tls.serverCertificateVerification = .noHostnameVerification
        tls.customVerificationCallback = { chain, promise in
            let matches = presented.record(chain) == pinned
            promise.succeed(matches ? .certificateVerified(VerificationMetadata(nil)) : .failed)
        }
        return .tls(tls)
    }

    /// TLS for a CA-issued certificate, verified against the system roots.
    static var systemTrust: HTTP2ClientTransport.Posix.TransportSecurity { .tls(.defaults) }

    /// The fingerprint a server presents, without trusting it or sending
    /// anything: what Add Server shows before pinning on first use.
    static func presentedFingerprint(host: String, port: Int) async throws -> CertificateFingerprint {
        let presented = PresentedCertificate()
        var configuration = TLSConfiguration.makeClientConfiguration()
        configuration.certificateVerification = .noHostnameVerification
        configuration.applicationProtocols = ["h2"]
        let context = try NIOSSLContext(configuration: configuration)
        let channel = try await ClientBootstrap(group: MultiThreadedEventLoopGroup.singleton)
            .connectTimeout(.seconds(5))
            .channelInitializer { channel in
                channel.eventLoop.makeCompletedFuture {
                    let handler = try NIOSSLClientHandler(
                        context: context,
                        serverHostname: host.isIPAddress ? nil : host,
                        customVerificationCallbackWithMetadata: { chain, promise in
                            _ = presented.record(chain)
                            promise.succeed(.failed)
                        }
                    )
                    try channel.pipeline.syncOperations.addHandler(handler)
                }
            }
            .connect(host: host, port: port).get()
        // The handshake ends right after the certificate; a server that never
        // answers is closed after five seconds.
        channel.eventLoop.scheduleTask(in: .seconds(5)) { channel.close(promise: nil) }
        try? await channel.closeFuture.get()
        guard let fingerprint = presented.fingerprint else {
            throw ConnectionError.unreachable(address: "\(host):\(port)", detail: "no certificate was presented")
        }
        return fingerprint
    }
}

extension String {
    var isIPAddress: Bool {
        var v4 = in_addr()
        var v6 = in6_addr()
        return inet_pton(AF_INET, self, &v4) == 1 || inet_pton(AF_INET6, self, &v6) == 1
    }
}

extension RemoteEndpoint {
    /// IP literals connect without SNI; names resolve through DNS and are sent
    /// as SNI.
    var target: any ResolvableTarget {
        var v4 = in_addr()
        var v6 = in6_addr()
        if inet_pton(AF_INET, host, &v4) == 1 {
            let target: ResolvableTargets.IPv4 = .ipv4(address: host, port: port)
            return target
        }
        if inet_pton(AF_INET6, host, &v6) == 1 {
            let target: ResolvableTargets.IPv6 = .ipv6(address: host, port: port)
            return target
        }
        let target: ResolvableTargets.DNS = .dns(host: host, port: port)
        return target
    }
}
