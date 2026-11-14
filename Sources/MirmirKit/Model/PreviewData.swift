#if DEBUG
import Foundation

/// Sample data behind `AppModel.preview`. Numbers are plausible for a
/// 64 GB Apple Silicon Mac; none of them come from a real server.
enum PreviewData {
    static let studio = InstanceRecord(
        id: UUID(uuidString: "00000000-0000-0000-0000-0000000057D1")!,
        name: "Mac Studio", target: .remote(RemoteEndpoint(host: "studio.local"))
    )
    static let gpuBox = InstanceRecord(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000B10")!,
        name: "GB10", target: .remote(RemoteEndpoint(host: "10.0.0.42", port: 7443))
    )
    static let downloadRepo = "mlx-community/gemma-3-27b-it-4bit"

    static let models: [LocalModel] = [
        model("mlx-community/Qwen3.6-35B-A3B-mxfp4", "MXFP4", "shared-routed hybrid", 19_800_000_000,
              [.tools, .thinking], state: .loaded, rank: 1),
        model("mlx-community/Qwen3-4B-4bit", "4-bit", "dense decoder", 2_300_000_000, [.tools, .thinking], rank: 2),
        model("mlx-community/gemma-3-12b-it-4bit", "4-bit", "dense decoder", 8_100_000_000, [.vision], state: .loading),
        model("nvidia/Nemotron-H-56B-Base-8K", "BF16", "hybrid Mamba", 112_000_000_000, [],
              loadability: .unavailable(reason: "Needs 118 GB; this Mac's budget is 51.8 GB.")),
        model("HuggingFaceTB/SmolLM2-1.7B-Instruct", "NF4", "dense decoder", 1_100_000_000, [], state: .missing),
    ]

    static let inspections: [String: ModelInspection] = [
        models[0].selector: inspection(weights: 19_800_000_000, kv: 4_600_000_000, budget: 51_800_000_000, tokens: 65_536),
        // Over budget: weights and K/V together exceed the track.
        models[3].selector: inspection(weights: 112_000_000_000, kv: 6_400_000_000, budget: 51_800_000_000, tokens: 8_192),
    ]

    static let sparkline: [Double] = (0..<60).map { index in
        let wave = sin(Double(index) / 5) * 9 + sin(Double(index) / 2.3) * 4
        return index > 44 && index < 49 ? 0 : max(0, 100 + wave)
    }

    static func telemetry(at date: Date, decode: Double, active: UInt64) -> TelemetrySnapshot {
        TelemetrySnapshot(
            sampledAt: date, uptime: 3 * 3600 + 1260, loadedModels: 1, activeRequests: active,
            totalRequests: 1_284, failedRequests: 3, promptTokens: 2_410_000, completionTokens: 386_000,
            currentDecode: decode, currentPrefill: nil, lastDecode: decode - 2.4, lastPrefill: 2_907,
            meanDecode: 97.3, meanPrefill: 2_644, lastTTFTMs: 184, meanTTFTMs: 231, currentTTFTMs: nil,
            hostMemory: MemoryReading(totalBytes: 68_700_000_000, availableBytes: 31_200_000_000, pool: .host),
            acceleratorMemory: MemoryReading(totalBytes: 51_800_000_000, availableBytes: 27_700_000_000, pool: .metalWorkingSet),
            kvTotalBlocks: 12_133, kvUsedBlocks: 3_870, kvCachedPrefixes: 14, kvHitTokens: 74_000, kvMissTokens: 26_000,
            activeStage: "decode", gpuUtilizationPercent: 87, deviceName: "Apple M3 Max"
        )
    }

    /// An hour of one-second samples: a busy stretch, an idle gap and bursts
    /// of prefill.
    static func history(endingAt end: Date, count: Int = 3_600) -> TelemetryHistory {
        let samples = (0..<count).map { index -> TelemetrySample in
            let t = Double(index)
            let busy = index % 900 < 640
            let decode = busy ? 95 + sin(t / 40) * 12 + sin(t / 7) * 5 : nil
            let prefill = busy && index % 97 < 3 ? 2_600 + sin(t) * 300 : nil
            let used = 22_000_000_000 + UInt64(max(0, sin(t / 300)) * 4_000_000_000)
            return TelemetrySample(
                sampledAt: end.addingTimeInterval(t - Double(count)), loadedModels: 1,
                activeRequests: busy ? UInt64(1 + index % 4) : 0, decode: decode, prefill: prefill,
                ttftMs: prefill == nil ? nil : 180 + sin(t) * 40,
                memory: MemoryReading(totalBytes: 68_700_000_000, availableBytes: 68_700_000_000 - used, pool: .host),
                kvTotalBlocks: 12_133, kvUsedBlocks: busy ? 3_870 : 0
            )
        }
        return TelemetryHistory(samples: samples, retentionLimit: 3_600, samplingInterval: 1)
    }

    static func activities(at now: Date) -> [Activity] {
        [
            activity("op-1", .generate, "Refactor the K/V history module", .running, "decode", "Chat · 1,204 tokens", now, -42),
            activity("op-2", .generate, "/v1/chat/completions", .running, "decode", "Zed · 2 requests", now, -18),
            activity("op-3", .generate, "/v1/chat/completions", .running, "prefill", "curl · prefill 8,192", now, -3),
            activity("op-4", .pull, downloadRepo, .running, "downloading", "6.4 of 17.1 GB", now, -95,
                     progress: ActivityProgress(current: 6_420_000_000, total: 17_100_000_000)),
            activity("op-5", .load, models[0].selector, .completed, "ready", "", now, -1_800),
            activity("op-6", .generate, "/v1/completions", .failed, "decode", "client disconnected", now, -600),
        ]
    }

    static func conversations(at now: Date, streaming: Bool) -> [Conversation] {
        let stats = GenerationStats(
            promptTokens: 1_204, completionTokens: 386, finishReason: "stop", elapsedMs: 3_910,
            decodeTokensPerSecond: 104.2, prefillTokensPerSecond: 2_871, ttftMs: 412
        )
        let reply = "Split `history.rs` into `history/mod.rs` and `history/ring.rs`. The ring buffer owns retention; "
            + "`mod.rs` keeps sampling and serialization.\n\n```rust\npub struct Ring<T> {\n    slots: Vec<Option<T>>,\n    head: usize,\n}\n```"
        let state: ReplyState = streaming ? .streaming : .completed(stats)
        return [
            Conversation(instanceID: InstanceRecord.thisMacID, title: "Refactor the K/V history module", model: models[0].selector, updatedAt: now, messages: [
                ChatMessage(date: now.addingTimeInterval(-60), body: .user(
                    text: "How should I split the K/V history module so files stay under 250 lines?", image: nil
                )),
                ChatMessage(date: now.addingTimeInterval(-55), body: .assistant(
                    text: streaming ? String(reply.prefix(120)) : reply,
                    reasoning: "The module mixes retention and sampling. Retention is the natural seam.",
                    thinkingSeconds: 2.4, state: state
                )),
            ]),
            Conversation(instanceID: InstanceRecord.thisMacID, title: "Explain prefix caching", model: models[1].selector,
                         updatedAt: now.addingTimeInterval(-7_200), messages: [
                ChatMessage(body: .user(text: "Explain prefix caching in two sentences.", image: nil)),
                ChatMessage(body: .assistant(
                    text: "Requests that share a prompt prefix reuse its K/V blocks instead of recomputing them. "
                        + "Prefill then starts at the first token that differs.",
                    reasoning: "", thinkingSeconds: nil, state: .completed(stats)
                )),
            ]),
            Conversation(instanceID: InstanceRecord.thisMacID, title: "New Chat", model: "", updatedAt: now.addingTimeInterval(-86_400)),
        ]
    }

    static let logLines = [
        "2026-11-13T08:49:44Z  INFO mirmir::daemon: starting mirmir server http_enabled=true http_bind=127.0.0.1:8080",
        "2026-11-13T08:49:44Z  INFO mirmir::daemon: gRPC server listening socket=~/.local/state/mirmir/mirmir.sock",
        "2026-11-13T08:49:44Z  INFO mirmir::daemon: HTTP server listening address=127.0.0.1:8080 web_enabled=true",
        "2026-11-13T08:49:45Z  WARN mirmir::application::telemetry::history: telemetry history could not be loaded",
        "2026-11-13T08:49:48Z  INFO libmir::model::warmup: warming accelerator execution profiles prompt_tokens=2048",
        "2026-11-13T08:49:49Z  INFO libmir::metal::tuning: selected Metal paged-attention execution profile execution=Direct",
        "2026-11-13T08:49:49Z  INFO libmir::model::warmup: accelerator execution profiles are warm",
    ]

    private static func model(
        _ repo: String, _ encoding: String, _ modelClass: String, _ size: UInt64, _ features: ModelFeatures,
        state: LocalModelState = .available, loadability: Loadability = .loadable, rank: UInt32? = nil
    ) -> LocalModel {
        LocalModel(
            selector: repo, repoID: repo, commit: "1cfa9a7208912126459214e8b04321603b3df60c",
            path: "/Users/preview/.cache/huggingface/hub/models--\(repo.replacingOccurrences(of: "/", with: "--"))",
            state: state, loadability: loadability, modelClass: modelClass, encoding: encoding,
            container: "safetensors", sizeBytes: size, features: features, imageInput: features.contains(.vision),
            managed: true, recentRank: rank
        )
    }

    private static func inspection(weights: UInt64, kv: UInt64, budget: UInt64, tokens: UInt64) -> ModelInspection {
        let workspace: UInt64 = 536_870_912
        let required = weights + kv + workspace
        return ModelInspection(
            settings: GenerationSettings(maxTokens: 4_096, temperature: 0.7, topP: 0.95, topK: 40, repetitionPenalty: 1.05),
            hasOverrides: false,
            memory: MemoryEstimate(
                weightBytes: weights, kvCacheBytes: kv, workspaceBytes: workspace, requiredBytes: required,
                availableBytes: budget, budgetBytes: budget, fit: required <= budget ? .fits : .doesNotFit,
                maxSafeContextTokens: required <= budget ? 131_072 : 0, configuredCacheTokens: tokens
            ),
            task: "text-generation", maxInputTokens: 262_144
        )
    }

    private static func activity(
        _ id: String, _ kind: ActivityKind, _ target: String, _ state: ActivityState, _ stage: String,
        _ detail: String, _ now: Date, _ offset: TimeInterval, progress: ActivityProgress? = nil
    ) -> Activity {
        Activity(
            id: id, kind: kind, target: target, state: state, stage: stage, detail: detail,
            startedAt: now.addingTimeInterval(offset), updatedAt: now.addingTimeInterval(state.isActive ? -1 : offset + 30),
            cancellable: state.isActive, progress: progress
        )
    }
}
#endif
