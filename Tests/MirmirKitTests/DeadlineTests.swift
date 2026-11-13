import Foundation
import Testing
@testable import MirmirKit

/// A server that answers Health and then stalls must fail unary calls within
/// their deadline, so the session reconnects and probes move on.
@Suite("Unary call deadlines")
struct DeadlineTests {
    /// Health keeps the standard deadline; every later unary call gives up
    /// after 300 ms so the tests stay fast.
    static let short = CallDeadlines(
        monitoring: .milliseconds(300), discovery: .milliseconds(300),
        catalog: .milliseconds(300), management: .milliseconds(300)
    )

    /// A short directory for the stalled server's socket.
    static func scratch() throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mm-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    @Test func everyUnaryKindHasAFiniteDeadline() {
        let kinds: [UnaryCall] = [.health, .monitoring, .discovery, .catalog, .management]
        for kind in kinds {
            #expect(CallDeadlines.standard.timeout(for: kind) > .zero)
            #expect(CallDeadlines.standard.options(for: kind).timeout == CallDeadlines.standard.timeout(for: kind))
        }
    }

    @Test func stalledTelemetryTimesOutAfterHealth() async throws {
        let directory = try Self.scratch()
        defer { try? FileManager.default.removeItem(at: directory) }
        let server = try await StallingServer(socket: directory.appendingPathComponent("mirmir.sock").path)
        defer { server.stop() }

        let connection = try await RuntimeConnection.connect(socket: server.socket, deadlines: Self.short)
        defer { connection.close() }
        #expect(connection.health.serverVersion == "0.6.0-stalled")

        let start = ContinuousClock.now
        let expected = ConnectionError.timedOut(address: server.socket, after: .milliseconds(300))
        await #expect(throws: expected) { _ = try await connection.telemetry() }
        await #expect(throws: expected) { _ = try await connection.activeSelectors() }
        #expect(ContinuousClock.now - start < .seconds(3))
        #expect(expected.isUnreachable)
    }

    #if canImport(Darwin)
    @Test @MainActor func stalledServerDoesNotHoldTheProbeOrTheSession() async throws {
        let directory = try Self.scratch()
        defer { try? FileManager.default.removeItem(at: directory) }
        let server = try await StallingServer(socket: directory.appendingPathComponent("mirmir.sock").path)
        defer { server.stop() }
        let model = AppModel(
            paths: SocketPaths(environment: ["HOME": directory.path, "MIRMIR_STATE_HOME": directory.path]),
            supervisor: ServerSupervisor(logFile: directory.appendingPathComponent("server.log")),
            credentials: MemoryCredentials(),
            modelFolders: ModelFolders(file: JSONFile(name: "model-folders.json", directory: directory)),
            deadlines: Self.short,
            chats: ChatStore(directory: directory)
        )
        model.serverPaused = true

        // This Mac probed as another instance: the probe finishes and marks it
        // offline instead of waiting forever.
        model.currentInstanceID = UUID()
        let start = ContinuousClock.now
        await model.probe(.thisMac)
        #expect(ContinuousClock.now - start < .seconds(3))
        guard case .offline(let reason) = model.summary(for: .thisMac).status else {
            Issue.record("probe left \(model.summary(for: .thisMac).status)")
            return
        }
        #expect(reason.contains("did not answer"))

        // The current session connects, then drops the stalled connection.
        model.currentInstanceID = InstanceRecord.thisMacID
        model.connectCurrent()
        defer { model.sessionTask?.cancel() }
        let deadline = ContinuousClock.now + .seconds(5)
        var lost: ConnectionError?
        while ContinuousClock.now < deadline {
            if case .offline(let error) = model.phase, case .timedOut = error {
                lost = error
                break
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(lost == .timedOut(address: server.socket, after: .milliseconds(300)))
    }
    #endif
}
