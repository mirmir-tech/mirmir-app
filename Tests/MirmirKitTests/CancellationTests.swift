import GRPCCore
import Testing
@testable import MirmirKit

@Suite("Cancelled calls")
@MainActor
struct CancellationTests {
    @Test func cancellationIsNotAFailure() {
        #expect(ConnectionError.wrap(CancellationError()) == .cancelled)
        let transport = RPCError(code: .unknown, message: "The transport threw an unexpected error.", cause: CancellationError())
        #expect(ConnectionError.wrap(transport) == .cancelled)
        #expect(ConnectionError.wrap(RPCError(code: .cancelled, message: "")) == .cancelled)
        #expect(!ConnectionError.cancelled.isUnreachable)
    }

    @Test func otherTransportErrorsKeepTheirCause() {
        struct Broken: Error {}
        let transport = RPCError(code: .unknown, message: "The transport threw an unexpected error.", cause: Broken())
        guard case .rpc(.unknown, let message) = ConnectionError.wrap(transport) else {
            Issue.record("expected an rpc error"); return
        }
        #expect(message.contains("Broken"))
    }

    @Test func cancelledCallsRaiseNoNotice() {
        let model = AppModel.preview()
        model.report(CancellationError(), "Inspecting x failed")
        #expect(model.notice == nil)
        model.report(RPCError(code: .internalError, message: "boom"), "Inspecting x failed")
        #expect(model.notice == "Inspecting x failed: boom")
    }
}

/// A removal the server refuses (a model loaded from a cache it would take,
/// a transfer in progress) is a failed precondition: reported with the
/// server's own words, not as a lost connection.
struct RefusalTests {
    @Test func aFailedPreconditionKeepsTheServersMessage() {
        let message = "Owner/Repo-GGUF is loaded from the cache this removal takes; unload it first"
        let error = ConnectionError.wrap(RPCError(code: .failedPrecondition, message: message))
        #expect(error == .rpc(code: .failedPrecondition, message: message))
        #expect(error.errorDescription == message)
        #expect(!error.isUnreachable)
    }
}
