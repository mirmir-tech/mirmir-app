import Foundation

public enum MessageBody: Hashable, Sendable {
    case user(text: String, image: MessageImage?)
    case assistant(text: String, reasoning: String, thinkingSeconds: Double?, state: ReplyState)
}

/// The layout Swift synthesizes for an enum with associated values
/// (`{"user": {"text": …}}`), written out so chats saved with the former
/// `hasImage` flag still load: a flagged image is `unavailable`.
extension MessageBody: Codable {
    private enum Case: String, CodingKey {
        case user, assistant
    }

    private enum UserKeys: String, CodingKey {
        case text, image, hasImage
    }

    private enum AssistantKeys: String, CodingKey {
        case text, reasoning, thinkingSeconds, state
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: Case.self)
        if container.contains(.user) {
            let user = try container.nestedContainer(keyedBy: UserKeys.self, forKey: .user)
            let legacy = try user.decodeIfPresent(Bool.self, forKey: .hasImage) == true
            let image = try user.decodeIfPresent(MessageImage.self, forKey: .image) ?? (legacy ? .unavailable : nil)
            self = .user(text: try user.decode(String.self, forKey: .text), image: image)
        } else {
            let assistant = try container.nestedContainer(keyedBy: AssistantKeys.self, forKey: .assistant)
            self = .assistant(
                text: try assistant.decode(String.self, forKey: .text),
                reasoning: try assistant.decode(String.self, forKey: .reasoning),
                thinkingSeconds: try assistant.decodeIfPresent(Double.self, forKey: .thinkingSeconds),
                state: try assistant.decode(ReplyState.self, forKey: .state)
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: Case.self)
        switch self {
        case .user(let text, let image):
            var user = container.nestedContainer(keyedBy: UserKeys.self, forKey: .user)
            try user.encode(text, forKey: .text)
            try user.encodeIfPresent(image, forKey: .image)
        case .assistant(let text, let reasoning, let thinkingSeconds, let state):
            var assistant = container.nestedContainer(keyedBy: AssistantKeys.self, forKey: .assistant)
            try assistant.encode(text, forKey: .text)
            try assistant.encode(reasoning, forKey: .reasoning)
            try assistant.encodeIfPresent(thinkingSeconds, forKey: .thinkingSeconds)
            try assistant.encode(state, forKey: .state)
        }
    }
}
