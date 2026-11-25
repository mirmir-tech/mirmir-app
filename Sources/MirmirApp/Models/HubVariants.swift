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

    /// The chosen variant, else the repository's default.
    func variant(of result: CatalogModel) -> CatalogVariant? {
        let name = name(for: result)
        return result.variants.first { $0.name == name } ?? result.defaultChoice
    }
}

/// GGUF repositories' files as the server lists them, shared by the table
/// and the inspector: a search sizes the variants from the parameter count,
/// the listing exactly. Each repository is listed once, when its row or its
/// inspector first shows.
@MainActor
@Observable
final class HubListings {
    enum Listing: Equatable {
        case listing
        case listed(ModelVariants)
        case failed(String)
    }

    private var listings: [String: Listing] = [:]

    func listing(of result: CatalogModel) -> Listing? {
        listings[result.id]
    }

    /// The result with its listed variants, else as the search sized them.
    func resolve(_ result: CatalogModel) -> CatalogModel {
        guard case .listed(let variants) = listings[result.id] else { return result }
        return result.listing(variants)
    }

    /// Lists a GGUF repository's files unless it is listed or being listed.
    /// The request outlives the row that asked for it, so a row scrolled
    /// away does not cancel what the inspector also waits for.
    func load(_ result: CatalogModel, on model: AppModel) {
        guard !result.variants.isEmpty else { return }
        switch listings[result.id] {
        case .listing?, .listed?: return
        case .failed?, nil: break
        }
        listings[result.id] = .listing
        Task {
            do {
                listings[result.id] = .listed(try await model.variants(of: result))
            } catch {
                listings[result.id] = .failed(error.localizedDescription)
            }
        }
    }
}

/// The quantization to download, with each one's size and memory fit.
struct QuantizationSection: View {
    let listing: HubListings.Listing?
    let choices: VariantChoices
    /// Resolved through `HubListings`.
    let result: CatalogModel

    var body: some View {
        InspectorSection(title: "Quantization", accessory: { accessory }) {
            Picker("Quantization", selection: Binding(get: { choices.name(for: result) }, set: { choices.choose($0, for: result) })) {
                ForEach(result.variants) { variant in
                    Text(label(variant)).tag(Optional(variant.name))
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            if let variant = choices.variant(of: result) {
                InspectorRow("Size", value: size(variant.size))
                InspectorRow("Memory", value: memory(variant), color: variant.memoryFit == .doesNotFit ? Palette.danger : nil)
            }
            switch listing {
            case .failed(let reason)?:
                InspectorNote("Sizes are estimated: \(reason)")
            case .listed?:
                EmptyView()
            case .listing?, nil:
                InspectorNote("Sizes are estimated from the parameter count until the files are listed.")
            }
        }
    }

    @ViewBuilder private var accessory: some View {
        if listing == .listing { ProgressView().controlSize(.mini) }
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
