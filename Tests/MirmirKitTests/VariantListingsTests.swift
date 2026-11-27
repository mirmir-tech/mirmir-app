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
        let variant = CatalogVariant(
            name: name, size: .exact(4_000), requiredBytes: 4_000, memoryFit: .fits, downloaded: false
        )
        return ModelVariants(variants: [variant], defaultVariant: name)
    }

    @Test func anEmptyListingFailsAndCanBeRetried() async throws {
        let listings = VariantListings()
        let pending = Pending()
        let first = listings.load("owner/repo", generation: 1, fetch: { try await pending.fetch() })
        await Task.yield()
        pending.reply(ModelVariants(variants: [], defaultVariant: nil))
        await first?.value
        if case .failed = listings.listing(of: "owner/repo") {
            // Expected: empty listings do not wipe search estimates permanently.
        } else {
            Issue.record("expected failed state for empty listing")
        }
        let retry = listings.load("owner/repo", generation: 1, fetch: { try await pending.fetch() })
        #expect(retry != nil)
        await Task.yield()
        pending.reply(listed("Q4_K_M"))
        await retry?.value
        #expect(listings.listing(of: "owner/repo") == .listed(listed("Q4_K_M")))
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

    /// A listing of `Q8_0` is cached; a fresh search on the same connection
    /// offers only `Q4_K_M`. The cached listing selects nothing for the new
    /// offer, the repository is listed again, the download takes what is
    /// offered, and a late reply for the old offer does not come back.
    @Test func aFreshOfferWithoutTheCachedDefaultListsAgain() async throws {
        let listings = VariantListings()
        let old = Pending(), fresh = Pending()
        let cached = listings.load("owner/model", offer: ["Q4_K_M", "Q8_0"], generation: 1, fetch: { try await old.fetch() })
        await Task.yield()
        old.reply(listed("Q8_0"))
        await cached?.value
        #expect(listings.listing(of: "owner/model", offer: ["Q4_K_M", "Q8_0"]) == .listed(listed("Q8_0")))

        var offered = CatalogModel(
            id: "owner/model", downloads: 0, likes: 0, gated: false, modelClass: "", compatibility: "supported",
            memoryFit: .fits, estimatedRequiredBytes: nil, reason: "", downloaded: false, features: [], encoding: nil
        )
        offered.variants = listed("Q4_K_M").variants
        offered.defaultVariant = "Q4_K_M"
        #expect(listings.listing(of: offered.id, offer: offered.offeredVariants) == nil)
        #expect(offered.pullID(for: offered.defaultChoice) == "owner/model:Q4_K_M")
        let again = listings.load(offered.id, offer: offered.offeredVariants, generation: 1, fetch: { try await fresh.fetch() })
        #expect(again != nil)
        await Task.yield()
        #expect(fresh.calls == 1)
        fresh.reply(listed("Q4_K_M"))
        await again?.value
        #expect(listings.listing(of: offered.id, offer: offered.offeredVariants) == .listed(listed("Q4_K_M")))

        // A reply for the old offer, delivered after the new one, is dropped.
        let late = Pending()
        let stale = listings.load("owner/model", offer: ["Q8_0"], generation: 1, fetch: { try await late.fetch() })
        let current = listings.load(offered.id, offer: offered.offeredVariants, generation: 1, fetch: { try await fresh.fetch() })
        await Task.yield()
        fresh.reply(listed("Q4_K_M"))
        await current?.value
        late.reply(listed("Q8_0"))
        await stale?.value
        #expect(listings.listing(of: offered.id, offer: offered.offeredVariants) == .listed(listed("Q4_K_M")))
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
