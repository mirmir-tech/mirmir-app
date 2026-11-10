import Foundation

/// What a server operation does, decoded from `ActivityEvent.kind`.
public enum ActivityKind: Hashable, Sendable {
    case generate, load, unload, pull, remove, restore, recovery
    case unrecognized(String)

    public var label: String {
        switch self {
        case .generate: "Generate"
        case .load: "Load"
        case .unload: "Unload"
        case .pull: "Download"
        case .remove: "Remove"
        case .restore: "Restore"
        case .recovery: "Recovery"
        case .unrecognized(let value): value.capitalized
        }
    }
}

/// Lifecycle of an operation, decoded from `ActivityEvent.state`.
public enum ActivityState: Hashable, Sendable {
    case queued
    case running
    case cancelling
    case completed
    case failed
    case cancelled
    case unrecognized(String)

    public var isActive: Bool {
        switch self {
        case .queued, .running, .cancelling: true
        default: false
        }
    }
}

public struct ActivityProgress: Hashable, Sendable {
    public let current: UInt64
    public let total: UInt64?

    public var fraction: Double? {
        guard let total, total > 0 else { return nil }
        return min(1, Double(current) / Double(total))
    }
}

/// The latest known state of one server operation.
public struct Activity: Identifiable, Hashable, Sendable {
    public let id: String
    public let kind: ActivityKind
    public let target: String
    public let state: ActivityState
    /// Server stage name (`prefill`, `decode`, `downloading`, …), shown as is.
    public let stage: String
    public let detail: String
    public let startedAt: Date
    public let updatedAt: Date
    public let cancellable: Bool
    public let progress: ActivityProgress?

    public var isPrefill: Bool { stage.contains("prefill") }
}
