#if DEBUG
import Foundation

/// The situations a SwiftUI preview can show.
public enum PreviewScenario: Sendable, CaseIterable {
    /// Connected to This Mac with a loaded model, sessions and history.
    case connected
    /// Connected, with a reply streaming in the selected chat.
    case generating
    /// The app launched `mirmir serve` and waits for its socket.
    case startingServer
    /// No server answers and none could be started.
    case offline
}

extension AppModel {
    /// A model filled with fixed sample data for SwiftUI previews. It never
    /// connects, never starts mirmir and never writes instances or chats.
    public static func preview(_ scenario: PreviewScenario = .connected) -> AppModel {
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("mirmir-preview", isDirectory: true)
        let supervisor = ServerSupervisor(logFile: scratch.appendingPathComponent("server.log"))
        let model = AppModel(
            paths: SocketPaths(environment: ["MIRMIR_STATE_HOME": scratch.path], home: scratch.path),
            supervisor: supervisor,
            credentials: MemoryCredentials(),
            modelFolders: ModelFolders(file: JSONFile(name: "model-folders.json", directory: scratch))
        )
        model.isPreview = true
        model.chat.persists = false
        model.fillPreview(scenario)
        return model
    }

    private func fillPreview(_ scenario: PreviewScenario) {
        let now = Date()
        instances = [.thisMac, PreviewData.studio, PreviewData.gpuBox]
        currentInstanceID = InstanceRecord.thisMacID
        summaries = [
            PreviewData.studio.id: InstanceSummary(
                status: .online(ServerHealth(protocolVersion: "2", serverVersion: "0.6.0")),
                telemetry: PreviewData.telemetry(at: now, decode: 61.2, active: 1),
                loadedModels: ["mlx-community/Qwen3-4B-4bit"]
            ),
            PreviewData.gpuBox.id: InstanceSummary(
                status: .updateNeeded(serverProtocol: "1", serverVersion: "0.4.2"), telemetry: nil, loadedModels: []
            ),
        ]
        supervisor.logs.append(lines: PreviewData.logLines, stream: .stderr)
        supervisor.logs.note("started Mirmir.app/Contents/Helpers/mirmir serve (pid 4242)")

        switch scenario {
        case .startingServer:
            phase = .startingServer
            return
        case .offline:
            let socket = paths.personalSocket
            phase = .offline(.noServer(socket: socket))
            summaries[InstanceRecord.thisMacID] = InstanceSummary(
                status: .offline(reason: "No server at \(socket)"), telemetry: nil, loadedModels: []
            )
            return
        case .connected, .generating:
            break
        }

        let connection = RuntimeConnection.preview()
        phase = .connected(connection)
        models = PreviewData.models
        activeSelectors = [PreviewData.models[0].selector]
        servingSelectors = Self.servingSelectors(models: models, active: activeSelectors)
        let snapshot = PreviewData.telemetry(at: now, decode: 108.6, active: 3)
        telemetry = snapshot
        sparkline = PreviewData.sparkline
        history = PreviewData.history(endingAt: now).downsampled()
        summaries[InstanceRecord.thisMacID] = InstanceSummary(
            status: .online(connection.health), telemetry: snapshot, loadedModels: activeSelectors
        )
        for activity in PreviewData.activities(at: now) { activities[activity.id] = activity }
        inspections = PreviewData.inspections
        loads = [PreviewData.models[2].selector: LoadProgress(
            phase: "loading weights", current: 412, total: 731, detail: "model-00003-of-00005.safetensors", finished: false
        )]
        transfers = [PreviewData.downloadRepo: TransferProgress(
            repoID: PreviewData.downloadRepo, phase: .downloading,
            downloadedBytes: 6_420_000_000, totalBytes: 17_100_000_000, message: ""
        )]
        chat.conversations = PreviewData.conversations(at: now, streaming: scenario == .generating)
        chat.selectedID = chat.conversations.first?.id
    }
}
#endif
