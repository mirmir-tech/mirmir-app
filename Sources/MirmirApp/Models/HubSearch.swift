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
    /// The query `results` answer, and the connection that answered it.
    private(set) var answered = ""
    private var answeredGeneration: UInt64?

    /// Run from `.task(id:)` keyed by the connection and the text, which
    /// cancels it when either changes again.
    func search(_ text: String, on model: AppModel) async {
        let query = text.trimmingCharacters(in: .whitespaces)
        guard query.count >= 2 else {
            clear()
            return
        }
        let generation = model.connectionGeneration
        if query == answered, answeredGeneration == generation, phase == .done { return }
        phase = .waiting
        do { try await Task.sleep(for: Self.pause) } catch { return }
        phase = .searching
        do {
            let found = try await model.search(query)
            guard !Task.isCancelled else { return }
            results = found
            answered = query
            answeredGeneration = generation
            phase = .done
        } catch {
            guard !Task.isCancelled else { return }
            phase = .failed(error.localizedDescription)
        }
    }

    func clear() {
        results = []
        answered = ""
        answeredGeneration = nil
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
    /// The part before the slash; empty without one, as for an id of "/"
    /// alone (as `LocalModel.owner`).
    var owner: String {
        let parts = id.split(separator: "/")
        return parts.count > 1 ? String(parts[0]) : ""
    }

    /// The repository's Hugging Face page; the id is the path, encoded as
    /// a path, so a server's odd id makes no invalid link.
    var hubPage: URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "huggingface.co"
        components.path = "/" + id
        return components.url
    }
}
