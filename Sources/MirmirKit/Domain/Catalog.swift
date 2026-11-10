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
