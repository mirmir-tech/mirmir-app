import Foundation

/// Where conversations are kept: `chats.json` and the attached images
/// beside it.
public struct ChatStore: Sendable {
    public let file: JSONFile<[Conversation]>
    public let attachments: AttachmentStore

    public init(directory: URL = JSONFile<Int>.defaultDirectory) {
        file = JSONFile(name: "chats.json", directory: directory)
        attachments = AttachmentStore(directory: directory.appendingPathComponent("attachments", isDirectory: true))
    }
}

/// Why saved chats did not load exactly as they were written. A file that
/// is about to be replaced is first copied aside, byte for byte.
public enum ChatLoadIssue: Hashable, Sendable {
    /// `count` conversations could not be read and were left out; the
    /// others loaded. The file as found is kept at `backup`.
    case dropped(count: Int, backup: URL)
    /// The file is not a list of conversations; history starts empty. The
    /// file as found is kept at `backup`.
    case unrecognized(backup: URL)
    /// The file could not be read, or not copied aside. It stays exactly as
    /// it is, and nothing of this session is saved over it.
    case notSaved(reason: String)

    public var message: String {
        switch self {
        case .dropped(let count, let backup):
            let chats = count == 1 ? "1 saved chat" : "\(count) saved chats"
            return "\(chats) could not be read and \(count == 1 ? "is" : "are") hidden. The original file is kept at \(backup.path)."
        case .unrecognized(let backup):
            return "Saved chats could not be read. The original file is kept at \(backup.path)."
        case .notSaved(let reason):
            return "Saved chats could not be read (\(reason)). The file is left untouched and chats of this session are not saved."
        }
    }

    /// Whether the issue holds for the whole session; the others are news
    /// that can be dismissed.
    public var isPersistent: Bool {
        if case .notSaved = self { true } else { false }
    }
}

/// Saved conversations and what went wrong reading them.
struct ChatHistory {
    var conversations: [Conversation] = []
    var issue: ChatLoadIssue?
}

extension ChatStore {
    /// Reads `chats.json`. A missing file is an empty history. Conversations
    /// decode one by one, so a single bad record hides only itself; whenever
    /// anything is left out, the original bytes are copied aside first, and
    /// a file that cannot be read or copied is never written over.
    func load(now: Date = Date()) -> ChatHistory {
        let data: Data
        do {
            guard let read = try file.read() else { return ChatHistory() }
            data = read
        } catch {
            return ChatHistory(issue: .notSaved(reason: error.localizedDescription))
        }
        let records = try? JSONDecoder.mirmir.decode([Lenient<Conversation>].self, from: data)
        let conversations = records?.compactMap(\.value) ?? []
        let dropped = (records?.count ?? 0) - conversations.count
        if records != nil, dropped == 0 { return ChatHistory(conversations: conversations) }
        do {
            let backup = try preserve(data, now: now)
            let issue: ChatLoadIssue = records == nil ? .unrecognized(backup: backup) : .dropped(count: dropped, backup: backup)
            return ChatHistory(conversations: conversations, issue: issue)
        } catch {
            return ChatHistory(conversations: conversations, issue: .notSaved(reason: error.localizedDescription))
        }
    }

    /// Writes `data` next to the file as `chats.json.corrupt-<UTC time>`,
    /// never over an earlier copy.
    func preserve(_ data: Data, now: Date) throws -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        let base = "\(file.url.lastPathComponent).corrupt-\(formatter.string(from: now))"
        let directory = file.url.deletingLastPathComponent()
        var backup = directory.appendingPathComponent(base)
        var attempt = 1
        while FileManager.default.fileExists(atPath: backup.path) {
            attempt += 1
            backup = directory.appendingPathComponent("\(base)-\(attempt)")
        }
        try data.write(to: backup, options: .withoutOverwriting)
        return backup
    }
}

/// One element of a list that decodes to nil instead of failing the list.
private struct Lenient<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: any Decoder) throws {
        value = try? Value(from: decoder)
    }
}

/// Why the latest chats are not on disk. The conversations stay in memory
/// and are saved again on the next change, on a retry, and before quitting.
public struct ChatSaveFailure: Hashable, Sendable {
    public let reason: String

    public var message: String {
        "Chats could not be saved: \(reason). They are kept in memory and saved again when the storage accepts writes."
    }
}
