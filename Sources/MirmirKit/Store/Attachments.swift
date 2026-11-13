import Foundation

/// The image attached to a user message.
public enum MessageImage: Hashable, Sendable, Codable {
    /// Kept in the attachment store under this id; every later request of
    /// the conversation sends it again.
    case stored(UUID)
    /// Attached before the app kept images: only the fact remains.
    case unavailable
}

/// Attached images, one file each beside `chats.json`, stored already
/// normalized to a format the server decodes. Requests are stateless, so a
/// conversation's image must outlive the message that attached it.
public struct AttachmentStore: Sendable {
    let directory: URL

    public init(directory: URL = JSONFile<Int>.defaultDirectory.appendingPathComponent("attachments", isDirectory: true)) {
        self.directory = directory
    }

    public func save(_ data: Data) throws -> UUID {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let id = UUID()
        try data.write(to: url(id), options: .atomic)
        return id
    }

    /// The image's bytes. A missing or unreadable file throws: a request
    /// must never quietly go without the image the conversation shows.
    public func load(_ id: UUID) throws -> Data {
        try Data(contentsOf: url(id))
    }

    public func remove(_ id: UUID) {
        try? FileManager.default.removeItem(at: url(id))
    }

    private func url(_ id: UUID) -> URL {
        directory.appendingPathComponent(id.uuidString)
    }
}
