import Foundation
import MirmirRPC
import Testing
@testable import MirmirKit

@Suite("Server configuration")
struct ConfigurationTests {
    private func value(_ key: String, _ value: String, source: String, editable: Bool = true) -> Mirmir_V1_ConfigurationValue {
        var wire = Mirmir_V1_ConfigurationValue()
        wire.key = key
        wire.value = value
        wire.source = source
        wire.editable = editable
        wire.restartRequired = key != "default_model"
        return wire
    }

    private func snapshot(remote: Bool = false) -> Mirmir_V1_ConfigurationSnapshot {
        var wire = Mirmir_V1_ConfigurationSnapshot()
        wire.values = [
            value("default_model", "auto", source: "default"),
            value("server.http_bind", "127.0.0.1:18080", source: "config.toml"),
            value("server.remote_bind", "off", source: "default", editable: false),
            value("server.remote_tls_cert", "self-signed", source: "default"),
            value("runtime.kv_cache_dtype", "auto", source: "default"),
        ]
        var token = Mirmir_V1_SecretState()
        token.configured = true
        token.source = "secrets.toml"
        wire.huggingFaceToken = token
        var key = Mirmir_V1_SecretState()
        key.configured = false
        key.source = "not configured"
        wire.httpApiKey = key
        if !remote {
            wire.configPath = "/c/config.toml"
            wire.secretsPath = "/c/secrets.toml"
        }
        return wire
    }

    @Test func snapshotDecodesToDomain() {
        let configuration = ServerConfiguration(snapshot())
        #expect(configuration.entries.count == 5)
        #expect(configuration.entry("server.http_bind")?.source == .configFile)
        #expect(configuration.entry("server.http_bind")?.isOverridden == true)
        #expect(configuration.entry("default_model")?.source == .defaultValue)
        #expect(configuration.entry("default_model")?.restartRequired == false)
        #expect(configuration.entry("server.remote_bind")?.access == .serverReadOnly)
        #expect(configuration.huggingFaceToken == .configured(.secretsFile))
        #expect(configuration.httpAPIKey == .missing)
        #expect(configuration.files == ConfigurationFiles(config: "/c/config.toml", secrets: "/c/secrets.toml"))
    }

    @Test func remoteSnapshotHasNoPaths() {
        #expect(ServerConfiguration(snapshot(remote: true)).files == nil)
    }

    @Test func unknownSourceIsKept() {
        #expect(ConfigurationSource(wire: "model.toml") == .unrecognized("model.toml"))
        #expect(ConfigurationSource(wire: "environment") == .environment)
    }

    @Test func entriesGroupByPrefixInServerOrder() {
        let groups = ServerConfiguration(snapshot()).sections
        #expect(groups.map(\.group) == [.general, .server, .runtime])
        #expect(groups[1].entries.map(\.key) == ["server.http_bind", "server.remote_bind", "server.remote_tls_cert"])
    }

    @Test func appManagesItsServersAddressAndCertificate() {
        let managed = ServerConfiguration(snapshot()).managedByApp()
        guard case .managedByApp = managed.entry("server.http_bind")?.access else {
            Issue.record("server.http_bind should be managed by the app")
            return
        }
        guard case .managedByApp = managed.entry("server.remote_tls_cert")?.access else {
            Issue.record("server.remote_tls_cert should be managed by the app")
            return
        }
        // The server's own refusal is kept, and other settings stay editable.
        #expect(managed.entry("server.remote_bind")?.access == .serverReadOnly)
        #expect(managed.entry("runtime.kv_cache_dtype")?.access == .editable)
    }

    @Test func changesEncodeTheirOperation() {
        let set = ConfigurationChange.set(key: "runtime.kv_blocks", value: "auto").wire
        #expect(set.setValue.key == "runtime.kv_blocks")
        #expect(set.setValue.value == "auto")
        #expect(ConfigurationChange.setHuggingFaceToken("hf_x").wire.setHfToken.token == "hf_x")
        if case .removeHfToken = ConfigurationChange.removeHuggingFaceToken.wire.operation {} else {
            Issue.record("removeHuggingFaceToken")
        }
        if case .testHfToken = ConfigurationChange.testHuggingFaceToken.wire.operation {} else {
            Issue.record("testHuggingFaceToken")
        }
        #expect(ConfigurationChange.setHTTPAPIKey("k").wire.setHTTPApiKey.key == "k")
        if case .removeHTTPApiKey = ConfigurationChange.removeHTTPAPIKey.wire.operation {} else {
            Issue.record("removeHTTPAPIKey")
        }
    }

    @Test func updateCarriesMessageAndRestart() {
        var wire = Mirmir_V1_UpdateConfigurationResponse()
        wire.configuration = snapshot()
        wire.message = "token belongs to bazyl"
        wire.restartRequired = true
        let update = ConfigurationUpdate(wire)
        #expect(update.message == "token belongs to bazyl")
        #expect(update.restartRequired)
        #expect(update.configuration.entries.count == 5)
    }
}
