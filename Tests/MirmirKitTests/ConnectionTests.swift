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
        #expect(paths.socket(for: .personal) == "/h/.local/state/mirmir/mirmir.sock")
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
            InstanceRecord.thisMac,
            InstanceRecord(name: "CUDA", target: .remote(RemoteEndpoint(host: "lab-cuda-01", port: 7443, pinnedFingerprint: CertificateFingerprint(String(repeating: "4f", count: 32))))),
        ]
        let data = try JSONEncoder.mirmir.encode(records)
        #expect(try JSONDecoder.mirmir.decode([InstanceRecord].self, from: data) == records)
    }
}

@Suite("Remote servers")
struct RemoteTests {
    @Test func fingerprintsUseMirmirsFormat() throws {
        let fingerprint = CertificateFingerprint(der: Array("certificate".utf8))
        #expect(fingerprint.hex.count == 32 * 3 - 1)
        #expect(fingerprint.hex == fingerprint.hex.uppercased())
        #expect(CertificateFingerprint(fingerprint.hex) == fingerprint)
        let plain = fingerprint.hex.replacingOccurrences(of: ":", with: "").lowercased()
        #expect(CertificateFingerprint(plain) == fingerprint)
        #expect(CertificateFingerprint("SHA256:" + fingerprint.hex) == fingerprint)
        #expect(CertificateFingerprint("AB:CD") == nil)
        #expect(CertificateFingerprint(String(repeating: "ZZ", count: 32)) == nil)
    }

    @Test func parsesRemoteAddresses() {
        #expect(RemoteEndpoint(address: "ziemniak.local")?.address == "ziemniak.local:7443")
        #expect(RemoteEndpoint(address: "10.0.0.4:9000")?.port == 9000)
        #expect(RemoteEndpoint(address: "[::1]")?.address == "[::1]:7443")
        #expect(RemoteEndpoint(address: "[::1]:9000")?.host == "::1")
        #expect(RemoteEndpoint(address: "host:notaport") == nil)
        #expect(RemoteEndpoint(address: "") == nil)
    }

    @Test func parsesPastedAddressesStrictly() {
        // The app shows remote addresses with their scheme; pasting one back works.
        #expect(RemoteEndpoint(address: "grpcs://host:7443")?.address == "host:7443")
        #expect(RemoteEndpoint(address: "GRPCS://[::1]:9000")?.address == "[::1]:9000")
        #expect(RemoteEndpoint(address: " lab.local:9000\n")?.port == 9000)
        #expect(RemoteEndpoint(address: "fe80::1")?.address == "[fe80::1]:7443")
        #expect(RemoteEndpoint(address: "[::1]foo") == nil)
        #expect(RemoteEndpoint(address: "[::1]:") == nil)
        #expect(RemoteEndpoint(address: "[::1") == nil)
        #expect(RemoteEndpoint(address: "[lab.local]:7443") == nil)
        #expect(RemoteEndpoint(address: "grpcs://host:7443/") == nil)
        #expect(RemoteEndpoint(address: "https://host") == nil)
        #expect(RemoteEndpoint(address: "lab local") == nil)
        #expect(RemoteEndpoint(address: "host:7443:1") == nil)
        #expect(RemoteEndpoint(address: "host:+7443") == nil)
        #expect(RemoteEndpoint(address: "host:70000") == nil)
        #expect(RemoteEndpoint(address: "grpcs://") == nil)
    }

    #if canImport(Darwin)
    // AppModel stores instances under Application Support, which
    // swift-corelibs-foundation does not provide.
    @Test @MainActor func remoteWithoutKeyNeedsOne() async {
        let model = AppModel(credentials: MemoryCredentials(), chats: nil)
        let record = InstanceRecord(name: "Lab", target: .remote(RemoteEndpoint(host: "lab")))
        await #expect(throws: ConnectionError.missingKey(address: "lab:7443")) {
            _ = try await model.open(record)
        }
    }
    #endif

    @Test func credentialsAreKeptPerInstance() throws {
        let store = MemoryCredentials()
        let first = UUID()
        try store.setKey("mmk_a", for: first)
        #expect(store.key(for: first) == "mmk_a")
        #expect(store.key(for: UUID()) == nil)
        store.removeKey(for: first)
        #expect(store.key(for: first) == nil)
    }

    @Test func rejectedKeysAndChangedCertificatesAreNamed() {
        let pinned = CertificateFingerprint(der: [1])
        let presented = CertificateFingerprint(der: [2])
        let changed = ConnectionError.remote(
            ConnectionError.rpc(code: .unavailable, message: ""), address: "lab:7443", pinned: pinned, presented: presented
        )
        #expect(changed == .certificateChanged(address: "lab:7443", pinned: pinned, presented: presented))
        let rejected = ConnectionError.remote(
            ConnectionError.rpc(code: .unauthenticated, message: "no"), address: "lab:7443", pinned: pinned, presented: pinned
        )
        #expect(rejected == .keyRejected(address: "lab:7443"))
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
