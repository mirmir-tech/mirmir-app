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
    /// The Hugging Face download sheet on the Models screen, opened from the
    /// screen's toolbar or the menu bar panel.
    public var presentingDownload = false

    // Instances.
    public internal(set) var instances: [InstanceRecord]
    public internal(set) var currentInstanceID: UUID
    public internal(set) var summaries: [UUID: InstanceSummary] = [:]

    // Connection and live data for the current instance.
    public internal(set) var phase: ConnectionPhase = .connecting
    public internal(set) var telemetry: TelemetrySnapshot?
    public internal(set) var history: TelemetryHistory = .empty
    public internal(set) var sparkline: [Double] = []
    public internal(set) var models: [LocalModel] = []
    public internal(set) var activeSelectors: [String] = []
    /// Listed selector → the active selector serving it, resolved off the
    /// main actor in `refreshModels`.
    public internal(set) var servingSelectors: [String: String] = [:]
    public internal(set) var activities: [String: Activity] = [:]
    public internal(set) var inspections: [String: ModelInspection] = [:]
    public internal(set) var loads: [String: LoadProgress] = [:]
    public internal(set) var transfers: [String: TransferProgress] = [:]
    public var notice: String?

    /// Set by Pause; keeps the app from restarting the server it stopped.
    public internal(set) var serverPaused = false

    public let supervisor: ServerSupervisor
    public let chat: ChatController
    /// Folders outside the container the user granted, for models.
    public let modelFolders: ModelFolders
    let paths: SocketPaths
    /// Deadlines of the unary calls on every connection the model opens.
    let deadlines: CallDeadlines
    let credentials: any CredentialStore
    let instanceFile = JSONFile<[InstanceRecord]>(name: "instances.json")
    var sessionTask: Task<Void, Never>?
    var probeTask: Task<Void, Never>?
    var refreshModelsSoon = false
    var lastStartError: String?
    var lastActivityPrune = Date.distantPast
    /// Previews: sample data that never reaches `instances.json`, and no
    /// notices from calls the inert preview connection rejects.
    var isPreview = false

    public init(
        paths: SocketPaths = SocketPaths(),
        supervisor: ServerSupervisor = ServerSupervisor(),
        credentials: any CredentialStore = Credentials.platformDefault,
        modelFolders: ModelFolders = ModelFolders(),
        deadlines: CallDeadlines = .standard,
        // Nil keeps chats in memory only (previews).
        chats: ChatStore? = ChatStore()
    ) {
        self.modelFolders = modelFolders
        self.paths = paths
        self.deadlines = deadlines
        self.credentials = credentials
        self.supervisor = supervisor
        self.chat = ChatController(store: chats)
        var stored = instanceFile.load() ?? []
        stored.removeAll { $0.isThisMac }
        instances = [.thisMac] + stored
        currentInstanceID = InstanceRecord.thisMacID
        chat.model = self
        chat.instanceChanged()
    }

    public var currentInstance: InstanceRecord {
        instances.first { $0.id == currentInstanceID } ?? .thisMac
    }

    public var connection: RuntimeConnection? { phase.connection }

    /// Whether results of a call on `connection` belong on screen: it is
    /// the current instance's open connection. Calls outlive a switch to
    /// another server or a reconnect, so every per-server write that follows
    /// an `await` checks this first; two servers can list the same selector.
    func isCurrent(_ connection: RuntimeConnection) -> Bool {
        phase.connection === connection
    }

    /// Starts connecting to the current instance and probing the others.
    public func start() {
        guard sessionTask == nil else { return }
        connectCurrent()
        probeTask = Task { [weak self] in await self?.probeLoop() }
    }

    public func select(instance id: UUID) {
        guard id != currentInstanceID, instances.contains(where: { $0.id == id }) else { return }
        currentInstanceID = id
        chat.instanceChanged()
        connectCurrent()
    }

    /// Saves an instance; a remote server's API key goes to the credential
    /// store, never to `instances.json`.
    public func add(_ record: InstanceRecord, key: String? = nil) {
        if let key {
            do {
                try credentials.setKey(key, for: record.id)
            } catch {
                notice = error.localizedDescription
                return
            }
        }
        instances.append(record)
        persistInstances()
        summaries[record.id] = .checking
        Task { await probe(record) }
    }

    public func remove(instance id: UUID) {
        guard id != InstanceRecord.thisMacID else { return }
        instances.removeAll { $0.id == id }
        credentials.removeKey(for: id)
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
            startServer()
            connectCurrent()
        }
    }

    /// Call from `applicationWillTerminate`. The streaming reply is saved
    /// as stopped, and every chat save is on disk, before anything closes.
    public func shutdown() {
        chat.terminate()
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
        servingSelectors = [:]
        activities = [:]
        inspections = [:]
        loads = [:]
        transfers = [:]
    }

    /// Shows a failed call as a notice. A call the app cancelled itself is
    /// not a failure and is dropped.
    /// A failure on a server that is no longer current names that server.
    func report(_ error: any Error, _ context: String? = nil, from connection: RuntimeConnection? = nil) {
        let error = ConnectionError.wrap(error)
        if case .cancelled = error { return }
        var message = context.map { "\($0): \(error.localizedDescription)" } ?? error.localizedDescription
        if let connection, !isCurrent(connection) { message = "\(connection.address): \(message)" }
        notice = message
    }

    private func persistInstances() {
        guard !isPreview else { return }
        do {
            try instanceFile.save(instances.filter { !$0.isThisMac })
        } catch {
            notice = "Could not save instances: \(error.localizedDescription)"
        }
    }
}
