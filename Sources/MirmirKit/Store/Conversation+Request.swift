import Foundation

/// Why a conversation's next request cannot be built.
public enum RequestError: Error, Hashable, Sendable {
    /// The newest image of the conversation, attached at `turn`, could not
    /// be read. The request is not sent: the model would otherwise answer
    /// without it, or about an older image, while the chat shows this one.
    case imageUnavailable(id: UUID, turn: Int)
    /// The request would carry an image, attached now or earlier in the
    /// chat, to a model that reports no image input. It is not sent rather
    /// than sent without the image, which the chat would still show.
    case imageNotSupported(model: String, origin: ImageOrigin)
}

/// Where the image of a request comes from.
public enum ImageOrigin: Hashable, Sendable {
    /// The composer's attachment.
    case composer
    /// An image attached earlier in the conversation, sent with every turn.
    case history
}

extension RequestError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .imageUnavailable:
            "The image attached in this chat could not be read, so the model cannot see it. "
                + "Attach it again to keep talking about it, or start a new chat."
        case .imageNotSupported(let model, .composer):
            "\(model) cannot read images. Remove the image from the message, or choose a vision model."
        case .imageNotSupported(let model, .history):
            "This chat has an image, which \(model) cannot read. Choose a vision model for this chat, "
                + "or start a new chat to continue without the image."
        }
    }
}

extension Conversation {
    /// The request for the reply that follows the last message: the history
    /// without failed replies, and the conversation's image. Requests are
    /// stateless, so the image is sent again with every turn, marked at the
    /// turn it was attached to. libmir takes one image per request: the
    /// newest attachment is sent and older ones go as text. The newest one
    /// is chosen before it is read; when it cannot be read the request
    /// fails rather than fall back to an older image or to text alone. An
    /// image from before the app kept images (`.unavailable`) is known to
    /// be gone and shown so: its turn goes as text.
    func request(
        replyingTo reply: UUID, maxTokens: UInt64?, temperature: Float?, image load: (UUID) throws -> Data
    ) throws(RequestError) -> GenerationRequest {
        var turns: [ChatTurn] = []
        var newest: (id: UUID, turn: Int)?
        for message in messages where message.id != reply {
            guard let turn = message.turn else { continue }
            switch message.body {
            case .user(_, .stored(let id)): newest = (id, turns.count)
            case .user(_, .unavailable): newest = nil
            default: break
            }
            turns.append(turn)
        }
        var image: TurnImage?
        if let newest {
            do {
                image = TurnImage(data: try load(newest.id), turn: newest.turn)
            } catch {
                throw .imageUnavailable(id: newest.id, turn: newest.turn)
            }
        }
        return GenerationRequest(model: model, turns: turns, maxTokens: maxTokens, temperature: temperature, image: image)
    }

    /// Whether the next request sends an image from the history: a stored
    /// image not followed by one known to be gone, as `request` chooses it.
    var sendsStoredImage: Bool {
        for message in messages.reversed() {
            switch message.body {
            case .user(_, .stored): return true
            case .user(_, .unavailable): return false
            default: continue
            }
        }
        return false
    }

    /// Images this conversation keeps in the attachment store.
    var storedImages: [UUID] {
        messages.compactMap { message in
            if case .user(_, .stored(let id)) = message.body { id } else { nil }
        }
    }
}
