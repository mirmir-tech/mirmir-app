import Foundation
import GRPCCore
import GRPCNIOTransportHTTP2
import GRPCProtobuf
import MirmirKit
import MirmirRPC

/// A `Runtime` service that answers Health and then stops answering:
/// Telemetry and ListActiveModels are accepted on the open connection but
/// never replied to, like a server that hangs after the handshake.
struct StallingRuntime: RegistrableRPCService {
    func registerMethods<Transport: ServerTransport>(with router: inout RPCRouter<Transport>) {
        router.registerHandler(
            forMethod: Mirmir_V1_Runtime.Method.Health.descriptor,
            deserializer: ProtobufDeserializer<Mirmir_V1_HealthRequest>(),
            serializer: ProtobufSerializer<Mirmir_V1_HealthResponse>()
        ) { _, _ in
            var reply = Mirmir_V1_HealthResponse()
            reply.protocolVersion = clientProtocolVersion
            reply.serverVersion = "0.6.0-stalled"
            return StreamingServerResponse(single: ServerResponse(message: reply))
        }
        router.registerHandler(
            forMethod: Mirmir_V1_Runtime.Method.Telemetry.descriptor,
            deserializer: ProtobufDeserializer<Mirmir_V1_TelemetryRequest>(),
            serializer: ProtobufSerializer<Mirmir_V1_TelemetrySnapshot>()
        ) { _, _ in try await Self.stall() }
        router.registerHandler(
            forMethod: Mirmir_V1_Runtime.Method.ListActiveModels.descriptor,
            deserializer: ProtobufDeserializer<Mirmir_V1_ListActiveModelsRequest>(),
            serializer: ProtobufSerializer<Mirmir_V1_ListActiveModelsResponse>()
        ) { _, _ in try await Self.stall() }
    }

    /// Waits until the client gives up and cancels the RPC.
    private static func stall<Output>() async throws -> StreamingServerResponse<Output> {
        try await Task.sleep(for: .seconds(3_600))
        throw RPCError(code: .internalError, message: "stalled call outlived its test")
    }
}

/// Serves `StallingRuntime` on a Unix socket for the duration of a test.
final class StallingServer: Sendable {
    let socket: String
    private let serving: Task<Void, any Error>

    init(socket: String) async throws {
        self.socket = socket
        let transport = HTTP2ServerTransport.Posix(
            address: .unixDomainSocket(path: socket), transportSecurity: .plaintext
        )
        let server = GRPCServer(transport: transport, services: [StallingRuntime()])
        serving = Task { try await server.serve() }
        _ = try await transport.listeningAddress
    }

    func stop() {
        serving.cancel()
        try? FileManager.default.removeItem(atPath: socket)
    }
}
