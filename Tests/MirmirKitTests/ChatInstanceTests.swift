import Foundation
import Testing
@testable import MirmirKit

@Suite("Chats per server")
@MainActor
struct ChatInstanceTests {
    @Test func legacyConversationBelongsToThisMac() throws {
        let json = #"{"id":"8C1D0F5E-2D52-4C3B-9D0E-6B2C5E1F7A10","title":"Old","model":"m","updatedAt":"2026-11-13T10:00:00Z","messages":[]}"#
        let conversation = try JSONDecoder.mirmir.decode(Conversation.self, from: Data(json.utf8))
        #expect(conversation.instanceID == InstanceRecord.thisMacID)
    }

    @Test func instanceRoundTrips() throws {
        let remote = UUID()
        let conversation = Conversation(instanceID: remote, model: "m")
        let decoded = try JSONDecoder.mirmir.decode(Conversation.self, from: JSONEncoder.mirmir.encode(conversation))
        #expect(decoded.instanceID == remote)
    }

    @Test func switchingServerShowsItsOwnChats() {
        let model = AppModel.preview()
        let local = model.chat.visibleConversations.count
        #expect(local > 0)
        let remote = model.instances[1]
        model.select(instance: remote.id)
        #expect(model.chat.visibleConversations.isEmpty)
        #expect(model.chat.selected == nil)

        let id = model.chat.newConversation(model: "nemotron-3.5-super")
        #expect(model.chat.visibleConversations.map(\.id) == [id])
        #expect(model.chat.conversations.first { $0.id == id }?.instanceID == remote.id)

        model.select(instance: InstanceRecord.thisMacID)
        #expect(model.chat.visibleConversations.count == local)
        #expect(model.chat.selected?.instanceID == InstanceRecord.thisMacID)
    }
}
