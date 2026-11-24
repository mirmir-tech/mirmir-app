import MirmirKit
import SwiftUI

/// A GGUF repository's quantizations for the inspector: the search's
/// estimates until the server lists the files, then their exact sizes.
@MainActor
@Observable
final class HubVariants {
    enum Listing: Equatable {
        case estimated
        case listing
        case listed
        case failed(String)
    }

    private(set) var choices: [CatalogVariant] = []
    private(set) var listing: Listing = .estimated
    var chosen: String?

    /// The chosen variant, else the repository's default.
    func variant(of result: CatalogModel) -> CatalogVariant? {
        choices.first { $0.name == chosen } ?? result.defaultChoice
    }

    /// Starts from the search's variants, then lists the files; run from
    /// `.task(id:)` keyed by the repository.
    func load(_ result: CatalogModel, on model: AppModel) async {
        choices = result.variants
        chosen = result.defaultVariant
        listing = .estimated
        guard !result.variants.isEmpty else { return }
        listing = .listing
        do {
            let listed = try await model.variants(of: result)
            guard !Task.isCancelled else { return }
            choices = listed.variants
            if chosen == nil { chosen = listed.defaultVariant }
            listing = .listed
        } catch {
            guard !Task.isCancelled else { return }
            listing = .failed(error.localizedDescription)
        }
    }
}

/// The quantization to download, with each one's size and memory fit.
struct QuantizationSection: View {
    @Bindable var variants: HubVariants
    let result: CatalogModel

    var body: some View {
        InspectorSection(title: "Quantization", accessory: { accessory }) {
            Picker("Quantization", selection: $variants.chosen) {
                ForEach(variants.choices) { variant in
                    Text(label(variant)).tag(Optional(variant.name))
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            if let variant = variants.variant(of: result) {
                InspectorRow("Size", value: size(variant.size))
                InspectorRow("Memory", value: memory(variant), color: variant.memoryFit == .doesNotFit ? Palette.danger : nil)
            }
            if case .failed(let reason) = variants.listing {
                InspectorNote("Sizes are estimated: \(reason)")
            } else if variants.listing != .listed {
                InspectorNote("Sizes are estimated from the parameter count until the files are listed.")
            }
        }
    }

    @ViewBuilder private var accessory: some View {
        if variants.listing == .listing { ProgressView().controlSize(.mini) }
    }

    private func label(_ variant: CatalogVariant) -> String {
        let marker = variant.name == result.defaultVariant ? " (default)" : ""
        let downloaded = variant.downloaded ? " ✓" : ""
        return "\(variant.name) · \(size(variant.size))\(marker)\(downloaded)"
    }

    private func size(_ size: VariantSize) -> String {
        switch size {
        case .exact(let bytes): Format.bytes(bytes)
        case .estimated(let bytes): "~\(Format.bytes(bytes))"
        case .unknown: "—"
        }
    }

    private func memory(_ variant: CatalogVariant) -> String {
        let needs = variant.requiredBytes.map { "Needs \(Format.bytes($0))" }
        let fit: String? = switch variant.memoryFit {
        case .fits: "fits"
        case .doesNotFit: "does not fit"
        case .unknown: nil
        }
        return [needs, fit].compactMap(\.self).joined(separator: ", ")
    }
}
