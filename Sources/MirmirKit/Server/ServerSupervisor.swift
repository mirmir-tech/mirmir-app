import Foundation
import Observation

/// Who runs the personal server, from the app's point of view.
public enum ServerOwnership: Hashable, Sendable {
    /// Nothing started by this app; a server may still be attached.
    case none
    /// `mirmir serve` launched by this app and still running.
    case running(pid: Int32, binary: String)
    /// The owned process exited.
    case exited(status: Int32)
    /// The binary could not be found or launched.
    case unavailable(reason: String)

    public var isRunning: Bool {
        if case .running = self { true } else { false }
    }
}

/// Starts and stops the personal `mirmir serve` process the app owns. A server
/// someone else started is never touched.
@MainActor
@Observable
public final class ServerSupervisor {
    public private(set) var ownership: ServerOwnership = .none
    public let logs: LogBuffer
    private let tail: LogTail
    private var process: Process?

    public init(logs: LogBuffer = LogBuffer(), logFile: URL = LogTail.defaultURL) {
        self.logs = logs
        self.tail = LogTail(url: logFile, logs: logs)
        tail.start()
    }

    /// Where the server this app starts writes its output.
    public var logFile: URL { tail.url }

    /// The app's runtime serves the OpenAI-compatible API on its own port, so
    /// it runs next to a mirmir CLI server, or anything else, on mirmir's
    /// default 8080.
    public nonisolated static let httpBind = "127.0.0.1:18080"
    private var configuring = false

    /// Starts the bundled server. `environment` adds variables to the app's
    /// own, such as `HF_HUB_CACHE` for a Hugging Face cache the user granted.
    /// The first start writes the server's configuration with the app's port.
    public func start(environment: [String: String] = [:]) {
        guard !ownership.isRunning, !configuring else { return }
        guard let binary = ServerBinary.resolve() else {
            ownership = .unavailable(reason: "This build of Mirmir does not include its server (Contents/Helpers/mirmir).")
            logs.note("bundled mirmir not found")
            return
        }
        let environment = ProcessInfo.processInfo.environment.merging(environment) { _, added in added }
        guard !FileManager.default.fileExists(atPath: SocketPaths(environment: environment).configFile) else {
            launch(binary, environment: environment)
            return
        }
        let setup = Process()
        setup.executableURL = binary
        setup.arguments = ["config", "set", "server.http_bind", Self.httpBind]
        setup.environment = environment
        setup.standardOutput = FileHandle.nullDevice
        setup.standardError = FileHandle.nullDevice
        setup.terminationHandler = { [weak self] _ in
            Task { @MainActor in
                self?.configuring = false
                self?.launch(binary, environment: environment)
            }
        }
        do {
            configuring = true
            try setup.run()
            logs.note("configuring the bundled server: HTTP API at \(Self.httpBind)")
        } catch {
            configuring = false
            launch(binary, environment: environment)
        }
    }

    private func launch(_ binary: URL, environment: [String: String]) {
        guard !ownership.isRunning else { return }
        let process = Process()
        process.executableURL = binary
        process.arguments = ["serve"]
        process.environment = environment
        // A file, not a pipe: the server may outlive the app, and writing to
        // a pipe nobody reads makes it fail.
        let output: FileHandle
        do {
            output = try tail.writer()
        } catch {
            ownership = .unavailable(reason: "Cannot open \(tail.url.path): \(error.localizedDescription)")
            return
        }
        process.standardOutput = output
        process.standardError = output
        process.standardInput = FileHandle.nullDevice
        process.terminationHandler = { [weak self] finished in
            let status = finished.terminationStatus
            Task { @MainActor in self?.exited(status: status) }
        }
        do {
            try process.run()
            self.process = process
            ownership = .running(pid: process.processIdentifier, binary: binary.path)
            logs.note("started \(binary.path) serve (pid \(process.processIdentifier))")
        } catch {
            ownership = .unavailable(reason: error.localizedDescription)
            logs.note("failed to start \(binary.path): \(error.localizedDescription)")
        }
    }

    /// Sends SIGTERM; mirmir shuts its listeners down gracefully.
    public func stop() {
        guard let process, process.isRunning else { return }
        logs.note("stopping server (pid \(process.processIdentifier))")
        process.terminate()
    }

    /// Blocks briefly so quitting the app does not orphan the server.
    public func stopAndWait(timeout: TimeInterval = 10) {
        guard let process, process.isRunning else { return }
        process.terminate()
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline { usleep(50_000) }
        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
    }

    private func exited(status: Int32) {
        process = nil
        ownership = .exited(status: status)
        logs.note("server exited with status \(status)")
    }
}
