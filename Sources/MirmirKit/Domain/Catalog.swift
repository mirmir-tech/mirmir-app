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
    /// Absent when nothing names the weights' encoding.
    public let encoding: String?
    /// A GGUF repository's quantizations, fewest bits per weight first;
    /// empty for other repositories.
    public internal(set) var variants: [CatalogVariant] = []
    /// The variant a download of `id` alone takes; the row's size and
    /// memory fit are its own.
    public internal(set) var defaultVariant: String? = nil
    /// The weights to download, estimated from the parameter count; a GGUF
    /// repository's variants carry their own sizes.
    public internal(set) var estimatedWeightBytes: UInt64? = nil
    /// The variant `reason` judges: the search's default, which a listing's
    /// own default does not replace.
    var judged = JudgedVariant.theDefault

    /// The variants the search offered, by name: what a listing of the
    /// repository was asked for.
    public var offeredVariants: [String] {
        variants.map(\.name)
    }

    /// The variant a download takes when none is chosen.
    public var defaultChoice: CatalogVariant? {
        variants.first { $0.name == defaultVariant } ?? variants.first
    }

    /// The result with the variants its files list, exactly sized, and the
    /// default those sizes give.
    public func listing(_ listed: ModelVariants) -> CatalogModel {
        var result = self
        result.judged = .variant(reasonVariant)
        result.variants = listed.variants
        result.defaultVariant = listed.defaultVariant
        return result
    }

    /// The variant the server judged in `reason`.
    public var reasonVariant: String? {
        switch judged {
        case .theDefault: defaultVariant
        case .variant(let name): name
        }
    }

    /// The server's reason, where it is `variant`'s: a GGUF repository is
    /// judged by the variant it would download by default at the fit the
    /// search gave it (`memoryFit`), and another variant's fit is its own,
    /// as is the judged one's once exact sizes change it. A repository that
    /// is unsupported as a whole is so for every variant.
    public func reason(for variant: CatalogVariant?) -> String? {
        guard !reason.isEmpty else { return nil }
        guard !variants.isEmpty, compatibility != "unsupported" else { return reason }
        guard let variant, variant.name == reasonVariant, variant.memoryFit == memoryFit else { return nil }
        return reason
    }

    /// What `PullModel` takes for `variant`: `id:name`, or `id` alone.
    public func pullID(for variant: CatalogVariant?) -> String {
        variant.map { "\(id):\($0.name)" } ?? id
    }
}

/// Which variant a search result's reason judges.
enum JudgedVariant: Hashable, Sendable {
    /// The result's default, as the search gave it.
    case theDefault
    /// The default the search gave, kept once a listing replaced it.
    case variant(String?)
}

/// How much is known of a GGUF variant's size.
public enum VariantSize: Hashable, Sendable {
    /// The listed files' sizes.
    case exact(UInt64)
    /// The parameter count at the type's bits per weight, before the files
    /// are listed.
    case estimated(UInt64)
    case unknown

    public var bytes: UInt64? {
        switch self {
        case .exact(let bytes), .estimated(let bytes): bytes
        case .unknown: nil
        }
    }
}

/// One quantization of a GGUF repository; it downloads as `repository:name`.
public struct CatalogVariant: Identifiable, Hashable, Sendable {
    public let name: String
    /// With the vision tower, when the repository offers one.
    public let size: VariantSize
    public let requiredBytes: UInt64?
    public let memoryFit: MemoryFit
    public let downloaded: Bool

    public var id: String { name }
}

/// A repository's variants with the sizes of their listed files.
public struct ModelVariants: Hashable, Sendable {
    public let variants: [CatalogVariant]
    public let defaultVariant: String?
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
