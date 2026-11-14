import GRPCCore

/// Adds a remote server's API key to every call as
/// `authorization: Bearer mmk_…`.
struct BearerKey: ClientInterceptor {
    private let value: String

    init(_ key: String) {
        value = "Bearer \(key)"
    }

    func intercept<Input: Sendable, Output: Sendable>(
        request: StreamingClientRequest<Input>,
        context: ClientContext,
        next: (StreamingClientRequest<Input>, ClientContext) async throws -> StreamingClientResponse<Output>
    ) async throws -> StreamingClientResponse<Output> {
        var request = request
        request.metadata.replaceOrAddString(value, forKey: "authorization")
        return try await next(request, context)
    }
}
