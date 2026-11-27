import Foundation
import Observation

/// GGUF repositories' variants as one connection's server lists them,
/// shared by the models table and the inspector. A listing belongs to the
/// connection generation that asked for it (`AppModel.connectionGeneration`):
/// a new connection, to another server or the same one at a new address,
/// starts from nothing, and a reply from an earlier connection is dropped,
/// even when the server it asked is the current one again. A listing also
/// belongs to the variants a search offered when it was asked for: a fresh
/// result offering others makes it stale, so it is listed again and
/// nothing selects from the old listing meanwhile.
@MainActor
@Observable
public final class VariantListings {
    public enum Listing: Equatable, Sendable {
        case listing
        case listed(ModelVariants)
        case failed(String)
    }

    /// A repository's listing and the offer it was asked for.
    private struct Entry {
        let offer: [String]
        let listing: Listing
    }

    private var generation: UInt64?
    private var listings: [String: Entry] = [:]

    public init() {}

    /// Forgets every listing when `generation` is not the one they belong to.
    public func reset(for generation: UInt64) {
        guard self.generation != generation else { return }
        self.generation = generation
        listings = [:]
    }

    /// `repository`'s listing for the variants `offer` names; none for a
    /// listing asked for another offer.
    public func listing(of repository: String, offer: [String] = []) -> Listing? {
        listings[repository].flatMap { $0.offer == offer ? $0.listing : nil }
    }

    /// Lists `repository`, as offered with `offer`, with `fetch` unless this
    /// generation listed it or is listing it for that offer. The returned
    /// task, for tests, finishes once the reply is kept or dropped.
    @discardableResult
    public func load(
        _ repository: String, offer: [String] = [], generation: UInt64,
        fetch: @escaping @MainActor () async throws -> ModelVariants
    ) -> Task<Void, Never>? {
        reset(for: generation)
        switch listing(of: repository, offer: offer) {
        case .listing?, .listed?: return nil
        case .failed?, nil: break
        }
        listings[repository] = Entry(offer: offer, listing: .listing)
        return Task { @MainActor [weak self] in
            let reply: Listing
            do {
                let listed = try await fetch()
                reply = listed.variants.isEmpty
                    ? .failed("No quantizations were listed for \(repository).")
                    : .listed(listed)
            } catch {
                reply = .failed(error.localizedDescription)
            }
            // A reply for an earlier connection or an earlier offer is stale.
            guard let self, self.generation == generation, listings[repository]?.offer == offer else { return }
            listings[repository] = Entry(offer: offer, listing: reply)
        }
    }
}
