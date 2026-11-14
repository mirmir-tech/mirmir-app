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
        do {
            let connection = try await open(record)
            defer { connection.close() }
            async let snapshot = connection.telemetry()
            async let selectors = connection.activeSelectors()
            let summary = InstanceSummary(
                status: .online(connection.health), telemetry: try await snapshot, loadedModels: try await selectors
            )
            guard shouldPublishProbe(of: record) else { return }
            summaries[record.id] = summary
        } catch {
            guard shouldPublishProbe(of: record) else { return }
            summaries[record.id] = InstanceSummary(
                status: InstanceStatus(error: ConnectionError.wrap(error)), telemetry: nil, loadedModels: []
            )
        }
    }

    /// A probe outlives the record it started with: its result is dropped
    /// when the probe was cancelled, the instance became current, or it was
    /// removed or edited meanwhile.
    private func shouldPublishProbe(of record: InstanceRecord) -> Bool {
        !Task.isCancelled && record.id != currentInstanceID && instances.contains(record)
    }

    public func summary(for record: InstanceRecord) -> InstanceSummary {
        summaries[record.id] ?? .checking
    }
}
