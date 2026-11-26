import Foundation
import Observation

/// GGUF repositories' variants as one connection's server lists them,
/// shared by the models table and the inspector. A listing belongs to the
/// connection generation that asked for it (`AppModel.connectionGeneration`):
/// a new connection, to another server or the same one at a new address,
/// starts from nothing, and a reply from an earlier connection is dropped,
/// even when the server it asked is the current one again.
@MainActor
@Observable
public final class VariantListings {
    public enum Listing: Equatable, Sendable {
        case listing
        case listed(ModelVariants)
        case failed(String)
    }

    private var generation: UInt64?
    private var listings: [String: Listing] = [:]

    public init() {}

    /// Forgets every listing when `generation` is not the one they belong to.
    public func reset(for generation: UInt64) {
        guard self.generation != generation else { return }
        self.generation = generation
        listings = [:]
    }

    public func listing(of repository: String) -> Listing? {
        listings[repository]
    }

    /// Lists `repository` with `fetch` unless this generation listed it or
    /// is listing it. The returned task, for tests, finishes once the reply
    /// is kept or dropped.
    @discardableResult
    public func load(
        _ repository: String, generation: UInt64, fetch: @escaping @MainActor () async throws -> ModelVariants
    ) -> Task<Void, Never>? {
        reset(for: generation)
        switch listings[repository] {
        case .listing?, .listed?: return nil
        case .failed?, nil: break
        }
        listings[repository] = .listing
        return Task { @MainActor [weak self] in
            let reply: Listing
            do {
                reply = .listed(try await fetch())
            } catch {
                reply = .failed(error.localizedDescription)
            }
            guard let self, self.generation == generation else { return }
            listings[repository] = reply
        }
    }
}
