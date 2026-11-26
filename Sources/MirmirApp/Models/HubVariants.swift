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

    private var server: InstanceRecord.ID?
    private var listings: [String: Listing] = [:]

    /// Discards cached listings when the active server changes, so another
    /// server's memory fits and defaults never stay shown.
    func reset(for server: InstanceRecord.ID) {
        guard self.server != server else { return }
        self.server = server
        listings = [:]
    }

    func listing(of result: CatalogModel) -> Listing? {
        listings[result.id]
    }

    /// The result with its listed variants, else as the search sized them.
    func resolve(_ result: CatalogModel) -> CatalogModel {
        guard case .listed(let variants) = listings[result.id] else { return result }
        return result.listing(variants)
    }

    /// Lists a GGUF repository's files unless it is listed or being listed
    /// for the current server. The request outlives the row that asked for
    /// it, so a row scrolled away does not cancel what the inspector also
    /// waits for, but a late reply after a server switch is dropped.
    func load(_ result: CatalogModel, on model: AppModel) {
        guard !result.variants.isEmpty else { return }
        let instance = model.currentInstanceID
        reset(for: instance)
        switch listings[result.id] {
        case .listing?, .listed?: return
        case .failed?, nil: break
        }
        listings[result.id] = .listing
        Task {
            do {
                let listed = try await model.variants(of: result)
                guard self.server == instance else { return }
                listings[result.id] = .listed(listed)
            } catch {
                guard self.server == instance else { return }
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
    let isDownloaded: (CatalogVariant) -> Bool

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
                InspectorRow("Memory", value: variant.memoryFit.summary(needs: variant.requiredBytes), color: variant.memoryFit.color)
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

    /// The choice with its size, and a tight or failed fit marked.
    private func label(_ variant: CatalogVariant) -> String {
        variant.label(defaultVariant: result.defaultVariant, downloaded: isDownloaded(variant)) + variant.memoryFit.marker
    }

    private func size(_ size: VariantSize) -> String { size.label }
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
    func label(defaultVariant: String?, downloaded: Bool? = nil) -> String {
        let marker = name == defaultVariant ? " (default)" : ""
        let downloaded = (downloaded ?? self.downloaded) ? " ✓" : ""
        return "\(name) · \(size.label)\(marker)\(downloaded)"
    }
}
