import Foundation
import MirmirRPC

/// Remote access management. mirmir serves these only over its local socket,
/// so they apply to This Mac's server.
extension RuntimeConnection {
    public func remoteAccess() async throws(ConnectionError) -> RemoteAccessStatus {
        try await call { RemoteAccessStatus(try await runtime.getRemoteAccess(Mirmir_V1_GetRemoteAccessRequest())) }
    }

    /// Starts or stops the TLS listener; an empty `bind` keeps the configured
    /// address or uses `0.0.0.0:7443`.
    public func setRemoteAccess(enabled: Bool, bind: String = "") async throws(ConnectionError) -> RemoteAccessStatus {
        var request = Mirmir_V1_SetRemoteAccessRequest()
        request.enabled = enabled
        request.bind = bind
        return try await call { RemoteAccessStatus(try await runtime.setRemoteAccess(request)) }
    }

    public func createRemoteKey(name: String, scope: RemoteKeyScope) async throws(ConnectionError) -> CreatedRemoteKey {
        var request = Mirmir_V1_CreateRemoteKeyRequest()
        request.name = name
        request.scope = scope.wire
        return try await call {
            let reply = try await runtime.createRemoteKey(request)
            return CreatedRemoteKey(key: RemoteKey(reply.key), secret: reply.secret)
        }
    }

    public func revokeRemoteKey(id: String) async throws(ConnectionError) -> Bool {
        var request = Mirmir_V1_RevokeRemoteKeyRequest()
        request.id = id
        return try await call { try await runtime.revokeRemoteKey(request).revoked }
    }
}
