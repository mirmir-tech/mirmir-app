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

    /// A deleted chat's images go only after the save without it is on
    /// disk: after a failed save the chat comes back with them.
    @Test func aDeletedChatKeepsItsImagesUntilTheSaveWithoutItSucceeds() throws {
        let directory = try ChatHistoryTests.scratch()
        defer {
            try? allowWrites(directory)
            try? FileManager.default.removeItem(at: directory)
        }
        let store = ChatStore(directory: directory)
        let image = try store.attachments.save(Data([1, 2, 3]))
        let chat = Conversation(instanceID: InstanceRecord.thisMacID, title: "Look", model: "m", messages: [
            ChatMessage(body: .user(text: "Look", image: .stored(image))),
        ])
        try store.file.save([chat])
        let model = ChatHistoryTests.model(directory)
        guard try refuseWrites(directory) else { return }

        model.chat.delete(chat.id)
        #expect(model.chat.saveNow() != nil)
        #expect(try store.attachments.load(image) == Data([1, 2, 3]), "the saved chat still shows its image")
        #expect(store.load().conversations.map(\.id) == [chat.id])

        try allowWrites(directory)
        #expect(model.chat.saveNow() == nil)
        #expect(store.load().conversations.isEmpty)
        #expect(throws: (any Error).self) { try store.attachments.load(image) }
    }
}
