import Foundation
import NIOCore
import NIOPosix

extension ConnectionError {
    /// A transport error in words. NIO's connection error is otherwise shown
    /// as "NIOConnectionError error 1", hiding which address failed and why;
    /// a host on the local network often has IPv6 addresses the server does
    /// not listen on and an IPv4 one that macOS may block for privacy.
    static func describe(_ error: any Error) -> String {
        switch error {
        case let error as NIOConnectionError:
            var parts = error.connectionErrors.map { "\($0.target): \(describe($0.error))" }
            if parts.isEmpty, let dns = error.dnsAError ?? error.dnsAAAAError {
                parts.append("\(error.host) did not resolve: \(describe(dns))")
            }
            return parts.isEmpty ? "no address answered" : parts.joined(separator: "; ")
        case let error as IOError:
            return describe(errno: error.errnoCode)
        case let error as ChannelError where error == .connectTimeout(.seconds(5)):
            return "timed out"
        default:
            return (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        }
    }

    private static func describe(errno code: Int32) -> String {
        let reason = String(cString: strerror(code))
        // macOS answers "No route to host" when Local Network privacy blocks
        // the app, even though the host is reachable from a terminal.
        guard code == EHOSTUNREACH || code == ENETUNREACH else { return reason }
        return reason + " (if other apps reach it, allow Mirmir in System Settings → Privacy & Security → Local Network)"
    }
}
