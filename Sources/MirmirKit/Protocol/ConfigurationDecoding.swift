import Foundation
import MirmirRPC

extension ConfigurationSource {
    init(wire: String) {
        switch wire {
        case "default": self = .defaultValue
        case "config.toml": self = .configFile
        case "secrets.toml": self = .secretsFile
        case "environment": self = .environment
        default: self = .unrecognized(wire)
        }
    }
}

extension SecretState {
    init(_ wire: Mirmir_V1_SecretState) {
        self = wire.configured ? .configured(ConfigurationSource(wire: wire.source)) : .missing
    }
}

extension ConfigurationEntry {
    init(_ wire: Mirmir_V1_ConfigurationValue) {
        self.init(
            key: wire.key,
            value: wire.value,
            source: ConfigurationSource(wire: wire.source),
            access: wire.editable ? .editable : .serverReadOnly,
            restartRequired: wire.restartRequired
        )
    }
}

extension ServerConfiguration {
    init(_ wire: Mirmir_V1_ConfigurationSnapshot) {
        // A remote key is given neither path; the local socket gets both.
        let files = wire.configPath.isEmpty
            ? nil : ConfigurationFiles(config: wire.configPath, secrets: wire.secretsPath)
        self.init(
            entries: wire.values.map(ConfigurationEntry.init),
            huggingFaceToken: wire.hasHuggingFaceToken ? SecretState(wire.huggingFaceToken) : .missing,
            httpAPIKey: wire.hasHTTPApiKey ? SecretState(wire.httpApiKey) : .missing,
            files: files
        )
    }
}

extension ConfigurationUpdate {
    init(_ wire: Mirmir_V1_UpdateConfigurationResponse) {
        self.init(
            configuration: ServerConfiguration(wire.configuration),
            message: wire.message,
            restartRequired: wire.restartRequired
        )
    }
}

extension ConfigurationChange {
    var wire: Mirmir_V1_UpdateConfigurationRequest {
        var request = Mirmir_V1_UpdateConfigurationRequest()
        switch self {
        case .set(let key, let value):
            var operation = Mirmir_V1_SetConfigurationValue()
            operation.key = key
            operation.value = value
            request.setValue = operation
        case .setHuggingFaceToken(let token):
            var operation = Mirmir_V1_SetHfToken()
            operation.token = token
            request.setHfToken = operation
        case .removeHuggingFaceToken:
            request.removeHfToken = Mirmir_V1_RemoveHfToken()
        case .testHuggingFaceToken:
            request.testHfToken = Mirmir_V1_TestHfToken()
        case .setHTTPAPIKey(let key):
            var operation = Mirmir_V1_SetHttpApiKey()
            operation.key = key
            request.setHTTPApiKey = operation
        case .removeHTTPAPIKey:
            request.removeHTTPApiKey = Mirmir_V1_RemoveHttpApiKey()
        }
        return request
    }
}
