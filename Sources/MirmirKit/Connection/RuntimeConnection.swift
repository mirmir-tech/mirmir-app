import Foundation
import GRPCCore
import GRPCNIOTransportHTTP2
import MirmirRPC

/// One open gRPC connection to a mirmir `Runtime` service. Every method speaks
/// domain types; protobuf stays inside `MirmirKit`.
public final class RuntimeConnection: Sendable {
    typealias Transport = HTTP2ClientTransport.Posix

    let grpc: GRPCClient<Transport>
    let runtime: Mirmir_V1_Runtime.Client<Transport>
    private let connections: Task<Void, Never>
    /// The socket path, or `host:port` of a remote server.
    public let address: String
    public let health: ServerHealth

    private init(grpc: GRPCClient<Transport>, connections: Task<Void, Never>, address: String, health: ServerHealth) {
        self.grpc = grpc
        self.runtime = Mirmir_V1_Runtime.Client(wrapping: grpc)
        self.connections = connections
        self.address = address
        self.health = health
    }

    /// Connects to a Unix socket and validates the protocol version.
    public static func connect(socket: String) async throws(ConnectionError) -> RuntimeConnection {
        guard SocketPaths.isSocket(socket) else { throw .noServer(socket: socket) }
        do {
            let transport = try HTTP2ClientTransport.Posix(
                // The default authority is the socket path, which is not a
                // valid HTTP/2 `:authority`; tonic rejects such requests.
                target: .unixDomainSocket(path: socket, authority: "localhost"),
                transportSecurity: .plaintext
            )
            return try await open(transport, interceptors: [], address: socket)
        } catch {
            throw ConnectionError.wrap(error)
        }
    }

    /// Connects to a remote server's TLS listener with its API key. A pinned
    /// fingerprint accepts exactly that certificate; without one the
    /// certificate must chain to a system CA.
    public static func connect(remote endpoint: RemoteEndpoint, key: String) async throws(ConnectionError) -> RuntimeConnection {
        let presented = PresentedCertificate()
        let security = endpoint.pinnedFingerprint.map { RemoteTLS.pinned($0, presented: presented) } ?? RemoteTLS.systemTrust
        do {
            let transport = try HTTP2ClientTransport.Posix(target: endpoint.target, transportSecurity: security)
            return try await open(transport, interceptors: [BearerKey(key)], address: endpoint.address)
        } catch {
            throw ConnectionError.remote(
                error, address: endpoint.address, pinned: endpoint.pinnedFingerprint, presented: presented.fingerprint
            )
        }
    }

    /// The certificate fingerprint a remote server presents, read without
    /// trusting it or sending a key: shown before pinning on first use.
    public static func presentedFingerprint(of endpoint: RemoteEndpoint) async throws(ConnectionError) -> CertificateFingerprint {
        do {
            return try await RemoteTLS.presentedFingerprint(host: endpoint.host, port: endpoint.port)
        } catch {
            if let error = error as? ConnectionError { throw error }
            throw .unreachable(address: endpoint.address, detail: error.localizedDescription)
        }
    }

    private static func open(
        _ transport: Transport, interceptors: [any ClientInterceptor], address: String
    ) async throws -> RuntimeConnection {
        let grpc = GRPCClient(transport: transport, interceptors: interceptors)
        let connections = Task<Void, Never> { _ = try? await grpc.runConnections() }
        let runtime = Mirmir_V1_Runtime.Client(wrapping: grpc)
        do {
            var options = CallOptions.defaults
            options.timeout = .seconds(5)
            let reply = try await runtime.health(Mirmir_V1_HealthRequest(), options: options)
            let health = ServerHealth(protocolVersion: reply.protocolVersion, serverVersion: reply.serverVersion)
            if case .updateNeeded(let server) = ProtocolCompatibility(health: health) {
                throw ConnectionError.updateNeeded(serverProtocol: server, serverVersion: health.serverVersion)
            }
            return RuntimeConnection(grpc: grpc, connections: connections, address: address, health: health)
        } catch {
            grpc.beginGracefulShutdown()
            connections.cancel()
            throw error
        }
    }

    public func close() {
        grpc.beginGracefulShutdown()
        connections.cancel()
    }

    /// Runs one unary call and converts failures to `ConnectionError`.
    func call<T: Sendable>(_ body: () async throws -> T) async throws(ConnectionError) -> T {
        do {
            return try await body()
        } catch {
            throw ConnectionError.wrap(error)
        }
    }
}

// MARK: - Unary calls

extension RuntimeConnection {
    public func ping() async throws(ConnectionError) -> ServerHealth {
        try await call {
            let reply = try await runtime.health(Mirmir_V1_HealthRequest())
            return ServerHealth(protocolVersion: reply.protocolVersion, serverVersion: reply.serverVersion)
        }
    }

    public func localModels() async throws(ConnectionError) -> [LocalModel] {
        try await call { try await runtime.listLocalModels(Mirmir_V1_ListLocalModelsRequest()).models.map(LocalModel.init) }
    }

    public func activeSelectors() async throws(ConnectionError) -> [String] {
        try await call { try await runtime.listActiveModels(Mirmir_V1_ListActiveModelsRequest()).selectors }
    }

    public func telemetry() async throws(ConnectionError) -> TelemetrySnapshot {
        try await call { TelemetrySnapshot(try await runtime.telemetry(Mirmir_V1_TelemetryRequest())) }
    }

    public func telemetryHistory(limit: Int) async throws(ConnectionError) -> TelemetryHistory {
        var request = Mirmir_V1_TelemetryHistoryRequest()
        request.limit = UInt32(clamping: limit)
        return try await call { TelemetryHistory(try await runtime.telemetryHistory(request)) }
    }

    public func inspect(selector: String) async throws(ConnectionError) -> ModelInspection {
        var request = Mirmir_V1_InspectModelRequest()
        request.selector = selector
        return try await call { ModelInspection(try await runtime.inspectModel(request)) }
    }

    public func updateSettings(selector: String, settings: GenerationSettings) async throws(ConnectionError) {
        var request = Mirmir_V1_UpdateModelGenerationRequest()
        request.selector = selector
        request.settings = settings.wire
        _ = try await call { try await runtime.updateModelGeneration(request) }
    }

    public func unload(selector: String) async throws(ConnectionError) -> Bool {
        var request = Mirmir_V1_UnloadModelRequest()
        request.selector = selector
        return try await call { try await runtime.unloadModel(request).unloaded }
    }

    public func search(query: String, limit: Int = 30) async throws(ConnectionError) -> [CatalogModel] {
        var request = Mirmir_V1_SearchModelsRequest()
        request.query = query
        request.limit = UInt32(clamping: limit)
        return try await call { try await runtime.searchModels(request).models.map(CatalogModel.init) }
    }

    public func remove(repoID: String) async throws(ConnectionError) -> UInt64 {
        var request = Mirmir_V1_RemoveModelRequest()
        request.repoID = repoID
        return try await call { try await runtime.removeModel(request).freedBytes }
    }

    public func cancel(operationID: String) async throws(ConnectionError) -> Bool {
        var request = Mirmir_V1_CancelOperationRequest()
        request.operationID = operationID
        return try await call { try await runtime.cancelOperation(request).accepted }
    }
}
