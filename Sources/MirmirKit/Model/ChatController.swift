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
    /// Why the latest save failed; nil once a save succeeds.
    public internal(set) var saveFailure: ChatSaveFailure?
    /// Numbers saves, so only the newest one's outcome is reported.
    @ObservationIgnored var saveGeneration = 0
    @ObservationIgnored var retryTask: Task<Void, Never>?
    /// Stored images a request needed but could not read, shown as
    /// unavailable on their messages. Read again on every send.
    public internal(set) var unreadableImages: Set<UUID> = []
    /// Images of a session whose chats are not saved: previews, and a
    /// session that must leave an unreadable `chats.json` untouched.
    @ObservationIgnored var sessionImages: [UUID: Data] = [:]
    /// Images of deleted chats, removed from the attachment store only once
    /// a save without those chats is on disk.
    @ObservationIgnored var discardedImages: Set<UUID> = []
    /// Whether a session that must not save over unreadable history changed
    /// its chats; quitting then loses those changes.
    public internal(set) var hasUnsavedChanges = false
    /// Serial, so saves land in order; encoding every chat stays off the
    /// main actor.
    let saver = DispatchQueue(label: "tech.mirmir.app.chats", qos: .utility)
    /// The reply streaming now, with the conversation that owns it.
    private var active: ActiveGeneration?
    /// Streaming publishes at most this often; every write re-renders the
    /// thread and the conversation list.
    private static let streamInterval: Duration = .milliseconds(50)
    private var lastStreamWrite: ContinuousClock.Instant?
    /// What each conversation's composer holds until it is sent.
    public internal(set) var drafts: [UUID: ComposerDraft] = [:]

    /// Whether the saved chats were read; until then nothing is saved, so
    /// the file another copy of the app may still write is not replaced.
    @ObservationIgnored var historyLoaded = false

    /// `loadingNow` false waits for `loadHistory`, as the app does until an
    /// older copy of itself has quit and saved its chats.
    init(store: ChatStore?, loadingNow: Bool = true) {
        self.store = store
        conversations = []
        if loadingNow { loadHistory() }
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

    public var isGenerating: Bool { active != nil }

    /// The conversation whose reply is streaming, if any.
    public var generatingConversation: UUID? { active?.conversation }

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
        guard !text.isEmpty, active == nil, let connection = model?.connection else { return false }
        let id = conversation ?? selected?.id ?? newConversation()
        if conversations.first(where: { $0.id == id })?.model.isEmpty == true, let loaded = model?.primaryModel {
            let selector = model?.servingSelector(for: loaded) ?? loaded.selector
            update(id) { $0.model = selector }
        }
        guard let conversation = conversations.first(where: { $0.id == id }), !conversation.model.isEmpty else {
            model?.notice = "Choose a loaded model before sending."
            return false
        }
        if let refusal = imageRefusal(for: conversation, attaching: image != nil) {
            model?.notice = refusal.localizedDescription
            return false
        }
        var attached: MessageImage?
        if let image {
            guard image.count <= MessageLimits.imageBytes else {
                model?.notice = ImageNormalizationError.tooLarge(bytes: image.count).localizedDescription
                return false
            }
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
        // Runs its main-actor parts only after `active` is set below.
        let task = Task {
            do {
                try await connection.generate(request) { event in
                    await self.receive(event, reply: reply.id)
                }
                finish(reply.id, state: nil)
            } catch {
                let cancelled = Task.isCancelled || ConnectionError.wrap(error) == .cancelled
                finish(reply.id, state: cancelled ? .stopped : .failed(message: error.localizedDescription))
            }
        }
        active = ActiveGeneration(
            conversation: id, reply: reply.id, stream: ReplyAccumulator(), task: task, connection: connection
        )
        return true
    }

    /// Ends the streaming reply now, keeping what streamed as stopped (as
    /// completed if its completion already arrived). Cancels the RPC and asks
    /// the server that runs it to cancel the operation, which frees the
    /// session even if the disconnect is observed late. Events and the
    /// finish that arrive afterwards belong to no active reply and are
    /// dropped.
    public func stop() {
        guard let current = active else { return }
        active = nil
        lastStreamWrite = nil
        current.task.cancel()
        if let operationID = current.operationID {
            let connection = current.connection
            Task { _ = try? await connection.cancel(operationID: operationID) }
        }
        let state = current.stream.stats.map(ReplyState.completed) ?? .stopped
        write(current.stream, state: state, conversation: current.conversation, reply: current.reply)
        persist()
    }

    /// Call when the app terminates, before the connection closes: stops the
    /// streaming reply as Stop does and saves every chat before returning.
    /// Returns why the chats are not on disk, if they are not.
    @discardableResult
    public func terminate() -> ChatSaveFailure? {
        stop()
        return saveNow()
    }

    private func receive(_ event: GenerationEvent, reply: UUID) {
        guard let current = active, current.reply == reply else { return }
        let stream = current.stream
        switch event {
        case .started(let id):
            active?.operationID = id
            return
        case .token(let text, let reasoning):
            stream.append(text, reasoning: reasoning)
            let now = ContinuousClock.now
            if let last = lastStreamWrite, now - last < Self.streamInterval { return }
            lastStreamWrite = now
        case .completed(let text, let reasoning, let stats):
            stream.complete(text: text, reasoning: reasoning, stats: stats)
        }
        let state = stream.stats.map(ReplyState.completed) ?? .streaming
        write(stream, state: state, conversation: current.conversation, reply: reply)
    }

    /// Records how the RPC ended, unless the reply was already ended by
    /// `stop` (or a newer one replaced it).
    private func finish(_ reply: UUID, state: ReplyState?) {
        guard let current = active, current.reply == reply else { return }
        active = nil
        lastStreamWrite = nil
        let final = state ?? current.stream.stats.map(ReplyState.completed) ?? .stopped
        write(current.stream, state: final, conversation: current.conversation, reply: reply)
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
