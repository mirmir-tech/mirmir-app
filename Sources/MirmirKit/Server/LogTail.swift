import Foundation

/// Follows the server log file. The server writes to a file instead of pipes
/// so it never sees a broken pipe when the app exits before it does.
@MainActor
public final class LogTail {
    let url: URL
    private let logs: LogBuffer
    private var offset: UInt64 = 0
    private var timer: Timer?

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
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        return handle
    }

    func start() {
        guard timer == nil else { return }
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? UInt64) ?? 0
        offset = size > Self.backlog ? size - Self.backlog : 0
        read(skipPartialLine: offset > 0)
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.read(skipPartialLine: false) }
        }
    }

    private func read(skipPartialLine: Bool) {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        if size < offset { offset = 0 }
        guard size > offset else { return }
        try? handle.seek(toOffset: offset)
        guard let data = try? handle.readToEnd() else { return }
        offset += UInt64(data.count)
        var text = String(decoding: data, as: UTF8.self)
        if skipPartialLine, let newline = text.firstIndex(of: "\n") {
            text = String(text[text.index(after: newline)...])
        }
        logs.append(text, stream: .stderr)
    }
}
