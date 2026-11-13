import GRPCCore

/// The kinds of unary `Runtime` calls, grouped by how long a healthy server
/// takes to answer them. Server-streaming calls (Generate, Load, Pull,
/// WatchActivity) have no deadline: they run until they end or are cancelled.
public enum UnaryCall: Hashable, Sendable {
    /// Health, as the connection handshake and as a ping.
    case health
    /// Telemetry, its history and the active models: polled every second.
    case monitoring
    /// Local models, model inspection and remote access status.
    case discovery
    /// Hugging Face search, which the server forwards to the Hub.
    case catalog
    /// Changes: settings, unload, remove, cancel, remote access and keys.
    case management
}

/// How long each kind of unary call may wait for its reply. A server that
/// keeps the transport open but stops answering fails the call with
/// `ConnectionError.timedOut` instead of leaving it pending forever.
public struct CallDeadlines: Hashable, Sendable {
    public var health: Duration
    public var monitoring: Duration
    public var discovery: Duration
    public var catalog: Duration
    public var management: Duration

    public init(
        health: Duration = .seconds(5),
        monitoring: Duration = .seconds(10),
        discovery: Duration = .seconds(15),
        catalog: Duration = .seconds(30),
        management: Duration = .seconds(60)
    ) {
        self.health = health
        self.monitoring = monitoring
        self.discovery = discovery
        self.catalog = catalog
        self.management = management
    }

    public static let standard = CallDeadlines()

    public func timeout(for call: UnaryCall) -> Duration {
        switch call {
        case .health: health
        case .monitoring: monitoring
        case .discovery: discovery
        case .catalog: catalog
        case .management: management
        }
    }

    func options(for call: UnaryCall) -> CallOptions {
        var options = CallOptions.defaults
        options.timeout = timeout(for: call)
        return options
    }
}
