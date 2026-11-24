import MirmirKit
import SwiftUI

/// The quantization chosen for each GGUF repository, shared by the table's
/// Download menu and the inspector's picker; the repository's default until
/// one is chosen.
@MainActor
@Observable
final class VariantChoices {
    private var names: [String: String] = [:]

    func name(for result: CatalogModel) -> String? {
        names[result.id] ?? result.defaultVariant
    }

    func choose(_ name: String?, for result: CatalogModel) {
        names[result.id] = name
    }

    /// The chosen variant among `variants`, else the repository's default.
    func variant(of result: CatalogModel, among variants: [CatalogVariant]? = nil) -> CatalogVariant? {
        let name = name(for: result)
        return (variants ?? result.variants).first { $0.name == name } ?? result.defaultChoice
    }
}

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

    /// Starts from the search's variants, then lists the files; run from
    /// `.task(id:)` keyed by the repository.
    func load(_ result: CatalogModel, on model: AppModel) async {
        choices = result.variants
        listing = .estimated
        guard !result.variants.isEmpty else { return }
        listing = .listing
        do {
            let listed = try await model.variants(of: result)
            guard !Task.isCancelled else { return }
            choices = listed.variants
            listing = .listed
        } catch {
            guard !Task.isCancelled else { return }
            listing = .failed(error.localizedDescription)
        }
    }
}

/// The quantization to download, with each one's size and memory fit.
struct QuantizationSection: View {
    let variants: HubVariants
    let choices: VariantChoices
    let result: CatalogModel

    var body: some View {
        InspectorSection(title: "Quantization", accessory: { accessory }) {
            Picker("Quantization", selection: Binding(get: { choices.name(for: result) }, set: { choices.choose($0, for: result) })) {
                ForEach(variants.choices) { variant in
                    Text(label(variant)).tag(Optional(variant.name))
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            if let variant = choices.variant(of: result, among: variants.choices) {
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
        variant.label(defaultVariant: result.defaultVariant)
    }

    private func size(_ size: VariantSize) -> String { size.label }

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

extension VariantSize {
    /// `~` marks a size estimated before the files are listed.
    var label: String {
        switch self {
        case .exact(let bytes): Format.bytes(bytes)
        case .estimated(let bytes): "~\(Format.bytes(bytes))"
        case .unknown: "—"
        }
    }
}

extension CatalogVariant {
    /// The variant with its size, the default and a downloaded mark.
    func label(defaultVariant: String?) -> String {
        let marker = name == defaultVariant ? " (default)" : ""
        let downloaded = downloaded ? " ✓" : ""
        return "\(name) · \(size.label)\(marker)\(downloaded)"
    }
}
