import Foundation
import Observation

/// Drives the Remote Access sheet of This Mac. It opens its own connection to
/// the local server for each action, because mirmir serves remote-access
/// management only over its Unix socket, whatever instance the window shows.
@MainActor
@Observable
public final class RemoteAccessController {
    public private(set) var status: RemoteAccessStatus?
    /// A key just created; its value is shown until the sheet dismisses it.
    public private(set) var created: CreatedRemoteKey?
    public private(set) var error: String?
    public private(set) var working = false

    private let model: AppModel

    public init(model: AppModel) {
        self.model = model
    }

    public func refresh() async {
        if let status = await withLocalServer({ connection throws(ConnectionError) in try await connection.remoteAccess() }) {
            self.status = status
        }
    }

    /// Starts the listener on `bind` (empty keeps the configured address or
    /// uses `0.0.0.0:7443`), or stops it; keys are kept either way.
    public func setEnabled(_ enabled: Bool, bind: String) async {
        let bind = bind.trimmingCharacters(in: .whitespaces)
        let updated = await withLocalServer { connection throws(ConnectionError) in
            try await connection.setRemoteAccess(enabled: enabled, bind: bind)
        }
        if let updated { status = updated }
    }

    public func createKey(name: String, scope: RemoteKeyScope) async {
        let name = name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else {
            error = "Name the key after the computer or app that will use it."
            return
        }
        let key = await withLocalServer { connection throws(ConnectionError) in
            try await connection.createRemoteKey(name: name, scope: scope)
        }
        guard let key else { return }
        created = key
        await refresh()
    }

    /// Revokes a key and lists the keys again; a failure stays shown, as a
    /// refresh would clear it.
    public func revoke(_ key: RemoteKey) async {
        let revoked = await withLocalServer { connection throws(ConnectionError) in
            try await connection.revokeRemoteKey(id: key.id)
        }
        guard revoked != nil else { return }
        await refresh()
    }

    public func dismissCreatedKey() {
        created = nil
    }

    public func clearError() {
        error = nil
    }

    private func withLocalServer<T: Sendable>(
        _ body: (RuntimeConnection) async throws(ConnectionError) -> T
    ) async -> T? {
        working = true
        defer { working = false }
        do {
            let connection = try await model.open(.thisMac)
            defer { connection.close() }
            let result = try await body(connection)
            error = nil
            return result
        } catch {
            self.error = error.localizedDescription
            return nil
        }
    }
}
