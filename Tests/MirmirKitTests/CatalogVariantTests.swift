import Foundation
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

    #if canImport(Darwin)
    @Test @MainActor func matchesInstalledVariantsAndDownloadsInAnyCase() throws {
        let model = AppModel.preview()
        let connection = try #require(model.connection)
        let installed = LocalModel(
            selector: "ggml-org--gemma-4-E4B-it-GGUF@q8_0",
            repoID: "GGML-ORG/gemma-4-e4b-it-gguf:q8_0",
            commit: "abc", path: "/tmp/model", state: .available, loadability: .loadable,
            modelClass: "", encoding: nil, container: "gguf", sizeBytes: 9_000,
            features: [], imageInput: false, managed: true, recentRank: nil
        )
        model.models = [installed]
        model.apply(Activity(
            id: "pull-q4", kind: .pull, target: "GGML-ORG/gemma-4-e4b-it-gguf:q4_0",
            state: .running, stage: "downloading", detail: "",
            startedAt: Date(), updatedAt: Date(), cancellable: true,
            progress: ActivityProgress(current: 1_000, total: 5_000)
        ), from: connection)
        model.apply(Activity(
            id: "pull-q8", kind: .pull, target: "ggml-org/gemma-4-E4B-it-GGUF:Q8_0",
            state: .running, stage: "validating", detail: "",
            startedAt: Date(), updatedAt: Date(), cancellable: false, progress: nil
        ), from: connection)
        let result = repository(default: "Q8_0")
        #expect(model.isDownloaded(result, variant: result.variants[1]))
        #expect(!model.isDownloaded(result, variant: result.variants[0]))
        #expect(model.download(for: result.pullID(for: result.variants[0]))?.cancellableOperation == "pull-q4")
        #expect(model.download(of: installed)?.stage == "Validating")
        #expect(model.unlistedDownloads.contains { $0.repoID == "GGML-ORG/gemma-4-e4b-it-gguf:q4_0" })
        #expect(!model.unlistedDownloads.contains { $0.repoID == "ggml-org/gemma-4-E4B-it-GGUF:Q8_0" })
    }
    #endif
}
