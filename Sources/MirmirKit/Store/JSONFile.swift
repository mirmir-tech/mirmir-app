import Foundation

/// A Codable value persisted as one JSON file under Application Support.
public struct JSONFile<Value: Codable>: Sendable {
    public let url: URL

    public init(name: String, directory: URL = JSONFile.defaultDirectory) {
        self.url = directory.appendingPathComponent(name)
    }

    public static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Mirmir", isDirectory: true)
    }

    public func load() -> Value? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder.mirmir.decode(Value.self, from: data)
    }

    public func save(_ value: Value) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder.mirmir.encode(value).write(to: url, options: .atomic)
    }
}

extension JSONEncoder {
    static var mirmir: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

extension JSONDecoder {
    static var mirmir: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
