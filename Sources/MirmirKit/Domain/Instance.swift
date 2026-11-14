import Foundation

/// Where a mirmir server can be reached. Mirrors mirmir's `Instance`.
///
/// The app is sandboxed: on this Mac it reaches only the server it bundles,
/// whose socket lives in its container. The CLI's personal socket, the system
/// socket and other sockets outside the container are not reachable, so they
/// are not instances the app can hold.
public enum InstanceTarget: Hashable, Sendable, Codable {
    /// The bundled server, with its state and socket in the app's container.
    case personal
    /// A remote server's TLS listener; its API key is kept in the Keychain.
    case remote(RemoteEndpoint)

    public var kind: InstanceKind {
        switch self {
        case .personal: .personal
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

    /// Parses `host`, `host:port`, `[v6]`, `[v6]:port` or a bare IPv6
    /// literal, optionally after `grpcs://` as the app displays it. Paths,
    /// whitespace inside the address and text after `]` other than a port
    /// are refused.
    public init?(address: String) {
        var text = Substring(address.trimmingCharacters(in: .whitespacesAndNewlines))
        if text.lowercased().hasPrefix(Self.scheme) { text = text.dropFirst(Self.scheme.count) }
        guard !text.contains(where: { $0 == "/" || $0.isWhitespace }) else { return nil }
        var host = text
        var port = Self.defaultPort
        if text.hasPrefix("[") {
            guard let close = text.firstIndex(of: "]") else { return nil }
            host = text[text.index(after: text.startIndex)..<close]
            let rest = text[text.index(after: close)...]
            if !rest.isEmpty {
                guard rest.hasPrefix(":"), let parsed = Self.port(rest.dropFirst()) else { return nil }
                port = parsed
            }
            guard String(host).isIPAddress, host.contains(":") else { return nil }
        } else if text.filter({ $0 == ":" }).count == 1, let colon = text.firstIndex(of: ":") {
            host = text[..<colon]
            guard let parsed = Self.port(text[text.index(after: colon)...]) else { return nil }
            port = parsed
        } else if text.contains(":") {
            // Several colons without brackets: only an IPv6 literal.
            guard String(text).isIPAddress else { return nil }
        }
        guard !host.isEmpty, !host.contains(where: { "[]".contains($0) }) else { return nil }
        self.init(host: String(host), port: port)
    }

    /// The scheme the app shows remote addresses with; accepted when pasted.
    public static let scheme = "grpcs://"

    private static func port(_ text: Substring) -> Int? {
        guard !text.isEmpty, text.allSatisfy(\.isASCII), text.allSatisfy(\.isNumber), let port = Int(text),
              (1...65535).contains(port)
        else { return nil }
        return port
    }

    public var address: String { host.contains(":") ? "[\(host)]:\(port)" : "\(host):\(port)" }
}

public enum InstanceKind: Sendable {
    case personal, remote

    public var label: String {
        switch self {
        // mirmir calls it the personal instance; to the user it is the
        // server on this Mac, as opposed to a remote one.
        case .personal: "Local"
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
