import Foundation

/// Lifecycle of one assistant reply. Exactly one state applies at a time.
public enum ReplyState: Hashable, Sendable, Codable {
    case streaming
    case completed(GenerationStats)
    case stopped
    case failed(message: String)
}

public struct ChatMessage: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public let date: Date
    public var body: MessageBody

    public init(id: UUID = UUID(), date: Date = Date(), body: MessageBody) {
        self.id = id
        self.date = date
        self.body = body
    }

    public var role: ChatRole {
        switch body {
        case .user: .user
        case .assistant: .assistant
        }
    }

    /// The turn replayed to the server as conversation history.
    public var turn: ChatTurn? {
        switch body {
        case .user(let text, _):
            return ChatTurn(role: .user, content: text)
        case .assistant(let text, let reasoning, _, let state):
            if case .failed = state { return nil }
            return ChatTurn(role: .assistant, content: text, reasoning: reasoning)
        }
    }
}

public struct Conversation: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    /// The server the conversation talks to; its model selector means
    /// nothing on another server.
    public let instanceID: UUID
    public var title: String
    public var model: String
    public var updatedAt: Date
    public var messages: [ChatMessage]

    public init(
        id: UUID = UUID(), instanceID: UUID, title: String = "New Chat", model: String,
        updatedAt: Date = Date(), messages: [ChatMessage] = []
    ) {
        self.id = id
        self.instanceID = instanceID
        self.title = title
        self.model = model
        self.updatedAt = updatedAt
        self.messages = messages
    }

    public var isStreaming: Bool {
        guard case .assistant(_, _, _, .streaming) = messages.last?.body else { return false }
        return true
    }

    /// Prompt plus completion tokens of the latest finished reply.
    public var contextTokens: UInt64? {
        for message in messages.reversed() {
            if case .assistant(_, _, _, .completed(let stats)) = message.body {
                return stats.promptTokens + stats.completionTokens
            }
        }
        return nil
    }

    public var subtitle: String {
        Conversation.modelName(model)
    }

    /// A readable name for a selector: a repository's last part, or the
    /// repository inside a Hugging Face cache path
    /// (`…/models--owner--name/snapshots/<commit>` → `name`).
    public static func modelName(_ selector: String) -> String {
        let parts = selector.split(separator: "/").map(String.init)
        if let snapshots = parts.lastIndex(of: "snapshots"), snapshots > 0 {
            let repository = parts[snapshots - 1]
            return repository.components(separatedBy: "--").last ?? repository
        }
        // A local directory named like the cache, `owner--name`.
        if selector.hasPrefix("/"), let last = parts.last, last.contains("--") {
            return last.components(separatedBy: "--").last ?? last
        }
        return parts.last ?? selector
    }
}

extension Conversation {
    private enum CodingKeys: String, CodingKey {
        case id, instanceID, title, model, updatedAt, messages
    }

    /// Chats saved before conversations were tied to a server have no
    /// `instanceID`; they belong to This Mac.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            instanceID: try container.decodeIfPresent(UUID.self, forKey: .instanceID) ?? InstanceRecord.thisMacID,
            title: try container.decode(String.self, forKey: .title),
            model: try container.decode(String.self, forKey: .model),
            updatedAt: try container.decode(Date.self, forKey: .updatedAt),
            messages: try container.decode([ChatMessage].self, forKey: .messages)
        )
    }
}
