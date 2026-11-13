import Foundation
import Testing
@testable import MirmirKit

/// Saved chats that do not decode are never written over unseen: valid
/// conversations still load, the original bytes are copied aside first, and
/// a file that cannot be read at all is left untouched.
@Suite("Saved chat history")
@MainActor
struct ChatHistoryTests {
    static func scratch() throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mm-chats-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// An app model that keeps everything in `directory`.
    static func model(_ directory: URL) -> AppModel {
        AppModel(
            paths: SocketPaths(environment: ["HOME": directory.path, "MIRMIR_STATE_HOME": directory.path]),
            supervisor: ServerSupervisor(logFile: directory.appendingPathComponent("server.log")),
            credentials: MemoryCredentials(),
            modelFolders: ModelFolders(file: JSONFile(name: "model-folders.json", directory: directory)),
            chats: ChatStore(directory: directory)
        )
    }

    static func conversation(_ title: String) -> Conversation {
        Conversation(instanceID: InstanceRecord.thisMacID, title: title, model: "m", messages: [
            ChatMessage(body: .user(text: title, image: nil)),
        ])
    }

    private func backups(in directory: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("chats.json.corrupt-") }
    }

    @Test func oneBadRecordHidesOnlyItselfAndTheOriginalIsKept() throws {
        let directory = try Self.scratch()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ChatStore(directory: directory)
        let valid = [Self.conversation("First"), Self.conversation("Second")]
        let records = try valid.map { try JSONSerialization.jsonObject(with: JSONEncoder.mirmir.encode($0)) }
        // A conversation of a future version: no `messages`.
        let future: [String: Any] = ["id": UUID().uuidString, "title": "Future", "model": "m", "updatedAt": "2026-11-01T00:00:00Z"]
        let original = try JSONSerialization.data(withJSONObject: [records[0], future, records[1]])
        try original.write(to: store.file.url)

        let model = Self.model(directory)
        #expect(Set(model.chat.conversations.map(\.title)) == ["First", "Second"])
        guard case .dropped(1, let backup) = model.chat.loadIssue else {
            Issue.record("load issue \(String(describing: model.chat.loadIssue))")
            return
        }
        #expect(try Data(contentsOf: backup) == original)
        #expect(try backups(in: directory).map(\.lastPathComponent) == [backup.lastPathComponent])

        model.chat.newConversation(model: "m")
        model.chat.flushSaves()
        let saved = store.load()
        #expect(saved.issue == nil)
        #expect(Set(saved.conversations.map(\.title)) == ["First", "Second", "New Chat"])
        #expect(try Data(contentsOf: backup) == original)
        model.chat.dismissLoadIssue()
        #expect(model.chat.loadIssue == nil)
    }

    @Test func aFileThatIsNotAListIsKeptAside() throws {
        let directory = try Self.scratch()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ChatStore(directory: directory)
        let original = Data("{\"truncated\": [".utf8)
        try original.write(to: store.file.url)

        let model = Self.model(directory)
        #expect(model.chat.conversations.isEmpty)
        guard case .unrecognized(let backup) = model.chat.loadIssue else {
            Issue.record("load issue \(String(describing: model.chat.loadIssue))")
            return
        }
        #expect(try Data(contentsOf: backup) == original)
        // A second launch before anything was saved keeps both copies.
        let again = Self.model(directory)
        #expect(try backups(in: directory).count == 2)
        again.chat.newConversation(model: "m")
        again.chat.flushSaves()
        #expect(store.load().conversations.count == 1)
    }

    @Test func noFileIsAnEmptyHistory() throws {
        let directory = try Self.scratch()
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = Self.model(directory)
        #expect(model.chat.conversations.isEmpty)
        #expect(model.chat.loadIssue == nil)
        model.chat.newConversation(model: "m")
        model.chat.flushSaves()
        #expect(ChatStore(directory: directory).load().conversations.count == 1)
    }

    /// Something that is not a readable file stands at `chats.json`.
    @Test func anUnreadablePathIsNeverWrittenOver() throws {
        let directory = try Self.scratch()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ChatStore(directory: directory)
        try FileManager.default.createDirectory(at: store.file.url, withIntermediateDirectories: true)
        let inside = store.file.url.appendingPathComponent("keep")
        try Data([1]).write(to: inside)

        let model = Self.model(directory)
        #expect(model.chat.loadIssue?.isPersistent == true)
        model.chat.newConversation(model: "m")
        model.chat.dismissLoadIssue()
        #expect(model.chat.loadIssue?.isPersistent == true, "a session that does not save keeps saying so")
        model.chat.flushSaves()
        #expect(try Data(contentsOf: inside) == Data([1]))
        #expect(try backups(in: directory).isEmpty)
        #expect(model.chat.conversations.count == 1, "the session still works in memory")
    }

    /// A file without read permission. Root reads it anyway, so the case
    /// exists only for other users.
    @Test(.enabled(if: getuid() != 0)) func aFileWithoutReadPermissionIsNeverWrittenOver() throws {
        let directory = try Self.scratch()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ChatStore(directory: directory)
        let original = try JSONEncoder.mirmir.encode([Self.conversation("Kept")])
        try original.write(to: store.file.url)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: store.file.url.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: store.file.url.path) }

        let model = Self.model(directory)
        guard case .notSaved = model.chat.loadIssue else {
            Issue.record("load issue \(String(describing: model.chat.loadIssue))")
            return
        }
        model.chat.newConversation(model: "m")
        model.chat.flushSaves()
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: store.file.url.path)
        #expect(try Data(contentsOf: store.file.url) == original)
    }
}
