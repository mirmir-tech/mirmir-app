import Foundation

/// Residency of a local checkpoint, decoded from `LocalModelInfo.state`.
public enum LocalModelState: Hashable, Sendable {
    case loaded
    case loading
    case available
    case paused
    case missing
    case error
    case unrecognized(String)

    /// The checkpoint is complete on disk: not a paused download, not
    /// missing.
    public var isOnDisk: Bool {
        switch self {
        case .paused, .missing: false
        case .loaded, .loading, .available, .error, .unrecognized: true
        }
    }

    public var label: String {
        switch self {
        case .loaded: "Loaded"
        case .loading: "Loading"
        case .available: "Ready"
        case .paused: "Paused"
        case .missing: "Missing"
        case .error: "Error"
        case .unrecognized(let value): value.capitalized
        }
    }
}

/// Whether the server can load a checkpoint, with the server's reason when not.
public enum Loadability: Hashable, Sendable {
    case loadable
    case unavailable(reason: String)
}

public struct ModelFeatures: OptionSet, Hashable, Sendable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }

    public static let tools = ModelFeatures(rawValue: 1 << 0)
    public static let thinking = ModelFeatures(rawValue: 1 << 1)
    public static let vision = ModelFeatures(rawValue: 1 << 2)
}

public struct LocalModel: Identifiable, Hashable, Sendable {
    /// The selector the server accepts for load, unload, inspect and generate.
    public let selector: String
    public let repoID: String
    public let commit: String
    public let path: String
    public let state: LocalModelState
    public let loadability: Loadability
    public let modelClass: String
    /// Absent when nothing names the weights' encoding.
    public let encoding: String?
    public let container: String
    public let sizeBytes: UInt64
    public let features: ModelFeatures
    public let imageInput: Bool
    public let managed: Bool
    public let recentRank: UInt32?

    public var id: String { selector }

    /// The repository name without its owner, e.g. `Qwen3.6-35B-A3B-mxfp4`;
    /// for a path, the model directory (or its Hugging Face repository).
    public var displayName: String {
        if repoID.isEmpty { return Conversation.modelName(selector) }
        let name = repoID.split(separator: "/").last.map(String.init) ?? repoID
        // A GGUF variant, `repository:VARIANT`, reads "repository · VARIANT".
        return name.replacingOccurrences(of: ":", with: " · ")
    }

    /// A model the server serves but does not list locally, such as a
    /// checkpoint loaded from a path outside its model directories. Only the
    /// selector is known.
    static func unlisted(selector: String) -> LocalModel {
        LocalModel(
            selector: selector, repoID: "", commit: "", path: selector.hasPrefix("/") ? selector : "",
            state: .loaded, loadability: .loadable, modelClass: "", encoding: nil, container: "",
            sizeBytes: 0, features: [], imageInput: false, managed: false, recentRank: nil
        )
    }

    public var owner: String? {
        let parts = repoID.split(separator: "/")
        return parts.count > 1 ? String(parts[0]) : nil
    }

    public var shortCommit: String { String(commit.prefix(7)) }
}

/// Whether a model fits this server's memory budget, as the server judges it.
public enum MemoryFit: Hashable, Sendable {
    /// It fits with room to spare.
    case fits
    /// It fits, with little of the budget left over: other work on the
    /// server, or a longer context, may not fit beside it.
    case tight
    case doesNotFit
    /// The server could not tell, or sent a judgement this client predates.
    case unknown
}

public struct MemoryEstimate: Hashable, Sendable {
    public let weightBytes: UInt64
    public let kvCacheBytes: UInt64
    public let workspaceBytes: UInt64
    public let requiredBytes: UInt64
    public let availableBytes: UInt64?
    public let budgetBytes: UInt64?
    public let fit: MemoryFit
    public let maxSafeContextTokens: UInt64?
    public let configuredCacheTokens: UInt64
}

public struct GenerationSettings: Hashable, Sendable {
    public var maxTokens: UInt64
    public var temperature: Float
    public var topP: Float
    public var topK: UInt64
    public var repetitionPenalty: Float

    public init(maxTokens: UInt64, temperature: Float, topP: Float, topK: UInt64, repetitionPenalty: Float) {
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.topP = topP
        self.topK = topK
        self.repetitionPenalty = repetitionPenalty
    }

    /// These settings with Max tokens from 1 up to `limit`.
    public func boundingMaxTokens(by limit: UInt64) -> GenerationSettings {
        var bounded = self
        bounded.maxTokens = min(max(maxTokens, 1), max(limit, 1))
        return bounded
    }
}

/// What a model does, decoded from `InspectModelResponse.task`.
public enum ModelTask: Hashable, Sendable {
    case generation, rerank, embedding
    case unrecognized(String)

    public init(wire: String) {
        switch wire {
        case "generation": self = .generation
        case "rerank": self = .rerank
        case "embedding": self = .embedding
        default: self = .unrecognized(wire)
        }
    }

    /// Generation defaults apply; an unknown task keeps them editable.
    public var generates: Bool {
        switch self {
        case .rerank, .embedding: false
        case .generation, .unrecognized: true
        }
    }
}

public struct ModelInspection: Hashable, Sendable {
    public let settings: GenerationSettings
    public let hasOverrides: Bool
    public let memory: MemoryEstimate?
    public let task: ModelTask
    public let maxInputTokens: UInt64
    /// The context the model can be given; nil hides the control.
    public let context: ModelContext?
}

/// Progress of a load, decoded from `ModelLifecycleEvent`.
public struct LoadProgress: Hashable, Sendable {
    public let phase: String
    public let current: UInt64
    public let total: UInt64?
    public let detail: String
    public let finished: Bool

    public var fraction: Double? {
        guard let total, total > 0 else { return nil }
        return min(1, Double(current) / Double(total))
    }
}
