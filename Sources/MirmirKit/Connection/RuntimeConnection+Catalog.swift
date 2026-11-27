import MirmirRPC

/// A GGUF repository's quantizations, beyond what a search estimated.
extension RuntimeConnection {
    /// `repoID`'s variants with the sizes of their listed files.
    public func variants(repoID: String) async throws(ConnectionError) -> ModelVariants {
        var request = Mirmir_V1_ListModelVariantsRequest()
        request.repoID = repoID
        return try await call(.catalog) { options in
            ModelVariants(try await runtime.listModelVariants(request, options: options))
        }
    }
}
