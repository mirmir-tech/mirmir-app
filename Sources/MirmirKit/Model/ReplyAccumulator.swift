import Foundation

/// Collects streamed fragments and measures how long the model reasoned.
@MainActor
final class ReplyAccumulator {
    private(set) var text = ""
    private(set) var reasoning = ""
    private(set) var stats: GenerationStats?
    private var reasoningStarted: Date?
    private(set) var thinkingSeconds: Double?

    func append(_ fragment: String, reasoning isReasoning: Bool) {
        if isReasoning {
            if reasoningStarted == nil { reasoningStarted = Date() }
            reasoning += fragment
        } else {
            if let started = reasoningStarted, thinkingSeconds == nil {
                thinkingSeconds = Date().timeIntervalSince(started)
            }
            text += fragment
        }
    }

    func complete(text: String, reasoning: String, stats: GenerationStats) {
        if !text.isEmpty { self.text = text }
        if !reasoning.isEmpty { self.reasoning = reasoning }
        if let started = reasoningStarted, thinkingSeconds == nil {
            thinkingSeconds = Date().timeIntervalSince(started)
        }
        self.stats = stats
    }
}
