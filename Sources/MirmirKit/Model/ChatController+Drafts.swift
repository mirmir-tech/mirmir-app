import Foundation

/// The image in a composer: being converted for the server, or ready.
public enum DraftImage: Hashable, Sendable {
    /// Converting; the token identifies this attachment, so a result that
    /// arrives after it was replaced or removed is dropped.
    case preparing(UUID)
    case ready(Data)
}

/// What a conversation's composer holds until it is sent. Kept per
/// conversation, so switching chats never carries text or an image over.
public struct ComposerDraft: Hashable, Sendable {
    public var text = ""
    public var image: DraftImage?

    public init(text: String = "", image: DraftImage? = nil) {
        self.text = text
        self.image = image
    }

    public var isPreparingImage: Bool {
        if case .preparing = image { true } else { false }
    }
}

extension ChatController {
    public func draft(for conversation: UUID) -> ComposerDraft {
        drafts[conversation] ?? ComposerDraft()
    }

    public func setDraftText(_ text: String, for conversation: UUID) {
        drafts[conversation, default: ComposerDraft()].text = text
    }

    /// Takes the image out of the composer; one still converting is
    /// dropped when it finishes.
    public func removeDraftImage(for conversation: UUID) {
        drafts[conversation]?.image = nil
    }

    /// Why a message to `conversation` must not be sent: it would carry an
    /// image (`attaching` one now, or one from the history) to a listed
    /// model without image input. A model the server does not list is not
    /// judged; the server answers for it.
    func imageRefusal(for conversation: Conversation, attaching: Bool) -> RequestError? {
        guard attaching || conversation.sendsStoredImage,
              let listed = model?.model(selector: conversation.model), !listed.imageInput
        else { return nil }
        return .imageNotSupported(model: listed.displayName, origin: attaching ? .composer : .history)
    }

    /// Attaches an image to `conversation`'s composer. `load` reads it and
    /// the conversion runs off the main actor; the result lands in the
    /// conversation it was attached in, and only if no newer attachment
    /// replaced it meanwhile.
    public func attachImage(to conversation: UUID, loading load: @escaping @Sendable () throws -> Data) async {
        let token = UUID()
        drafts[conversation, default: ComposerDraft()].image = .preparing(token)
        let result = await Task.detached(priority: .userInitiated) { () -> Result<Data, any Error> in
            Result { try ImageNormalizer.normalized(try load()) }
        }.value
        guard case .preparing(token) = drafts[conversation]?.image else { return }
        switch result {
        case .success(let data):
            drafts[conversation]?.image = .ready(data)
        case .failure(let error):
            drafts[conversation]?.image = nil
            model?.notice = error.localizedDescription
        }
    }

    /// Sends `conversation`'s draft, only while it is the selected
    /// conversation and its image is ready.
    public func sendDraft(of conversation: UUID) {
        guard conversation == selectedID, let draft = drafts[conversation], !draft.isPreparingImage else { return }
        let image: Data? = if case .ready(let data) = draft.image { data } else { nil }
        if send(draft.text, image: image, to: conversation) { drafts[conversation] = nil }
    }
}
