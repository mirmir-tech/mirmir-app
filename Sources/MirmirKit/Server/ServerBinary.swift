import Foundation

/// Locates the `mirmir` executable used to start the personal server.
public enum ServerBinary {
    public static let overrideKey = "mirmirBinaryPath"

    /// Search order: explicit setting, `MIRMIR_BINARY`, the helper bundled in
    /// `Mirmir.app/Contents/Helpers`, then common install locations and `PATH`.
    public static func resolve(
        override: String? = UserDefaults.standard.string(forKey: overrideKey),
        environment: [String: String] = ProcessInfo.processInfo.environment,
        bundle: Bundle = .main
    ) -> URL? {
        candidates(override: override, environment: environment, bundle: bundle)
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    static func candidates(override: String?, environment: [String: String], bundle: Bundle) -> [URL] {
        var urls: [URL] = []
        if let override, !override.isEmpty { urls.append(URL(fileURLWithPath: (override as NSString).expandingTildeInPath)) }
        if let binary = environment["MIRMIR_BINARY"] { urls.append(URL(fileURLWithPath: binary)) }
        urls.append(bundle.bundleURL.appendingPathComponent("Contents/Helpers/mirmir"))
        let home = environment["HOME"] ?? NSHomeDirectory()
        let directories = ["/opt/homebrew/bin", "/usr/local/bin", "\(home)/.cargo/bin", "\(home)/.local/bin"]
            + (environment["PATH"] ?? "").split(separator: ":").map(String.init)
        var seen = Set<String>()
        for directory in directories where seen.insert(directory).inserted {
            urls.append(URL(fileURLWithPath: directory).appendingPathComponent("mirmir"))
        }
        return urls
    }
}
