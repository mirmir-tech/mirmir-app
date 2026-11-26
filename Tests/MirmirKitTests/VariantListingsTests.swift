import Testing
@testable import MirmirKit

/// Variant listings belong to the connection that asked for them: a reply
/// from an earlier connection never lands, even on the same server again,
/// and a new connection to the same server lists afresh.
@Suite("Variant listings per connection")
@MainActor
struct VariantListingsTests {
    /// A reply a test releases when it chooses.
    @MainActor
    final class Pending {
        var continuation: CheckedContinuation<ModelVariants, Error>?
        var calls = 0

        func fetch() async throws -> ModelVariants {
            calls += 1
            return try await withCheckedThrowingContinuation { continuation = $0 }
        }

        func reply(_ listed: ModelVariants) {
            continuation?.resume(returning: listed)
            continuation = nil
        }
    }

    private func listed(_ name: String) -> ModelVariants {
        ModelVariants(variants: [], defaultVariant: name)
    }

    /// A on generation 1, B on 2, A again on 3: the first reply from A,
    /// delivered last, does not replace the listing A gave on 3.
    @Test func aReplyFromAnEarlierConnectionIsDropped() async throws {
        let listings = VariantListings()
        let first = Pending(), again = Pending()
        let late = listings.load("owner/repo", generation: 1, fetch: { try await first.fetch() })
        await Task.yield()
        listings.reset(for: 2)
        #expect(listings.listing(of: "owner/repo") == nil)
        let current = listings.load("owner/repo", generation: 3, fetch: { try await again.fetch() })
        await Task.yield()
        again.reply(listed("Q8_0"))
        await current?.value
        first.reply(listed("Q2_K"))
        await late?.value
        #expect(listings.listing(of: "owner/repo") == .listed(listed("Q8_0")))
    }

    /// The same server at a new address is a new connection: what it listed
    /// before is not reused, it is asked again.
    @Test func aNewConnectionListsAgain() async throws {
        let listings = VariantListings()
        let pending = Pending()
        let before = listings.load("owner/repo", generation: 1, fetch: { try await pending.fetch() })
        await Task.yield()
        pending.reply(listed("Q4_K_M"))
        await before?.value
        #expect(listings.load("owner/repo", generation: 1, fetch: { try await pending.fetch() }) == nil)
        #expect(pending.calls == 1)
        let after = listings.load("owner/repo", generation: 2, fetch: { try await pending.fetch() })
        #expect(listings.listing(of: "owner/repo") == .listing)
        await Task.yield()
        #expect(pending.calls == 2)
        pending.reply(listed("Q2_K"))
        await after?.value
        #expect(listings.listing(of: "owner/repo") == .listed(listed("Q2_K")))
    }

    /// Switching servers, switching back and editing a server's address
    /// each start a new connection generation; a rename does not.
    @Test func connectionsCountSwitchesAndAddressEdits() {
        let model = AppModel.preview()
        let studio = PreviewData.studio
        let start = model.connectionGeneration
        model.select(instance: studio.id)
        let switched = model.connectionGeneration
        #expect(switched > start)
        let moved = InstanceRecord(id: studio.id, name: studio.name, target: .remote(RemoteEndpoint(host: "10.0.0.9")))
        model.update(moved)
        let edited = model.connectionGeneration
        #expect(edited > switched)
        model.update(InstanceRecord(id: studio.id, name: "Renamed", target: moved.target))
        #expect(model.connectionGeneration == edited)
        model.select(instance: InstanceRecord.thisMacID)
        model.select(instance: studio.id)
        #expect(model.connectionGeneration > edited + 1)
    }
}
