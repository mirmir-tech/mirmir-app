import AppKit
import MirmirKit
import SwiftUI

/// The Settings window: what this app itself keeps. A server's own
/// configuration is a screen of the main window, next to its models.
struct SettingsView: View {
    var body: some View {
        GeneralSettingsView()
    }
}

/// Model folders the bundled server may read, and where it runs.
struct GeneralSettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Form {
            Section {
                if model.modelFolders.folders.isEmpty {
                    Text("None. The server keeps the models it downloads in the app's container.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                ForEach(model.modelFolders.folders) { folder in
                    HStack(spacing: 10) {
                        Image(systemName: icon(folder.kind)).foregroundStyle(Palette.muted).frame(width: 18)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(display(folder.path)).font(.mono(12)).lineLimit(1).truncationMode(.middle)
                            if let failure = model.modelFolders.failures[folder.id] {
                                Text(describe(failure)).font(.system(size: 11)).foregroundStyle(Palette.danger)
                            } else {
                                Text(summary(folder.kind)).font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button("Remove", role: .destructive) { model.removeModelFolder(folder.id) }
                            .controlSize(.small)
                    }
                }
                Button("Add Folder…", action: addFolder)
            } header: {
                Text("Model folders")
            } footer: {
                Text("Mirmir runs its own server in its sandbox, separate from the mirmir CLI. Grant a Hugging Face cache, such as ~/.cache/huggingface, to use the models in it without downloading them again.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Section("Server") {
                LabeledContent("Configuration") {
                    Button("Open Configuration…") {
                        MainWindow.show(.configuration, model: model, openWindow: openWindow)
                    }
                }
                LabeledContent("Runtime", value: "Bundled mirmir")
                LabeledContent("OpenAI-compatible API", value: "http://\(ServerSupervisor.httpBind)/v1").font(.mono(11))
                    .textSelection(.enabled)
                LabeledContent("Socket", value: display(SocketPaths().personalSocket)).font(.mono(11))
                LabeledContent("Status", value: ownership)
            }
            Section("About") {
                LabeledContent("Client protocol", value: clientProtocolVersion)
                if let health = model.connection?.health {
                    LabeledContent("Server", value: "mirmir \(health.serverVersion) · protocol \(health.protocolVersion)")
                }
            }
        }
        .formStyle(.grouped)
        .paletteBackground(Palette.canvas)
        .frame(width: 560)
        .padding(.vertical, 8)
        // A grant that could not be saved is reported here, where it was made.
        .overlay(alignment: .bottom) { NoticeBanner() }
    }

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Grant Access"
        panel.message = "Choose a folder with models, such as ~/.cache/huggingface"
        if panel.runModal() == .OK, let url = panel.url { model.addModelFolder(url) }
    }

    private func icon(_ kind: ModelFolder.Kind) -> String {
        if case .huggingFaceCache = kind { "shippingbox" } else { "folder" }
    }

    private func describe(_ failure: FolderAccessFailure) -> String {
        switch failure {
        case .unresolvable: "Not found. Remove it, or add the folder again where it is now."
        case .refused: "macOS refused access. Add the folder again to renew the grant."
        }
    }

    private func summary(_ kind: ModelFolder.Kind) -> String {
        switch kind {
        case .huggingFaceCache: "Hugging Face cache: its models are listed in Models"
        case .folder: "Folder: load its models with Models → Load from Folder"
        }
    }

    /// Paths in the real home, shortened to `~`; the sandbox's own home is
    /// the container, so NSHomeDirectory would not match them.
    private func display(_ path: String) -> String {
        let home = String(cString: getpwuid(getuid()).pointee.pw_dir)
        return path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }

    private var ownership: String {
        switch model.supervisor.ownership {
        case .none: model.connection == nil ? "Not running" : "Running, not started by this run of Mirmir"
        case .configuring: "Configuring the first launch"
        case .running(let pid, _): "Running (pid \(pid))"
        case .exited(let status): "Exited with status \(status)"
        case .unavailable(let reason): reason
        }
    }
}

#if DEBUG
#Preview("Settings") { GeneralSettingsView().previewModel() }
#endif
