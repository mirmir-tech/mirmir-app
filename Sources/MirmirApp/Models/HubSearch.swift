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
    let download: ModelDownload?
    let downloaded: Bool
    let start: (String) -> Void

    var body: some View {
        if let download {
            ModelStatus(load: nil, download: download, loadability: .loadable, state: .available)
        } else if downloaded {
            Pill(text: "Downloaded", color: Palette.success)
        } else {
            // The Hub marks a repository gated for everyone; whether this
            // server's token was granted access shows only when it downloads.
            Button("Download") { start(result.id) }
                .controlSize(.small)
                .help(result.gated ? "Gated repository: accept its terms on Hugging Face and add your token in Configuration." : "Download \(result.id)")
        }
    }
}

extension CatalogModel {
    var name: String { id.split(separator: "/").last.map(String.init) ?? id }
    var owner: String { id.contains("/") ? String(id.split(separator: "/")[0]) : "" }
}
