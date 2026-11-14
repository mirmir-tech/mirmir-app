import Foundation
import GRPCCore
import GRPCNIOTransportHTTP2
import GRPCProtobuf
import MirmirKit
import MirmirRPC
import Synchronization

/// What a `StandInRuntime` received.
final class RuntimeRecord: Sendable {
    private let state = Mutex<(images: [Int], cancelled: [String])>(([], []))

    /// The image size of every Generate request, in arrival order.
    var generatedImageSizes: [Int] { state.withLock { $0.images } }
    /// The operation ids of every CancelOperation request.
    var cancelledOperations: [String] { state.withLock { $0.cancelled } }

    fileprivate func generated(imageBytes: Int) { state.withLock { $0.images.append(imageBytes) } }
    fileprivate func cancelled(_ operation: String) { state.withLock { $0.cancelled.append(operation) } }
}

/// A `Runtime` service that answers Health, records Generate and
/// CancelOperation requests, and streams a scripted reply: Started with
/// operation `op-<n>`, one reasoning and one answer fragment 150 ms apart,
/// then either a completion or, when `holds`, nothing more until the client
/// cancels.
struct StandInRuntime: RegistrableRPCService {
    static let reasoning = "Thinking it over"
    static let answer = "The partial answer"

    let record: RuntimeRecord
    let holds: Bool

    func registerMethods<Transport: ServerTransport>(with router: inout RPCRouter<Transport>) {
        router.registerHandler(
            forMethod: Mirmir_V1_Runtime.Method.Health.descriptor,
            deserializer: ProtobufDeserializer<Mirmir_V1_HealthRequest>(),
            serializer: ProtobufSerializer<Mirmir_V1_HealthResponse>()
        ) { _, _ in
            var reply = Mirmir_V1_HealthResponse()
            reply.protocolVersion = clientProtocolVersion
            reply.serverVersion = "0.6.0-stand-in"
            return StreamingServerResponse(single: ServerResponse(message: reply))
        }
        router.registerHandler(
            forMethod: Mirmir_V1_Runtime.Method.CancelOperation.descriptor,
            deserializer: ProtobufDeserializer<Mirmir_V1_CancelOperationRequest>(),
            serializer: ProtobufSerializer<Mirmir_V1_CancelOperationResponse>()
        ) { [record] request, _ in
            for try await message in request.messages { record.cancelled(message.operationID) }
            var reply = Mirmir_V1_CancelOperationResponse()
            reply.accepted = true
            return StreamingServerResponse(single: ServerResponse(message: reply))
        }
        router.registerHandler(
            forMethod: Mirmir_V1_Runtime.Method.Generate.descriptor,
            deserializer: ProtobufDeserializer<Mirmir_V1_GenerateRequest>(),
            serializer: ProtobufSerializer<Mirmir_V1_GenerateEvent>()
        ) { [record, holds] request, _ in
            for try await message in request.messages { record.generated(imageBytes: message.image.count) }
            let operation = "op-\(record.generatedImageSizes.count)"
            return StreamingServerResponse { writer in
                try await writer.write(Self.started(operation))
                // Paced beyond the app's 50 ms stream interval, so every
                // fragment is shown as it arrives.
                try await writer.write(Self.token(Self.reasoning, reasoning: true))
                try await Task.sleep(for: .milliseconds(150))
                try await writer.write(Self.token(Self.answer, reasoning: false))
                if holds {
                    try await Task.sleep(for: .seconds(3_600))
                } else {
                    try await writer.write(Self.completion())
                }
                return [:]
            }
        }
    }

    private static func started(_ operation: String) -> Mirmir_V1_GenerateEvent {
        var event = Mirmir_V1_GenerateEvent()
        event.started.operationID = operation
        return event
    }

    private static func token(_ text: String, reasoning: Bool) -> Mirmir_V1_GenerateEvent {
        var event = Mirmir_V1_GenerateEvent()
        event.token.text = text
        event.token.reasoning = reasoning
        return event
    }

    private static func completion() -> Mirmir_V1_GenerateEvent {
        var event = Mirmir_V1_GenerateEvent()
        event.completion.text = answer
        event.completion.reasoning = reasoning
        event.completion.promptTokens = 1
        event.completion.completionTokens = 2
        event.completion.finishReason = "stop"
        return event
    }
}

/// Serves `StandInRuntime` on a Unix socket for the duration of a test, with
/// mirmir's request limit (`MessageLimits.messageBytes`).
final class StandInServer: Sendable {
    let socket: String
    let record = RuntimeRecord()
    private let serving: Task<Void, any Error>

    init(socket: String, holds: Bool) async throws {
        self.socket = socket
        let transport = HTTP2ServerTransport.Posix(
            address: .unixDomainSocket(path: socket), transportSecurity: .plaintext,
            config: .defaults { $0.rpc.maxRequestPayloadSize = MessageLimits.messageBytes }
        )
        let server = GRPCServer(transport: transport, services: [StandInRuntime(record: record, holds: holds)])
        serving = Task { try await server.serve() }
        _ = try await transport.listeningAddress
    }

    func stop() {
        serving.cancel()
        try? FileManager.default.removeItem(atPath: socket)
    }
}

/// Polls `condition` on the main actor until it holds or `timeout` passes.
@MainActor
func eventually(_ timeout: Duration = .seconds(5), _ condition: () -> Bool) async throws -> Bool {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if condition() { return true }
        try await Task.sleep(for: .milliseconds(10))
    }
    return condition()
}
