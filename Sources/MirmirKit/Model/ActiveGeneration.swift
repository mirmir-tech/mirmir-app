import Foundation

/// The one reply streaming at a time: the conversation and message it fills,
/// what has streamed so far, and the RPC on the server that runs it.
@MainActor
struct ActiveGeneration {
    let conversation: UUID
    let reply: UUID
    /// Everything streamed so far, which may be ahead of what is on screen.
    let stream: ReplyAccumulator
    let task: Task<Void, Never>
    /// The server running it; a cancel goes there even after a switch.
    let connection: RuntimeConnection
    /// The server's id for the operation, known once it has started.
    var operationID: String?
}
