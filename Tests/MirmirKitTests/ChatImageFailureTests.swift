import Foundation
import Testing
@testable import MirmirKit

/// The newest image of a conversation is the one a request sends. When it
/// cannot be read the request fails: it never falls back to an older image
/// or quietly goes without one.
@Suite("Unreadable images")
@MainActor
struct ChatImageFailureTests {
    private func store() -> AttachmentStore {
        AttachmentStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
    }

    private func pending() -> ChatMessage {
        ChatMessage(body: .assistant(text: "", reasoning: "", thinkingSeconds: nil, state: .streaming))
    }

    private func answer(_ text: String) -> ChatMessage {
        ChatMessage(body: .assistant(text: text, reasoning: "", thinkingSeconds: nil, state: .completed(.init(
            promptTokens: 1, completionTokens: 1, finishReason: "stop", elapsedMs: 1,
            decodeTokensPerSecond: nil, prefillTokensPerSecond: nil, ttftMs: nil
        ))))
    }

    @Test func aLostNewerImageNeverSendsTheOlderOne() throws {
        let attachments = store()
        let a = try attachments.save(Data([1])), b = try attachments.save(Data([2]))
        attachments.remove(b)
        let next = pending()
        let conversation = Conversation(instanceID: UUID(), model: "m", messages: [
            ChatMessage(body: .user(text: "A", image: .stored(a))), answer("Red."),
            ChatMessage(body: .user(text: "B", image: .stored(b))), answer("Blue."),
            ChatMessage(body: .user(text: "And now?", image: nil)), next,
        ])
        #expect(throws: RequestError.imageUnavailable(id: b, turn: 2)) {
            try conversation.request(replyingTo: next.id, maxTokens: nil, temperature: nil, image: attachments.load)
        }
    }

    @Test func anUnreadableOnlyImageIsNotSentAsTextAlone() throws {
        let attachments = store()
        let lost = UUID()
        let next = pending()
        let conversation = Conversation(instanceID: UUID(), model: "m", messages: [
            ChatMessage(body: .user(text: "Describe this", image: .stored(lost))), next,
        ])
        #expect(throws: RequestError.imageUnavailable(id: lost, turn: 0)) {
            try conversation.request(replyingTo: next.id, maxTokens: nil, temperature: nil, image: attachments.load)
        }
    }

    @Test func anImageTheAppNeverKeptStillSendsText() throws {
        let next = pending()
        let conversation = Conversation(instanceID: UUID(), model: "m", messages: [
            ChatMessage(body: .user(text: "Old", image: .unavailable)), next,
        ])
        let request = try conversation.request(replyingTo: next.id, maxTokens: nil, temperature: nil) { _ in
            Issue.record("an image that was never kept is not read")
            return Data()
        }
        #expect(request.image == nil)
    }

    /// Sending in a chat whose newest image is gone fails with a notice and
    /// keeps the chat as it was; attaching an image again sends.
    @Test func sendingFailsVisiblyAndAttachingAgainContinues() throws {
        let directory = try ChatHistoryTests.scratch()
        defer { try? FileManager.default.removeItem(at: directory) }
        let chats = ChatStore(directory: directory)
        let a = try chats.attachments.save(Data([1])), b = try chats.attachments.save(Data([2]))
        let conversation = Conversation(instanceID: InstanceRecord.thisMacID, model: "m", messages: [
            ChatMessage(body: .user(text: "A", image: .stored(a))), answer("Red."),
            ChatMessage(body: .user(text: "B", image: .stored(b))), answer("Blue."),
        ])
        try chats.file.save([conversation])
        chats.attachments.remove(b)

        let model = ChatHistoryTests.model(directory)
        model.phase = .connected(RuntimeConnection.preview())
        model.chat.selectedID = conversation.id
        #expect(!model.chat.send("And now?"))
        #expect(model.notice == RequestError.imageUnavailable(id: b, turn: 2).localizedDescription)
        #expect(model.chat.unreadableImages == [b])
        #expect(model.chat.selected?.messages.map(\.id) == conversation.messages.map(\.id))

        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 0])
        #expect(model.chat.send("This one", image: png))
        #expect(model.chat.selected?.messages.count == conversation.messages.count + 2)
        model.chat.stop()
    }
}
