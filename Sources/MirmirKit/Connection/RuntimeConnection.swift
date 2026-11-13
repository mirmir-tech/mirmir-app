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
    /// How long each kind of unary call waits for its reply.
    public let deadlines: CallDeadlines

    private init(
        grpc: GRPCClient<Transport>, connections: Task<Void, Never>, address: String, health: ServerHealth,
        deadlines: CallDeadlines
    ) {
        self.grpc = grpc
        self.runtime = Mirmir_V1_Runtime.Client(wrapping: grpc)
        self.connections = connections
        self.address = address
        self.health = health
        self.deadlines = deadlines
    }

    /// Connects to a Unix socket and validates the protocol version.
    public static func connect(
        socket: String, deadlines: CallDeadlines = .standard
    ) async throws(ConnectionError) -> RuntimeConnection {
        guard SocketPaths.isSocket(socket) else { throw .noServer(socket: socket) }
        do {
            let transport = try HTTP2ClientTransport.Posix(
                // The default authority is the socket path, which is not a
                // valid HTTP/2 `:authority`; tonic rejects such requests.
                target: .unixDomainSocket(path: socket, authority: "localhost"),
                transportSecurity: .plaintext
            )
            return try await open(transport, interceptors: [], address: socket, deadlines: deadlines)
        } catch {
            throw ConnectionError.wrap(error)
        }
    }

    /// Connects to a remote server's TLS listener with its API key. A pinned
    /// fingerprint accepts exactly that certificate; without one the
    /// certificate must chain to a system CA.
    public static func connect(
        remote endpoint: RemoteEndpoint, key: String, deadlines: CallDeadlines = .standard
    ) async throws(ConnectionError) -> RuntimeConnection {
        let presented = PresentedCertificate()
        let security = endpoint.pinnedFingerprint.map { RemoteTLS.pinned($0, presented: presented) } ?? RemoteTLS.systemTrust
        do {
            let transport = try HTTP2ClientTransport.Posix(target: endpoint.target, transportSecurity: security)
            return try await open(
                transport, interceptors: [BearerKey(key)], address: endpoint.address, deadlines: deadlines
            )
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
            throw .unreachable(address: endpoint.address, detail: ConnectionError.describe(error))
        }
    }

    private static func open(
        _ transport: Transport, interceptors: [any ClientInterceptor], address: String, deadlines: CallDeadlines
    ) async throws -> RuntimeConnection {
        let grpc = GRPCClient(transport: transport, interceptors: interceptors)
        let connections = Task<Void, Never> { _ = try? await grpc.runConnections() }
        let runtime = Mirmir_V1_Runtime.Client(wrapping: grpc)
        do {
            let reply = try await runtime.health(Mirmir_V1_HealthRequest(), options: deadlines.options(for: .health))
            let health = ServerHealth(protocolVersion: reply.protocolVersion, serverVersion: reply.serverVersion)
            if case .updateNeeded(let server) = ProtocolCompatibility(health: health) {
                throw ConnectionError.updateNeeded(serverProtocol: server, serverVersion: health.serverVersion)
            }
            return RuntimeConnection(
                grpc: grpc, connections: connections, address: address, health: health, deadlines: deadlines
            )
        } catch {
            grpc.beginGracefulShutdown()
            connections.cancel()
            throw error
        }
    }

    #if DEBUG
    /// A connection for SwiftUI previews: it never dials a server and every
    /// call on it fails at once, so previews only render the data they were
    /// given.
    public static func preview() -> RuntimeConnection {
        let transport = try! HTTP2ClientTransport.Posix(
            target: .unixDomainSocket(path: "/nonexistent/mirmir-preview.sock", authority: "localhost"),
            transportSecurity: .plaintext
        )
        // Closed before it ever runs: calls fail instead of waiting for a
        // connection that never comes.
        let grpc = GRPCClient(transport: transport)
        grpc.beginGracefulShutdown()
        return RuntimeConnection(
            grpc: grpc,
            connections: Task {},
            address: "preview",
            health: ServerHealth(protocolVersion: "2", serverVersion: "0.6.0"),
            deadlines: .standard
        )
    }
    #endif

    public func close() {
        grpc.beginGracefulShutdown()
        connections.cancel()
    }

    /// Runs one unary call under its kind's deadline and converts failures
    /// to `ConnectionError`; a missed deadline is `.timedOut`.
    func call<T: Sendable>(
        _ kind: UnaryCall, _ body: (CallOptions) async throws -> T
    ) async throws(ConnectionError) -> T {
        do {
            return try await body(deadlines.options(for: kind))
        } catch let error as RPCError where error.code == .deadlineExceeded {
            throw .timedOut(address: address, after: deadlines.timeout(for: kind))
        } catch {
            throw ConnectionError.wrap(error)
        }
    }

    /// Runs one server-streaming call, which has no deadline: it lasts until
    /// the stream ends or the calling task is cancelled.
    func stream(_ body: () async throws -> Void) async throws(ConnectionError) {
        do {
            try await body()
        } catch {
            throw ConnectionError.wrap(error)
        }
    }
}

// MARK: - Unary calls

extension RuntimeConnection {
    public func ping() async throws(ConnectionError) -> ServerHealth {
        try await call(.health) { options in
            let reply = try await runtime.health(Mirmir_V1_HealthRequest(), options: options)
            return ServerHealth(protocolVersion: reply.protocolVersion, serverVersion: reply.serverVersion)
        }
    }

    public func localModels() async throws(ConnectionError) -> [LocalModel] {
        try await call(.discovery) { options in
            try await runtime.listLocalModels(Mirmir_V1_ListLocalModelsRequest(), options: options).models.map(LocalModel.init)
        }
    }

    public func activeSelectors() async throws(ConnectionError) -> [String] {
        try await call(.monitoring) { options in
            try await runtime.listActiveModels(Mirmir_V1_ListActiveModelsRequest(), options: options).selectors
        }
    }

    public func telemetry() async throws(ConnectionError) -> TelemetrySnapshot {
        try await call(.monitoring) { options in
            TelemetrySnapshot(try await runtime.telemetry(Mirmir_V1_TelemetryRequest(), options: options))
        }
    }

    public func telemetryHistory(limit: Int) async throws(ConnectionError) -> TelemetryHistory {
        var request = Mirmir_V1_TelemetryHistoryRequest()
        request.limit = UInt32(clamping: limit)
        return try await call(.monitoring) { options in
            TelemetryHistory(try await runtime.telemetryHistory(request, options: options))
        }
    }

    public func inspect(selector: String) async throws(ConnectionError) -> ModelInspection {
        var request = Mirmir_V1_InspectModelRequest()
        request.selector = selector
        return try await call(.discovery) { options in ModelInspection(try await runtime.inspectModel(request, options: options)) }
    }

    public func updateSettings(selector: String, settings: GenerationSettings) async throws(ConnectionError) {
        var request = Mirmir_V1_UpdateModelGenerationRequest()
        request.selector = selector
        request.settings = settings.wire
        _ = try await call(.management) { options in try await runtime.updateModelGeneration(request, options: options) }
    }

    public func unload(selector: String) async throws(ConnectionError) -> Bool {
        var request = Mirmir_V1_UnloadModelRequest()
        request.selector = selector
        return try await call(.management) { options in try await runtime.unloadModel(request, options: options).unloaded }
    }

    public func search(query: String, limit: Int = 30) async throws(ConnectionError) -> [CatalogModel] {
        var request = Mirmir_V1_SearchModelsRequest()
        request.query = query
        request.limit = UInt32(clamping: limit)
        return try await call(.catalog) { options in
            try await runtime.searchModels(request, options: options).models.map(CatalogModel.init)
        }
    }

    public func remove(repoID: String) async throws(ConnectionError) -> UInt64 {
        var request = Mirmir_V1_RemoveModelRequest()
        request.repoID = repoID
        return try await call(.management) { options in try await runtime.removeModel(request, options: options).freedBytes }
    }

    public func cancel(operationID: String) async throws(ConnectionError) -> Bool {
        var request = Mirmir_V1_CancelOperationRequest()
        request.operationID = operationID
        return try await call(.management) { options in try await runtime.cancelOperation(request, options: options).accepted }
    }
}
