import Foundation
import Testing
@testable import MirmirKit

/// A remote server's chats belong to its identity: an edit keeps it, and a
/// server re-added at a removed one's address takes it back.
@Suite("Editing and re-adding servers")
@MainActor
struct InstanceEditTests {
    private let pin = CertificateFingerprint(der: [7, 7, 7])

    @Test func anEditKeepsTheServersIdentityAndChats() throws {
        let model = AppModel.preview()
        let studio = PreviewData.studio
        model.select(instance: studio.id)
        let chat = model.chat.newConversation(model: "m")

        let edited = InstanceRecord(
            id: studio.id, name: "Studio", target: .remote(RemoteEndpoint(host: "10.0.0.9", port: 9443, pinnedFingerprint: pin))
        )
        model.update(edited, key: "mmk_new")
        #expect(model.instances.first { $0.id == studio.id } == edited)
        #expect(model.instances.count == 3)
        #expect(model.savedKey(for: studio.id) == "mmk_new")
        #expect(model.chat.visibleConversations.map(\.id) == [chat])

        // A rename alone keeps the key.
        model.update(InstanceRecord(id: studio.id, name: "Renamed", target: edited.target))
        #expect(model.currentInstance.name == "Renamed")
        #expect(model.savedKey(for: studio.id) == "mmk_new")
        // This Mac is not edited.
        model.update(InstanceRecord(id: InstanceRecord.thisMacID, name: "Other", target: .personal))
        #expect(model.instances[0] == .thisMac)
    }

    @Test func reAddingARemovedServerReattachesItsChats() {
        let model = AppModel.preview()
        let studio = PreviewData.studio
        model.select(instance: studio.id)
        let chat = model.chat.newConversation(model: "m")
        model.remove(instance: studio.id)
        #expect(!model.instances.contains { $0.id == studio.id })
        #expect(model.chatCount(of: studio.id) == 1)

        // The same host in another case and port spelling, a new certificate.
        let again = InstanceRecord(name: "Studio again", target: .remote(RemoteEndpoint(host: "STUDIO.local", pinnedFingerprint: pin)))
        model.add(again, key: "mmk_b")
        let added = model.instances.last
        #expect(added?.id == studio.id)
        #expect(added?.name == "Studio again")
        #expect(model.savedKey(for: studio.id) == "mmk_b")
        model.select(instance: studio.id)
        #expect(model.chat.visibleConversations.map(\.id) == [chat])
        // Taken back once: another server at that address is a new one.
        #expect(model.reattached(again).id == again.id)
    }

    @Test func aServerWithoutChatsLeavesNothingToReattach() {
        let model = AppModel.preview()
        let gpu = PreviewData.gpuBox
        #expect(model.chatCount(of: gpu.id) == 0)
        model.remove(instance: gpu.id)
        let again = InstanceRecord(name: "GPU", target: gpu.target)
        #expect(model.reattached(again).id == again.id)
    }

    @Test func aProbeDoesNotBringBackARemovedServer() async {
        let model = AppModel.preview()
        let gpu = PreviewData.gpuBox
        model.remove(instance: gpu.id)
        // No key is saved: the probe fails at once, after the removal.
        await model.probe(gpu)
        #expect(model.summaries[gpu.id] == nil)
    }

    @Test func aProbeOfAnEditedServerIsDropped() async {
        let model = AppModel.preview()
        let gpu = PreviewData.gpuBox
        let before = model.summaries[gpu.id]
        let stale = InstanceRecord(id: gpu.id, name: gpu.name, target: .remote(RemoteEndpoint(host: "old.local")))
        await model.probe(stale)
        #expect(model.summaries[gpu.id] == before)
    }
}
