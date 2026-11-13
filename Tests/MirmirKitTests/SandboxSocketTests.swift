import Foundation
import Testing
@testable import MirmirKit

@Suite("Sandboxed socket path")
struct SandboxSocketTests {
    /// The container of a 32-character account, the review's failing case.
    static let account = String(repeating: "a", count: 32)

    @Test func longContainerHomeBindsItsSocketThroughTheRuntimeLink() throws {
        let scratch = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mm-\(UUID().uuidString.prefix(8))", isDirectory: true)
        let home = scratch.appendingPathComponent("Users/\(Self.account)/Library/Containers/tech.mirmir.app/Data").path
        // The sandbox's per-app user directory: `/var/folders/…/0/<bundle id>/`.
        let system = SocketPaths.systemDarwinUserDirectory() ?? NSTemporaryDirectory()
        let userDirectory = (system as NSString).appendingPathComponent("tech.mirmir.test-\(UUID().uuidString.prefix(8))")
        defer {
            try? FileManager.default.removeItem(atPath: userDirectory)
            try? FileManager.default.removeItem(at: scratch)
        }
        let sandbox = ["HOME": home, "APP_SANDBOX_CONTAINER_ID": "tech.mirmir.app"]

        // Without the link the socket does not fit in `sun_path`.
        let standard = SocketPaths(environment: ["HOME": home], darwinUserDirectory: userDirectory).personalSocket
        #expect(standard.utf8.count > SocketPaths.maximumSocketPathLength)
        #expect(throws: POSIXError(.ENAMETOOLONG)) { _ = try UnixSocket.bind(standard) }

        let paths = SocketPaths(environment: sandbox, darwinUserDirectory: userDirectory)
        let socket = paths.personalSocket
        #expect(socket.utf8.count <= SocketPaths.maximumSocketPathLength)
        // The server resolves the same socket from the environment it gets.
        let server = SocketPaths(environment: sandbox.merging(paths.serverEnvironment) { $1 }, darwinUserDirectory: nil)
        #expect(server.personalSocket == socket)

        try paths.prepareRuntimeDirectory()
        try paths.prepareRuntimeDirectory()
        // What mirmir's `ensure_runtime_dirs` creates before it binds.
        try FileManager.default.createDirectory(atPath: server.runtimeDirectory, withIntermediateDirectories: true)
        let listener = try UnixSocket.bind(socket)
        defer { close(listener) }
        #expect(SocketPaths.isSocket(socket))
        // The socket itself lives in the container, as the sandbox requires.
        let target = try #require(paths.runtimeLink?.target)
        #expect(target.hasPrefix(home + "/"))
        #expect(SocketPaths.isSocket((target as NSString).appendingPathComponent("mirmir/mirmir.sock")))
    }

    @Test func staleRuntimeLinkIsReplaced() throws {
        let scratch = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mm-\(UUID().uuidString.prefix(8))", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let paths = SocketPaths(
            environment: ["HOME": scratch.appendingPathComponent("home").path, "APP_SANDBOX_CONTAINER_ID": "tech.mirmir.app"],
            darwinUserDirectory: scratch.appendingPathComponent("user").path
        )
        let link = try #require(paths.runtimeLink)
        try FileManager.default.createDirectory(at: scratch.appendingPathComponent("user"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: link.alias, withDestinationPath: "/nonexistent")
        try paths.prepareRuntimeDirectory()
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: link.alias) == link.target)
    }

    @Test func outsideTheSandboxTheCLIResolutionApplies() {
        let debug = SocketPaths(environment: ["HOME": "/Users/test"], darwinUserDirectory: "/var/folders/xx/abc/0/")
        #expect(debug.runtimeLink == nil)
        #expect(debug.serverEnvironment.isEmpty)
        #expect(debug.personalSocket == "/Users/test/.local/state/mirmir/mirmir.sock")
        let explicit = SocketPaths(
            environment: ["HOME": "/h", "APP_SANDBOX_CONTAINER_ID": "tech.mirmir.app", "XDG_RUNTIME_DIR": "/run/user/1"],
            darwinUserDirectory: "/var/folders/xx/abc/0/tech.mirmir.app/"
        )
        #expect(explicit.runtimeLink == nil)
        #expect(explicit.personalSocket == "/run/user/1/mirmir/mirmir.sock")
    }
}

/// A real AF_UNIX listener, bound the way mirmir binds its socket.
enum UnixSocket {
    static func bind(_ path: String) throws -> Int32 {
        var address = sockaddr_un()
        let bytes = path.utf8CString
        guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else { throw POSIXError(.ENAMETOOLONG) }
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            bytes.withUnsafeBytes { raw.copyMemory(from: $0) }
        }
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0, listen(descriptor, 1) == 0 else {
            let code = POSIXErrorCode(rawValue: errno) ?? .EIO
            close(descriptor)
            throw POSIXError(code)
        }
        return descriptor
    }
}
