import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Recovering the app's own server left running by an earlier run that
/// crashed or was killed. Such a server serves the container socket but is
/// no child of this run; it is taken over only after the process at the other
/// end of the socket is verified to be this bundle's helper, so Pause, Quit
/// and a folder grant's restart act on it as on one this run started.
extension ServerSupervisor {
    /// Shown for a server on the container socket this run could not verify
    /// as its own helper, such as one another copy of Mirmir started.
    public static let unverifiedServerAdvice = "This Mac's server was started outside this run of Mirmir, "
        + "for example by another copy of the app, so it cannot be paused or restarted here. "
        + "Quit the copy that started it, or end its mirmir process in Activity Monitor."

    /// Takes over the server serving `socket` when it is `binary`, this
    /// bundle's helper. Returns whether it did; a server this run already
    /// owns or starts is left as it is.
    @discardableResult
    public func recover(serving socket: String, binary: URL? = ServerBinary.resolve()) async -> Bool {
        guard case .none = ownership, let binary else { return false }
        let pid = await Task.detached(priority: .utility) { Self.helperPID(serving: socket, binary: binary) }.value
        guard let pid, case .none = ownership else { return false }
        adopt(pid: pid, binary: binary)
        return true
    }

    private func adopt(pid: Int32, binary: URL) {
        #if canImport(Darwin)
        let source = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.recoveredExited(pid) }
        }
        source.resume()
        recovered = source
        #endif
        ownership = .running(pid: pid, binary: binary.path)
        logs.note("recovered the bundled server an earlier run left running (pid \(pid))")
    }

    /// The exit status of a recovered server goes to its own parent; this
    /// run only learns that nothing it runs is left.
    private func recoveredExited(_ pid: Int32) {
        recovered?.cancel()
        recovered = nil
        guard case .running(pid, _) = ownership else { return }
        ownership = .none
        logs.note("server exited (pid \(pid))")
    }

    /// The process serving `socket` when its executable is `binary`.
    nonisolated static func helperPID(serving socket: String, binary: URL) -> Int32? {
        guard let pid = peerPID(of: socket), let path = executablePath(of: pid) else { return nil }
        func real(_ path: String) -> String { URL(fileURLWithPath: path).resolvingSymlinksInPath().path }
        return real(path) == real(binary.path) ? pid : nil
    }

    /// The process listening on a Unix socket, from the kernel's record of
    /// the peer of a connection to it.
    nonisolated static func peerPID(of socket: String) -> Int32? {
        #if canImport(Darwin)
        var address = sockaddr_un()
        let bytes = socket.utf8CString
        guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else { return nil }
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            bytes.withUnsafeBytes { raw.copyMemory(from: $0) }
        }
        let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return nil }
        defer { close(descriptor) }
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else { return nil }
        var pid: pid_t = 0
        var length = socklen_t(MemoryLayout<pid_t>.size)
        guard getsockopt(descriptor, SOL_LOCAL, LOCAL_PEERPID, &pid, &length) == 0, pid > 0 else { return nil }
        return pid
        #else
        return nil
        #endif
    }

    /// The executable of a process; nil when the sandbox does not tell.
    nonisolated static func executablePath(of pid: Int32) -> String? {
        #if canImport(Darwin)
        var buffer = [UInt8](repeating: 0, count: Int(MAXPATHLEN) * 4)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(decoding: buffer.prefix(Int(length)), as: UTF8.self)
        #else
        return nil
        #endif
    }
}
