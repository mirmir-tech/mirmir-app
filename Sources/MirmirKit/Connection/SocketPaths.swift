import Foundation

/// Resolves the socket exactly like mirmir's `config::Paths::discover`. The
/// app is sandboxed and its server inherits that sandbox, so `HOME` is the
/// app's container for both: this is the bundled server's own socket, never
/// the CLI's.
///
/// Under the sandbox the container path is too long for a socket: with a
/// long account name `~/Library/Containers/tech.mirmir.app/Data/.local/state/
/// mirmir/mirmir.sock` exceeds the 103 bytes of Darwin's `sun_path`. The
/// sandbox lets a socket be bound only inside the container, so the server's
/// runtime directory stays there but is reached through `runtimeLink`, a
/// short symlink in the app's per-user directory under `/var/folders`. The
/// server gets it as `XDG_RUNTIME_DIR` (`serverEnvironment`), so the app and
/// the server name the same socket by the same short path.
public struct SocketPaths: Sendable {
    public let environment: [String: String]
    public let home: String
    /// `confstr(_CS_DARWIN_USER_DIR)`: `/var/folders/…/0/`, with the app's
    /// own subdirectory under the sandbox. Its length does not depend on the
    /// account name.
    public let darwinUserDirectory: String?

    public init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        home: String = NSHomeDirectory(),
        darwinUserDirectory: String? = SocketPaths.systemDarwinUserDirectory()
    ) {
        self.environment = environment
        self.home = environment["HOME"] ?? home
        self.darwinUserDirectory = darwinUserDirectory
    }

    public var stateDirectory: String {
        if let state = environment["MIRMIR_STATE_HOME"] { return state }
        if let xdg = environment["XDG_STATE_HOME"] { return (xdg as NSString).appendingPathComponent("mirmir") }
        return (home as NSString).appendingPathComponent(".local/state/mirmir")
    }

    /// mirmir's `config.toml`, resolved like `Paths::discover`.
    public var configFile: String {
        let directory = environment["MIRMIR_CONFIG_HOME"]
            ?? environment["XDG_CONFIG_HOME"].map { ($0 as NSString).appendingPathComponent("mirmir") }
            ?? (home as NSString).appendingPathComponent(".config/mirmir")
        return (directory as NSString).appendingPathComponent("config.toml")
    }

    public var runtimeDirectory: String {
        if let runtime = environment["XDG_RUNTIME_DIR"] ?? runtimeLink?.alias {
            return (runtime as NSString).appendingPathComponent("mirmir")
        }
        return stateDirectory
    }

    /// The sandboxed server's short runtime root, when the app chooses it:
    /// under the sandbox and without an explicit `XDG_RUNTIME_DIR`. Outside
    /// the sandbox (debug runs) the CLI's resolution applies unchanged.
    public var runtimeLink: RuntimeLink? {
        guard environment["XDG_RUNTIME_DIR"] == nil, environment["APP_SANDBOX_CONTAINER_ID"] != nil,
              let darwinUserDirectory
        else { return nil }
        return RuntimeLink(
            alias: (darwinUserDirectory as NSString).appendingPathComponent("run"),
            target: (stateDirectory as NSString).appendingPathComponent("run")
        )
    }

    /// Variables that make the server resolve the same socket as the app.
    public var serverEnvironment: [String: String] {
        runtimeLink.map { ["XDG_RUNTIME_DIR": $0.alias] } ?? [:]
    }

    /// Creates the runtime link's target inside the container and points the
    /// link at it, replacing a stale one. Without a link there is nothing to
    /// prepare: the server creates its runtime directory itself.
    public func prepareRuntimeDirectory() throws {
        guard let link = runtimeLink else { return }
        let files = FileManager.default
        try files.createDirectory(
            atPath: link.target, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]
        )
        if (try? files.destinationOfSymbolicLink(atPath: link.alias)) == link.target { return }
        try? files.removeItem(atPath: link.alias)
        try files.createDirectory(
            atPath: (link.alias as NSString).deletingLastPathComponent, withIntermediateDirectories: true
        )
        try files.createSymbolicLink(atPath: link.alias, withDestinationPath: link.target)
    }

    /// The per-user directory under `/var/folders`; nil off Darwin, where
    /// there is no app sandbox and so no runtime link.
    public static func systemDarwinUserDirectory() -> String? {
        #if canImport(Darwin)
        let length = confstr(_CS_DARWIN_USER_DIR, nil, 0)
        guard length > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: length)
        guard confstr(_CS_DARWIN_USER_DIR, &buffer, length) == length else { return nil }
        return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        #else
        return nil
        #endif
    }

    public var personalSocket: String {
        (runtimeDirectory as NSString).appendingPathComponent("mirmir.sock")
    }

    public func socket(for target: InstanceTarget) -> String? {
        switch target {
        case .personal: personalSocket
        case .remote: nil
        }
    }

    /// Darwin's `sun_path` holds 104 bytes including the terminating NUL.
    public static let maximumSocketPathLength = 103

    public static func isSocket(_ path: String) -> Bool {
        let type = (try? FileManager.default.attributesOfItem(atPath: path))?[.type] as? FileAttributeType
        return type == .typeSocket
    }
}

/// A short path that stands for a directory inside the sandbox container.
public struct RuntimeLink: Hashable, Sendable {
    /// The symlink, in the app's per-user directory under `/var/folders`.
    public let alias: String
    /// The real directory, in the container, where the socket is bound.
    public let target: String
}
