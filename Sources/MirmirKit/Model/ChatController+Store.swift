import Foundation

/// Saving chats and keeping their images.
extension ChatController {
    /// The store this session saves to: none for previews, and none when
    /// the saved chats could not be read or copied aside, so the file is
    /// never written over.
    var savingStore: ChatStore? {
        if case .notSaved = loadIssue { return nil }
        return store
    }

    /// Dismisses a load issue that was news. One that holds for the whole
    /// session (chats are not being saved) stays.
    public func dismissLoadIssue() {
        if loadIssue?.isPersistent == false { loadIssue = nil }
    }

    func persist() {
        guard let file = savingStore?.file else { return }
        let snapshot = conversations
        saver.async { try? file.save(snapshot) }
    }

    /// Waits for the saves queued so far.
    func flushSaves() {
        saver.sync {}
    }

    /// Keeps a new image: in the attachment store when chats are saved,
    /// else in memory for this session.
    func keep(_ image: Data) throws -> UUID {
        if let attachments = savingStore?.attachments { return try attachments.save(image) }
        let id = UUID()
        sessionImages[id] = image
        return id
    }

    func imageData(_ id: UUID) throws -> Data {
        if let data = sessionImages[id] { return data }
        guard let attachments = store?.attachments else { throw CocoaError(.fileReadNoSuchFile) }
        return try attachments.load(id)
    }

    /// A reply still streaming when the app quit is stored as stopped.
    static func settled(_ conversation: Conversation) -> Conversation {
        var conversation = conversation
        for index in conversation.messages.indices {
            if case .assistant(let text, let reasoning, let seconds, .streaming) = conversation.messages[index].body {
                conversation.messages[index].body = .assistant(text: text, reasoning: reasoning, thinkingSeconds: seconds, state: .stopped)
            }
        }
        return conversation
    }
}
