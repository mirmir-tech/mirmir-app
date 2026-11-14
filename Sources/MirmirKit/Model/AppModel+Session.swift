import Foundation

extension AppModel {
    static let serverStartTimeout: TimeInterval = 30
    static let retryDelay: Duration = .seconds(3)

    /// Connects, starts the personal server when nobody serves it, and keeps
    /// reconnecting until the task is cancelled by an instance switch.
    func session(for instance: InstanceRecord) async {
        var startedAt: Date?
        while !Task.isCancelled {
            do {
                let connection = try await open(instance)
                guard !Task.isCancelled else { connection.close(); return }
                startedAt = nil
                if instance.isThisMac, case .none = supervisor.ownership, let socket = paths.socket(for: .personal) {
                    // A server an earlier run left behind is this app's to
                    // pause and restart once it is verified as its helper.
                    await supervisor.recover(serving: socket)
                }
                phase = .connected(connection)
                summaries[instance.id] = InstanceSummary(status: .online(connection.health), telemetry: nil, loadedModels: [])
                let lost = await runConnected(connection, instance: instance)
                connection.close()
                if Task.isCancelled { return }
                let error = lost ?? offlineError(for: instance)
                phase = .offline(error)
                summaries[instance.id] = InstanceSummary(status: InstanceStatus(error: error), telemetry: nil, loadedModels: [])
            } catch {
                if Task.isCancelled { return }
                if shouldStartServer(for: instance, after: error, startedAt: startedAt) {
                    startServer()
                    startedAt = Date()
                } else if instance.isThisMac, startedAt == nil, supervisor.ownership.isStarting {
                    // Started by Resume, a restart or the first-launch
                    // configuration rather than by this session: it is
                    // still starting, not offline.
                    startedAt = Date()
                }
                if let startedAt, waitingForServer(since: startedAt) {
                    // A missing socket is expected while the server boots;
                    // anything else is worth seeing in Logs.
                    if !error.isUnreachable, error.localizedDescription != lastStartError {
                        lastStartError = error.localizedDescription
                        supervisor.logs.note("connect failed: \(error.localizedDescription)")
                    }
                    if case .startingServer = phase {} else { phase = .startingServer }
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
        return !supervisor.ownership.isStarting
    }

    private func waitingForServer(since start: Date) -> Bool {
        supervisor.ownership.isStarting && Date().timeIntervalSince(start) < Self.serverStartTimeout
    }

    /// Polls telemetry and models while watching activity. Returns the
    /// error when the server becomes unreachable or stops answering within
    /// the monitoring deadlines, and nil when cancelled.
    func runConnected(_ connection: RuntimeConnection, instance: InstanceRecord) async -> ConnectionError? {
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                try? await connection.watchActivity { activity in
                    await self.apply(activity, from: connection)
                }
            }
            let lost = await pollLoop(connection, instance: instance)
            group.cancelAll()
            return lost
        }
    }

    private func pollLoop(_ connection: RuntimeConnection, instance: InstanceRecord) async -> ConnectionError? {
        var tick = 0
        while !Task.isCancelled {
            do {
                try await refreshTelemetry(connection, instance: instance)
                if tick % 2 == 0 { try await refreshHistory(connection) }
                if tick % 5 == 0 || refreshModelsSoon { try await refreshModels(connection) }
            } catch {
                // A timeout counts as unreachable: a server that answers
                // Health and then stalls is reconnected, not polled forever.
                if error.isUnreachable { return error }
                report(error)
            }
            tick += 1
            try? await Task.sleep(for: .seconds(1))
        }
        return nil
    }

    func refreshTelemetry(_ connection: RuntimeConnection, instance: InstanceRecord) async throws(ConnectionError) {
        let snapshot = try await connection.telemetry()
        guard isCurrent(connection) else { return }
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
        let raw = try await connection.telemetryHistory(limit: max(limit, 1))
        // Thousands of samples cost the charts far more than they can show;
        // bucket them off the main actor and publish only real changes.
        let prepared = await Task.detached(priority: .utility) { raw.downsampled() }.value
        guard isCurrent(connection) else { return }
        if prepared != history { history = prepared }
    }

    func refreshModels(_ connection: RuntimeConnection) async throws(ConnectionError) {
        let listed = try await connection.localModels()
        let active = try await connection.activeSelectors()
        // Matching resolves symlinks on disk: do it once per refresh, off the
        // main actor, instead of in every table row and sort comparison. Only
        // This Mac's paths are on this disk; a result for a connection that
        // is no longer current is dropped by `publishModels`.
        let local = currentInstance.target.kind.isLocal
        let serving = await Task.detached(priority: .utility) {
            Self.servingSelectors(models: listed, active: active, resolvingPaths: local)
        }.value
        publishModels(listed, active: active, serving: serving, from: connection)
    }

    func publishModels(_ listed: [LocalModel], active: [String], serving: [String: String], from connection: RuntimeConnection) {
        guard isCurrent(connection) else { return }
        refreshModelsSoon = false
        if listed != models { models = listed }
        if active != activeSelectors { activeSelectors = active }
        if serving != servingSelectors { servingSelectors = serving }
    }

    func apply(_ activity: Activity, from connection: RuntimeConnection) {
        guard isCurrent(connection) else { return }
        activities[activity.id] = activity
        if !activity.state.isActive {
            switch activity.kind {
            case .load, .unload, .pull, .remove, .restore: refreshModelsSoon = true
            default: break
            }
        }
        // `includeHistory` replays a burst of events on connect; pruning the
        // whole dictionary for each of them is wasted work on the main actor.
        let now = Date()
        guard now.timeIntervalSince(lastActivityPrune) > 5 else { return }
        lastActivityPrune = now
        let cutoff = now.addingTimeInterval(-3600)
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
