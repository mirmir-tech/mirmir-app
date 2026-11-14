import Foundation

/// Follows the server log file. The server writes to a file instead of pipes
/// so it never sees a broken pipe when the app exits before it does.
///
/// Reading, line splitting and ANSI stripping run on a private serial queue;
/// the main actor only receives finished lines, at most twice a second.
public final class LogTail: @unchecked Sendable {
    let url: URL
    private let logs: LogBuffer
    private let queue = DispatchQueue(label: "tech.mirmir.app.log-tail", qos: .utility)
    // Mutable state below is touched only on `queue`.
    private var offset: UInt64 = 0
    private var partial = ""
    private var skipPartialLine = false
    private var timer: DispatchSourceTimer?

    /// The most of an existing file shown when the app starts.
    static let backlog: UInt64 = 64 * 1024

    init(url: URL, logs: LogBuffer) {
        self.url = url
        self.logs = logs
    }

    public static var defaultURL: URL {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/Mirmir/server.log")
    }

    /// Opens the file for the server, creating it and its directory.
    func writer() throws -> FileHandle {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            _ = FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        return handle
    }

    func start() {
        queue.async { [self] in
            guard timer == nil else { return }
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? UInt64) ?? 0
            offset = size > Self.backlog ? size - Self.backlog : 0
            skipPartialLine = offset > 0
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now(), repeating: .milliseconds(500), leeway: .milliseconds(100))
            timer.setEventHandler { [weak self] in self?.read() }
            timer.resume()
            self.timer = timer
        }
    }

    private func read() {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        if size < offset { offset = 0; partial = "" }
        guard size > offset else { return }
        try? handle.seek(toOffset: offset)
        guard let data = try? handle.readToEnd() else { return }
        offset += UInt64(data.count)

        var pieces = (partial + String(decoding: data, as: UTF8.self)).components(separatedBy: "\n")
        partial = pieces.removeLast()
        if skipPartialLine, !pieces.isEmpty {
            pieces.removeFirst()
            skipPartialLine = false
        }
        let lines = pieces.lazy.filter { !$0.isEmpty }.map(LogBuffer.stripANSI).suffix(logs.capacity)
        guard !lines.isEmpty else { return }
        let batch = Array(lines)
        let logs = logs
        DispatchQueue.main.async {
            MainActor.assumeIsolated { logs.append(lines: batch, stream: .stderr) }
        }
    }
}
