import Foundation

extension Conversation {
    /// The request for the reply that follows the last message: the history
    /// without failed replies, and the conversation's image. Requests are
    /// stateless, so the image is sent again with every turn, marked at the
    /// turn it was attached to. libmir takes one image per request: a newer
    /// attachment replaces the older one, whose turn then goes as text.
    func request(
        replyingTo reply: UUID, maxTokens: UInt64?, temperature: Float?, image load: (UUID) -> Data?
    ) -> GenerationRequest {
        var turns: [ChatTurn] = []
        var image: TurnImage?
        for message in messages where message.id != reply {
            guard let turn = message.turn else { continue }
            if case .user(_, .stored(let id)) = message.body, let data = load(id) {
                image = TurnImage(data: data, turn: turns.count)
            }
            turns.append(turn)
        }
        return GenerationRequest(model: model, turns: turns, maxTokens: maxTokens, temperature: temperature, image: image)
    }

    /// Images this conversation keeps in the attachment store.
    var storedImages: [UUID] {
        messages.compactMap { message in
            if case .user(_, .stored(let id)) = message.body { id } else { nil }
        }
    }
}
