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
        let request = try conversation.request(replyingTo: next.id, maxTokens: nil, temperature: nil, image: attachments.load)
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
        let request = try loaded.request(replyingTo: next.id, maxTokens: nil, temperature: nil, image: attachments.load)
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
        let request = try conversation.request(replyingTo: next.id, maxTokens: nil, temperature: nil, image: attachments.load)
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

    /// A phone's JPEG is stored sideways or mirrored with an EXIF tag the
    /// server's decoder ignores: its pixels must arrive upright. The fixture
    /// is red on its left half and blue on its right.
    @Test(arguments: [
        // EXIF orientation, shown size, and the colors shown at the top-left
        // and bottom-right.
        (UInt32(6), 32, 64, "red", "blue"),  // rotated 90° clockwise
        (UInt32(8), 32, 64, "blue", "red"),  // rotated 90° counterclockwise
        (UInt32(3), 64, 32, "blue", "red"),  // rotated 180°
        (UInt32(2), 64, 32, "blue", "red"),  // mirrored
        (UInt32(1), 64, 32, "red", "blue"),  // upright
    ])
    func taggedJPEGsArriveUpright(orientation: UInt32, width: Int, height: Int, topLeft: String, bottomRight: String) throws {
        let jpeg = try Self.halves(orientation: orientation)
        let converted = try ImageNormalizer.normalized(jpeg)
        if orientation == 1 { #expect(converted == jpeg) }
        // Raw pixels, ignoring any tag, as libmir's decoder reads them.
        let source = try #require(CGImageSourceCreateWithData(converted as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect((image.width, image.height) == (width, height))
        #expect(try Self.color(of: image, x: 4, y: 4) == topLeft)
        #expect(try Self.color(of: image, x: width - 5, y: height - 5) == bottomRight)
    }

    private static func halves(orientation: UInt32) throws -> Data {
        let context = try #require(CGContext(
            data: nil, width: 64, height: 32, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
        context.setFillColor(red: 0, green: 0, blue: 1, alpha: 1)
        context.fill(CGRect(x: 32, y: 0, width: 32, height: 32))
        let output = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(output, "public.jpeg" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try #require(context.makeImage()), [kCGImagePropertyOrientation: orientation] as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        return output as Data
    }

    /// "red" or "blue" at a point measured from the top-left of the stored
    /// pixels.
    private static func color(of image: CGImage, x: Int, y: Int) throws -> String {
        let context = try #require(CGContext(
            data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let pixels = try #require(context.data).assumingMemoryBound(to: UInt8.self)
        let offset = (y * image.width + x) * 4
        return pixels[offset] > pixels[offset + 2] ? "red" : "blue"
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
