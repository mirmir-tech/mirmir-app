import MirmirKit
import SwiftUI

/// Search Hugging Face through the server's catalog and start a pull.
struct DownloadSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [CatalogModel] = []
    @State private var searching = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Download a Model").font(.system(size: 15, weight: .semibold))
            HStack {
                TextField("Search Hugging Face, e.g. mlx-community Qwen3", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(search)
                Button("Search", action: search).disabled(query.isEmpty || searching)
            }
            if let error { Text(error).font(.system(size: 12)).foregroundStyle(Palette.danger) }
            List(results) { result in
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(result.id).fontWeight(.medium).lineLimit(1)
                        HStack(spacing: 6) {
                            FeatureChips(features: result.features)
                            Text(details(result)).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                        }
                        if !result.reason.isEmpty {
                            Text(result.reason).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
                        }
                    }
                    Spacer()
                    action(for: result)
                }
                .padding(.vertical, 3)
            }
            .paletteBackground()
            .overlay {
                if searching { ProgressView() }
                else if results.isEmpty { Text("Search to see compatible checkpoints.").foregroundStyle(.secondary) }
            }
            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 640, height: 520)
        .background(Palette.canvas)
    }

    @ViewBuilder private func action(for result: CatalogModel) -> some View {
        if result.downloaded {
            Pill(text: "Downloaded", color: Palette.success)
        } else if let transfer = model.transfers[result.id] {
            ProgressView(value: transfer.fraction ?? 0).frame(width: 80)
        } else {
            // The Hub marks a repository gated for everyone; whether this
            // server's token was granted access shows only when it downloads.
            Button("Download") { model.pull(result.id) }
                .help(result.gated ? "Gated repository: accept its terms on Hugging Face and add your token in Configuration." : "")
        }
    }

    private func details(_ result: CatalogModel) -> String {
        var parts = [result.encoding, result.compatibility].filter { !$0.isEmpty }
        if let required = result.estimatedRequiredBytes { parts.append("needs \(Format.gigabytes(required)) GB") }
        switch result.memoryFit {
        case .fits: parts.append("fits")
        case .doesNotFit: parts.append("does not fit")
        case .unknown: break
        }
        return parts.joined(separator: " · ")
    }

    private func search() {
        guard !query.isEmpty else { return }
        searching = true
        error = nil
        Task {
            do {
                results = try await model.search(query)
            } catch {
                self.error = error.localizedDescription
            }
            searching = false
        }
    }
}
