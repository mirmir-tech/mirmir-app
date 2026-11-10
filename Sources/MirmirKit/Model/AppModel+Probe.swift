import Foundation

extension AppModel {
    static let probeInterval: Duration = .seconds(10)

    /// Refreshes the cards of instances that are not the current one.
    func probeLoop() async {
        while !Task.isCancelled {
            for record in instances where record.id != currentInstanceID {
                await probe(record)
            }
            try? await Task.sleep(for: Self.probeInterval)
        }
    }

    func probe(_ record: InstanceRecord) async {
        guard let socket = paths.socket(for: record.target) else {
            if case .remote(let endpoint) = record.target {
                summaries[record.id] = InstanceSummary(
                    status: InstanceStatus(error: .remoteUnavailable(address: endpoint.address)),
                    telemetry: nil, loadedModels: []
                )
            }
            return
        }
        do {
            let connection = try await RuntimeConnection.connect(socket: socket)
            defer { connection.close() }
            async let snapshot = connection.telemetry()
            async let selectors = connection.activeSelectors()
            let summary = InstanceSummary(
                status: .online(connection.health), telemetry: try await snapshot, loadedModels: try await selectors
            )
            guard record.id != currentInstanceID else { return }
            summaries[record.id] = summary
        } catch {
            guard record.id != currentInstanceID else { return }
            summaries[record.id] = InstanceSummary(
                status: InstanceStatus(error: ConnectionError.wrap(error)), telemetry: nil, loadedModels: []
            )
        }
    }

    public func summary(for record: InstanceRecord) -> InstanceSummary {
        summaries[record.id] ?? .checking
    }
}
