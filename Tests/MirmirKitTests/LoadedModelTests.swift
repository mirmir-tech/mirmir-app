import Foundation
import Testing
@testable import MirmirKit

@Suite("Loaded models")
@MainActor
struct LoadedModelTests {
    static let path = "/Users/someone/Models/mlx-community--gemma-4-26b-a4b-it-8bit"

    @Test func unlistedActiveModelIsLoaded() {
        let model = AppModel.preview()
        model.activeSelectors.append(Self.path)
        let loaded = model.loadedModels
        #expect(loaded.contains { $0.selector == Self.path })
        #expect(loaded.first { $0.selector == Self.path }?.displayName == "gemma-4-26b-a4b-it-8bit")
    }

    @Test func primaryIsTheLastGeneratingModel() throws {
        let model = AppModel.preview()
        model.activeSelectors.append(Self.path)
        let now = Date()
        model.activities = [:]
        model.apply(Activity(
            id: "g", kind: .generate, target: Self.path, state: .completed, stage: "completed", detail: "",
            startedAt: now, updatedAt: now, cancellable: false, progress: nil
        ), from: try #require(model.connection))
        #expect(model.primaryModel?.selector == Self.path)
    }

    @Test func activityTargetShowsTheModelName() {
        let model = AppModel.preview()
        model.activeSelectors.append(Self.path)
        let activity = Activity(
            id: "g", kind: .generate, target: Self.path, state: .running, stage: "decode", detail: "",
            startedAt: Date(), updatedAt: Date(), cancellable: true, progress: nil
        )
        #expect(model.displayTarget(of: activity) == "gemma-4-26b-a4b-it-8bit")
        let endpoint = Activity(
            id: "h", kind: .generate, target: "/v1/chat/completions", state: .running, stage: "decode", detail: "",
            startedAt: Date(), updatedAt: Date(), cancellable: true, progress: nil
        )
        #expect(model.displayTarget(of: endpoint) == "/v1/chat/completions")
    }

    @Test func idleSamplesHaveNoLiveRate() {
        let busy = TelemetrySample(sampledAt: Date(), loadedModels: 1, activeRequests: 1, decode: 45, prefill: 70, ttftMs: nil, memory: nil, kvTotalBlocks: 0, kvUsedBlocks: 0)
        let idle = TelemetrySample(sampledAt: Date(), loadedModels: 1, activeRequests: 0, decode: 45, prefill: 70, ttftMs: nil, memory: nil, kvTotalBlocks: 0, kvUsedBlocks: 0)
        #expect(busy.liveDecode == 45 && busy.livePrefill == 70)
        #expect(idle.liveDecode == nil && idle.livePrefill == nil)
    }

    @Test func runningPullIsADownloadNotAFailure() throws {
        let model = AppModel.preview()
        let partial = try #require(model.models.first { !$0.repoID.isEmpty })
        #expect(model.download(of: partial) == nil)
        let now = Date()
        model.apply(Activity(
            id: "p", kind: .pull, target: partial.repoID, state: .running, stage: "downloading", detail: "",
            startedAt: now, updatedAt: now, cancellable: true, progress: ActivityProgress(current: 25, total: 100)
        ), from: try #require(model.connection))
        #expect(model.download(of: partial) == ModelDownload(fraction: 0.25))
        model.apply(Activity(
            id: "p", kind: .pull, target: partial.repoID, state: .completed, stage: "completed", detail: "",
            startedAt: now, updatedAt: now, cancellable: false, progress: nil
        ), from: try #require(model.connection))
        #expect(model.download(of: partial) == nil)
    }
}
