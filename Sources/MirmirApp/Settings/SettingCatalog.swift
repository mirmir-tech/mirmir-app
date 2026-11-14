import MirmirKit
import SwiftUI

/// How a setting is shown and edited. mirmir validates every value, so a
/// key this catalog does not know is still shown, under Other, as text.
struct SettingDescription {
    let title: String
    let help: String
    let category: SettingCategory
    let control: SettingControl
}

enum SettingControl {
    /// Free text; an empty field sends `auto` when `automatic` is set.
    case text(automatic: Bool)
    /// A whole number; empty means `auto` when `automatic` is set.
    case number(unit: SettingUnit?, automatic: Bool)
    case toggle
    /// `auto` for the backend default, or one of the documented alternatives;
    /// a value set elsewhere is offered as it is.
    case choice([SettingChoice])
}

enum SettingUnit {
    case bytes, seconds, microseconds, percent, tokens, pixels

    var label: String {
        switch self {
        case .bytes: "bytes"
        case .seconds: "s"
        case .microseconds: "µs"
        case .percent: "%"
        case .tokens: "tokens"
        case .pixels: "px"
        }
    }
}

struct SettingChoice: Hashable {
    let value: String
    let label: String
}

/// The cards of the Configuration screen, in the order they are shown.
enum SettingCategory: CaseIterable, Identifiable {
    case defaults, httpAPI, remoteAccess, scheduling, kvCache, memory, vision, other

    var id: Self { self }

    var title: String {
        switch self {
        case .defaults: "DEFAULTS"
        case .httpAPI: "HTTP API"
        case .remoteAccess: "REMOTE ACCESS"
        case .scheduling: "SCHEDULING"
        case .kvCache: "K/V CACHE"
        case .memory: "MEMORY"
        case .vision: "VISION"
        case .other: "OTHER"
        }
    }

    var summary: String {
        switch self {
        case .defaults: "What the server does when a request leaves it open."
        case .httpAPI: "The OpenAI-compatible API your editor, scripts and browser use."
        case .remoteAccess: "The TLS listener other Macs and the mirmir CLI connect to."
        case .scheduling: "How requests are batched between prefill and decode."
        case .kvCache: "Where attention keys and values live while a model answers."
        case .memory: "How much memory stays outside model admission."
        case .vision: "Limits for images sent to vision models."
        case .other: "Settings this version of Mirmir does not describe yet."
        }
    }

    var symbol: String {
        switch self {
        case .defaults: "star"
        case .httpAPI: "network"
        case .remoteAccess: "lock.shield"
        case .scheduling: "arrow.triangle.branch"
        case .kvCache: "square.stack.3d.up"
        case .memory: "memorychip"
        case .vision: "photo"
        case .other: "ellipsis.circle"
        }
    }

    var color: Color {
        switch self {
        case .defaults, .httpAPI, .remoteAccess: Palette.signal
        case .scheduling, .kvCache: Palette.brass
        case .memory, .vision: Palette.success
        case .other: Palette.muted
        }
    }
}

enum SettingCatalog {
    static func describe(_ key: String) -> SettingDescription {
        known[key] ?? SettingDescription(title: key, help: "", category: .other, control: .text(automatic: false))
    }

    private static let automatic = SettingChoice(value: "auto", label: "Automatic")

    private static let known: [String: SettingDescription] = [
        "default_model": text(
            "Default model", "Answers API requests that name no model. Automatic picks a loaded one.", .defaults
        ),
        "server.http_bind": text("Address", "Where the API listens.", .httpAPI, automatic: false),
        "server.allow_remote": toggle("Allow a network address", "Lets the API listen where other machines reach it.", .httpAPI),
        "server.web_enabled": toggle("Web dashboard", "Serves mirmir's browser dashboard at /ui/.", .httpAPI),
        "server.cors_origins": text(
            "Browser origins", "Exact origins, separated by commas, that web pages may call the API from.", .httpAPI,
            automatic: false
        ),
        "server.request_timeout_seconds": number("Request timeout", "How long one request may take.", .httpAPI, .seconds, automatic: false),
        "server.max_concurrency": number("Concurrent requests", "Requests handled at the same time.", .httpAPI, nil, automatic: false),
        "server.body_limit_bytes": number("Request size limit", "Largest request body accepted.", .httpAPI, .bytes, automatic: false),
        "server.remote_bind": text("Listener", "Turned on and off with Remote Access in Instances.", .remoteAccess, automatic: false),
        "server.remote_tls_cert": text("Certificate", "PEM certificate; empty uses a self-signed one.", .remoteAccess),
        "server.remote_tls_key": text("Private key", "PEM key for the certificate.", .remoteAccess),
        "runtime.max_batch_requests": number("Batch requests", "Requests decoded together at most.", .scheduling, nil),
        "runtime.max_batch_tokens": number("Batch tokens", "Token budget of one scheduler step.", .scheduling, .tokens),
        "runtime.prefill_batch_wait_us": number("Prefill batch wait", "Short wait to gather a prefill batch.", .scheduling, .microseconds),
        "runtime.decode_batch_wait_us": number("Decode batch wait", "Short wait to gather a decode batch.", .scheduling, .microseconds),
        "runtime.decode_priority_burst": number("Decode priority burst", "Decode steps run before other waiting work.", .scheduling, nil),
        "runtime.cached_prefill_policy": choice(
            "Cached prefill", "Interleaving admits one cached continuation during decode: earlier first tokens, slower decode.",
            .scheduling, [("interleave_one_block", "Interleave one block")]
        ),
        "runtime.prefill_decode_policy": choice(
            "Prefill and decode", "Complete cohort finishes a prefill group first: fuller decode batches, later first tokens.",
            .scheduling, [("complete_cohort", "Complete cohort")]
        ),
        "runtime.prefill_refill_policy": choice(
            "Prefill refill", "Short prompts of up to 128 tokens may join a running prefill (CUDA).",
            .scheduling, [("short_prompt", "Short prompts")]
        ),
        "runtime.speculative_draft_tokens": number(
            "Speculative draft tokens", "1 to 8, for a CUDA checkpoint with a prediction head.", .scheduling, .tokens
        ),
        "runtime.kv_cache_dtype": text(
            "Storage type", "Such as bfloat16 or fp8; the backend checks what it supports.", .kvCache
        ),
        "runtime.kv_block_size": number("Block size", "Tokens stored in one block.", .kvCache, .tokens),
        "runtime.kv_blocks": number("Blocks", "Total cache capacity, in blocks.", .kvCache, nil),
        "runtime.metal_decode_reservation": choice(
            "Decode reservation", "Generation budget reserves pages for a request's whole answer.",
            .kvCache, [("generation_budget", "Generation budget")]
        ),
        "runtime.memory_reserve_percent": number("Reserve", "Share of memory kept free of models.", .memory, .percent),
        "runtime.memory_reserve_bytes": number("Fixed reserve", "Memory kept free in addition.", .memory, .bytes),
        "runtime.vision_max_pixels": number("Image size limit", "Largest image area after resizing.", .vision, .pixels),
        "runtime.vision_attention_budget_bytes": number("Attention budget", "Workspace for image attention.", .vision, .bytes),
        "runtime.vision_memory_percent": number("Vision memory", "Memory automatic image budgets may use.", .vision, .percent),
    ]

    private static func text(
        _ title: String, _ help: String, _ category: SettingCategory, automatic: Bool = true
    ) -> SettingDescription {
        SettingDescription(title: title, help: help, category: category, control: .text(automatic: automatic))
    }

    private static func toggle(_ title: String, _ help: String, _ category: SettingCategory) -> SettingDescription {
        SettingDescription(title: title, help: help, category: category, control: .toggle)
    }

    private static func number(
        _ title: String, _ help: String, _ category: SettingCategory, _ unit: SettingUnit?, automatic: Bool = true
    ) -> SettingDescription {
        SettingDescription(title: title, help: help, category: category, control: .number(unit: unit, automatic: automatic))
    }

    private static func choice(
        _ title: String, _ help: String, _ category: SettingCategory, _ values: [(String, String)]
    ) -> SettingDescription {
        let choices = [automatic] + values.map { SettingChoice(value: $0.0, label: $0.1) }
        return SettingDescription(title: title, help: help, category: category, control: .choice(choices))
    }
}
