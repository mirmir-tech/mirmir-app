import Foundation
import GRPCCore

public enum ConnectionError: Error, Hashable, Sendable, LocalizedError {
    /// No server socket exists at the path.
    case noServer(socket: String)
    /// The server answered with a different `Runtime` protocol.
    case updateNeeded(serverProtocol: String, serverVersion: String)
    /// A remote server could not be reached or its TLS handshake failed.
    case unreachable(address: String, detail: String)
    /// No API key is saved for a remote server.
    case missingKey(address: String)
    /// A remote server presented a certificate other than the pinned one.
    case certificateChanged(address: String, pinned: CertificateFingerprint, presented: CertificateFingerprint)
    /// A remote server refused the API key: unknown, revoked or malformed.
    case keyRejected(address: String)
    /// The key's scope does not allow the call, or the call is local-only.
    case permissionDenied(message: String)
    /// The RPC failed with a gRPC status.
    case rpc(code: RPCError.Code, message: String)
    /// The app cancelled the call itself (instance switch, view gone, Stop).
    /// Never a failure to report.
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .noServer(let socket):
            "No mirmir server is listening at \(socket)."
        case .updateNeeded(let server, let version):
            "Server protocol \(server) (mirmir \(version)) differs from this app's protocol \(clientProtocolVersion). Update mirmir."
        case .unreachable(let address, let detail):
            "Cannot reach \(address): \(detail)."
        case .missingKey(let address):
            "No API key is saved for \(address). Edit the server and enter one."
        case .certificateChanged(let address, let pinned, let presented):
            "\(address) presented certificate \(presented), not the trusted \(pinned). If the server's certificate was replaced, remove and add the server again."
        case .keyRejected(let address):
            "\(address) refused the API key. It may have been revoked; create a new one on the server."
        case .permissionDenied(let message):
            message
        case .rpc(let code, let message):
            message.isEmpty ? "The server returned \(code)." : message
        case .cancelled:
            "Cancelled."
        }
    }

    /// Whether the server is gone rather than refusing one request.
    public var isUnreachable: Bool {
        switch self {
        case .noServer, .unreachable: true
        case .rpc(let code, _): code == .unavailable
        case .updateNeeded, .missingKey, .certificateChanged, .keyRejected, .permissionDenied, .cancelled: false
        }
    }

    static func wrap(_ error: any Error) -> ConnectionError {
        if let error = error as? ConnectionError { return error }
        if error is CancellationError { return .cancelled }
        if let error = error as? RPCError {
            // grpc-swift wraps a cancelled task as an unexpected transport error.
            if error.code == .cancelled || error.cause is CancellationError { return .cancelled }
            if error.code == .permissionDenied { return .permissionDenied(message: error.message) }
            // grpc-swift reports transport failures as "The transport threw an
            // unexpected error." and keeps the reason only in `cause`.
            if let cause = error.cause {
                return .rpc(code: error.code, message: "\(error.message) \(describe(cause))")
            }
            return .rpc(code: error.code, message: error.message)
        }
        return .rpc(code: .unknown, message: describe(error))
    }

    /// Classifies a failed call to a remote server, naming certificate and key
    /// problems that the transport reports only as unavailable.
    static func remote(
        _ error: any Error, address: String, pinned: CertificateFingerprint?, presented: CertificateFingerprint?
    ) -> ConnectionError {
        if let pinned, let presented, pinned != presented {
            return .certificateChanged(address: address, pinned: pinned, presented: presented)
        }
        let wrapped = wrap(error)
        switch wrapped {
        case .rpc(.unauthenticated, _): return .keyRejected(address: address)
        case .rpc(.unavailable, let message), .rpc(.deadlineExceeded, let message):
            var detail = message.isEmpty ? "no answer" : message
            if pinned == nil {
                // Without a pin, a self-signed certificate fails the system
                // trust check, which the transport reports only as a closed
                // connection.
                detail += " If the server uses its self-signed certificate, add it again and trust its fingerprint"
            }
            return .unreachable(address: address, detail: detail)
        default: return wrapped
        }
    }
}
