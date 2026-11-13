import Foundation
import Testing
@testable import MirmirKit

/// An image attached in the app reaches vision inference. Opt-in: needs a
/// running server and a vision model it can load.
///
///     MIRMIR_E2E_SOCKET=/path/mirmir.sock MIRMIR_E2E_VISION_MODEL=/path/model \
///     MIRMIR_E2E_IMAGE=/path/image.png swift test --filter VisionEndToEnd
@Suite("Vision end to end", .enabled(if: ProcessInfo.processInfo.environment["MIRMIR_E2E_SOCKET"] != nil))
struct VisionEndToEndTests {
    private actor Reply {
        var text = ""
        var streamed = ""
        var stats: GenerationStats?
        var thought = ""
        func token(_ text: String, reasoning: Bool) { if reasoning { thought += text } else { streamed += text } }
        func complete(_ text: String, _ stats: GenerationStats) { self.text = text; self.stats = stats }
        /// The answer: the completion's text, else what streamed.
        var answer: String { text.isEmpty ? streamed : text }
    }

    @Test(.timeLimit(.minutes(10))) func anAttachedImageReachesVisionInference() async throws {
        let environment = ProcessInfo.processInfo.environment
        let model = try #require(environment["MIRMIR_E2E_VISION_MODEL"])
        let image = try Data(contentsOf: URL(fileURLWithPath: try #require(environment["MIRMIR_E2E_IMAGE"])))
        let connection = try await RuntimeConnection.connect(socket: try #require(environment["MIRMIR_E2E_SOCKET"]))
        defer { connection.close() }
        try await connection.load(selector: model) { _ in }

        // What ChatController.send builds for a message with an attachment.
        let request = GenerationRequest(
            model: model, turns: [ChatTurn(role: .user, content: "What is in this image? Answer in one sentence.")],
            maxTokens: 1024, temperature: 0, image: image
        )
        let reply = Reply()
        try await connection.generate(request) { event in
            switch event {
            case .token(let text, let reasoning): await reply.token(text, reasoning: reasoning)
            case .completed(let text, _, let stats): await reply.complete(text, stats)
            case .started: break
            }
        }
        let stats = try #require(await reply.stats)
        // The image's tokens are part of the prompt, far beyond the question.
        #expect(stats.promptTokens > 64)
        let answer = await reply.answer
        print("vision reasoning: \(await reply.thought.prefix(300))")
        print("vision reply (\(stats.promptTokens) prompt tokens, \(stats.finishReason)): \(answer)")
        #expect(!answer.isEmpty)
    }
}
