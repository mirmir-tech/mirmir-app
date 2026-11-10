import Foundation

/// The `Runtime` protocol this client speaks. Must equal mirmir's
/// `application::PROTOCOL_VERSION` for the generated code in `MirmirRPC`.
public let clientProtocolVersion = "1"

/// Result of comparing a server's `Health` with this client, the same rule as
/// mirmir's `validate_protocol`.
public enum ProtocolCompatibility: Hashable, Sendable {
    case compatible
    case updateNeeded(serverProtocol: String)

    public init(health: ServerHealth) {
        self = health.protocolVersion == clientProtocolVersion
            ? .compatible
            : .updateNeeded(serverProtocol: health.protocolVersion)
    }
}
