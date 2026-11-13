import Foundation
import Testing
@testable import MirmirKit

/// Results of calls on a server that is no longer current never reach the
/// screen, even when both servers list the same selector.
@Suite("Server switch isolation")
@MainActor
struct ServerSwitchTests {
    /// Switches to the second preview server and connects it, with no
    /// session task racing the test.
    private func switchToRemote(_ model: AppModel) -> RuntimeConnection {
        model.select(instance: model.instances[1].id)
        model.sessionTask?.cancel()
        let remote = RuntimeConnection.preview()
        model.phase = .connected(remote)
        return remote
    }

    @Test func aLateUnloadOnThePreviousServerLeavesTheCurrentOneAlone() async throws {
        let model = AppModel.preview()
        let shared = PreviewData.models[0].selector
        let inspection = try #require(PreviewData.inspections.values.first)
        model.unload(shared)
        _ = switchToRemote(model)
        model.models = [PreviewData.models[0]]
        model.inspections[shared] = inspection

        // The preview connection fails the unload at once; let it finish.
        for _ in 0..<50 where model.notice == nil { try await Task.sleep(for: .milliseconds(20)) }
        #expect(model.inspections[shared] != nil)
        #expect(model.models.map(\.selector) == [shared])
        #expect(model.notice?.hasPrefix("preview: Unloading") == true)
    }

    @Test func staleModelListsProgressAndActivityAreDropped() {
        let model = AppModel.preview()
        let previous = model.connection!
        let current = switchToRemote(model)
        let shared = PreviewData.models[0].selector
        let progress = LoadProgress(phase: "loading weights", current: 1, total: 2, detail: "", finished: false)
        let transfer = TransferProgress(repoID: "a/b", phase: .downloading, downloadedBytes: 1, totalBytes: 2, message: "")
        let activity = Activity(
            id: "g", kind: .generate, target: shared, state: .running, stage: "decode", detail: "",
            startedAt: Date(), updatedAt: Date(), cancellable: true, progress: nil
        )

        model.publishModels([PreviewData.models[0]], active: [shared], serving: [shared: shared], from: previous)
        model.setLoad(shared, progress, from: previous)
        model.setTransfer("a/b", transfer, from: previous)
        model.apply(activity, from: previous)
        #expect(model.models.isEmpty && model.activeSelectors.isEmpty && model.servingSelectors.isEmpty)
        #expect(model.loads.isEmpty && model.transfers.isEmpty && model.activities.isEmpty)

        model.publishModels([PreviewData.models[0]], active: [shared], serving: [shared: shared], from: current)
        model.setLoad(shared, progress, from: current)
        model.apply(activity, from: current)
        #expect(model.activeSelectors == [shared])
        #expect(model.loads[shared] != nil && model.activities["g"] != nil)
    }

    @Test func aLocalFolderNeverLoadsOnARemoteServer() {
        let model = AppModel.preview()
        #expect(model.canLoadLocalFolders)
        _ = switchToRemote(model)
        #expect(!model.canLoadLocalFolders)
        model.loadModel(at: URL(fileURLWithPath: "/Users/someone/models/qwen"))
        #expect(model.loads.isEmpty)
        #expect(model.modelFolders.folders.isEmpty)
        #expect(model.notice?.contains("This Mac") == true)
    }
}

@Suite("Image requests")
struct ImageRequestTests {
    private let turns = [
        ChatTurn(role: .user, content: "Describe this image"),
        ChatTurn(role: .assistant, content: "A red square."),
        ChatTurn(role: .user, content: "What color is it?"),
    ]

    @Test func theImageTurnCarriesTheMarker() {
        let wire = GenerationRequest(model: "m", turns: turns, image: TurnImage(data: Data([1, 2, 3]), turn: 0)).wire
        #expect(wire.messages.map(\.content) == ["<|mirmir_image|>\nDescribe this image", "A red square.", "What color is it?"])
        #expect(wire.image == Data([1, 2, 3]))
    }

    @Test func textOnlyRequestsAreUnchanged() {
        let wire = GenerationRequest(model: "m", turns: turns).wire
        #expect(wire.messages.map(\.content) == ["Describe this image", "A red square.", "What color is it?"])
    }
}

@Suite("Add Server test")
struct RemoteTestTests {
    private let health = ServerHealth(protocolVersion: "2", serverVersion: "0.6.0")
    private let pin = CertificateFingerprint(der: [1, 2, 3])

    @Test func onlyAPassWithTheCurrentInputsCanBeAdded() throws {
        let tested = try #require(RemoteCandidate(address: "box.local", key: "mmk_a", pinned: pin))
        let passed = RemoteTestResult(candidate: tested, outcome: .passed(health, models: 2))
        #expect(passed.approved(for: tested, testing: false) == tested)
        #expect(passed.approved(for: tested, testing: true) == nil)
        #expect(passed.approved(for: RemoteCandidate(address: "box.local", key: "mmk_b", pinned: pin), testing: false) == nil)
        #expect(passed.approved(for: RemoteCandidate(address: "box.local", key: "mmk_a", pinned: nil), testing: false) == nil)
        #expect(passed.approved(for: RemoteCandidate(address: "other.local", key: "mmk_a", pinned: pin), testing: false) == nil)
        let failed = RemoteTestResult(candidate: tested, outcome: .failed("no route"))
        #expect(failed.approved(for: tested, testing: false) == nil)
    }

    @Test func keysAreComparedTrimmed() {
        #expect(RemoteCandidate(address: "box.local", key: " mmk_a ", pinned: nil)
            == RemoteCandidate(address: "box.local", key: "mmk_a", pinned: nil))
    }
}
