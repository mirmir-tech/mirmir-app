import Foundation

/// Resolves the socket exactly like mirmir's `config::Paths::discover`. The
/// app is sandboxed and its server inherits that sandbox, so `HOME` is the
/// app's container for both: this is the bundled server's own socket, never
/// the CLI's.
public struct SocketPaths: Sendable {
    public let environment: [String: String]
    public let home: String

    public init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        home: String = NSHomeDirectory()
    ) {
        self.environment = environment
        self.home = environment["HOME"] ?? home
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
        if let runtime = environment["XDG_RUNTIME_DIR"] {
            return (runtime as NSString).appendingPathComponent("mirmir")
        }
        return stateDirectory
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

    public static func isSocket(_ path: String) -> Bool {
        let type = (try? FileManager.default.attributesOfItem(atPath: path))?[.type] as? FileAttributeType
        return type == .typeSocket
    }
}
