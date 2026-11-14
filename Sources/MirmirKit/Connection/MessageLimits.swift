import GRPCCore

/// How large one gRPC message to or from a `Runtime` server may be. mirmir
/// accepts requests up to 32 MiB, raised from gRPC's 4 MiB default so a
/// Generate request carries an image the server's media policy accepts
/// (up to 20 MiB) together with its conversation.
public enum MessageLimits {
    /// The largest image a request carries; mirmir's media policy limit.
    public static let imageBytes = 20 * 1024 * 1024
    /// The largest message either side sends: mirmir's request limit.
    public static let messageBytes = 32 * 1024 * 1024

    /// Applies `messageBytes` to every method in both directions. grpc-swift
    /// otherwise caps a message at 4 MiB. Timeouts stay per call
    /// (`CallDeadlines`).
    static var serviceConfig: ServiceConfig {
        let every = MethodConfig(
            names: [MethodConfig.Name(service: "")],
            maxRequestMessageBytes: messageBytes,
            maxResponseMessageBytes: messageBytes
        )
        return ServiceConfig(methodConfig: [every])
    }
}
