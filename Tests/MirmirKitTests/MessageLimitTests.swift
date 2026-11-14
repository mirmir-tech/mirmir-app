import Foundation
import GRPCCore
import MirmirRPC
import Testing
@testable import MirmirKit

/// An image the server's media policy accepts (up to 20 MiB) reaches the
/// server past gRPC's 4 MiB default; a larger one is made to fit, or refused
/// where it cannot be re-encoded.
@Suite("Message size limits", .serialized)
struct MessageLimitTests {
    @Test func everyCallCarriesMessagesUpToTheServerLimit() throws {
        let transport = try RuntimeConnection.transport(
            target: .unixDomainSocket(path: "/nonexistent/mirmir.sock", authority: "localhost"), security: .plaintext
        )
        for method in [Mirmir_V1_Runtime.Method.Generate.descriptor, Mirmir_V1_Runtime.Method.Health.descriptor] {
            let config = transport.config(forMethod: method)
            #expect(config?.maxRequestMessageBytes == MessageLimits.messageBytes)
            #expect(config?.maxResponseMessageBytes == MessageLimits.messageBytes)
            // Deadlines stay per call.
            #expect(config?.timeout == nil)
        }
        #expect(MessageLimits.imageBytes == 20 * 1024 * 1024)
        #expect(MessageLimits.messageBytes > MessageLimits.imageBytes + 4 * 1024 * 1024)
    }

    @MainActor @Test func anImageOverFourMebibytesReachesTheServer() async throws {
        // Generated off the main actor, which other suites' tests share.
        let png = await Task.detached { NoisyPNG.make(width: 2048, height: 1024) }.value
        #expect(png.count > 6_000_000)
        // An upright PNG under the limit is sent as it is.
        let image = try await Task.detached { try ImageNormalizer.normalized(png) }.value
        #expect(image == png)

        let directory = try DeadlineTests.scratch()
        defer { try? FileManager.default.removeItem(at: directory) }
        let server = try await StandInServer(socket: directory.appendingPathComponent("mirmir.sock").path, holds: false)
        defer { server.stop() }
        let model = ChatHistoryTests.model(directory)
        defer { model.shutdown() }
        model.phase = .connected(try await RuntimeConnection.connect(socket: server.socket))

        let id = model.chat.newConversation(model: "m")
        #expect(model.chat.send("Describe this", image: image, to: id))
        #expect(try await eventually { !model.chat.isGenerating })
        #expect(server.record.generatedImageSizes == [png.count])
        guard case .assistant(let text, _, _, .completed) = model.chat.conversations.first(where: { $0.id == id })?.messages.last?.body else {
            Issue.record("reply did not complete: \(String(describing: model.notice))"); return
        }
        #expect(text == StandInRuntime.answer)
    }

    @Test func anImageOverTheLimitIsMadeToFit() throws {
        let png = NoisyPNG.make(width: 4096, height: 2048)
        #expect(png.count > MessageLimits.imageBytes)
        #if canImport(ImageIO)
        let fitted = try ImageNormalizer.normalized(png)
        #expect(fitted.count <= MessageLimits.imageBytes)
        #expect(fitted.starts(with: [0xFF, 0xD8, 0xFF]))
        #else
        #expect(throws: ImageNormalizationError.tooLarge(bytes: png.count)) { try ImageNormalizer.normalized(png) }
        #endif
    }

    @MainActor @Test func sendingRefusesAnImageOverTheLimit() throws {
        let directory = try ChatHistoryTests.scratch()
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = ChatHistoryTests.model(directory)
        model.phase = .connected(RuntimeConnection.preview())
        let id = model.chat.newConversation(model: "m")
        let oversized = Data([0x89, 0x50, 0x4E, 0x47]) + Data(count: MessageLimits.imageBytes)
        #expect(!model.chat.send("Too big", image: oversized, to: id))
        #expect(model.notice == ImageNormalizationError.tooLarge(bytes: oversized.count).localizedDescription)
        #expect(model.chat.conversations.first { $0.id == id }?.messages.isEmpty == true)
        #expect(!model.chat.isGenerating)
    }
}
