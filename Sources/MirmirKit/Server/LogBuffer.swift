import Foundation
import Observation

public enum LogStream: Sendable {
    case stdout, stderr, supervisor
}

public struct LogLine: Identifiable, Hashable, Sendable {
    public let id: Int
    public let date: Date
    public let stream: LogStream
    public let text: String
}

/// Bounded, observable log of the server process this app owns.
@MainActor
@Observable
public final class LogBuffer {
    public private(set) var lines: [LogLine] = []
    private var nextID = 0
    private var partial: [LogStream: String] = [:]
    public let capacity: Int

    public init(capacity: Int = 4000) {
        self.capacity = capacity
    }

    public func append(_ text: String, stream: LogStream) {
        let combined = (partial[stream] ?? "") + text
        var pieces = combined.components(separatedBy: "\n")
        partial[stream] = pieces.removeLast()
        for piece in pieces where !piece.isEmpty {
            lines.append(LogLine(id: nextID, date: Date(), stream: stream, text: Self.stripANSI(piece)))
            nextID += 1
        }
        if lines.count > capacity { lines.removeFirst(lines.count - capacity) }
    }

    public func note(_ text: String) {
        append(text + "\n", stream: .supervisor)
    }

    public func clear() {
        lines.removeAll()
        partial.removeAll()
    }

    static func stripANSI(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{1B}\\[[0-9;]*[A-Za-z]", with: "", options: .regularExpression)
    }
}
