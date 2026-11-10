import Foundation
import GRPCCore

public enum ConnectionError: Error, Hashable, Sendable, LocalizedError {
    /// No server socket exists at the path.
    case noServer(socket: String)
    /// The server answered with a different `Runtime` protocol.
    case updateNeeded(serverProtocol: String, serverVersion: String)
    /// Remote access is designed but not served by mirmir yet.
    case remoteUnavailable(address: String)
    /// The RPC failed with a gRPC status.
    case rpc(code: RPCError.Code, message: String)

    public var errorDescription: String? {
        switch self {
        case .noServer(let socket):
            "No mirmir server is listening at \(socket)."
        case .updateNeeded(let server, let version):
            "Server protocol \(server) (mirmir \(version)) differs from this app's protocol \(clientProtocolVersion). Update mirmir."
        case .remoteUnavailable(let address):
            "Remote access to \(address) needs mirmir's TLS listener, which is not released yet."
        case .rpc(let code, let message):
            message.isEmpty ? "The server returned \(code)." : message
        }
    }

    /// Whether the server is gone rather than refusing one request.
    public var isUnreachable: Bool {
        switch self {
        case .noServer, .remoteUnavailable: true
        case .rpc(let code, _): code == .unavailable
        case .updateNeeded: false
        }
    }

    static func wrap(_ error: any Error) -> ConnectionError {
        if let error = error as? ConnectionError { return error }
        if let error = error as? RPCError {
            return .rpc(code: error.code, message: error.message)
        }
        return .rpc(code: .unknown, message: error.localizedDescription)
    }
}
