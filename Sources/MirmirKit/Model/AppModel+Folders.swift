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

    /// Loads the model in a folder the user chose. The folder stays granted,
    /// so the server can restore the model on the next launch.
    public func loadModel(at url: URL) {
        guard addModelFolder(url) != nil else { return }
        load(url.path)
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
            supervisor.start(environment: modelFolders.serverEnvironment)
            connectCurrent()
        }
    }
}
