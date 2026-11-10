import Foundation

public enum ChatRole: String, Hashable, Sendable, Codable {
    case system, user, assistant
}

/// One turn sent to `Generate`.
public struct ChatTurn: Hashable, Sendable {
    public let role: ChatRole
    public let content: String
    public let reasoning: String?

    public init(role: ChatRole, content: String, reasoning: String? = nil) {
        self.role = role
        self.content = content
        self.reasoning = reasoning
    }
}

public struct GenerationRequest: Sendable {
    public let model: String
    public let turns: [ChatTurn]
    public let maxTokens: UInt64?
    public let temperature: Float?
    public let image: Data?

    public init(model: String, turns: [ChatTurn], maxTokens: UInt64? = nil, temperature: Float? = nil, image: Data? = nil) {
        self.model = model
        self.turns = turns
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.image = image
    }
}

/// Final statistics of one generation, from `Completion`.
public struct GenerationStats: Hashable, Sendable, Codable {
    public let promptTokens: UInt64
    public let completionTokens: UInt64
    public let finishReason: String
    public let elapsedMs: Double
    public let decodeTokensPerSecond: Double?
    public let prefillTokensPerSecond: Double?
    public let ttftMs: Double?

    public init(
        promptTokens: UInt64, completionTokens: UInt64, finishReason: String, elapsedMs: Double,
        decodeTokensPerSecond: Double?, prefillTokensPerSecond: Double?, ttftMs: Double?
    ) {
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.finishReason = finishReason
        self.elapsedMs = elapsedMs
        self.decodeTokensPerSecond = decodeTokensPerSecond
        self.prefillTokensPerSecond = prefillTokensPerSecond
        self.ttftMs = ttftMs
    }
}

public enum GenerationEvent: Sendable {
    case started(operationID: String)
    /// A text fragment on the answer or the reasoning channel.
    case token(text: String, reasoning: Bool)
    case completed(text: String, reasoning: String, stats: GenerationStats)
}
