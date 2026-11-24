import MirmirKit
import Observation
import SwiftUI

/// Hugging Face results for the Models screen's search text, through the
/// server's catalog. A search starts once the text has rested for
/// `pause`; newer text cancels the older search, and its results stay shown
/// until the newer ones arrive, as in Finder.
@MainActor
@Observable
final class HubSearch {
    enum Phase: Equatable {
        case idle
        case waiting
        case searching
        case done
        case failed(String)
    }

    static let pause: Duration = .milliseconds(1_500)

    private(set) var results: [CatalogModel] = []
    private(set) var phase: Phase = .idle
    /// The query `results` answer.
    private(set) var answered = ""

    /// Run from `.task(id:)` keyed by the text, which cancels it when the
    /// text changes again.
    func search(_ text: String, on model: AppModel) async {
        let query = text.trimmingCharacters(in: .whitespaces)
        guard query.count >= 2 else {
            clear()
            return
        }
        if query == answered, phase == .done { return }
        phase = .waiting
        do { try await Task.sleep(for: Self.pause) } catch { return }
        phase = .searching
        do {
            let found = try await model.search(query)
            guard !Task.isCancelled else { return }
            results = found
            answered = query
            phase = .done
        } catch {
            guard !Task.isCancelled else { return }
            phase = .failed(error.localizedDescription)
        }
    }

    func clear() {
        results = []
        answered = ""
        phase = .idle
    }
}

/// Download, or where the result's download stands. Whether it is on the
/// server comes from the server's current list, not from the search: results
/// are kept, and a checkpoint removed since must offer Download again.
struct HubAction: View {
    let result: CatalogModel
    /// What the button downloads: the repository, or one GGUF variant.
    let pullID: String
    let download: ModelDownload?
    let downloaded: Bool
    let start: (String) -> Void
    var label = "Download"

    var body: some View {
        if let download {
            ModelStatus(load: nil, download: download, loadability: .loadable, state: .available)
        } else if downloaded {
            Pill(text: "Downloaded", color: Palette.success)
        } else {
            // The Hub marks a repository gated for everyone; whether this
            // server's token was granted access shows only when it downloads.
            Button(label) { start(pullID) }
                .controlSize(.small)
                .help(result.gated ? "Gated repository: accept its terms on Hugging Face and add your token in Configuration." : "Download \(pullID)")
        }
    }
}

extension CatalogModel {
    /// How many quantizations a GGUF row offers.
    var quantizations: String {
        variants.count > 1 ? "\(variants.count) quantizations" : (defaultChoice?.name ?? "")
    }

    var name: String { id.split(separator: "/").last.map(String.init) ?? id }
    var owner: String { id.contains("/") ? String(id.split(separator: "/")[0]) : "" }
}

/// A GGUF repository's Download in the table: the button downloads the
/// chosen quantization, its menu lists every one with its size and fit,
/// and picking one chooses it for the inspector too.
struct HubVariantMenu: View {
    let result: CatalogModel
    let choices: VariantChoices
    let model: AppModel
    let start: (String) -> Void

    var body: some View {
        let variant = choices.variant(of: result)
        let pullID = result.pullID(for: variant)
        if let download = model.downloads[pullID] {
            ModelStatus(load: nil, download: download, loadability: .loadable, state: .available)
        } else {
            Menu {
                ForEach(result.variants) { option in
                    Button {
                        choices.choose(option.name, for: result)
                    } label: {
                        if option.name == variant?.name {
                            Label(menuLabel(option), systemImage: "checkmark")
                        } else {
                            Text(menuLabel(option))
                        }
                    }
                }
            } label: {
                Text(model.isDownloaded(result, variant: variant) ? "\(variant?.name ?? "") ✓" : "Download \(variant?.name ?? "")")
            } primaryAction: {
                if !model.isDownloaded(result, variant: variant) { start(pullID) }
            }
            .menuStyle(.button)
            .controlSize(.small)
            .fixedSize()
            .help("Download \(pullID); the arrow chooses another quantization")
        }
    }

    private func menuLabel(_ variant: CatalogVariant) -> String {
        let fit = variant.memoryFit == .doesNotFit ? " · does not fit" : ""
        return variant.label(defaultVariant: result.defaultVariant) + fit
    }
}
