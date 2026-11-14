import Foundation
import GRPCCore
import GRPCProtobuf
import MirmirRPC

/// InspectModel, LoadModel and UpdateModelGeneration for `StandInRuntime`:
/// each records the context it was sent. The model reports a context of
/// 16..40,960 tokens in 16-token blocks, automatic sizing to 194,128 tokens,
/// and a memory estimate at the requested (else saved) context.
extension StandInRuntime {
    static let automaticTokens: UInt64 = 194_128

    func registerModelMethods<Transport: ServerTransport>(with router: inout RPCRouter<Transport>) {
        router.registerHandler(
            forMethod: Mirmir_V1_Runtime.Method.InspectModel.descriptor,
            deserializer: ProtobufDeserializer<Mirmir_V1_InspectModelRequest>(),
            serializer: ProtobufSerializer<Mirmir_V1_InspectModelResponse>()
        ) { [record] request, _ in
            var context: Mirmir_V1_ModelContextChoice?
            for try await message in request.messages { context = message.hasContext ? message.context : nil }
            record.recordModelCall { $0.inspected.append(context) }
            return StreamingServerResponse(single: ServerResponse(message: Self.inspection(context)))
        }
        router.registerHandler(
            forMethod: Mirmir_V1_Runtime.Method.LoadModel.descriptor,
            deserializer: ProtobufDeserializer<Mirmir_V1_LoadModelRequest>(),
            serializer: ProtobufSerializer<Mirmir_V1_ModelLifecycleEvent>()
        ) { [record] request, _ in
            for try await message in request.messages {
                record.recordModelCall { $0.loaded.append(message.hasContext ? message.context : nil) }
            }
            return StreamingServerResponse { writer in
                var event = Mirmir_V1_ModelLifecycleEvent()
                event.phase = "ready"
                event.model = Mirmir_V1_ModelInfo()
                try await writer.write(event)
                return [:]
            }
        }
        router.registerHandler(
            forMethod: Mirmir_V1_Runtime.Method.UpdateModelGeneration.descriptor,
            deserializer: ProtobufDeserializer<Mirmir_V1_UpdateModelGenerationRequest>(),
            serializer: ProtobufSerializer<Mirmir_V1_UpdateModelGenerationResponse>()
        ) { [record] request, _ in
            for try await message in request.messages {
                record.recordModelCall { $0.updated.append((message.hasSettings, message.hasContext ? message.context : nil)) }
            }
            var reply = Mirmir_V1_UpdateModelGenerationResponse()
            reply.modelID = "m"
            return StreamingServerResponse(single: ServerResponse(message: reply))
        }
    }

    private static func inspection(_ context: Mirmir_V1_ModelContextChoice?) -> Mirmir_V1_InspectModelResponse {
        var reply = Mirmir_V1_InspectModelResponse()
        reply.settings.maxTokens = 4_096
        reply.capabilities.maxInputTokens = 40_960
        reply.context.blockTokens = 16
        reply.context.minTokens = 16
        reply.context.maxTokens = 40_960
        reply.context.saved.automatic = true
        reply.context.automaticTokens = automaticTokens
        if case .tokens(let tokens) = context?.choice {
            reply.memory.configuredCacheTokens = tokens
        } else {
            reply.memory.configuredCacheTokens = automaticTokens
        }
        reply.memory.fit = "fits"
        return reply
    }
}
