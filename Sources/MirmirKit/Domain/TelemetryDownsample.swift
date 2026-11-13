import Foundation

extension TelemetryHistory {
    /// Points a chart draws per series. A 1 h range at one sample a second
    /// is 3,600 samples; drawing every one costs Swift Charts far more than
    /// the pixels can show.
    public static let chartPoints = 240

    /// Merges consecutive samples into at most `maxPoints` buckets. Rates and
    /// request counts keep each bucket's peak, so short bursts stay visible;
    /// levels (memory, K/V, loaded models) keep the bucket's last reading.
    public func downsampled(maxPoints: Int = Self.chartPoints) -> TelemetryHistory {
        guard maxPoints > 0, samples.count > maxPoints else { return self }
        let size = (samples.count + maxPoints - 1) / maxPoints
        let merged = stride(from: 0, to: samples.count, by: size).map { start in
            Self.merge(samples[start..<min(start + size, samples.count)])
        }
        return TelemetryHistory(samples: merged, retentionLimit: retentionLimit, samplingInterval: samplingInterval)
    }

    private static func merge(_ bucket: ArraySlice<TelemetrySample>) -> TelemetrySample {
        let last = bucket[bucket.endIndex - 1]
        return TelemetrySample(
            sampledAt: last.sampledAt,
            loadedModels: last.loadedModels,
            activeRequests: bucket.map(\.activeRequests).max() ?? last.activeRequests,
            decode: bucket.compactMap(\.decode).max(),
            prefill: bucket.compactMap(\.prefill).max(),
            ttftMs: bucket.compactMap(\.ttftMs).max(),
            memory: bucket.last { $0.memory != nil }?.memory,
            kvTotalBlocks: last.kvTotalBlocks,
            kvUsedBlocks: last.kvUsedBlocks
        )
    }
}

extension TelemetrySample {
    /// mirmir records the current rate or, when idle, the last one; charting
    /// that would hold the last request's speed across idle time. A rate
    /// counts only while the server is handling a request.
    public var liveDecode: Double? { activeRequests > 0 ? decode : nil }
    public var livePrefill: Double? { activeRequests > 0 ? prefill : nil }
}
