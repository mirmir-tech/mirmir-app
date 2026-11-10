import Foundation
import MirmirRPC
import Testing
@testable import MirmirKit

@Suite("Protocol decoding")
struct DecodingTests {
    @Test func localModelStatesMapToDomain() {
        #expect(LocalModelState(wire: "ready") == .loaded)
        #expect(LocalModelState(wire: "available") == .available)
        #expect(LocalModelState(wire: "loading") == .loading)
        #expect(LocalModelState(wire: "weird") == .unrecognized("weird"))
    }

    @Test func localModelKeepsLoadabilityReason() {
        var wire = Mirmir_V1_LocalModelInfo()
        wire.id = "id"
        wire.selector = "mlx-community/Qwen3-4B"
        wire.repoID = "mlx-community/Qwen3-4B"
        wire.state = "available"
        wire.loadable = false
        wire.loadUnavailableReason = "Shared K/V unsupported"
        wire.toolUse = true
        wire.vision = true
        let model = LocalModel(wire)
        #expect(model.loadability == .unavailable(reason: "Shared K/V unsupported"))
        #expect(model.features == [.tools, .vision])
        #expect(model.displayName == "Qwen3-4B")
        #expect(model.owner == "mlx-community")
        #expect(model.recentRank == nil)
    }

    @Test func selectorFallsBackToID() {
        var wire = Mirmir_V1_LocalModelInfo()
        wire.id = "local-path-model"
        #expect(LocalModel(wire).selector == "local-path-model")
    }

    @Test func activityStatesAndKinds() {
        var wire = Mirmir_V1_ActivityEvent()
        wire.operationID = "op-1"
        wire.kind = "pull"
        wire.state = "cancelling"
        wire.current = 5
        wire.total = 10
        let activity = Activity(wire)
        #expect(activity.kind == .pull)
        #expect(activity.state == .cancelling)
        #expect(activity.state.isActive)
        #expect(activity.progress?.fraction == 0.5)
        #expect(ActivityState(wire: "completed").isActive == false)
    }

    @Test func missingTelemetryRatesStayNil() {
        var wire = Mirmir_V1_TelemetrySnapshot()
        wire.lastDecodeTokensPerSecond = 98.5
        wire.kvHitTokens = 3
        wire.kvMissTokens = 1
        let snapshot = TelemetrySnapshot(wire)
        #expect(snapshot.currentDecode == nil)
        #expect(snapshot.decode == 98.5)
        #expect(snapshot.prefill == nil)
        #expect(snapshot.memory == nil)
        #expect(snapshot.prefixHitRatio == 0.75)
    }

    @Test func memoryReadingNeedsBothValues() {
        #expect(MemoryReading(total: 100, available: nil, source: "host") == nil)
        let reading = MemoryReading(total: 100, available: 40, source: "host")
        #expect(reading?.usedBytes == 60)
    }

    @Test func historyIsSortedByTime() {
        var later = Mirmir_V1_TelemetryHistorySample()
        later.sampledAtUnixMs = 2000
        var earlier = Mirmir_V1_TelemetryHistorySample()
        earlier.sampledAtUnixMs = 1000
        var wire = Mirmir_V1_TelemetryHistoryResponse()
        wire.samples = [later, earlier]
        wire.samplingIntervalMs = 1000
        wire.retentionLimit = 3600
        let history = TelemetryHistory(wire)
        #expect(history.samples.map(\.sampledAt.timeIntervalSince1970) == [1, 2])
        #expect(history.samplingInterval == 1)
    }

    @Test func completionPrefersDecodeRate() {
        var wire = Mirmir_V1_Completion()
        wire.tokensPerSecond = 50
        wire.decodeTokensPerSecond = 104.2
        wire.ttftMs = 210
        let stats = GenerationStats(wire)
        #expect(stats.decodeTokensPerSecond == 104.2)
        #expect(stats.ttftMs == 210)
        #expect(stats.prefillTokensPerSecond == nil)
    }

    @Test func generationRequestCarriesHistory() {
        let request = GenerationRequest(
            model: "m",
            turns: [ChatTurn(role: .user, content: "hi"), ChatTurn(role: .assistant, content: "hello", reasoning: "think")],
            temperature: 0.7
        ).wire
        #expect(request.messages.map(\.role) == ["user", "assistant"])
        #expect(request.messages[1].reasoningContent == "think")
        #expect(request.hasMaxTokens == false)
        #expect(request.temperature == 0.7)
    }
}
