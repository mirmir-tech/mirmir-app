import Foundation
import Testing
@testable import MirmirKit

@Suite("Socket resolution and compatibility")
struct ConnectionTests {
    @Test func personalSocketDefaultsToStateDirectory() {
        let paths = SocketPaths(environment: ["HOME": "/Users/test"])
        #expect(paths.personalSocket == "/Users/test/.local/state/mirmir/mirmir.sock")
    }

    @Test func runtimeDirectoryWinsOverStateHome() {
        let paths = SocketPaths(environment: ["HOME": "/h", "MIRMIR_STATE_HOME": "/state", "XDG_RUNTIME_DIR": "/run/user/1"])
        #expect(paths.personalSocket == "/run/user/1/mirmir/mirmir.sock")
    }

    @Test func stateHomeOverridesXDG() {
        let paths = SocketPaths(environment: ["HOME": "/h", "MIRMIR_STATE_HOME": "/state", "XDG_STATE_HOME": "/xdg"])
        #expect(paths.personalSocket == "/state/mirmir.sock")
        let xdg = SocketPaths(environment: ["HOME": "/h", "XDG_STATE_HOME": "/xdg"])
        #expect(xdg.personalSocket == "/xdg/mirmir/mirmir.sock")
    }

    @Test func targetsResolveToSockets() {
        let paths = SocketPaths(environment: ["HOME": "/h"])
        #expect(paths.socket(for: .system) == "/run/mirmir/mirmir.sock")
        #expect(paths.socket(for: .socket(path: "/tmp/a.sock")) == "/tmp/a.sock")
        #expect(paths.socket(for: .remote(RemoteEndpoint(host: "lab", port: 7443))) == nil)
    }

    @Test func protocolMismatchNeedsUpdate() {
        #expect(ProtocolCompatibility(health: ServerHealth(protocolVersion: clientProtocolVersion, serverVersion: "0.5.5")) == .compatible)
        #expect(ProtocolCompatibility(health: ServerHealth(protocolVersion: "0", serverVersion: "0.4.0")) == .updateNeeded(serverProtocol: "0"))
    }

    @Test func missingSocketIsNoServer() async {
        await #expect(throws: ConnectionError.noServer(socket: "/nonexistent/mirmir.sock")) {
            _ = try await RuntimeConnection.connect(socket: "/nonexistent/mirmir.sock")
        }
    }

    @Test func instanceRecordsRoundTrip() throws {
        let records = [
            InstanceRecord(name: "Lab", target: .socket(path: "/tmp/lab.sock")),
            InstanceRecord(name: "CUDA", target: .remote(RemoteEndpoint(host: "lab-cuda-01", port: 7443, pinnedFingerprint: "4F:8E"))),
        ]
        let data = try JSONEncoder.mirmir.encode(records)
        #expect(try JSONDecoder.mirmir.decode([InstanceRecord].self, from: data) == records)
    }
}

@Suite("Logs and chat")
@MainActor
struct LogAndChatTests {
    @Test func logBufferJoinsPartialLines() {
        let logs = LogBuffer(capacity: 3)
        logs.append("first\nsec", stream: .stderr)
        logs.append("ond\n\u{1B}[32mthird\u{1B}[0m\nfourth\n", stream: .stderr)
        #expect(logs.lines.map(\.text) == ["second", "third", "fourth"])
    }

    @Test func accumulatorMeasuresThinking() {
        let reply = ReplyAccumulator()
        reply.append("hmm", reasoning: true)
        reply.append("Answer", reasoning: false)
        #expect(reply.reasoning == "hmm")
        #expect(reply.text == "Answer")
        #expect(reply.thinkingSeconds != nil)
    }

    @Test func failedRepliesAreNotReplayed() {
        let failed = ChatMessage(body: .assistant(text: "partial", reasoning: "", thinkingSeconds: nil, state: .failed(message: "x")))
        let stopped = ChatMessage(body: .assistant(text: "partial", reasoning: "", thinkingSeconds: nil, state: .stopped))
        #expect(failed.turn == nil)
        #expect(stopped.turn?.content == "partial")
    }
}

@Suite("Model names")
struct ModelNameTests {
    @Test func cachePathsShowTheRepository() {
        #expect(Conversation.modelName("/s/hf-hub/models--mlx-community--Qwen3-0.6B-4bit/snapshots/73e3e38") == "Qwen3-0.6B-4bit")
        #expect(Conversation.modelName("mlx-community/Qwen3-4B") == "Qwen3-4B")
        #expect(Conversation.modelName("alias") == "alias")
    }
}
