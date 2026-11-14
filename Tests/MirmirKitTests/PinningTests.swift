import Foundation
import GRPCCore
import GRPCNIOTransportHTTP2
import Testing
@testable import MirmirKit

/// A real TLS handshake on loopback against the certificate pin: the pinned
/// certificate is accepted, any other is refused as changed, and a
/// self-signed certificate without a pin fails the system trust check.
@Suite("Certificate pinning over TLS")
struct PinningTests {
    /// Self-signed P-256, CN "mirmir loopback test", SAN 127.0.0.1 and
    /// localhost, valid until 2126. Test material only: never trusted
    /// anywhere else.
    static let certificate = """
-----BEGIN CERTIFICATE-----
MIIBkDCCATagAwIBAgIUemzLzwX3D3XUTX7BZ3ZitfEiHfIwCgYIKoZIzj0EAwIw
HzEdMBsGA1UEAwwUbWlybWlyIGxvb3BiYWNrIHRlc3QwIBcNMjYxMTE0MTMxNDIy
WhgPMjEyNjEwMjExMzE0MjJaMB8xHTAbBgNVBAMMFG1pcm1pciBsb29wYmFjayB0
ZXN0MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEAHXjIg86a4rCGkc4LQG1kQQ7
nKQCtTh58WtdlW35zPkXzIyJHkzMlx7qWRqCRnW2LSQTQ23JHQp7kYRTV5XWLKNO
MEwwHQYDVR0OBBYEFHtQBobIm1sISFhyP8Pyl2eM8J2pMA8GA1UdEwEB/wQFMAMB
Af8wGgYDVR0RBBMwEYcEfwAAAYIJbG9jYWxob3N0MAoGCCqGSM49BAMCA0gAMEUC
IQCr4OeUPNjtalVW7gHRIaR8XaqFZYkrDi6eiQx2jMflbQIgXd+cCUggGm8TSyfJ
8SM9UhwFmHsBUhDdEmWga7yelrM=
-----END CERTIFICATE-----
"""
    static let privateKey = """
-----BEGIN PRIVATE KEY-----
MIGHAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBG0wawIBAQQgDQt7+PovfxCVHh5v
1wQGM7D3afU5OAbJ+xsQ36XS/bGhRANCAAQAdeMiDzprisIaRzgtAbWRBDucpAK1
OHnxa12VbfnM+RfMjIkeTMyXHupZGoJGdbYtJBNDbckdCnuRhFNXldYs
-----END PRIVATE KEY-----
"""
    /// What `openssl x509 -noout -fingerprint -sha256` prints for it.
    static let opensslFingerprint = "22:F1:B9:09:74:BA:AE:8B:08:67:B6:DD:75:5B:79:ED:B4:61:DA:62:35:27:89:63:C7:8F:47:ED:22:30:BB:53"

    /// Short deadlines, so a refused handshake fails the test quickly.
    static let deadlines = CallDeadlines(health: .seconds(3))

    /// The certificate's DER bytes, read from its PEM independently of the
    /// TLS stack.
    static var certificateDER: [UInt8] {
        get throws {
            let body = certificate.split(separator: "\n").filter { !$0.hasPrefix("-----") }.joined()
            return Array(try #require(Data(base64Encoded: body)))
        }
    }

    @Test func thePresentedFingerprintIsTheCertificatesSHA256() async throws {
        let server = try await TLSServer()
        defer { server.stop() }
        let expected = CertificateFingerprint(der: try Self.certificateDER)
        #expect(expected.hex == Self.opensslFingerprint)
        #expect(try await RuntimeConnection.presentedFingerprint(of: server.endpoint(pinned: nil)) == expected)
    }

    @Test func thePinnedCertificateIsAccepted() async throws {
        let server = try await TLSServer()
        defer { server.stop() }
        let pin = CertificateFingerprint(der: try Self.certificateDER)
        let connection = try await RuntimeConnection.connect(
            remote: server.endpoint(pinned: pin), key: "mmk_test", deadlines: Self.deadlines
        )
        defer { connection.close() }
        #expect(connection.health.serverVersion == "0.6.0-stand-in")
        #expect(try await connection.ping().protocolVersion == clientProtocolVersion)
    }

    @Test func anotherCertificateThanThePinnedOneIsRefused() async throws {
        let server = try await TLSServer()
        defer { server.stop() }
        let presented = CertificateFingerprint(der: try Self.certificateDER)
        let wrong = CertificateFingerprint(der: [1, 2, 3])
        let endpoint = server.endpoint(pinned: wrong)
        await #expect(throws: ConnectionError.certificateChanged(address: endpoint.address, pinned: wrong, presented: presented)) {
            _ = try await RuntimeConnection.connect(remote: endpoint, key: "mmk_test", deadlines: Self.deadlines)
        }
    }

    @Test func aSelfSignedCertificateWithoutAPinIsRefused() async throws {
        let server = try await TLSServer()
        defer { server.stop() }
        let endpoint = server.endpoint(pinned: nil)
        do {
            let connection = try await RuntimeConnection.connect(remote: endpoint, key: "mmk_test", deadlines: Self.deadlines)
            connection.close()
            Issue.record("an unpinned self-signed certificate was trusted")
        } catch {
            guard case .unreachable(let address, let detail) = error else {
                Issue.record("unexpected error \(error)")
                return
            }
            #expect(address == endpoint.address)
            #expect(detail.contains("trust its fingerprint"))
        }
    }
}

/// `StandInRuntime` on a TLS listener at 127.0.0.1 with the test
/// certificate, on a free port.
final class TLSServer: Sendable {
    let port: Int
    private let serving: Task<Void, any Error>

    init() async throws {
        let transport = HTTP2ServerTransport.Posix(
            address: .ipv4(host: "127.0.0.1", port: 0),
            transportSecurity: .tls(
                certificateChain: [.bytes(Array(PinningTests.certificate.utf8), format: .pem)],
                privateKey: .bytes(Array(PinningTests.privateKey.utf8), format: .pem)
            )
        )
        let server = GRPCServer(transport: transport, services: [StandInRuntime(record: RuntimeRecord(), holds: false)])
        serving = Task { try await server.serve() }
        port = try #require(try await transport.listeningAddress.ipv4?.port)
    }

    func endpoint(pinned: CertificateFingerprint?) -> RemoteEndpoint {
        RemoteEndpoint(host: "127.0.0.1", port: port, pinnedFingerprint: pinned)
    }

    func stop() {
        serving.cancel()
    }
}
