import Foundation

/// Where a mirmir server can be reached. Mirrors mirmir's `Instance`, plus the
/// planned remote target from the product decisions.
public enum InstanceTarget: Hashable, Sendable, Codable {
    /// The per-user server whose socket is resolved like `Paths::discover`.
    case personal
    /// The shared system server at `/run/mirmir/mirmir.sock`.
    case system
    /// An explicitly selected Unix socket.
    case socket(path: String)
    /// A remote server over gRPC + TLS. Not served by mirmir yet.
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
    public var host: String
    public var port: Int
    /// SHA-256 fingerprint pinned on first use. `nil` until trusted.
    public var pinnedFingerprint: String?

    public init(host: String, port: Int, pinnedFingerprint: String? = nil) {
        self.host = host
        self.port = port
        self.pinnedFingerprint = pinnedFingerprint
    }

    public var address: String { "\(host):\(port)" }
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
