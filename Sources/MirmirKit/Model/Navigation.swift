import Foundation

public enum SidebarSection: String, CaseIterable, Identifiable, Hashable, Sendable {
    case overview, chat, models, instances, sessions, logs, configuration

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .overview: "Overview"
        case .chat: "Chat"
        case .models: "Models"
        case .instances: "Instances"
        case .sessions: "Sessions"
        case .logs: "Logs"
        case .configuration: "Configuration"
        }
    }
}

public enum TimeRange: String, CaseIterable, Identifiable, Hashable, Sendable {
    case fiveMinutes, hour, day

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .fiveMinutes: "5 min"
        case .hour: "1 h"
        case .day: "24 h"
        }
    }

    public var duration: TimeInterval {
        switch self {
        case .fiveMinutes: 300
        case .hour: 3600
        case .day: 86400
        }
    }
}

/// How the app reaches the current instance.
public enum ConnectionPhase: Sendable {
    case connecting
    /// The app launched `mirmir serve` and waits for its socket.
    case startingServer
    case connected(RuntimeConnection)
    case offline(ConnectionError)

    public var connection: RuntimeConnection? {
        if case .connected(let connection) = self { connection } else { nil }
    }
}

/// Reachability of an instance as shown on its card.
public enum InstanceStatus: Hashable, Sendable {
    case checking
    case online(ServerHealth)
    case updateNeeded(serverProtocol: String, serverVersion: String)
    case offline(reason: String)

    public init(error: ConnectionError) {
        switch error {
        case .updateNeeded(let server, let version): self = .updateNeeded(serverProtocol: server, serverVersion: version)
        default: self = .offline(reason: error.localizedDescription)
        }
    }
}

/// What a probe of a non-current instance learned.
public struct InstanceSummary: Hashable, Sendable {
    public var status: InstanceStatus
    public var telemetry: TelemetrySnapshot?
    public var loadedModels: [String]

    public static let checking = InstanceSummary(status: .checking, telemetry: nil, loadedModels: [])
}
