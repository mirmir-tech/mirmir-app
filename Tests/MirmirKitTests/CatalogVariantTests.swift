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

/// The server's reason judges the variant its search would download: a
/// listing that names another default keeps the reason with the variant it
/// was computed for, not with the new default.
struct CatalogReasonTests {
    private func variant(_ name: String) -> CatalogVariant {
        CatalogVariant(name: name, size: .exact(9_000), requiredBytes: 9_000, memoryFit: .tight, downloaded: false)
    }

    private func repository(reason: String) -> CatalogModel {
        var result = CatalogModel(
            id: "owner/model-GGUF", downloads: 0, likes: 0, gated: false, modelClass: "",
            compatibility: "supported", memoryFit: .tight, estimatedRequiredBytes: nil, reason: reason,
            downloaded: false, features: [], encoding: nil
        )
        result.variants = [variant("Q4_0"), variant("Q8_0")]
        result.defaultVariant = "Q8_0"
        return result
    }

    @Test func keepsTheReasonWithTheVariantItJudged() {
        let found = repository(reason: "Q8_0 needs 9 GB")
        #expect(found.reason(for: variant("Q8_0")) == "Q8_0 needs 9 GB")
        #expect(found.reason(for: variant("Q4_0")) == nil)
        let listed = found.listing(ModelVariants(variants: [variant("Q4_0"), variant("Q8_0")], defaultVariant: "Q4_0"))
        #expect(listed.defaultVariant == "Q4_0")
        #expect(listed.reasonVariant == "Q8_0")
        #expect(listed.reason(for: listed.defaultChoice) == nil)
        #expect(listed.reason(for: variant("Q8_0")) == "Q8_0 needs 9 GB")
        // Listed again, it still judges what the search judged.
        let relisted = listed.listing(ModelVariants(variants: [variant("Q4_0")], defaultVariant: "Q4_0"))
        #expect(relisted.reasonVariant == "Q8_0")
    }

    /// The search judged `Q8_0` to fit by its estimate; the exact listing
    /// keeps it the default but finds it does not fit. The estimate's
    /// explanation no longer holds for it.
    @Test func exactSizingThatReversesTheFitDropsTheEstimatesReason() {
        let fitting = CatalogVariant(name: "Q8_0", size: .estimated(9_000), requiredBytes: 9_000, memoryFit: .fits, downloaded: false)
        var found = CatalogModel(
            id: "owner/model-GGUF", downloads: 0, likes: 0, gated: false, modelClass: "",
            compatibility: "supported", memoryFit: .fits, estimatedRequiredBytes: 9_000,
            reason: "estimated weights and runtime reserve fit the current budget",
            downloaded: false, features: [], encoding: nil
        )
        found.variants = [fitting]
        found.defaultVariant = "Q8_0"
        #expect(found.reason(for: found.defaultChoice) != nil)
        let exact = CatalogVariant(name: "Q8_0", size: .exact(90_000), requiredBytes: 90_000, memoryFit: .doesNotFit, downloaded: false)
        let listed = found.listing(ModelVariants(variants: [exact], defaultVariant: "Q8_0"))
        #expect(listed.defaultChoice?.memoryFit == .doesNotFit)
        #expect(listed.reason(for: listed.defaultChoice) == nil)
    }

    @Test func aRepositoryWithoutVariantsKeepsItsReason() {
        var plain = repository(reason: "needs 9 GB")
        plain.variants = []
        plain.defaultVariant = nil
        #expect(plain.reason(for: nil) == "needs 9 GB")
        #expect(repository(reason: "").reason(for: variant("Q8_0")) == nil)
    }

    @Test func anUnsupportedGgufRepositoryKeepsItsReasonAcrossVariants() {
        var unsupported = CatalogModel(
            id: "owner/bert-GGUF", downloads: 0, likes: 0, gated: false, modelClass: "bert",
            compatibility: "unsupported", memoryFit: .fits, estimatedRequiredBytes: nil,
            reason: "architecture is not supported", downloaded: false, features: [], encoding: nil
        )
        unsupported.variants = [variant("Q4_0"), variant("Q8_0")]
        unsupported.defaultVariant = "Q8_0"
        #expect(unsupported.reason(for: variant("Q4_0")) == "architecture is not supported")
        #expect(unsupported.reason(for: variant("Q8_0")) == "architecture is not supported")
    }
}
