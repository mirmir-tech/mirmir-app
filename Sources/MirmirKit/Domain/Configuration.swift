import Foundation

/// A server's configuration as its `Runtime` service presents it: every
/// setting with its effective value, and whether the two secrets are set.
/// Secrets are never returned in clear text.
public struct ServerConfiguration: Hashable, Sendable {
    public let entries: [ConfigurationEntry]
    public let huggingFaceToken: SecretState
    public let httpAPIKey: SecretState
    /// Where the server keeps `config.toml` and `secrets.toml`; `nil` over a
    /// remote key, which is not told the server's paths.
    public let files: ConfigurationFiles?

    public init(
        entries: [ConfigurationEntry], huggingFaceToken: SecretState, httpAPIKey: SecretState,
        files: ConfigurationFiles?
    ) {
        self.entries = entries
        self.huggingFaceToken = huggingFaceToken
        self.httpAPIKey = httpAPIKey
        self.files = files
    }

    /// Entries in the server's order, grouped by the part of mirmir they set.
    public var sections: [ConfigurationSection] {
        ConfigurationGroup.allCases.compactMap { group in
            let entries = entries.filter { $0.group == group }
            return entries.isEmpty ? nil : ConfigurationSection(group: group, entries: entries)
        }
    }

    public func entry(_ key: String) -> ConfigurationEntry? {
        entries.first { $0.key == key }
    }
}

public struct ConfigurationSection: Hashable, Sendable, Identifiable {
    public let group: ConfigurationGroup
    public let entries: [ConfigurationEntry]

    public var id: ConfigurationGroup { group }
}

public struct ConfigurationFiles: Hashable, Sendable {
    public let config: String
    public let secrets: String
}

/// One setting. `value` is the effective value as mirmir prints it, with
/// `auto` for an optional setting that is not overridden.
public struct ConfigurationEntry: Hashable, Sendable, Identifiable {
    public let key: String
    public let value: String
    public let source: ConfigurationSource
    public let access: ConfigurationAccess
    /// Whether a change takes effect only after the server restarts.
    public let restartRequired: Bool

    public var id: String { key }

    public init(
        key: String, value: String, source: ConfigurationSource, access: ConfigurationAccess, restartRequired: Bool
    ) {
        self.key = key
        self.value = value
        self.source = source
        self.access = access
        self.restartRequired = restartRequired
    }

    public var group: ConfigurationGroup { ConfigurationGroup(key: key) }

    /// Whether `config.toml` overrides the default, so it can be reset.
    public var isOverridden: Bool { source == .configFile }
}

public enum ConfigurationGroup: Hashable, Sendable, CaseIterable {
    case general
    case server
    case runtime

    init(key: String) {
        if key.hasPrefix("server.") {
            self = .server
        } else if key.hasPrefix("runtime.") {
            self = .runtime
        } else {
            self = .general
        }
    }
}

/// Where an effective value comes from.
public enum ConfigurationSource: Hashable, Sendable {
    case defaultValue
    case configFile
    case secretsFile
    case environment
    case unrecognized(String)
}

/// Whether this app may change a setting, and if not, why.
public enum ConfigurationAccess: Hashable, Sendable {
    case editable
    /// The server refuses the change here: some settings change only with
    /// Remote Access, and a remote key may not change the server's own.
    case serverReadOnly
    /// Mirmir sets it for the server it runs, so a change would break the app.
    case managedByApp(reason: String)

    public var isEditable: Bool { self == .editable }
}

/// A secret is reported only as set or not, with where it comes from.
public enum SecretState: Hashable, Sendable {
    case missing
    case configured(ConfigurationSource)

    public var isConfigured: Bool {
        if case .configured = self { true } else { false }
    }
}

/// One change to a server's configuration.
public enum ConfigurationChange: Hashable, Sendable {
    /// Sets a setting; `auto` (or empty) removes an optional override.
    case set(key: String, value: String)
    case setHuggingFaceToken(String)
    case removeHuggingFaceToken
    /// Asks the Hugging Face Hub who the stored token belongs to.
    case testHuggingFaceToken
    case setHTTPAPIKey(String)
    case removeHTTPAPIKey
}

/// What the server answered to a change.
public struct ConfigurationUpdate: Hashable, Sendable {
    public let configuration: ServerConfiguration
    /// mirmir's own description of what happened, such as the account a
    /// Hugging Face token belongs to.
    public let message: String
    public let restartRequired: Bool
}

extension ServerConfiguration {
    /// Settings the bundled server must keep for this app: the HTTP address
    /// it shows and the certificate paths the sandbox could not read.
    func managedByApp() -> ServerConfiguration {
        let managed: [String: String] = [
            "server.http_bind": "Mirmir sets this address for the server it runs, and shows it in Settings.",
            "server.remote_tls_cert": "The sandboxed server reads only its own folder; Remote Access uses its self-signed certificate.",
            "server.remote_tls_key": "The sandboxed server reads only its own folder; Remote Access uses its self-signed certificate.",
        ]
        let entries = entries.map { entry in
            guard entry.access == .editable, let reason = managed[entry.key] else { return entry }
            return ConfigurationEntry(
                key: entry.key, value: entry.value, source: entry.source,
                access: .managedByApp(reason: reason), restartRequired: entry.restartRequired
            )
        }
        return ServerConfiguration(
            entries: entries, huggingFaceToken: huggingFaceToken, httpAPIKey: httpAPIKey, files: files
        )
    }
}
