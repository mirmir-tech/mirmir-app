import Foundation

/// Where a mirmir server can be reached. Mirrors mirmir's `Instance`.
public enum InstanceTarget: Hashable, Sendable, Codable {
    /// The per-user server whose socket is resolved like `Paths::discover`.
    case personal
    /// The shared system server at `/run/mirmir/mirmir.sock`.
    case system
    /// An explicitly selected Unix socket.
    case socket(path: String)
    /// A remote server's TLS listener; its API key is kept in the Keychain.
    case remote(RemoteEndpoint)

    public static let systemSocket = "/run/mirmir/mirmir.sock"

    public var kind: InstanceKind {
        switch self {
        case .personal: .personal
        case .system: .system
        case .socket: .socket
        case .remote: .remote
        }
    }
}

public struct RemoteEndpoint: Hashable, Sendable, Codable {
    public static let defaultPort = 7443

    public var host: String
    public var port: Int
    /// The certificate trusted on first use. `nil` trusts CA-issued
    /// certificates through the system roots instead.
    public var pinnedFingerprint: CertificateFingerprint?

    public init(host: String, port: Int = Self.defaultPort, pinnedFingerprint: CertificateFingerprint? = nil) {
        self.host = host
        self.port = port
        self.pinnedFingerprint = pinnedFingerprint
    }

    /// Parses `host`, `host:port`, `[v6]` or `[v6]:port`.
    public init?(address: String) {
        let text = address.trimmingCharacters(in: .whitespaces)
        var host = text
        var port = Self.defaultPort
        if text.hasPrefix("["), let close = text.firstIndex(of: "]") {
            host = String(text[text.index(after: text.startIndex)..<close])
            let rest = text[text.index(after: close)...]
            if rest.hasPrefix(":") {
                guard let parsed = Int(rest.dropFirst()) else { return nil }
                port = parsed
            }
        } else if text.filter({ $0 == ":" }).count == 1, let colon = text.firstIndex(of: ":") {
            host = String(text[..<colon])
            guard let parsed = Int(text[text.index(after: colon)...]) else { return nil }
            port = parsed
        }
        guard !host.isEmpty, (1...65535).contains(port) else { return nil }
        self.init(host: host, port: port)
    }

    public var address: String { host.contains(":") ? "[\(host)]:\(port)" : "\(host):\(port)" }
}

public enum InstanceKind: Sendable {
    case personal, system, socket, remote

    public var label: String {
        switch self {
        case .personal: "Personal"
        case .system: "System"
        case .socket: "Socket"
        case .remote: "Remote"
        }
    }

    public var isLocal: Bool { self != .remote }
}

/// A saved instance as shown in the sidebar, menu bar and Instances screen.
public struct InstanceRecord: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public var name: String
    public var target: InstanceTarget

    public init(id: UUID = UUID(), name: String, target: InstanceTarget) {
        self.id = id
        self.name = name
        self.target = target
    }

    /// The fixed identity of "This Mac", so it survives store rewrites.
    public static let thisMacID = UUID(uuidString: "00000000-0000-0000-0000-00000000A11C")!

    public static let thisMac = InstanceRecord(id: thisMacID, name: "This Mac", target: .personal)

    public var isThisMac: Bool { id == Self.thisMacID }
}
