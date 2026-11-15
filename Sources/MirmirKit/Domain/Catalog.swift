import Foundation

/// One Hugging Face search result from `SearchModels`.
public struct CatalogModel: Identifiable, Hashable, Sendable {
    public let id: String
    public let downloads: UInt64
    public let likes: UInt64
    public let gated: Bool
    public let modelClass: String
    public let compatibility: String
    public let memoryFit: MemoryFit
    public let estimatedRequiredBytes: UInt64?
    public let reason: String
    public let downloaded: Bool
    public let features: ModelFeatures
    public let encoding: String
}

/// Transfer phase of `PullModel`, decoded from `ModelTransferEvent.phase`.
public enum TransferPhase: Hashable, Sendable {
    case queued, checking, resolving, downloading, validating, available
    case unrecognized(String)

    public var label: String {
        switch self {
        case .queued: "Queued"
        case .checking: "Checking"
        case .resolving: "Resolving"
        case .downloading: "Downloading"
        case .validating: "Validating"
        case .available: "Available"
        case .unrecognized(let value): value.capitalized
        }
    }
}

/// A running download of a repository: one this app started, or a server
/// pull from any client. Until it finishes the checkpoint is incomplete,
/// which is progress, not an error.
public struct ModelDownload: Hashable, Sendable {
    public let repoID: String
    /// The server's stage, e.g. Resolving or Downloading.
    public let stage: String
    public let downloadedBytes: UInt64?
    public let totalBytes: UInt64?
    /// The server operation, when it can be cancelled.
    public let cancellableOperation: String?

    public init(repoID: String, stage: String, downloadedBytes: UInt64?, totalBytes: UInt64?, cancellableOperation: String? = nil) {
        self.repoID = repoID
        self.stage = stage
        self.downloadedBytes = downloadedBytes
        self.totalBytes = totalBytes
        self.cancellableOperation = cancellableOperation
    }

    /// Downloaded share of the repository, when its size is known.
    public var fraction: Double? {
        guard let downloadedBytes, let totalBytes, totalBytes > 0 else { return nil }
        return min(1, Double(downloadedBytes) / Double(totalBytes))
    }

    /// The repository name without its owner.
    public var displayName: String { repoID.split(separator: "/").last.map(String.init) ?? repoID }
}

public struct TransferProgress: Hashable, Sendable {
    public let repoID: String
    public let phase: TransferPhase
    public let downloadedBytes: UInt64
    public let totalBytes: UInt64?
    public let message: String

    public var fraction: Double? {
        guard let totalBytes, totalBytes > 0 else { return nil }
        return min(1, Double(downloadedBytes) / Double(totalBytes))
    }
}
