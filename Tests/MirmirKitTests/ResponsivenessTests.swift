import Foundation
import Testing
@testable import MirmirKit

@Suite("Main-actor relief")
struct ResponsivenessTests {
    @Test func downsamplingBoundsChartPointsAndKeepsPeaks() {
        let start = Date(timeIntervalSince1970: 0)
        let samples = (0..<3_600).map { index in
            TelemetrySample(
                sampledAt: start.addingTimeInterval(Double(index)), loadedModels: 1,
                activeRequests: index == 1_234 ? 9 : 1, decode: index == 2_000 ? 500 : 100,
                prefill: nil, ttftMs: nil, memory: nil, kvTotalBlocks: 10, kvUsedBlocks: 2
            )
        }
        let history = TelemetryHistory(samples: samples, retentionLimit: 3_600, samplingInterval: 1)
        let reduced = history.downsampled()
        #expect(reduced.samples.count <= TelemetryHistory.chartPoints)
        #expect(reduced.samples.compactMap(\.decode).max() == 500)
        #expect(reduced.samples.map(\.activeRequests).max() == 9)
        #expect(reduced.samples.last?.sampledAt == samples.last?.sampledAt)
        #expect(reduced.retentionLimit == 3_600)
    }

    @Test func shortHistoryIsUnchanged() {
        let history = TelemetryHistory(samples: [], retentionLimit: 0, samplingInterval: 1)
        #expect(history.downsampled() == history)
    }

    @Test func servingSelectorsMatchExactAndResolvedPaths() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let real = directory.appendingPathComponent("real")
        let link = directory.appendingPathComponent("link")
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        defer { try? FileManager.default.removeItem(at: directory) }

        let models = PreviewData.models
        let linked = models[1]
        let viaLink = LocalModel(
            selector: link.path, repoID: linked.repoID, commit: linked.commit, path: link.path, state: .available,
            loadability: .loadable, modelClass: "", encoding: "", container: "", sizeBytes: 0, features: [],
            imageInput: false, managed: false, recentRank: nil
        )
        let serving = AppModel.servingSelectors(models: [models[0], viaLink], active: [models[0].selector, real.path])
        #expect(serving[models[0].selector] == models[0].selector)
        #expect(serving[link.path] == real.path)
    }

    @MainActor @Test func previewConnectionFailsImmediately() async {
        let connection = RuntimeConnection.preview()
        let started = ContinuousClock.now
        await #expect(throws: ConnectionError.self) { try await connection.telemetry() }
        #expect(ContinuousClock.now - started < .seconds(2))
    }

    @MainActor @Test func previewModelIsConnectedWithSampleData() {
        let model = AppModel.preview()
        #expect(model.connection != nil)
        #expect(model.primaryModel?.repoID == "mlx-community/Qwen3.6-35B-A3B-mxfp4")
        #expect(model.history.samples.count <= TelemetryHistory.chartPoints)
        #expect(!model.chat.conversations.isEmpty)
    }
}
