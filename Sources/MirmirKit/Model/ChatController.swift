import Foundation
import Observation

/// Conversations and the one generation streaming at a time.
@MainActor
@Observable
public final class ChatController {
    public private(set) var conversations: [Conversation]
    public var selectedID: UUID?
    public var temperature: Float?
    public var maxTokens: UInt64?

    weak var model: AppModel?
    private let file = JSONFile<[Conversation]>(name: "chats.json")
    private var generation: Task<Void, Never>?
    private var operationID: String?

    init() {
        conversations = (file.load() ?? []).map(Self.settled).sorted { $0.updatedAt > $1.updatedAt }
        selectedID = conversations.first?.id
    }

    public var selected: Conversation? {
        conversations.first { $0.id == selectedID }
    }

    public var isGenerating: Bool { generation != nil }

    @discardableResult
    public func newConversation(model selector: String? = nil) -> UUID {
        let selector = selector ?? model?.primaryModel.map { model?.servingSelector(for: $0) ?? $0.selector } ?? ""
        let conversation = Conversation(model: selector)
        conversations.insert(conversation, at: 0)
        selectedID = conversation.id
        persist()
        return conversation.id
    }

    public func delete(_ id: UUID) {
        if id == selectedID { stop() }
        conversations.removeAll { $0.id == id }
        if selectedID == id { selectedID = conversations.first?.id }
        persist()
    }

    public func setModel(_ selector: String, for id: UUID) {
        update(id) { $0.model = selector }
    }

    public func send(_ text: String, image: Data? = nil) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, generation == nil, let connection = model?.connection else { return }
        let id = selectedID ?? newConversation()
        if conversations.first(where: { $0.id == id })?.model.isEmpty == true, let loaded = model?.primaryModel {
            let selector = model?.servingSelector(for: loaded) ?? loaded.selector
            update(id) { $0.model = selector }
        }
        guard let conversation = conversations.first(where: { $0.id == id }), !conversation.model.isEmpty else {
            model?.notice = "Choose a loaded model before sending."
            return
        }
        let reply = ChatMessage(body: .assistant(text: "", reasoning: "", thinkingSeconds: nil, state: .streaming))
        update(id) { conversation in
            if conversation.messages.isEmpty { conversation.title = String(text.prefix(60)) }
            conversation.messages.append(ChatMessage(body: .user(text: text, hasImage: image != nil)))
            conversation.messages.append(reply)
        }
        let turns = (conversations.first { $0.id == id }?.messages ?? []).dropLast().compactMap(\.turn)
        let request = GenerationRequest(
            model: conversation.model, turns: Array(turns), maxTokens: maxTokens, temperature: temperature, image: image
        )
        let stream = ReplyAccumulator()
        generation = Task {
            do {
                try await connection.generate(request) { event in
                    await self.receive(event, into: stream, conversation: id, reply: reply.id)
                }
                finish(id, reply.id, stream: stream, state: nil)
            } catch {
                let state: ReplyState = Task.isCancelled ? .stopped : .failed(message: error.localizedDescription)
                finish(id, reply.id, stream: stream, state: state)
            }
        }
    }

    /// Cancels the RPC and asks the server to cancel the operation, which
    /// frees the session even if the disconnect is observed late.
    public func stop() {
        guard let generation else { return }
        generation.cancel()
        if let operationID, let connection = model?.connection {
            Task { _ = try? await connection.cancel(operationID: operationID) }
        }
    }

    private func receive(_ event: GenerationEvent, into stream: ReplyAccumulator, conversation: UUID, reply: UUID) {
        switch event {
        case .started(let id):
            operationID = id
        case .token(let text, let reasoning):
            stream.append(text, reasoning: reasoning)
        case .completed(let text, let reasoning, let stats):
            stream.complete(text: text, reasoning: reasoning, stats: stats)
        }
        write(stream, state: stream.stats.map(ReplyState.completed) ?? .streaming, conversation: conversation, reply: reply)
    }

    private func finish(_ conversation: UUID, _ reply: UUID, stream: ReplyAccumulator, state: ReplyState?) {
        let final = state ?? stream.stats.map(ReplyState.completed) ?? .stopped
        write(stream, state: final, conversation: conversation, reply: reply)
        generation = nil
        operationID = nil
        persist()
    }

    private func write(_ stream: ReplyAccumulator, state: ReplyState, conversation: UUID, reply: UUID) {
        update(conversation, persisting: false) { conversation in
            guard let index = conversation.messages.firstIndex(where: { $0.id == reply }) else { return }
            conversation.messages[index].body = .assistant(
                text: stream.text, reasoning: stream.reasoning, thinkingSeconds: stream.thinkingSeconds, state: state
            )
        }
    }

    private func update(_ id: UUID, persisting: Bool = true, _ change: (inout Conversation) -> Void) {
        guard let index = conversations.firstIndex(where: { $0.id == id }) else { return }
        change(&conversations[index])
        conversations[index].updatedAt = Date()
        if persisting { persist() }
    }

    private func persist() {
        try? file.save(conversations)
    }

    /// A reply still streaming when the app quit is stored as stopped.
    private static func settled(_ conversation: Conversation) -> Conversation {
        var conversation = conversation
        for index in conversation.messages.indices {
            if case .assistant(let text, let reasoning, let seconds, .streaming) = conversation.messages[index].body {
                conversation.messages[index].body = .assistant(text: text, reasoning: reasoning, thinkingSeconds: seconds, state: .stopped)
            }
        }
        return conversation
    }
}

/// Collects streamed fragments and measures how long the model reasoned.
@MainActor
final class ReplyAccumulator {
    private(set) var text = ""
    private(set) var reasoning = ""
    private(set) var stats: GenerationStats?
    private var reasoningStarted: Date?
    private(set) var thinkingSeconds: Double?

    func append(_ fragment: String, reasoning isReasoning: Bool) {
        if isReasoning {
            if reasoningStarted == nil { reasoningStarted = Date() }
            reasoning += fragment
        } else {
            if let started = reasoningStarted, thinkingSeconds == nil {
                thinkingSeconds = Date().timeIntervalSince(started)
            }
            text += fragment
        }
    }

    func complete(text: String, reasoning: String, stats: GenerationStats) {
        if !text.isEmpty { self.text = text }
        if !reasoning.isEmpty { self.reasoning = reasoning }
        if let started = reasoningStarted, thinkingSeconds == nil {
            thinkingSeconds = Date().timeIntervalSince(started)
        }
        self.stats = stats
    }
}
