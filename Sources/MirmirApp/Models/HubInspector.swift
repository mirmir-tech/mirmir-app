import MirmirKit
import SwiftUI

/// A Hugging Face result: whether it runs on this server, and Download.
struct HubInspector: View {
    @Environment(AppModel.self) private var model
    /// As the search found it; its listing sizes the variants exactly.
    let found: CatalogModel
    let choices: VariantChoices
    let listings: VariantListings
    let download: (String) -> Void

    private var result: CatalogModel { listings.resolve(found) }

    var body: some View {
        let result = result
        let variant = choices.variant(of: result)
        let pullID = result.pullID(for: variant)
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                InspectorHeader(title: result.name, subtitle: result.id, features: result.features)
                HStack {
                    HubAction(
                        result: result, pullID: pullID, download: model.download(for: pullID),
                        downloaded: model.isDownloaded(result, variant: variant), start: download,
                        label: variant.map { "Download \($0.name)" } ?? "Download"
                    )
                        .buttonStyle(.borderedProminent)
                    Spacer()
                    if let page = result.hubPage {
                        Link(destination: page) {
                            Label("Hugging Face", systemImage: "arrow.up.right.square")
                        }
                        .font(.system(size: 12))
                    }
                }
                if !result.variants.isEmpty {
                    QuantizationSection(
                        listing: listings.listing(of: found), choices: choices, result: result,
                        isDownloaded: { model.isDownloaded(result, variant: $0) }
                    )
                }
                InspectorSection("On this server") {
                    if result.variants.isEmpty {
                        InspectorRow("Memory", value: result.memoryFit.summary(needs: result.estimatedRequiredBytes), color: result.memoryFit.color)
                    }
                    InspectorRow("Compatibility", value: result.compatibility)
                    // The server judges a GGUF repository by its default
                    // quantization; another chosen one has its own fit above.
                    if let reason = result.reason(for: variant) {
                        InspectorNote(reason)
                    }
                    if result.gated { InspectorNote("Gated: accept its terms on Hugging Face and add your token in Configuration.") }
                }
                InspectorSection("Model") {
                    InspectorRow("Class", value: result.modelClass)
                    InspectorRow("Encoding", value: result.encoding ?? "—")
                    InspectorRow("Downloads", value: Format.grouped(result.downloads))
                    InspectorRow("Likes", value: Format.grouped(result.likes))
                }
            }
            .padding(16)
        }
        .task(id: "\(model.connectionGeneration):\(found.id)") { listings.load(found, on: model) }
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

/// An incomplete download nobody is running: resume it, or remove its files.
struct PausedDownloadCard: View {
    @Environment(AppModel.self) private var model
    let local: LocalModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Download incomplete").font(.system(size: 12, weight: .semibold))
            InspectorNote("The download stopped before it finished. Resume it to load the model.")
            HStack {
                Button("Resume Download") { model.pull(local.repoID) }
                    .buttonStyle(.borderedProminent)
                    .disabled(local.repoID.isEmpty || model.connection == nil)
                Spacer()
                if local.managed, !local.repoID.isEmpty {
                    Button("Remove", role: .destructive) { model.removeCheckpoint(local.repoID) }
                }
            }
        }
        .card(padding: 12)
    }
}
