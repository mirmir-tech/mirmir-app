import Foundation
import Testing
@testable import MirmirKit

/// A composer's text and image belong to the conversation they were typed
/// and attached in; switching chats never carries them over.
@Suite("Composer drafts")
@MainActor
struct ComposerDraftTests {
    private let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 0])

    /// Two chats of the preview's This Mac, with `a` selected.
    private func twoChats() throws -> (AppModel, UUID, UUID) {
        let model = AppModel.preview()
        let a = model.chat.newConversation(model: "m")
        let b = model.chat.newConversation(model: "m")
        model.chat.selectedID = a
        return (model, a, b)
    }

    private func lastUserMessage(_ model: AppModel, _ id: UUID) -> MessageBody? {
        model.chat.conversations.first { $0.id == id }?.messages.last { $0.role == .user }?.body
    }

    @Test func aPreparedAttachmentStaysInItsConversation() async throws {
        let (model, a, b) = try twoChats()
        let png = png
        model.chat.setDraftText("Describe this", for: a)
        await model.chat.attachImage(to: a) { png }
        #expect(model.chat.draft(for: a).image == .ready(png))

        model.chat.selectedID = b
        model.chat.sendDraft(of: a)
        #expect(lastUserMessage(model, a) == nil, "a conversation that is not selected never sends")
        model.chat.setDraftText("Hello", for: b)
        model.chat.sendDraft(of: b)
        #expect(lastUserMessage(model, b) == .user(text: "Hello", image: nil))
        #expect(model.chat.draft(for: b) == ComposerDraft())
        #expect(model.chat.draft(for: a) == ComposerDraft(text: "Describe this", image: .ready(png)))
    }

    @Test func aConversionFinishingAfterASwitchLandsInItsOwnConversation() async throws {
        let (model, a, b) = try twoChats()
        let release = DispatchSemaphore(value: 0)
        let png = png
        let attaching = Task { await model.chat.attachImage(to: a) { release.wait(); return png } }
        while !model.chat.draft(for: a).isPreparingImage { await Task.yield() }

        model.chat.selectedID = b
        model.chat.setDraftText("Hello", for: b)
        release.signal()
        await attaching.value
        #expect(model.chat.draft(for: a).image == .ready(png))
        #expect(model.chat.draft(for: b).image == nil)
        model.chat.sendDraft(of: b)
        #expect(lastUserMessage(model, b) == .user(text: "Hello", image: nil))
    }

    @Test func aReplacedOrRemovedAttachmentIgnoresItsLateResult() async throws {
        let (model, a, _) = try twoChats()
        let release = DispatchSemaphore(value: 0)
        let png = png
        let attaching = Task { await model.chat.attachImage(to: a) { release.wait(); return png } }
        while !model.chat.draft(for: a).isPreparingImage { await Task.yield() }
        model.chat.removeDraftImage(for: a)
        release.signal()
        await attaching.value
        #expect(model.chat.draft(for: a).image == nil)
    }

    @Test func sendingWaitsForTheImage() async throws {
        let (model, a, _) = try twoChats()
        let release = DispatchSemaphore(value: 0)
        let png = png
        model.chat.setDraftText("Describe this", for: a)
        let attaching = Task { await model.chat.attachImage(to: a) { release.wait(); return png } }
        while !model.chat.draft(for: a).isPreparingImage { await Task.yield() }
        model.chat.sendDraft(of: a)
        #expect(lastUserMessage(model, a) == nil)
        release.signal()
        await attaching.value
        model.chat.sendDraft(of: a)
        guard case .user("Describe this", .stored)? = lastUserMessage(model, a) else {
            Issue.record("the draft was not sent with its image")
            return
        }
    }
}
