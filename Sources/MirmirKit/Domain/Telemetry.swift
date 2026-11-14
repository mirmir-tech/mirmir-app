import Foundation

public struct ServerHealth: Hashable, Sendable {
    public let protocolVersion: String
    public let serverVersion: String
}

/// One `Telemetry` snapshot with optional rates kept optional: a missing value
/// means "not measured", never zero.
public struct TelemetrySnapshot: Hashable, Sendable {
    public let sampledAt: Date
    public let uptime: TimeInterval
    public let loadedModels: UInt64
    public let activeRequests: UInt64
    public let totalRequests: UInt64
    public let failedRequests: UInt64
    public let promptTokens: UInt64
    public let completionTokens: UInt64
    public let currentDecode: Double?
    public let currentPrefill: Double?
    public let lastDecode: Double?
    public let lastPrefill: Double?
    public let meanDecode: Double?
    public let meanPrefill: Double?
    public let lastTTFTMs: Double?
    public let meanTTFTMs: Double?
    public let currentTTFTMs: Double?
    /// Host RAM reported by the operating system.
    public let hostMemory: MemoryReading?
    /// The accelerator backend's budget; absent until the backend reports one.
    public let acceleratorMemory: MemoryReading?
    public let kvTotalBlocks: UInt64
    public let kvUsedBlocks: UInt64
    public let kvCachedPrefixes: UInt64
    public let kvHitTokens: UInt64
    public let kvMissTokens: UInt64
    public let activeStage: String
    public let gpuUtilizationPercent: Double?
    public let deviceName: String

    /// The memory to headline: the accelerator budget models load into, else
    /// host RAM.
    public var memory: MemoryReading? { acceleratorMemory ?? hostMemory }

    /// The rate to headline: live decode while generating, else the last one.
    public var decode: Double? { currentDecode ?? lastDecode }
    public var prefill: Double? { currentPrefill ?? lastPrefill }

    public var prefixHitRatio: Double? {
        let total = kvHitTokens + kvMissTokens
        return total == 0 ? nil : Double(kvHitTokens) / Double(total)
    }

    public var kvUsageRatio: Double? {
        kvTotalBlocks == 0 ? nil : Double(kvUsedBlocks) / Double(kvTotalBlocks)
    }
}

/// Which memory a reading measures. Decoded from the typed protocol 2 pool,
/// never from a label.
public enum MemoryPool: Hashable, Sendable {
    case host
    case metalWorkingSet
    case cudaDevice
    case cudaUnified

    public var label: String {
        switch self {
        case .host: "Host RAM"
        case .metalWorkingSet: "Metal working set"
        case .cudaDevice: "CUDA device memory"
        case .cudaUnified: "CUDA unified memory"
        }
    }
}

public struct MemoryReading: Hashable, Sendable {
    public let totalBytes: UInt64
    public let availableBytes: UInt64
    public let pool: MemoryPool

    public var usedBytes: UInt64 { totalBytes > availableBytes ? totalBytes - availableBytes : 0 }
    public var usedRatio: Double { totalBytes == 0 ? 0 : Double(usedBytes) / Double(totalBytes) }
}

public struct TelemetrySample: Hashable, Sendable, Identifiable {
    public let sampledAt: Date
    public let loadedModels: UInt64
    public let activeRequests: UInt64
    public let decode: Double?
    public let prefill: Double?
    public let ttftMs: Double?
    /// Host RAM; history never samples accelerator memory.
    public let memory: MemoryReading?
    public let kvTotalBlocks: UInt64
    public let kvUsedBlocks: UInt64

    public var id: Date { sampledAt }
}

public struct TelemetryHistory: Hashable, Sendable {
    public let samples: [TelemetrySample]
    public let retentionLimit: Int
    public let samplingInterval: TimeInterval

    public static let empty = TelemetryHistory(samples: [], retentionLimit: 0, samplingInterval: 1)
}
