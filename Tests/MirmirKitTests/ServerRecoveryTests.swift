import Foundation
import Testing
@testable import MirmirKit

#if canImport(Darwin)
import Darwin

/// A server an earlier run left on the container socket is taken over only
/// when the process serving it is the bundle's own helper.
@Suite("Recovering the app's server")
@MainActor
struct ServerRecoveryTests {
    private static var ownExecutable: URL {
        get throws { URL(fileURLWithPath: try #require(ServerSupervisor.executablePath(of: getpid()))) }
    }

    @Test func thePeerOfTheSocketIsTheProcessServingIt() async throws {
        let directory = try DeadlineTests.scratch()
        defer { try? FileManager.default.removeItem(at: directory) }
        let server = try await StandInServer(socket: directory.appendingPathComponent("mirmir.sock").path, holds: false)
        defer { server.stop() }

        #expect(ServerSupervisor.peerPID(of: server.socket) == getpid())
        #expect(ServerSupervisor.helperPID(serving: server.socket, binary: try Self.ownExecutable) == getpid())
        let other = URL(fileURLWithPath: "/usr/bin/true")
        #expect(ServerSupervisor.helperPID(serving: server.socket, binary: other) == nil)
        #expect(ServerSupervisor.peerPID(of: directory.appendingPathComponent("none.sock").path) == nil)
    }

    @Test func onlyTheBundlesHelperIsRecovered() async throws {
        let directory = try DeadlineTests.scratch()
        defer { try? FileManager.default.removeItem(at: directory) }
        let server = try await StandInServer(socket: directory.appendingPathComponent("mirmir.sock").path, holds: false)
        defer { server.stop() }

        let stranger = ServerSupervisor(logFile: directory.appendingPathComponent("a.log"))
        #expect(await stranger.recover(serving: server.socket, binary: URL(fileURLWithPath: "/usr/bin/true")) == false)
        #expect(stranger.ownership == .none)

        // Never stopped here: the "helper" is this test process.
        let own = ServerSupervisor(logFile: directory.appendingPathComponent("b.log"))
        let binary = try Self.ownExecutable
        #expect(await own.recover(serving: server.socket, binary: binary))
        #expect(own.ownership == .running(pid: getpid(), binary: binary.path))
        #expect(own.ownership.isStarting)
        // Already owned: nothing else is taken over.
        #expect(await own.recover(serving: server.socket, binary: binary) == false)
    }

    @Test func configuringCountsAsStarting() {
        #expect(ServerOwnership.configuring.isStarting)
        #expect(!ServerOwnership.configuring.isRunning)
        #expect(ServerOwnership.running(pid: 1, binary: "/x").isStarting)
        #expect(!ServerOwnership.none.isStarting)
        #expect(!ServerOwnership.exited(status: 0).isStarting)
        #expect(!ServerOwnership.unavailable(reason: "").isStarting)
    }
}
#endif
