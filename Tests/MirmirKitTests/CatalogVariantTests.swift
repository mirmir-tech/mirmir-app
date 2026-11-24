import Testing
@testable import MirmirKit

/// A GGUF repository's variants: decoded sizes, the default choice and
/// what a download pulls.
struct CatalogVariantTests {
    private func variant(_ name: String, _ size: VariantSize, downloaded: Bool = false) -> CatalogVariant {
        CatalogVariant(name: name, size: size, requiredBytes: size.bytes, memoryFit: .fits, downloaded: downloaded)
    }

    private func repository(default chosen: String?) -> CatalogModel {
        var result = CatalogModel(
            id: "ggml-org/gemma-4-E4B-it-GGUF", downloads: 0, likes: 0, gated: false, modelClass: "",
            compatibility: "unknown", memoryFit: .fits, estimatedRequiredBytes: nil, reason: "",
            downloaded: false, features: [], encoding: ""
        )
        result.variants = [variant("Q4_0", .estimated(5_000)), variant("Q8_0", .exact(9_000))]
        result.defaultVariant = chosen
        return result
    }

    @Test func decodesASizeOnlyWithItsKind() {
        #expect(VariantSize(kind: "exact", bytes: 7) == .exact(7))
        #expect(VariantSize(kind: "estimated", bytes: 7) == .estimated(7))
        #expect(VariantSize(kind: "estimated", bytes: nil) == .unknown)
        #expect(VariantSize(kind: "unknown", bytes: 7) == .unknown)
    }

    @Test func pullsTheChosenVariantByRepositoryAndName() {
        let result = repository(default: "Q8_0")
        #expect(result.defaultChoice?.name == "Q8_0")
        #expect(result.pullID(for: result.defaultChoice) == "ggml-org/gemma-4-E4B-it-GGUF:Q8_0")
        #expect(result.pullID(for: nil) == "ggml-org/gemma-4-E4B-it-GGUF")
        // Without a default, the first variant.
        #expect(repository(default: nil).defaultChoice?.name == "Q4_0")
    }

    @Test func namesADownloadedVariantAfterItsRepository() {
        let local = LocalModel(
            selector: "ggml-org--gemma-4-E4B-it-GGUF--Q8_0", repoID: "ggml-org/gemma-4-E4B-it-GGUF:Q8_0",
            commit: "", path: "", state: .available, loadability: .loadable, modelClass: "", encoding: "",
            container: "", sizeBytes: 0, features: [], imageInput: false, managed: true, recentRank: nil
        )
        #expect(local.displayName == "gemma-4-E4B-it-GGUF · Q8_0")
    }
}
