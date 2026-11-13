import Foundation
import Testing
@testable import MirmirKit

/// A streaming reply survives quitting the app as it was on screen, and
/// belongs to its own conversation: deleting that conversation stops it,
/// deleting another one does not.
@Suite("Generation lifecycle", .serialized)
@MainActor
struct GenerationLifecycleTests {
    /// An app model keeping its chats in `directory`, connected to a
    /// stand-in server there whose replies stay open until cancelled.
    @MainActor
    private struct Harness {
        let directory: URL
        let server: StandInServer
        let model: AppModel

        init(holds: Bool = true) async throws {
            directory = try DeadlineTests.scratch()
            server = try await StandInServer(socket: directory.appendingPathComponent("mirmir.sock").path, holds: holds)
            model = ChatHistoryTests.model(directory)
            model.phase = .connected(try await RuntimeConnection.connect(socket: server.socket))
        }

        var chat: ChatController { model.chat }

        func reply(in conversation: UUID) -> MessageBody? {
            chat.conversations.first { $0.id == conversation }?.messages.last?.body
        }

        /// Starts a reply in a new conversation and waits until both of its
        /// fragments are on screen.
        func streamingConversation() async throws -> UUID {
            let id = chat.newConversation(model: "m")
            #expect(chat.send("Hello", to: id))
            let shown = try await eventually {
                reply(in: id) == .assistant(
                    text: StandInRuntime.answer, reasoning: StandInRuntime.reasoning,
                    thinkingSeconds: thinkingSeconds(id), state: .streaming
                )
            }
            #expect(shown)
            return id
        }

        private func thinkingSeconds(_ id: UUID) -> Double? {
            guard case .assistant(_, _, let seconds, _) = reply(in: id) else { return nil }
            return seconds
        }

        func saved() -> [Conversation] {
            ChatStore(directory: directory).load().conversations
        }

        func tearDown() {
            model.shutdown()
            server.stop()
            try? FileManager.default.removeItem(at: directory)
        }
    }

    @Test func quittingKeepsTheVisibleReplyAsStopped() async throws {
        let harness = try await Harness()
        defer { harness.tearDown() }
        let id = try await harness.streamingConversation()
        guard case .assistant(let text, let reasoning, let seconds, .streaming) = harness.reply(in: id) else {
            Issue.record("no streaming reply"); return
        }
        // Streaming alone saves nothing of the reply.
        harness.chat.flushSaves()
        #expect(harness.saved().first { $0.id == id }?.messages.last?.body
            == .assistant(text: "", reasoning: "", thinkingSeconds: nil, state: .streaming))

        harness.model.shutdown()
        let stopped = MessageBody.assistant(text: text, reasoning: reasoning, thinkingSeconds: seconds, state: .stopped)
        #expect(!harness.chat.isGenerating)
        #expect(harness.reply(in: id) == stopped)
        #expect(harness.saved().first { $0.id == id }?.messages.last?.body == stopped)

        // The cancelled RPC finishing late changes nothing, on screen or on disk.
        try await Task.sleep(for: .milliseconds(300))
        harness.chat.flushSaves()
        #expect(harness.reply(in: id) == stopped)
        #expect(harness.saved().first { $0.id == id }?.messages.last?.body == stopped)
    }

    @Test func quittingWritesEveryPendingSave() async throws {
        let harness = try await Harness()
        defer { harness.tearDown() }
        let ids = (0..<25).map { harness.chat.newConversation(model: "m\($0)") }
        harness.chat.delete(ids[0])
        harness.model.shutdown()
        let saved = harness.saved()
        #expect(Set(saved.map(\.id)) == Set(ids.dropFirst()))
        #expect(saved.count == 24)
    }

    @Test func deletingTheGeneratingChatFromAnotherStopsItsReply() async throws {
        let harness = try await Harness()
        defer { harness.tearDown() }
        let a = try await harness.streamingConversation()
        let b = harness.chat.newConversation(model: "m")
        #expect(harness.chat.selectedID == b)
        #expect(harness.chat.generatingConversation == a)

        harness.chat.delete(a)
        #expect(!harness.chat.isGenerating)
        #expect(harness.chat.conversations.contains { $0.id == a } == false)
        #expect(try await eventually { harness.server.record.cancelledOperations == ["op-1"] })
        // B is free to send at once.
        #expect(harness.chat.send("Next", to: b))
        harness.chat.stop()
    }

    @Test func deletingAnotherChatLeavesTheReplyGenerating() async throws {
        let harness = try await Harness()
        defer { harness.tearDown() }
        let a = try await harness.streamingConversation()
        let b = harness.chat.newConversation(model: "m")

        harness.chat.delete(b)
        #expect(harness.chat.isGenerating)
        #expect(harness.chat.generatingConversation == a)
        try await Task.sleep(for: .milliseconds(200))
        #expect(harness.server.record.cancelledOperations.isEmpty)
        guard case .assistant(_, _, _, .streaming) = harness.reply(in: a) else {
            Issue.record("A's reply stopped: \(String(describing: harness.reply(in: a)))"); return
        }
        harness.chat.stop()
        #expect(try await eventually { harness.server.record.cancelledOperations == ["op-1"] })
    }
}
