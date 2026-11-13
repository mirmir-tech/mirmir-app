import Foundation

extension AppModel {
    /// Grants a folder the user chose. A Hugging Face cache reaches the
    /// server through `HF_HUB_CACHE`, so the server this app runs restarts
    /// to list its models.
    @discardableResult
    public func addModelFolder(_ url: URL) -> ModelFolder? {
        let before = modelFolders.huggingFaceCache
        do {
            let folder = try modelFolders.add(url)
            if modelFolders.huggingFaceCache != before { restartServer() }
            return folder
        } catch {
            report(error, "Granting \(url.lastPathComponent) failed")
            return nil
        }
    }

    public func removeModelFolder(_ id: UUID) {
        let before = modelFolders.huggingFaceCache
        modelFolders.remove(id)
        if modelFolders.huggingFaceCache != before { restartServer() }
    }

    /// Whether a folder on this Mac can be loaded: only into the app's own
    /// server. A remote server cannot read this Mac's paths.
    public var canLoadLocalFolders: Bool {
        currentInstance.isThisMac && connection != nil
    }

    /// Loads the model in a folder the user chose into the app's own server.
    /// The folder stays granted, so the server can restore the model on the
    /// next launch. Never sends a path on this Mac to a remote server.
    public func loadModel(at url: URL) {
        guard canLoadLocalFolders else {
            notice = "Models in a folder on this Mac load only on This Mac. Switch to This Mac first."
            return
        }
        guard let folder = addModelFolder(url) else { return }
        // A Hugging Face cache is not a checkpoint: its models are listed.
        if case .folder = folder.kind { load(folder.path) }
    }

    /// Restarts the bundled server with the current folders; a server this
    /// app did not start is left alone.
    func restartServer() {
        guard supervisor.ownership.isRunning else { return }
        supervisor.stop()
        Task {
            for _ in 0..<100 where supervisor.ownership.isRunning {
                try? await Task.sleep(for: .milliseconds(100))
            }
            startServer()
            connectCurrent()
        }
    }
}
