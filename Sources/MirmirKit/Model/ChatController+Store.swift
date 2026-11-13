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

    /// Queues a save of every chat. Its outcome updates `saveFailure`; a
    /// failure keeps the chats in memory and retries them later.
    func persist() {
        guard let file = savingStore?.file else { return }
        saveGeneration += 1
        let generation = saveGeneration
        let snapshot = conversations
        saver.async { [weak self] in
            let result = Result { try file.save(snapshot) }
            Task { @MainActor in self?.saved(result, generation: generation) }
        }
    }

    /// Saves every chat now, after the saves already queued, and returns
    /// why they are not on disk, if they are not.
    @discardableResult
    public func saveNow() -> ChatSaveFailure? {
        guard let file = savingStore?.file else { return nil }
        saveGeneration += 1
        let snapshot = conversations
        let result = saver.sync { Result { try file.save(snapshot) } }
        saved(result, generation: saveGeneration)
        return saveFailure
    }

    /// Saves again after a failure, as the banner's Retry does.
    public func retrySaving() {
        persist()
    }

    /// Delay before a failed save is tried again on its own.
    static let saveRetryDelay: Duration = .seconds(10)

    private func saved(_ result: Result<Void, any Error>, generation: Int) {
        guard generation == saveGeneration else { return }
        retryTask?.cancel()
        switch result {
        case .success:
            saveFailure = nil
        case .failure(let error):
            saveFailure = ChatSaveFailure(reason: error.localizedDescription)
            retryTask = Task { [weak self] in
                try? await Task.sleep(for: Self.saveRetryDelay)
                guard !Task.isCancelled else { return }
                self?.persist()
            }
        }
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
