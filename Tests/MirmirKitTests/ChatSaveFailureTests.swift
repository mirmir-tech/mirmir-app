import Foundation
import Testing
@testable import MirmirKit

/// A save the storage refuses after a normal launch is reported, keeps the
/// chats in memory and succeeds once the storage accepts writes again.
@Suite("Failed chat saves")
@MainActor
struct ChatSaveFailureTests {
    /// Makes `directory` read-only; false where writes still succeed (root).
    private func refuseWrites(_ directory: URL) throws -> Bool {
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
        let probe = directory.appendingPathComponent("probe")
        let refused = !FileManager.default.createFile(atPath: probe.path, contents: Data())
        try? FileManager.default.removeItem(at: probe)
        return refused
    }

    private func allowWrites(_ directory: URL) throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
    }

    @Test func aRefusedSaveIsReportedAndRetriedOnceStorageRecovers() throws {
        let directory = try ChatHistoryTests.scratch()
        defer {
            try? allowWrites(directory)
            try? FileManager.default.removeItem(at: directory)
        }
        try ChatStore(directory: directory).file.save([ChatHistoryTests.conversation("Original")])
        let model = ChatHistoryTests.model(directory)
        #expect(model.chat.loadIssue == nil)
        guard try refuseWrites(directory) else { return }

        model.chat.newConversation(model: "m")
        let failure = model.chat.terminate()
        #expect(failure != nil, "terminate reports that the chats are not on disk")
        #expect(model.chat.saveFailure == failure)
        #expect(model.chat.conversations.count == 2, "the unsaved chat stays in memory")

        try allowWrites(directory)
        #expect(model.chat.saveNow() == nil)
        #expect(model.chat.saveFailure == nil)
        #expect(ChatStore(directory: directory).load().conversations.count == 2)
    }

    @Test func aQueuedSaveFailureShowsAndARetryClearsIt() async throws {
        let directory = try ChatHistoryTests.scratch()
        defer {
            try? allowWrites(directory)
            try? FileManager.default.removeItem(at: directory)
        }
        try ChatStore(directory: directory).file.save([ChatHistoryTests.conversation("Original")])
        let model = ChatHistoryTests.model(directory)
        guard try refuseWrites(directory) else { return }

        model.chat.newConversation(model: "m")
        for _ in 0..<100 where model.chat.saveFailure == nil {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(model.chat.saveFailure != nil, "a failed background save is visible")

        try allowWrites(directory)
        model.chat.retrySaving()
        for _ in 0..<100 where model.chat.saveFailure != nil {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(model.chat.saveFailure == nil)
        #expect(ChatStore(directory: directory).load().conversations.count == 2)
    }
}
