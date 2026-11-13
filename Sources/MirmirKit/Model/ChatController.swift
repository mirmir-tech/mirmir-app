import Foundation
import Observation

/// Conversations and the one generation streaming at a time.
@MainActor
@Observable
public final class ChatController {
    public internal(set) var conversations: [Conversation]
    public var selectedID: UUID?
    public var temperature: Float?
    public var maxTokens: UInt64?

    weak var model: AppModel?
    private let file = JSONFile<[Conversation]>(name: "chats.json")
    /// Serial, so saves land in order; encoding every chat stays off the
    /// main actor.
    private let saver = DispatchQueue(label: "tech.mirmir.app.chats", qos: .utility)
    private var generation: Task<Void, Never>?
    private var operationID: String?
    /// Streaming publishes at most this often; every write re-renders the
    /// thread and the conversation list.
    private static let streamInterval: Duration = .milliseconds(50)
    private var lastStreamWrite: ContinuousClock.Instant?
    /// Off for previews, so sample chats never reach `chats.json`.
    var persists = true
    /// Images attached to messages, sent again with every later turn.
    var attachments = AttachmentStore()
    /// What each conversation's composer holds until it is sent.
    public internal(set) var drafts: [UUID: ComposerDraft] = [:]

    init() {
        conversations = (file.load() ?? []).map(Self.settled).sorted { $0.updatedAt > $1.updatedAt }
        selectedID = conversations.first?.id
    }

    /// The current server's conversations; the others stay saved for when
    /// that server is current again.
    public var visibleConversations: [Conversation] {
        guard let instance = model?.currentInstanceID else { return [] }
        return conversations.filter { $0.instanceID == instance }
    }

    public var selected: Conversation? {
        visibleConversations.first { $0.id == selectedID }
    }

    /// Called when the current server changes: select its latest chat.
    func instanceChanged() {
        stop()
        selectedID = visibleConversations.first?.id
    }

    public var isGenerating: Bool { generation != nil }

    @discardableResult
    public func newConversation(model selector: String? = nil) -> UUID {
        let selector = selector ?? model?.primaryModel.map { model?.servingSelector(for: $0) ?? $0.selector } ?? ""
        guard let instance = model?.currentInstanceID else { return UUID() }
        let conversation = Conversation(instanceID: instance, model: selector)
        conversations.insert(conversation, at: 0)
        selectedID = conversation.id
        persist()
        return conversation.id
    }

    public func delete(_ id: UUID) {
        if id == selectedID { stop() }
        if persists, let conversation = conversations.first(where: { $0.id == id }) {
            conversation.storedImages.forEach(attachments.remove)
        }
        drafts[id] = nil
        conversations.removeAll { $0.id == id }
        if selectedID == id { selectedID = visibleConversations.first?.id }
        persist()
    }

    public func setModel(_ selector: String, for id: UUID) {
        update(id) { $0.model = selector }
    }

    /// Sends a message. `image` must already be normalized for the server
    /// (`ImageNormalizer`); it is kept with the message, so later turns and
    /// a reopened chat still send it.
    /// Sends to `conversation`, else the selected one or a new one. Returns
    /// whether the message was sent.
    @discardableResult
    public func send(_ text: String, image: Data? = nil, to conversation: UUID? = nil) -> Bool {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, generation == nil, let connection = model?.connection else { return false }
        let id = conversation ?? selected?.id ?? newConversation()
        if conversations.first(where: { $0.id == id })?.model.isEmpty == true, let loaded = model?.primaryModel {
            let selector = model?.servingSelector(for: loaded) ?? loaded.selector
            update(id) { $0.model = selector }
        }
        guard let conversation = conversations.first(where: { $0.id == id }), !conversation.model.isEmpty else {
            model?.notice = "Choose a loaded model before sending."
            return false
        }
        var attached: MessageImage?
        if let image {
            do {
                attached = .stored(persists ? try attachments.save(image) : UUID())
            } catch {
                model?.notice = "Could not keep the image: \(error.localizedDescription)"
                return false
            }
        }
        let reply = ChatMessage(body: .assistant(text: "", reasoning: "", thinkingSeconds: nil, state: .streaming))
        update(id) { conversation in
            if conversation.messages.isEmpty { conversation.title = String(text.prefix(60)) }
            conversation.messages.append(ChatMessage(body: .user(text: text, image: attached)))
            conversation.messages.append(reply)
        }
        guard let updated = conversations.first(where: { $0.id == id }) else { return false }
        let attachments = attachments
        let request = updated.request(replyingTo: reply.id, maxTokens: maxTokens, temperature: temperature) { stored in
            // The new image is in memory; earlier ones come from disk.
            if case .stored(stored) = attached, let image { image } else { attachments.load(stored) }
        }
        let stream = ReplyAccumulator()
        generation = Task {
            do {
                try await connection.generate(request) { event in
                    await self.receive(event, into: stream, conversation: id, reply: reply.id)
                }
                finish(id, reply.id, stream: stream, state: nil)
            } catch {
                let cancelled = Task.isCancelled || ConnectionError.wrap(error) == .cancelled
                let state: ReplyState = cancelled ? .stopped : .failed(message: error.localizedDescription)
                finish(id, reply.id, stream: stream, state: state)
            }
        }
        return true
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
            return
        case .token(let text, let reasoning):
            stream.append(text, reasoning: reasoning)
            let now = ContinuousClock.now
            if let last = lastStreamWrite, now - last < Self.streamInterval { return }
            lastStreamWrite = now
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
        lastStreamWrite = nil
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
        guard persists else { return }
        let snapshot = conversations
        let file = file
        saver.async { try? file.save(snapshot) }
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
