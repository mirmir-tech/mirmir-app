import Foundation

/// Locates the `mirmir` executable the app runs as its server: the one it
/// bundles at `Mirmir.app/Contents/Helpers/mirmir`. The app is sandboxed, so
/// a `mirmir` on PATH or elsewhere is neither reachable nor wanted; the
/// bundled one matches the app's protocol and carries the sandbox
/// inheritance entitlement.
public enum ServerBinary {
    public static func resolve(bundle: Bundle = .main) -> URL? {
        let url = bundled(in: bundle)
        return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
    }

    static func bundled(in bundle: Bundle) -> URL {
        bundle.bundleURL.appendingPathComponent("Contents/Helpers/mirmir")
    }
}
