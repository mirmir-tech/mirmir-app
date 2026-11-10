import Foundation

extension AppModel {
    /// Models resident on the server. `ListActiveModels` is authoritative:
    /// a checkpoint reached through a symlinked cache can be listed as
    /// available under one path while it is active under its resolved path.
    public var loadedModels: [LocalModel] {
        models.filter { $0.state == .loaded || activeSelector(for: $0) != nil }
    }

    /// The model the menu bar and chat default to.
    public var primaryModel: LocalModel? {
        loadedModels.first
    }

    /// The state to show: loaded when the server serves it, else its own.
    public func displayState(of local: LocalModel) -> LocalModelState {
        activeSelector(for: local) != nil ? .loaded : local.state
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
        if activeSelectors.contains(local.selector) { return local.selector }
        let resolved = Self.resolved(local.path.isEmpty ? local.selector : local.path)
        return activeSelectors.first { Self.resolved($0) == resolved }
    }

    static func resolved(_ path: String) -> String {
        guard path.hasPrefix("/") else { return path }
        return URL(fileURLWithPath: path).resolvingSymlinksInPath().path
    }

    public func load(_ selector: String) {
        guard let connection else { return }
        loads[selector] = LoadProgress(phase: "queued", current: 0, total: nil, detail: "", finished: false)
        Task {
            do {
                try await connection.load(selector: selector) { progress in
                    await self.setLoad(selector, progress)
                }
            } catch {
                notice = "Loading \(selector) failed: \(error.localizedDescription)"
            }
            loads[selector] = nil
            try? await refreshModels(connection)
        }
    }

    public func unload(_ selector: String) {
        guard let connection else { return }
        Task {
            do {
                _ = try await connection.unload(selector: selector)
            } catch {
                notice = "Unloading \(selector) failed: \(error.localizedDescription)"
            }
            inspections[selector] = nil
            try? await refreshModels(connection)
        }
    }

    public func inspect(_ selector: String) async {
        guard let connection else { return }
        do {
            inspections[selector] = try await connection.inspect(selector: selector)
        } catch {
            notice = "Inspecting \(selector) failed: \(error.localizedDescription)"
        }
    }

    public func updateSettings(_ selector: String, _ settings: GenerationSettings) async {
        guard let connection else { return }
        do {
            try await connection.updateSettings(selector: selector, settings: settings)
            inspections[selector] = try await connection.inspect(selector: selector)
        } catch {
            notice = "Saving settings failed: \(error.localizedDescription)"
        }
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
                    await self.setTransfer(repoID, progress)
                }
            } catch {
                notice = "Downloading \(repoID) failed: \(error.localizedDescription)"
            }
            transfers[repoID] = nil
            try? await refreshModels(connection)
        }
    }

    public func removeCheckpoint(_ repoID: String) {
        guard let connection else { return }
        Task {
            do {
                _ = try await connection.remove(repoID: repoID)
            } catch {
                notice = "Removing \(repoID) failed: \(error.localizedDescription)"
            }
            try? await refreshModels(connection)
        }
    }

    public func cancel(_ activity: Activity) {
        guard let connection, activity.cancellable else { return }
        Task { _ = try? await connection.cancel(operationID: activity.id) }
    }

    func setLoad(_ selector: String, _ progress: LoadProgress) {
        loads[selector] = progress
    }

    func setTransfer(_ repoID: String, _ progress: TransferProgress) {
        transfers[repoID] = progress
    }
}
