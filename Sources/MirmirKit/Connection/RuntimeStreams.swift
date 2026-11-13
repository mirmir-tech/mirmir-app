import Foundation
import GRPCCore
import MirmirRPC

// Server-streaming calls. Each runs until the stream ends; cancelling the
// calling task cancels the RPC, which the server observes as a disconnect.

extension RuntimeConnection {
    public func load(
        selector: String,
        onProgress: @escaping @Sendable (LoadProgress) async -> Void
    ) async throws(ConnectionError) {
        var request = Mirmir_V1_LoadModelRequest()
        request.selector = selector
        try await call {
            try await runtime.loadModel(request) { response in
                for try await event in response.messages {
                    await onProgress(LoadProgress(event))
                }
            }
        }
    }

    public func pull(
        repoID: String,
        onProgress: @escaping @Sendable (TransferProgress) async -> Void
    ) async throws(ConnectionError) {
        var request = Mirmir_V1_PullModelRequest()
        request.repoID = repoID
        try await call {
            try await runtime.pullModel(request) { response in
                for try await event in response.messages {
                    await onProgress(TransferProgress(event))
                }
            }
        }
    }

    /// Streams activity until the connection closes or the task is cancelled.
    public func watchActivity(onEvent: @escaping @Sendable (Activity) async -> Void) async throws(ConnectionError) {
        var request = Mirmir_V1_WatchActivityRequest()
        request.includeHistory = true
        try await call {
            try await runtime.watchActivity(request) { response in
                for try await event in response.messages {
                    await onEvent(Activity(event))
                }
            }
        }
    }

    public func generate(
        _ generation: GenerationRequest,
        onEvent: @escaping @Sendable (GenerationEvent) async -> Void
    ) async throws(ConnectionError) {
        let request = generation.wire
        try await call {
            try await runtime.generate(request) { response in
                for try await event in response.messages {
                    switch event.event {
                    case .started(let started):
                        await onEvent(.started(operationID: started.operationID))
                    case .token(let token):
                        await onEvent(.token(text: token.text, reasoning: token.reasoning))
                    case .completion(let completion):
                        await onEvent(.completed(
                            text: completion.text, reasoning: completion.reasoning,
                            stats: GenerationStats(completion)
                        ))
                    case nil:
                        continue
                    }
                }
            }
        }
    }
}

extension GenerationRequest {
    /// libmir's `IMAGE_PLACEHOLDER`.
    static let imagePlaceholder = "<|mirmir_image|>"

    var wire: Mirmir_V1_GenerateRequest {
        var request = Mirmir_V1_GenerateRequest()
        request.model = model
        // The engine places the image where its marker is and requires exactly
        // one; like the TUI and web chat, it goes before the last user turn.
        let imageTurn = image == nil ? nil : turns.lastIndex { $0.role == .user }
        request.messages = turns.enumerated().map { index, turn in
            var message = Mirmir_V1_ChatMessageInput()
            message.role = turn.role.rawValue
            message.content = index == imageTurn ? "\(Self.imagePlaceholder)\n\(turn.content)" : turn.content
            if let reasoning = turn.reasoning, !reasoning.isEmpty { message.reasoningContent = reasoning }
            return message
        }
        if let maxTokens { request.maxTokens = maxTokens }
        if let temperature { request.temperature = temperature }
        if let image { request.image = image }
        return request
    }
}
