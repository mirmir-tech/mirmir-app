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
    /// Where chats and their images are kept; nil for previews, whose
    /// sample chats stay in memory.
    let store: ChatStore?
    /// Why the saved chats did not load as written; shown above the list.
    public internal(set) var loadIssue: ChatLoadIssue?
    /// Stored images a request needed but could not read, shown as
    /// unavailable on their messages. Read again on every send.
    public internal(set) var unreadableImages: Set<UUID> = []
    /// Images of a session whose chats are not saved: previews, and a
    /// session that must leave an unreadable `chats.json` untouched.
    @ObservationIgnored var sessionImages: [UUID: Data] = [:]
    /// Serial, so saves land in order; encoding every chat stays off the
    /// main actor.
    let saver = DispatchQueue(label: "tech.mirmir.app.chats", qos: .utility)
    private var generation: Task<Void, Never>?
    private var operationID: String?
    /// Streaming publishes at most this often; every write re-renders the
    /// thread and the conversation list.
    private static let streamInterval: Duration = .milliseconds(50)
    private var lastStreamWrite: ContinuousClock.Instant?
    /// What each conversation's composer holds until it is sent.
    public internal(set) var drafts: [UUID: ComposerDraft] = [:]

    init(store: ChatStore?) {
        let history = store?.load() ?? ChatHistory()
        self.store = store
        loadIssue = history.issue
        conversations = history.conversations.map(Self.settled).sorted { $0.updatedAt > $1.updatedAt }
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
        if let conversation = conversations.first(where: { $0.id == id }) {
            conversation.storedImages.forEach { sessionImages[$0] = nil }
            if let attachments = savingStore?.attachments { conversation.storedImages.forEach(attachments.remove) }
        }
        drafts[id] = nil
        conversations.removeAll { $0.id == id }
        if selectedID == id { selectedID = visibleConversations.first?.id }
        persist()
    }

    public func setModel(_ selector: String, for id: UUID) {
        update(id) { $0.model = selector }
    }

    /// Sends a message to `conversation`, else the selected one or a new
    /// one; returns whether it was sent. `image` must already be normalized
    /// (`ImageNormalizer`); it is kept with the message, so later turns and
    /// a reopened chat still send it. When the conversation's newest image
    /// cannot be read nothing is sent: the notice says so, the draft stays,
    /// and attaching the image again (or starting a new chat) continues.
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
                attached = .stored(try keep(image))
            } catch {
                model?.notice = "Could not keep the image: \(error.localizedDescription)"
                return false
            }
        }
        let user = ChatMessage(body: .user(text: text, image: attached))
        let reply = ChatMessage(body: .assistant(text: "", reasoning: "", thinkingSeconds: nil, state: .streaming))
        var pending = conversation
        pending.messages += [user, reply]
        let request: GenerationRequest
        var read: UUID?
        do {
            request = try pending.request(replyingTo: reply.id, maxTokens: maxTokens, temperature: temperature) { stored in
                read = stored
                // The new image is in memory; earlier ones come from disk.
                if case .stored(stored) = attached, let image { return image }
                return try imageData(stored)
            }
        } catch {
            if case .imageUnavailable(let id, _) = error { unreadableImages.insert(id) }
            model?.notice = error.localizedDescription
            return false
        }
        if let read { unreadableImages.remove(read) }
        update(id) { conversation in
            if conversation.messages.isEmpty { conversation.title = String(text.prefix(60)) }
            conversation.messages += [user, reply]
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
}
