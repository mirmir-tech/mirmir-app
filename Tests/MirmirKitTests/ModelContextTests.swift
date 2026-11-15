import Foundation
import MirmirRPC
import Testing
@testable import MirmirKit

@Suite("Model context")
struct ModelContextTests {
    @Test func contextDecodesIntoDomain() {
        var wire = Mirmir_V1_InspectModelResponse()
        wire.context.blockTokens = 16
        wire.context.minTokens = 16
        wire.context.maxTokens = 40_960
        wire.context.saved.tokens = 8_192
        wire.context.automaticTokens = 194_128
        wire.context.residentTokens = 8_192
        let context = ModelInspection(wire).context
        #expect(context == ModelContext(
            blockTokens: 16, minTokens: 16, maxTokens: 40_960, saved: .tokens(8_192),
            automaticTokens: 194_128, residentTokens: 8_192
        ))
        #expect(context?.tokens(for: .automatic) == 194_128)
        #expect(context?.initialTokens == 8_192)
    }

    @Test func oldServersReportNoContext() {
        // 0.6.0 servers and models without K/V: the control is hidden.
        #expect(ModelInspection(Mirmir_V1_InspectModelResponse()).context == nil)
        var wire = Mirmir_V1_InspectModelResponse()
        wire.context.maxTokens = 2_048
        let context = ModelInspection(wire).context
        #expect(context?.saved == .automatic, "an unset choice is automatic")
        #expect(context?.residentTokens == nil)
    }

    @Test func choicesRoundTrip() {
        for choice in [ContextChoice.automatic, .tokens(8_192)] {
            #expect(ContextChoice(choice.wire) == choice)
        }
        #expect(ContextChoice.tokens(16).wire.tokens == 16)
        #expect(ContextChoice.automatic.wire.automatic)
    }

    @Test func logScaleSpansTheRangeInWholeBlocks() {
        let scale = LogScale(lower: 16, upper: 40_960, step: 16)
        #expect(scale.value(at: 0) == 16)
        #expect(scale.value(at: 1) == 40_960)
        #expect(scale.value(at: -1) == 16 && scale.value(at: 2) == 40_960)
        // Halfway on a log scale is the geometric mean, 809.5, snapped.
        #expect(scale.value(at: 0.5) == 816)
        for step in 0...100 {
            let value = scale.value(at: Double(step) / 100)
            #expect(value % 16 == 0 && (16...40_960).contains(value))
        }
        #expect(abs(scale.position(of: 8_192) - log(512) / log(2_560)) < 1e-9)
        #expect(scale.value(at: scale.position(of: 8_192)) == 8_192)
        #expect(scale.position(of: 1) == 0 && scale.position(of: 1_000_000) == 1)
    }

    @Test func snappingKeepsTheBoundsReachable() {
        let scale = LogScale(lower: 16, upper: 40_000, step: 16)
        #expect(scale.snapped(8_199) == 8_192)
        #expect(scale.snapped(8_200) == 8_208, "halves round up")
        #expect(scale.snapped(3) == 16)
        // 40,000 is not a whole block; the nearest block past it is clamped.
        #expect(scale.snapped(39_999) == 40_000)
        #expect(scale.snapped(.max) == 40_000)
        let degenerate = LogScale(lower: 0, upper: 0, step: 0)
        #expect(degenerate.value(at: 0.5) == 1 && degenerate.position(of: 5) == 0)
    }
}

/// The app model sends the chosen context to the server and keeps the
/// saved-context inspection apart from candidate estimates.
@Suite("Model context calls", .serialized)
@MainActor
struct ModelContextCallTests {
    private func harness() async throws -> (URL, StandInServer, AppModel) {
        let directory = try DeadlineTests.scratch()
        let server = try await StandInServer(socket: directory.appendingPathComponent("mirmir.sock").path, holds: false)
        let model = ChatHistoryTests.model(directory)
        model.phase = .connected(try await RuntimeConnection.connect(socket: server.socket))
        return (directory, server, model)
    }

    @Test func loadSendsTheChosenContextAndSwitchSendsNone() async throws {
        let (directory, server, model) = try await harness()
        defer { model.shutdown(); server.stop(); try? FileManager.default.removeItem(at: directory) }
        model.load("m", context: .tokens(8_192))
        #expect(try await eventually { server.record.modelCalls.loaded.count == 1 && model.loads["m"] == nil })
        model.load("m")
        #expect(try await eventually { server.record.modelCalls.loaded.count == 2 })
        #expect(server.record.modelCalls.loaded == [ContextChoice.tokens(8_192).wire, nil])
    }

    @Test func estimateLeavesTheSavedInspectionAlone() async throws {
        let (directory, server, model) = try await harness()
        defer { model.shutdown(); server.stop(); try? FileManager.default.removeItem(at: directory) }
        await model.inspect("m")
        #expect(model.inspections["m"]?.context?.saved == .automatic)
        let estimate = await model.estimate("m", context: .tokens(4_096))
        #expect(estimate?.configuredCacheTokens == 4_096)
        #expect(model.inspections["m"]?.memory?.configuredCacheTokens == StandInRuntime.automaticTokens)
        #expect(server.record.modelCalls.inspected == [nil, ContextChoice.tokens(4_096).wire])
    }

    @Test func savingAContextSendsItWithoutSettings() async throws {
        let (directory, server, model) = try await harness()
        defer { model.shutdown(); server.stop(); try? FileManager.default.removeItem(at: directory) }
        await model.updateSettings("m", nil, context: .tokens(2_048))
        let settings = GenerationSettings(maxTokens: 512, temperature: 0.7, topP: 0.9, topK: 40, repetitionPenalty: 1)
        await model.updateSettings("m", settings)
        let updated = server.record.modelCalls.updated
        #expect(updated.map(\.settings) == [false, true])
        #expect(updated.map(\.context) == [ContextChoice.tokens(2_048).wire, nil])
        #expect(model.inspections["m"] != nil, "a save shows what the server saved")
    }

    @Test func maxTokensFollowASmallerContext() {
        let settings = GenerationSettings(maxTokens: 8_192, temperature: 0.7, topP: 0.9, topK: 40, repetitionPenalty: 1)
        #expect(settings.boundingMaxTokens(by: 1_024).maxTokens == 1_024)
        #expect(settings.boundingMaxTokens(by: 16_384).maxTokens == 8_192)
        #expect(GenerationSettings(maxTokens: 0, temperature: 0, topP: 1, topK: 0, repetitionPenalty: 1)
            .boundingMaxTokens(by: 1_024).maxTokens == 1)
    }
}