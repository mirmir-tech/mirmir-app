import Foundation

extension AppModel {
    /// Models resident on the server. `ListActiveModels` is authoritative:
    /// a checkpoint reached through a symlinked cache can be listed as
    /// available under one path while it is active under its resolved path.
    public var loadedModels: [LocalModel] {
        let listed = models.filter { $0.state == .loaded || activeSelector(for: $0) != nil }
        let served = Set(listed.map { servingSelector(for: $0) })
        return listed + activeSelectors.filter { !served.contains($0) }.map(LocalModel.unlisted)
    }

    /// The model the menu bar, Overview and chat default to: the loaded model
    /// that generated most recently, else the one the server used last. The
    /// first loaded model may be an embedding or reranking model.
    public var primaryModel: LocalModel? {
        let loaded = loadedModels
        let lastGenerated = activities.values
            .filter { $0.kind == .generate }
            .max { $0.updatedAt < $1.updatedAt }?.target
        if let lastGenerated, let match = loaded.first(where: { servingSelector(for: $0) == lastGenerated || $0.selector == lastGenerated }) {
            return match
        }
        return loaded.min { ($0.recentRank ?? .max) < ($1.recentRank ?? .max) }
    }

    /// What an activity acts on, for display: a known model by its name
    /// rather than its selector, which is often a path in the user's home.
    public func displayTarget(of activity: Activity) -> String {
        if activity.target.isEmpty { return activity.kind.label }
        let loaded = loadedModels.first { servingSelector(for: $0) == activity.target || $0.selector == activity.target }
        return (loaded ?? model(selector: activity.target))?.displayName ?? activity.target
    }

    /// The state to show: loaded when the server serves it, else its own.
    public func displayState(of local: LocalModel) -> LocalModelState {
        activeSelector(for: local) != nil ? .loaded : local.state
    }

    /// The running download of the model's repository: one this app started,
    /// or a server pull from any client, such as the CLI.
    public func download(of local: LocalModel) -> ModelDownload? {
        guard !local.repoID.isEmpty else { return nil }
        if let transfer = transfers[local.repoID] { return ModelDownload(fraction: transfer.fraction) }
        let pull = activities.values.first { $0.kind == .pull && $0.target == local.repoID && $0.state.isActive }
        return pull.map { ModelDownload(fraction: $0.progress?.fraction) }
    }

    /// The selector to send for generation and unload: the one the server
    /// reports as active when it differs from the listed selector.
    public func servingSelector(for local: LocalModel) -> String {
        activeSelector(for: local) ?? local.selector
    }

    public func model(selector: String) -> LocalModel? {
        models.first { $0.selector == selector }
            ?? models.first { activeSelector(for: $0) == selector }
    }

    func activeSelector(for local: LocalModel) -> String? {
        servingSelectors[local.selector]
    }

    /// Pairs each listed model with the active selector serving it. Paths
    /// are compared through their symlinks only on a server on this Mac
    /// (`resolvingPaths`), as only those paths are this Mac's; that touches
    /// the file system, so call it off the main actor. A remote server's
    /// paths are compared as written.
    nonisolated static func servingSelectors(
        models: [LocalModel], active: [String], resolvingPaths: Bool
    ) -> [String: String] {
        guard !active.isEmpty else { return [:] }
        let exact = Set(active)
        func resolved(_ path: String) -> String { resolvingPaths ? Self.resolved(path) : path }
        let resolvedActive = active.map { (resolved($0), $0) }
        var serving: [String: String] = [:]
        for local in models {
            if exact.contains(local.selector) {
                serving[local.selector] = local.selector
                continue
            }
            let target = resolved(local.path.isEmpty ? local.selector : local.path)
            if let match = resolvedActive.first(where: { $0.0 == target }) { serving[local.selector] = match.1 }
        }
        return serving
    }

    nonisolated static func resolved(_ path: String) -> String {
        guard path.hasPrefix("/") else { return path }
        return URL(fileURLWithPath: path).resolvingSymlinksInPath().path
    }

    public func search(_ query: String) async throws(ConnectionError) -> [CatalogModel] {
        guard let connection else { throw .noServer(socket: currentInstance.name) }
        return try await connection.search(query: query)
    }

    public func pull(_ repoID: String) {
        guard let connection, transfers[repoID] == nil else { return }
        transfers[repoID] = TransferProgress(repoID: repoID, phase: .queued, downloadedBytes: 0, totalBytes: nil, message: "")
        Task {
            do {
                try await connection.pull(repoID: repoID) { progress in
                    await self.setTransfer(repoID, progress, from: connection)
                }
            } catch {
                report(error, "Downloading \(repoID) failed", from: connection)
            }
            if isCurrent(connection) { transfers[repoID] = nil }
            try? await refreshModels(connection)
        }
    }

    public func removeCheckpoint(_ repoID: String) {
        guard let connection else { return }
        Task {
            do {
                _ = try await connection.remove(repoID: repoID)
            } catch {
                report(error, "Removing \(repoID) failed", from: connection)
            }
            try? await refreshModels(connection)
        }
    }

    public func cancel(_ activity: Activity) {
        guard let connection, activity.cancellable else { return }
        Task { _ = try? await connection.cancel(operationID: activity.id) }
    }

    func setTransfer(_ repoID: String, _ progress: TransferProgress, from connection: RuntimeConnection) {
        if isCurrent(connection) { transfers[repoID] = progress }
    }
}
