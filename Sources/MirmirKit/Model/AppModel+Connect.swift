import Foundation

extension AppModel {
    /// Opens a connection to a saved instance: its Unix socket, or a remote
    /// server's TLS listener with the key from the credential store.
    func open(_ record: InstanceRecord) async throws(ConnectionError) -> RuntimeConnection {
        if case .remote(let endpoint) = record.target {
            guard let key = credentials.key(for: record.id) else { throw .missingKey(address: endpoint.address) }
            return try await RuntimeConnection.connect(remote: endpoint, key: key)
        }
        guard let socket = paths.socket(for: record.target) else {
            throw .noServer(socket: address(of: record))
        }
        return try await RuntimeConnection.connect(socket: socket)
    }

    /// Where a connection to the instance goes: the socket path or
    /// `grpcs://host:port`, for display.
    public func address(of record: InstanceRecord) -> String {
        if case .remote(let endpoint) = record.target { return "grpcs://\(endpoint.address)" }
        let socket = paths.socket(for: record.target) ?? ""
        return socket.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    /// The error shown when an open connection to the instance closes.
    func offlineError(for record: InstanceRecord) -> ConnectionError {
        if case .remote(let endpoint) = record.target {
            return .unreachable(address: endpoint.address, detail: "the connection closed")
        }
        return .noServer(socket: paths.socket(for: record.target) ?? address(of: record))
    }
}
