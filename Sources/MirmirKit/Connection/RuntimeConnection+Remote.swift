import Foundation
import MirmirRPC

/// Remote access management. mirmir serves these only over its local socket,
/// so they apply to This Mac's server.
extension RuntimeConnection {
    public func remoteAccess() async throws(ConnectionError) -> RemoteAccessStatus {
        try await call(.discovery) { options in
            RemoteAccessStatus(try await runtime.getRemoteAccess(Mirmir_V1_GetRemoteAccessRequest(), options: options))
        }
    }

    /// Starts or stops the TLS listener; an empty `bind` keeps the configured
    /// address or uses `0.0.0.0:7443`.
    public func setRemoteAccess(enabled: Bool, bind: String = "") async throws(ConnectionError) -> RemoteAccessStatus {
        var request = Mirmir_V1_SetRemoteAccessRequest()
        request.enabled = enabled
        request.bind = bind
        return try await call(.management) { options in
            RemoteAccessStatus(try await runtime.setRemoteAccess(request, options: options))
        }
    }

    public func createRemoteKey(name: String, scope: RemoteKeyScope) async throws(ConnectionError) -> CreatedRemoteKey {
        var request = Mirmir_V1_CreateRemoteKeyRequest()
        request.name = name
        request.scope = scope.wire
        return try await call(.management) { options in
            let reply = try await runtime.createRemoteKey(request, options: options)
            return CreatedRemoteKey(key: RemoteKey(reply.key), secret: reply.secret)
        }
    }

    public func revokeRemoteKey(id: String) async throws(ConnectionError) -> Bool {
        var request = Mirmir_V1_RevokeRemoteKeyRequest()
        request.id = id
        return try await call(.management) { options in try await runtime.revokeRemoteKey(request, options: options).revoked }
    }
}
