import Foundation
import Testing
@testable import MirmirKit

@Suite("Downloads in the model list")
@MainActor
struct DownloadListingTests {
    static let repo = "example/Unlisted-Model-4bit"

    private func pull(_ state: ActivityState, stage: String, progress: ActivityProgress? = nil) -> Activity {
        Activity(
            id: "pull", kind: .pull, target: Self.repo, state: state, stage: stage, detail: "",
            startedAt: Date(), updatedAt: Date(), cancellable: true, progress: progress
        )
    }

    @Test func aPullFromAnyClientIsListedBeforeItsCheckpoint() throws {
        let model = AppModel.preview()
        let connection = try #require(model.connection)
        model.refreshModelsSoon = false
        model.apply(pull(.running, stage: "resolving"), from: connection)
        let download = try #require(model.unlistedDownloads.first { $0.repoID == Self.repo })
        #expect(download.stage == "Resolving")
        #expect(download.cancellableOperation == "pull")
        // The server lists the checkpoint once files arrive: look for it.
        #expect(model.refreshModelsSoon)
    }

    @Test func aListedCheckpointTakesOverItsDownloadRow() throws {
        let model = AppModel.preview()
        let connection = try #require(model.connection)
        model.apply(pull(.running, stage: "downloading", progress: ActivityProgress(current: 1, total: 4)), from: connection)
        let listed = try #require(model.models.first { !$0.repoID.isEmpty })
        model.apply(Activity(
            id: "other", kind: .pull, target: listed.repoID, state: .running, stage: "downloading", detail: "",
            startedAt: Date(), updatedAt: Date(), cancellable: false, progress: nil
        ), from: connection)
        #expect(!model.unlistedDownloads.contains { $0.repoID == listed.repoID })
        #expect(model.download(of: listed)?.cancellableOperation == nil)
        #expect(model.unlistedDownloads.first { $0.repoID == Self.repo }?.fraction == 0.25)
    }

    @Test func aFinishedPullLeavesTheList() throws {
        let model = AppModel.preview()
        let connection = try #require(model.connection)
        model.apply(pull(.running, stage: "downloading"), from: connection)
        model.apply(pull(.completed, stage: "completed"), from: connection)
        #expect(!model.unlistedDownloads.contains { $0.repoID == Self.repo })
    }

    @Test func anAppTransferShowsItsBytes() throws {
        let model = AppModel.preview()
        let download = try #require(model.downloads[PreviewData.downloadRepo])
        #expect(download.downloadedBytes == 6_420_000_000 && download.totalBytes == 17_100_000_000)
        #expect(download.stage == "Downloading")
        // The server's pull of the same repository can cancel it.
        #expect(download.cancellableOperation != nil)
    }

    @Test func inspectionTasksAreTyped() {
        #expect(ModelTask(wire: "generation").generates)
        #expect(!ModelTask(wire: "rerank").generates)
        #expect(!ModelTask(wire: "embedding").generates)
        #expect(ModelTask(wire: "speech") == .unrecognized("speech"))
    }
}
