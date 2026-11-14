import Foundation
import Testing
@testable import MirmirKit

/// An image is never sent to a model that reports no image input, and
/// never dropped silently: the message stays in the composer with a notice.
@Suite("Images and models without vision")
@MainActor
struct VisionRefusalTests {
    private let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 0])
    /// Qwen3 4B lists no image input; Gemma 3 12B does.
    private let textOnly = PreviewData.models[1]
    private let vision = PreviewData.models[2]

    private func chat(_ local: LocalModel) -> (AppModel, UUID) {
        let model = AppModel.preview()
        let id = model.chat.newConversation(model: local.selector)
        model.chat.selectedID = id
        return (model, id)
    }

    @Test func anAttachmentToATextModelIsRefusedAndKept() async throws {
        let (model, id) = chat(textOnly)
        let png = png
        model.chat.setDraftText("Describe this", for: id)
        await model.chat.attachImage(to: id) { png }
        model.chat.sendDraft(of: id)
        #expect(model.chat.conversations.first { $0.id == id }?.messages.isEmpty == true)
        #expect(model.chat.draft(for: id) == ComposerDraft(text: "Describe this", image: .ready(png)))
        #expect(model.notice == RequestError.imageNotSupported(model: textOnly.displayName, origin: .composer).localizedDescription)

        // Removing the image sends the text.
        model.chat.removeDraftImage(for: id)
        model.chat.sendDraft(of: id)
        #expect(model.chat.conversations.first { $0.id == id }?.messages.first?.body == .user(text: "Describe this", image: nil))
    }

    @Test func aChatWithAnImageIsNotContinuedOnATextModel() async throws {
        let (model, id) = chat(vision)
        let png = png
        model.chat.setDraftText("Describe this", for: id)
        await model.chat.attachImage(to: id) { png }
        model.chat.sendDraft(of: id)
        model.chat.stop()
        #expect(model.chat.conversations.first { $0.id == id }?.messages.count == 2)

        model.chat.setModel(textOnly.selector, for: id)
        #expect(model.chat.send("And now?", to: id) == false)
        #expect(model.notice == RequestError.imageNotSupported(model: textOnly.displayName, origin: .history).localizedDescription)
        #expect(model.chat.conversations.first { $0.id == id }?.messages.count == 2)

        model.chat.setModel(vision.selector, for: id)
        #expect(model.chat.send("And now?", to: id))
    }

    @Test func aModelTheServerDoesNotListIsNotJudged() async throws {
        let (model, id) = chat(textOnly)
        model.chat.setModel("/models/unlisted", for: id)
        #expect(model.chat.send("Look", image: png, to: id))
    }
}
