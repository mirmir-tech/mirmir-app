import Foundation

extension AppModel {
    static let serverStartTimeout: TimeInterval = 30
    static let retryDelay: Duration = .seconds(3)

    /// Connects, starts the personal server when nobody serves it, and keeps
    /// reconnecting until the task is cancelled by an instance switch.
    func session(for instance: InstanceRecord) async {
        var startedAt: Date?
        while !Task.isCancelled {
            guard let socket = paths.socket(for: instance.target) else {
                if case .remote(let endpoint) = instance.target {
                    phase = .offline(.remoteUnavailable(address: endpoint.address))
                }
                return
            }
            do {
                let connection = try await RuntimeConnection.connect(socket: socket)
                guard !Task.isCancelled else { connection.close(); return }
                startedAt = nil
                phase = .connected(connection)
                summaries[instance.id] = InstanceSummary(status: .online(connection.health), telemetry: nil, loadedModels: [])
                await runConnected(connection, instance: instance)
                connection.close()
                if Task.isCancelled { return }
                phase = .offline(.noServer(socket: socket))
            } catch {
                if Task.isCancelled { return }
                if shouldStartServer(for: instance, after: error, startedAt: startedAt) {
                    supervisor.start()
                    startedAt = Date()
                }
                if let startedAt, waitingForServer(since: startedAt) {
                    // A missing socket is expected while the server boots;
                    // anything else is worth seeing in Logs.
                    if !error.isUnreachable, error.localizedDescription != lastStartError {
                        lastStartError = error.localizedDescription
                        supervisor.logs.note("connect failed: \(error.localizedDescription)")
                    }
                    phase = .startingServer
                    try? await Task.sleep(for: .milliseconds(300))
                    continue
                }
                phase = .offline(error)
                summaries[instance.id] = InstanceSummary(status: InstanceStatus(error: error), telemetry: nil, loadedModels: [])
            }
            try? await Task.sleep(for: Self.retryDelay)
        }
    }

    private func shouldStartServer(for instance: InstanceRecord, after error: ConnectionError, startedAt: Date?) -> Bool {
        // A refused connection usually means a stale socket file; `mirmir serve`
        // recovers it, so start the server for any unreachable error.
        guard instance.isThisMac, !serverPaused, startedAt == nil, error.isUnreachable else { return false }
        if case .unavailable = supervisor.ownership { return false }
        return !supervisor.ownership.isRunning
    }

    private func waitingForServer(since start: Date) -> Bool {
        supervisor.ownership.isRunning && Date().timeIntervalSince(start) < Self.serverStartTimeout
    }

    /// Polls telemetry and models while watching activity. Returns when the
    /// server becomes unreachable.
    func runConnected(_ connection: RuntimeConnection, instance: InstanceRecord) async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                try? await connection.watchActivity { activity in
                    await self.apply(activity)
                }
            }
            await pollLoop(connection, instance: instance)
            group.cancelAll()
        }
    }

    private func pollLoop(_ connection: RuntimeConnection, instance: InstanceRecord) async {
        var tick = 0
        while !Task.isCancelled {
            do {
                try await refreshTelemetry(connection, instance: instance)
                if tick % 2 == 0 { try await refreshHistory(connection) }
                if tick % 5 == 0 || refreshModelsSoon { try await refreshModels(connection) }
            } catch {
                if error.isUnreachable { return }
                notice = error.localizedDescription
            }
            tick += 1
            try? await Task.sleep(for: .seconds(1))
        }
    }

    func refreshTelemetry(_ connection: RuntimeConnection, instance: InstanceRecord) async throws(ConnectionError) {
        let snapshot = try await connection.telemetry()
        telemetry = snapshot
        sparkline.append(snapshot.currentDecode ?? 0)
        if sparkline.count > 60 { sparkline.removeFirst(sparkline.count - 60) }
        summaries[instance.id] = InstanceSummary(
            status: .online(connection.health), telemetry: snapshot, loadedModels: activeSelectors
        )
    }

    func refreshHistory(_ connection: RuntimeConnection) async throws(ConnectionError) {
        let interval = history.samplingInterval
        let wanted = Int((range.duration / max(interval, 0.001)).rounded(.up))
        let limit = history.retentionLimit > 0 ? min(wanted, history.retentionLimit) : wanted
        history = try await connection.telemetryHistory(limit: max(limit, 1))
    }

    func refreshModels(_ connection: RuntimeConnection) async throws(ConnectionError) {
        refreshModelsSoon = false
        models = try await connection.localModels()
        activeSelectors = try await connection.activeSelectors()
    }

    func apply(_ activity: Activity) {
        activities[activity.id] = activity
        if !activity.state.isActive {
            switch activity.kind {
            case .load, .unload, .pull, .remove, .restore: refreshModelsSoon = true
            default: break
            }
        }
        let cutoff = Date().addingTimeInterval(-3600)
        activities = activities.filter { $0.value.state.isActive || $0.value.updatedAt > cutoff }
    }

    /// Activity still in flight, newest first.
    public var activeOperations: [Activity] {
        activities.values.filter(\.state.isActive).sorted { $0.startedAt > $1.startedAt }
    }

    public var recentOperations: [Activity] {
        activities.values.sorted { $0.updatedAt > $1.updatedAt }
    }
}
