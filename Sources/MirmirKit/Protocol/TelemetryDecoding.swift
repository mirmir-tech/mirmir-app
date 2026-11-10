import Foundation
import MirmirRPC

extension TelemetrySnapshot {
    init(_ wire: Mirmir_V1_TelemetrySnapshot) {
        func optional(_ present: Bool, _ value: Double) -> Double? { present ? value : nil }
        self.init(
            sampledAt: Date(unixMilliseconds: wire.sampledAtUnixMs),
            uptime: TimeInterval(wire.uptimeMs) / 1000,
            loadedModels: wire.loadedModels,
            activeRequests: wire.activeRequests,
            totalRequests: wire.totalRequests,
            failedRequests: wire.failedRequests,
            promptTokens: wire.promptTokens,
            completionTokens: wire.completionTokens,
            currentDecode: optional(wire.hasCurrentDecodeTokensPerSecond, wire.currentDecodeTokensPerSecond),
            currentPrefill: optional(wire.hasCurrentPrefillTokensPerSecond, wire.currentPrefillTokensPerSecond),
            lastDecode: optional(wire.hasLastDecodeTokensPerSecond, wire.lastDecodeTokensPerSecond),
            lastPrefill: optional(wire.hasLastPrefillTokensPerSecond, wire.lastPrefillTokensPerSecond),
            meanDecode: optional(wire.hasMeanDecodeTokensPerSecond, wire.meanDecodeTokensPerSecond),
            meanPrefill: optional(wire.hasMeanPrefillTokensPerSecond, wire.meanPrefillTokensPerSecond),
            lastTTFTMs: optional(wire.hasLastTtftMs, wire.lastTtftMs),
            meanTTFTMs: optional(wire.hasMeanTtftMs, wire.meanTtftMs),
            currentTTFTMs: optional(wire.hasCurrentTtftMs, wire.currentTtftMs),
            memory: MemoryReading(
                total: wire.hasHostTotalMemoryBytes ? wire.hostTotalMemoryBytes : nil,
                available: wire.hasHostAvailableMemoryBytes ? wire.hostAvailableMemoryBytes : nil,
                source: wire.memorySource
            ),
            kvTotalBlocks: wire.kvTotalBlocks,
            kvUsedBlocks: wire.kvUsedBlocks,
            kvCachedPrefixes: wire.kvCachedPrefixes,
            kvHitTokens: wire.kvHitTokens,
            kvMissTokens: wire.kvMissTokens,
            activeStage: wire.activeStage,
            gpuUtilizationPercent: optional(wire.hasGpuUtilizationPercent, wire.gpuUtilizationPercent),
            deviceName: wire.deviceName
        )
    }
}

extension MemoryReading {
    init?(total: UInt64?, available: UInt64?, source: String) {
        guard let total, let available, total > 0 else { return nil }
        self.init(totalBytes: total, availableBytes: available, source: source)
    }
}

extension TelemetrySample {
    init(_ wire: Mirmir_V1_TelemetryHistorySample) {
        self.init(
            sampledAt: Date(unixMilliseconds: wire.sampledAtUnixMs),
            loadedModels: wire.loadedModels,
            activeRequests: wire.activeRequests,
            decode: wire.hasDecodeTokensPerSecond ? wire.decodeTokensPerSecond : nil,
            prefill: wire.hasPrefillTokensPerSecond ? wire.prefillTokensPerSecond : nil,
            ttftMs: wire.hasTtftMs ? wire.ttftMs : nil,
            memory: MemoryReading(
                total: wire.hasMemoryTotalBytes ? wire.memoryTotalBytes : nil,
                available: wire.hasMemoryAvailableBytes ? wire.memoryAvailableBytes : nil,
                source: wire.memorySource
            ),
            kvTotalBlocks: wire.kvTotalBlocks,
            kvUsedBlocks: wire.kvUsedBlocks
        )
    }
}

extension TelemetryHistory {
    init(_ wire: Mirmir_V1_TelemetryHistoryResponse) {
        self.init(
            samples: wire.samples.map(TelemetrySample.init).sorted { $0.sampledAt < $1.sampledAt },
            retentionLimit: Int(wire.retentionLimit),
            samplingInterval: max(0.001, TimeInterval(wire.samplingIntervalMs) / 1000)
        )
    }
}
