import Foundation
import MirmirRPC

/// The server's settings and secrets. A remote key reads a redacted copy and
/// may change only what its scope and the server allow.
extension RuntimeConnection {
    public func configuration() async throws(ConnectionError) -> ServerConfiguration {
        try await call(.discovery) { options in
            ServerConfiguration(try await runtime.getConfiguration(Mirmir_V1_GetConfigurationRequest(), options: options))
        }
    }

    /// Applies one change. The server validates it and answers with the
    /// whole configuration as it now stands.
    public func updateConfiguration(_ change: ConfigurationChange) async throws(ConnectionError) -> ConfigurationUpdate {
        let request = change.wire
        // Testing a token asks the Hugging Face Hub, like a catalog search.
        let kind: UnaryCall = change == .testHuggingFaceToken ? .catalog : .management
        return try await call(kind) { options in
            ConfigurationUpdate(try await runtime.updateConfiguration(request, options: options))
        }
    }
}
