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
        // As the composer does: HEIC and other formats become JPEG.
        let file = try Data(contentsOf: URL(fileURLWithPath: try #require(environment["MIRMIR_E2E_IMAGE"])))
        let image = try ImageNormalizer.normalized(file)
        let connection = try await RuntimeConnection.connect(socket: try #require(environment["MIRMIR_E2E_SOCKET"]))
        defer { connection.close() }
        try await connection.load(selector: model) { _ in }

        // What ChatController.send builds for a message with an attachment.
        let request = GenerationRequest(
            model: model, turns: [ChatTurn(role: .user, content: "What is in this image? Answer in one sentence.")],
            maxTokens: 1024, temperature: 0, image: TurnImage(data: image, turn: 0)
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

        // A follow-up turn, built from the stored conversation as the app
        // does, still shows the model the image.
        let attachments = AttachmentStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let id = try attachments.save(image)
        let next = ChatMessage(body: .assistant(text: "", reasoning: "", thinkingSeconds: nil, state: .streaming))
        let conversation = Conversation(instanceID: UUID(), model: model, messages: [
            ChatMessage(body: .user(text: "What is in this image? Answer in one sentence.", image: .stored(id))),
            ChatMessage(body: .assistant(text: answer, reasoning: "", thinkingSeconds: nil, state: .completed(stats))),
            ChatMessage(body: .user(text: "What color is the background? Answer with one word.", image: nil)),
            next,
        ])
        let followUp = Reply()
        try await connection.generate(conversation.request(replyingTo: next.id, maxTokens: 1024, temperature: 0, image: attachments.load)) { event in
            switch event {
            case .token(let text, let reasoning): await followUp.token(text, reasoning: reasoning)
            case .completed(let text, _, let stats): await followUp.complete(text, stats)
            case .started: break
            }
        }
        let second = try #require(await followUp.stats)
        print("vision follow-up (\(second.promptTokens) prompt tokens): \(await followUp.answer)")
        #expect(second.promptTokens > stats.promptTokens)
        #expect(!(await followUp.answer).isEmpty)
    }
}
