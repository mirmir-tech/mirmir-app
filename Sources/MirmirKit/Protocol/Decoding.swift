import Foundation
import MirmirRPC

// The only place protocol strings become typed values. Views and the app model
// work with the domain types exclusively.

extension LocalModelState {
    init(wire: String) {
        switch wire {
        case "ready": self = .loaded
        case "loading": self = .loading
        case "available": self = .available
        case "paused": self = .paused
        case "missing": self = .missing
        case "error": self = .error
        default: self = .unrecognized(wire)
        }
    }
}

extension MemoryFit {
    init(wire: String) {
        switch wire {
        case "fits": self = .fits
        case "does_not_fit": self = .doesNotFit
        default: self = .unknown
        }
    }
}

extension ActivityKind {
    init(wire: String) {
        switch wire {
        case "generate": self = .generate
        case "load": self = .load
        case "unload": self = .unload
        case "pull": self = .pull
        case "remove": self = .remove
        case "restore": self = .restore
        case "recovery": self = .recovery
        default: self = .unrecognized(wire)
        }
    }
}

extension ActivityState {
    init(wire: String) {
        switch wire {
        case "queued": self = .queued
        case "running": self = .running
        case "cancelling": self = .cancelling
        case "completed": self = .completed
        case "failed": self = .failed
        case "cancelled": self = .cancelled
        default: self = .unrecognized(wire)
        }
    }
}

extension TransferPhase {
    init(wire: String) {
        switch wire {
        case "queued": self = .queued
        case "checking": self = .checking
        case "resolving": self = .resolving
        case "downloading": self = .downloading
        case "validating": self = .validating
        case "available": self = .available
        default: self = .unrecognized(wire)
        }
    }
}

extension ModelFeatures {
    init(toolUse: Bool, thinking: Bool, vision: Bool) {
        var features: ModelFeatures = []
        if toolUse { features.insert(.tools) }
        if thinking { features.insert(.thinking) }
        if vision { features.insert(.vision) }
        self = features
    }
}

extension Date {
    init(unixMilliseconds: UInt64) {
        self.init(timeIntervalSince1970: TimeInterval(unixMilliseconds) / 1000)
    }
}

extension LocalModel {
    init(_ wire: Mirmir_V1_LocalModelInfo) {
        self.init(
            selector: wire.selector.isEmpty ? wire.id : wire.selector,
            repoID: wire.repoID,
            commit: wire.commit,
            path: wire.path,
            state: LocalModelState(wire: wire.state),
            loadability: wire.loadable ? .loadable : .unavailable(reason: wire.loadUnavailableReason),
            modelClass: wire.modelClass,
            encoding: wire.encoding,
            container: wire.container,
            sizeBytes: wire.sizeBytes,
            features: ModelFeatures(toolUse: wire.toolUse, thinking: wire.thinking, vision: wire.vision),
            imageInput: wire.imageInput,
            managed: wire.managed,
            recentRank: wire.hasRecentRank ? wire.recentRank : nil
        )
    }
}

extension MemoryEstimate {
    init(_ wire: Mirmir_V1_ModelMemoryEstimate) {
        self.init(
            weightBytes: wire.weightBytes,
            kvCacheBytes: wire.kvCacheBytes,
            workspaceBytes: wire.workspaceBytes,
            requiredBytes: wire.requiredBytes,
            availableBytes: wire.hasAvailableBytes ? wire.availableBytes : nil,
            budgetBytes: wire.hasBudgetBytes ? wire.budgetBytes : nil,
            fit: MemoryFit(wire: wire.fit),
            maxSafeContextTokens: wire.hasMaxSafeContextTokens ? wire.maxSafeContextTokens : nil,
            configuredCacheTokens: wire.configuredCacheTokens
        )
    }
}

extension GenerationSettings {
    init(_ wire: Mirmir_V1_GenerationSettings) {
        self.init(
            maxTokens: wire.maxTokens, temperature: wire.temperature, topP: wire.topP,
            topK: wire.topK, repetitionPenalty: wire.repetitionPenalty
        )
    }

    var wire: Mirmir_V1_GenerationSettings {
        var value = Mirmir_V1_GenerationSettings()
        value.maxTokens = maxTokens
        value.temperature = temperature
        value.topP = topP
        value.topK = topK
        value.repetitionPenalty = repetitionPenalty
        return value
    }
}

extension ModelInspection {
    init(_ wire: Mirmir_V1_InspectModelResponse) {
        self.init(
            settings: GenerationSettings(wire.settings),
            hasOverrides: wire.hasMirmirOverrides_p,
            memory: wire.hasMemory ? MemoryEstimate(wire.memory) : nil,
            task: wire.task,
            maxInputTokens: wire.capabilities.maxInputTokens
        )
    }
}

extension LoadProgress {
    init(_ wire: Mirmir_V1_ModelLifecycleEvent) {
        self.init(
            phase: wire.phase, current: wire.current, total: wire.hasTotal ? wire.total : nil,
            detail: wire.detail, finished: wire.hasModel
        )
    }
}

extension Activity {
    init(_ wire: Mirmir_V1_ActivityEvent) {
        self.init(
            id: wire.operationID,
            kind: ActivityKind(wire: wire.kind),
            target: wire.target,
            state: ActivityState(wire: wire.state),
            stage: wire.stage,
            detail: wire.detail,
            startedAt: Date(unixMilliseconds: wire.startedAtUnixMs),
            updatedAt: Date(unixMilliseconds: wire.updatedAtUnixMs),
            cancellable: wire.cancellable,
            progress: wire.hasCurrent ? ActivityProgress(current: wire.current, total: wire.hasTotal ? wire.total : nil) : nil
        )
    }
}

extension CatalogModel {
    init(_ wire: Mirmir_V1_CatalogModel) {
        self.init(
            id: wire.id, downloads: wire.downloads, likes: wire.likes, gated: wire.gated,
            modelClass: wire.modelClass, compatibility: wire.compatibility,
            memoryFit: MemoryFit(wire: wire.memoryFit),
            estimatedRequiredBytes: wire.hasEstimatedRequiredBytes ? wire.estimatedRequiredBytes : nil,
            reason: wire.reason, downloaded: wire.downloaded,
            features: ModelFeatures(toolUse: wire.toolUse, thinking: wire.thinking, vision: wire.vision),
            encoding: wire.encoding
        )
    }
}

extension TransferProgress {
    init(_ wire: Mirmir_V1_ModelTransferEvent) {
        self.init(
            repoID: wire.repoID, phase: TransferPhase(wire: wire.phase),
            downloadedBytes: wire.downloadedBytes,
            totalBytes: wire.hasTotalBytes ? wire.totalBytes : nil,
            message: wire.message
        )
    }
}

extension GenerationStats {
    init(_ wire: Mirmir_V1_Completion) {
        self.init(
            promptTokens: wire.promptTokens,
            completionTokens: wire.completionTokens,
            finishReason: wire.finishReason,
            elapsedMs: wire.elapsedMs,
            decodeTokensPerSecond: wire.hasDecodeTokensPerSecond ? wire.decodeTokensPerSecond
                : (wire.hasTokensPerSecond ? wire.tokensPerSecond : nil),
            prefillTokensPerSecond: wire.hasPrefillTokensPerSecond ? wire.prefillTokensPerSecond : nil,
            ttftMs: wire.hasTtftMs ? wire.ttftMs : nil
        )
    }
}
