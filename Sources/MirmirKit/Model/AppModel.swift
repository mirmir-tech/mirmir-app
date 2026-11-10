import Foundation
import Observation

/// The single source of truth for every window and the menu bar panel. It
/// holds one current connection; switching the instance switches everything.
@MainActor
@Observable
public final class AppModel {
    // Navigation shared by the window, menu bar and keyboard shortcuts.
    public var section: SidebarSection = .overview
    public var range: TimeRange = .hour

    // Instances.
    public private(set) var instances: [InstanceRecord]
    public private(set) var currentInstanceID: UUID
    public internal(set) var summaries: [UUID: InstanceSummary] = [:]

    // Connection and live data for the current instance.
    public internal(set) var phase: ConnectionPhase = .connecting
    public internal(set) var telemetry: TelemetrySnapshot?
    public internal(set) var history: TelemetryHistory = .empty
    public internal(set) var sparkline: [Double] = []
    public internal(set) var models: [LocalModel] = []
    public internal(set) var activeSelectors: [String] = []
    public internal(set) var activities: [String: Activity] = [:]
    public internal(set) var inspections: [String: ModelInspection] = [:]
    public internal(set) var loads: [String: LoadProgress] = [:]
    public internal(set) var transfers: [String: TransferProgress] = [:]
    public var notice: String?

    /// Set by Pause; keeps the app from restarting the server it stopped.
    public internal(set) var serverPaused = false

    public let supervisor: ServerSupervisor
    public let chat: ChatController
    let paths: SocketPaths
    let instanceFile = JSONFile<[InstanceRecord]>(name: "instances.json")
    var sessionTask: Task<Void, Never>?
    var probeTask: Task<Void, Never>?
    var refreshModelsSoon = false
    var lastStartError: String?

    public init(paths: SocketPaths = SocketPaths(), supervisor: ServerSupervisor = ServerSupervisor()) {
        self.paths = paths
        self.supervisor = supervisor
        self.chat = ChatController()
        var stored = instanceFile.load() ?? []
        stored.removeAll { $0.isThisMac }
        if stored.isEmpty, SocketPaths.isSocket(InstanceTarget.systemSocket) {
            stored.append(InstanceRecord(name: "System", target: .system))
        }
        instances = [.thisMac] + stored
        currentInstanceID = InstanceRecord.thisMacID
        chat.model = self
    }

    public var currentInstance: InstanceRecord {
        instances.first { $0.id == currentInstanceID } ?? .thisMac
    }

    public var connection: RuntimeConnection? { phase.connection }

    /// Starts connecting to the current instance and probing the others.
    public func start() {
        guard sessionTask == nil else { return }
        connectCurrent()
        probeTask = Task { [weak self] in await self?.probeLoop() }
    }

    public func select(instance id: UUID) {
        guard id != currentInstanceID, instances.contains(where: { $0.id == id }) else { return }
        currentInstanceID = id
        connectCurrent()
    }

    public func add(_ record: InstanceRecord) {
        instances.append(record)
        persistInstances()
        summaries[record.id] = .checking
        Task { await probe(record) }
    }

    public func remove(instance id: UUID) {
        guard id != InstanceRecord.thisMacID else { return }
        instances.removeAll { $0.id == id }
        summaries[id] = nil
        persistInstances()
        if currentInstanceID == id { select(instance: InstanceRecord.thisMacID) }
    }

    /// Stops the server this app started; an attached server is left alone.
    public func pauseServer() {
        serverPaused = true
        supervisor.stop()
    }

    public func resumeServer() {
        serverPaused = false
        if currentInstance.isThisMac, connection == nil {
            supervisor.start()
            connectCurrent()
        }
    }

    /// Call from `applicationWillTerminate`.
    public func shutdown() {
        sessionTask?.cancel()
        probeTask?.cancel()
        connection?.close()
        supervisor.stopAndWait()
    }

    func connectCurrent() {
        sessionTask?.cancel()
        connection?.close()
        resetLiveState()
        phase = .connecting
        let instance = currentInstance
        sessionTask = Task { [weak self] in await self?.session(for: instance) }
    }

    func resetLiveState() {
        telemetry = nil
        history = .empty
        sparkline = []
        models = []
        activeSelectors = []
        activities = [:]
        inspections = [:]
        loads = [:]
    }

    private func persistInstances() {
        do {
            try instanceFile.save(instances.filter { !$0.isThisMac })
        } catch {
            notice = "Could not save instances: \(error.localizedDescription)"
        }
    }
}
