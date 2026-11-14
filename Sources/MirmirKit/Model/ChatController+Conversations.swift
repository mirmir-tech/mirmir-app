import Foundation

/// Starting and deleting conversations.
extension ChatController {
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

    /// Deletes a conversation; a reply it is still generating is stopped
    /// first, wherever the selection is. Other conversations' replies go on.
    /// Its images are removed after the save without it succeeds, so a chat
    /// that returns after a failed save or a crash still has them.
    public func delete(_ id: UUID) {
        if generatingConversation == id { stop() }
        if let conversation = conversations.first(where: { $0.id == id }) {
            conversation.storedImages.forEach { sessionImages[$0] = nil }
            if savingStore != nil { discardedImages.formUnion(conversation.storedImages) }
        }
        drafts[id] = nil
        conversations.removeAll { $0.id == id }
        if selectedID == id { selectedID = visibleConversations.first?.id }
        persist()
    }
}
