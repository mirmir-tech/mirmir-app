import Foundation

/// The Add Server inputs a connection test covers: the endpoint with the
/// certificate pin the user trusted, and the API key.
public struct RemoteCandidate: Hashable, Sendable {
    public let endpoint: RemoteEndpoint
    public let key: String

    /// `pinned` is the trusted fingerprint, or nil for a CA-issued
    /// certificate. Nil when the address does not parse.
    public init?(address: String, key: String, pinned: CertificateFingerprint?) {
        guard var endpoint = RemoteEndpoint(address: address) else { return nil }
        endpoint.pinnedFingerprint = pinned
        self.endpoint = endpoint
        self.key = key.trimmingCharacters(in: .whitespaces)
    }
}

/// A finished connection test, tied to the exact inputs it ran with.
public struct RemoteTestResult: Sendable {
    public enum Outcome: Sendable {
        case passed(ServerHealth, models: Int)
        case failed(String)
    }

    public let candidate: RemoteCandidate
    public let outcome: Outcome

    public init(candidate: RemoteCandidate, outcome: Outcome) {
        self.candidate = candidate
        self.outcome = outcome
    }

    /// The server to save: only one that passed with exactly the current
    /// inputs. Editing the address, key or certificate trust after a pass,
    /// or a test still running, leaves nothing to add.
    public func approved(for current: RemoteCandidate?, testing: Bool) -> RemoteCandidate? {
        guard !testing, case .passed = outcome, candidate == current else { return nil }
        return candidate
    }
}
