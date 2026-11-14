#if DEBUG
import Foundation

extension PreviewData {
    /// A bundled server with a few overrides, as previews show it.
    static let configuration = ServerConfiguration(
        entries: [
            entry("default_model", "auto", restart: false),
            entry("server.http_bind", "127.0.0.1:18080", .configFile),
            entry("server.allow_remote", "false"),
            entry("server.web_enabled", "true", .configFile),
            entry("server.cors_origins", ""),
            entry("server.body_limit_bytes", "29360128"),
            entry("server.request_timeout_seconds", "300"),
            entry("server.max_concurrency", "16"),
            entry("server.remote_bind", "0.0.0.0:7443", .configFile, editable: false, restart: false),
            entry("server.remote_tls_cert", "self-signed"),
            entry("server.remote_tls_key", "self-signed"),
            entry("runtime.kv_block_size", "auto"),
            entry("runtime.kv_blocks", "auto"),
            entry("runtime.kv_cache_dtype", "auto"),
            entry("runtime.max_batch_requests", "8", .configFile),
            entry("runtime.cached_prefill_policy", "interleave_one_block", .configFile),
            entry("runtime.metal_decode_reservation", "auto"),
            entry("runtime.memory_reserve_percent", "auto"),
            entry("runtime.vision_memory_percent", "auto"),
        ],
        huggingFaceToken: .configured(.secretsFile),
        httpAPIKey: .missing,
        files: ConfigurationFiles(
            config: "~/Library/Containers/tech.mirmir.app/Data/.config/mirmir/config.toml",
            secrets: "~/Library/Containers/tech.mirmir.app/Data/.config/mirmir/secrets.toml"
        )
    )

    private static func entry(
        _ key: String, _ value: String, _ source: ConfigurationSource = .defaultValue,
        editable: Bool = true, restart: Bool = true
    ) -> ConfigurationEntry {
        ConfigurationEntry(
            key: key, value: value, source: source, access: editable ? .editable : .serverReadOnly,
            restartRequired: restart
        )
    }
}
#endif
