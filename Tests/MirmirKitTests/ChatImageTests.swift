import Foundation
import Testing
@testable import MirmirKit
#if canImport(ImageIO)
import ImageIO
#endif

/// A conversation keeps its image: every later request sends it again,
/// marked at the turn it was attached to, also after a reload.
@Suite("Images in a conversation")
struct ChatImageTests {
    private func store() throws -> AttachmentStore {
        AttachmentStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
    }

    private func reply(_ state: ReplyState = .completed(.init(
        promptTokens: 1, completionTokens: 1, finishReason: "stop", elapsedMs: 1,
        decodeTokensPerSecond: nil, prefillTokensPerSecond: nil, ttftMs: nil
    )), _ text: String = "A red square.") -> ChatMessage {
        ChatMessage(body: .assistant(text: text, reasoning: "", thinkingSeconds: nil, state: state))
    }

    private func pending() -> ChatMessage {
        ChatMessage(body: .assistant(text: "", reasoning: "", thinkingSeconds: nil, state: .streaming))
    }

    @Test func aFollowUpTurnStillSendsTheImageAtItsOwnTurn() throws {
        let attachments = try store()
        let id = try attachments.save(Data([7, 7, 7]))
        let next = pending()
        let conversation = Conversation(instanceID: UUID(), model: "m", messages: [
            ChatMessage(body: .user(text: "Describe this image", image: .stored(id))), reply(),
            ChatMessage(body: .user(text: "What color is it?", image: nil)), next,
        ])
        let request = conversation.request(replyingTo: next.id, maxTokens: nil, temperature: nil, image: attachments.load)
        #expect(request.image == TurnImage(data: Data([7, 7, 7]), turn: 0))
        #expect(request.wire.messages.map(\.content).first == "<|mirmir_image|>\nDescribe this image")
        #expect(request.wire.messages.last?.content == "What color is it?")
    }

    @Test func theImageSurvivesAReload() throws {
        let attachments = try store()
        let id = try attachments.save(Data([1, 2]))
        let next = pending()
        let saved = Conversation(instanceID: UUID(), model: "m", messages: [
            ChatMessage(body: .user(text: "Look", image: .stored(id))), reply(),
            ChatMessage(body: .user(text: "And now?", image: nil)), next,
        ])
        let loaded = try JSONDecoder.mirmir.decode(Conversation.self, from: JSONEncoder.mirmir.encode(saved))
        #expect(loaded.messages.map(\.body) == saved.messages.map(\.body))
        let request = loaded.request(replyingTo: next.id, maxTokens: nil, temperature: nil, image: attachments.load)
        #expect(request.image == TurnImage(data: Data([1, 2]), turn: 0))
    }

    @Test func aNewerImageReplacesTheOlderOne() throws {
        let attachments = try store()
        let first = try attachments.save(Data([1])), second = try attachments.save(Data([2]))
        let next = pending()
        let conversation = Conversation(instanceID: UUID(), model: "m", messages: [
            ChatMessage(body: .user(text: "One", image: .stored(first))), reply(.failed(message: "boom"), ""),
            ChatMessage(body: .user(text: "One again", image: nil)), reply(),
            ChatMessage(body: .user(text: "Two", image: .stored(second))), next,
        ])
        let request = conversation.request(replyingTo: next.id, maxTokens: nil, temperature: nil, image: attachments.load)
        // The failed reply sends no turn, so "Two" is turn 3.
        #expect(request.turns.map(\.content) == ["One", "One again", "A red square.", "Two"])
        #expect(request.image == TurnImage(data: Data([2]), turn: 3))
        #expect(conversation.storedImages == [first, second])
    }

    @Test func chatsSavedWithTheFormerFlagLoad() throws {
        let json = #"{"user":{"text":"Old","hasImage":true}}"#
        #expect(try JSONDecoder.mirmir.decode(MessageBody.self, from: Data(json.utf8)) == .user(text: "Old", image: .unavailable))
        let plain = #"{"user":{"text":"Old","hasImage":false}}"#
        #expect(try JSONDecoder.mirmir.decode(MessageBody.self, from: Data(plain.utf8)) == .user(text: "Old", image: nil))
    }

    @Test func serverFormatsPassThrough() throws {
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 0])
        #expect(try ImageNormalizer.normalized(png) == png)
        #expect(throws: ImageNormalizationError.unreadable) { try ImageNormalizer.normalized(Data("not an image".utf8)) }
    }

    #if canImport(ImageIO)
    @Test func aHEICPhotoBecomesJPEG() throws {
        let heic = try Self.heicFixture(width: 64, height: 32)
        #expect(!ImageNormalizer.isServerFormat(heic))
        let converted = try ImageNormalizer.normalized(heic)
        #expect(converted.starts(with: [0xFF, 0xD8, 0xFF]))
        let source = try #require(CGImageSourceCreateWithData(converted as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect((image.width, image.height) == (64, 32))
    }

    @Test func transparencyBecomesWhite() throws {
        let context = try #require(CGContext(
            data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        let output = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(output, "public.tiff" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try #require(context.makeImage()), nil)
        #expect(CGImageDestinationFinalize(destination))

        let converted = try ImageNormalizer.normalized(output as Data)
        let source = try #require(CGImageSourceCreateWithData(converted as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let pixel = try #require(CGContext(
            data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        pixel.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        let rgb = try #require(pixel.data).assumingMemoryBound(to: UInt8.self)
        #expect(rgb[0] > 240 && rgb[1] > 240 && rgb[2] > 240)
    }

    /// A real HEIC file, as an iPhone writes, encoded by ImageIO.
    static func heicFixture(width: Int, height: Int) throws -> Data {
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        context.setFillColor(red: 0.9, green: 0.1, blue: 0.1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())
        let output = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(output, "public.heic" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return output as Data
    }
    #endif
}
