import Foundation

/// Resolves sockets exactly like mirmir's `config::Paths::discover`, so the
/// app finds the same personal server as the CLI and TUI.
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
        case .system: InstanceTarget.systemSocket
        case .socket(let path): (path as NSString).expandingTildeInPath
        case .remote: nil
        }
    }

    public static func isSocket(_ path: String) -> Bool {
        let type = (try? FileManager.default.attributesOfItem(atPath: path))?[.type] as? FileAttributeType
        return type == .typeSocket
    }
}
