import MirmirKit
import SwiftUI

/// A Hugging Face result: whether it runs on this server, and Download.
struct HubInspector: View {
    @Environment(AppModel.self) private var model
    let result: CatalogModel
    let download: (String) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                InspectorHeader(title: result.name, subtitle: result.id, features: result.features)
                HStack {
                    HubAction(
                        result: result, download: model.downloads[result.id],
                        downloaded: model.isDownloaded(result), start: download
                    )
                        .buttonStyle(.borderedProminent)
                    Spacer()
                    Link(destination: URL(string: "https://huggingface.co/\(result.id)")!) {
                        Label("Hugging Face", systemImage: "arrow.up.right.square")
                    }
                    .font(.system(size: 12))
                }
                InspectorSection("On this server") {
                    InspectorRow("Memory", value: memory, color: result.memoryFit == .doesNotFit ? Palette.danger : nil)
                    InspectorRow("Compatibility", value: result.compatibility)
                    if !result.reason.isEmpty { InspectorNote(result.reason) }
                    if result.gated { InspectorNote("Gated: accept its terms on Hugging Face and add your token in Configuration.") }
                }
                InspectorSection("Model") {
                    InspectorRow("Class", value: result.modelClass)
                    InspectorRow("Encoding", value: result.encoding)
                    InspectorRow("Downloads", value: Format.grouped(result.downloads))
                    InspectorRow("Likes", value: Format.grouped(result.likes))
                }
            }
            .padding(16)
        }
    }

    private var memory: String {
        let needs = result.estimatedRequiredBytes.map { "Needs \(Format.bytes($0))" }
        let fit: String? = switch result.memoryFit {
        case .fits: "fits"
        case .doesNotFit: "does not fit"
        case .unknown: nil
        }
        return [needs, fit].compactMap(\.self).joined(separator: ", ")
    }
}

/// A download whose checkpoint the server does not list yet.
struct DownloadInspector: View {
    let download: ModelDownload

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                InspectorHeader(title: download.displayName, subtitle: download.repoID, features: [])
                DownloadProgressCard(download: download)
            }
            .padding(16)
        }
    }
}

/// Progress of a running download, with Cancel when the server allows it.
struct DownloadProgressCard: View {
    @Environment(AppModel.self) private var model
    let download: ModelDownload

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(download.stage).font(.system(size: 12, weight: .semibold))
                Spacer()
                if download.cancellableOperation != nil {
                    Button("Cancel", role: .destructive) { model.cancel(download) }.controlSize(.small)
                }
            }
            if let fraction = download.fraction {
                ProgressView(value: fraction)
            } else {
                ProgressView().progressViewStyle(.linear)
            }
            Text(bytes).font(.mono(11)).foregroundStyle(.secondary)
            Text("The model can be loaded once its download finishes.").font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .card(padding: 12)
    }

    private var bytes: String {
        let done = download.downloadedBytes.map(Format.bytes) ?? "—"
        guard let total = download.totalBytes else { return done }
        let percent = download.fraction.map { " · \(Int($0 * 100))%" } ?? ""
        return "\(done) of \(Format.bytes(total))\(percent)"
    }
}
