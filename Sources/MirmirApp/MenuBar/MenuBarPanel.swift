import Charts
import MirmirKit
import SwiftUI

struct MenuBarPanel: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if model.connection != nil {
                LiveCard().padding(.horizontal, 10)
                sessions
            } else {
                offline.padding(.horizontal, 10)
            }
            Divider().padding(.horizontal, 10).padding(.top, 8)
            actions.padding(6)
            Divider().padding(.horizontal, 10)
            footer
        }
        .frame(width: 360)
        .background(Palette.panel)
        .tint(Palette.signal)
    }

    private var header: some View {
        HStack(spacing: 10) {
            MarkTile(size: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text("Mirmir").font(.system(size: 13, weight: .semibold))
                InstancePicker()
            }
            Spacer()
            Button { MainWindow.closeMenuBarPanel(); openSettings(); NSApp.activate() } label: {
                Image(systemName: "gearshape").foregroundStyle(Palette.muted)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
        }
        .padding(EdgeInsets(top: 14, leading: 14, bottom: 12, trailing: 14))
    }

    /// Keeps the live card's place and shape while there is nothing live to
    /// show, so the panel does not collapse to a line of text.
    private var offline: some View {
        let (title, detail, busy) = offlineState
        return VStack(alignment: .leading, spacing: 8) {
            Text("SERVER").sectionLabel(busy ? Palette.signal : Palette.muted)
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 13, weight: .semibold))
                    Text(detail).font(.system(size: 11)).foregroundStyle(Palette.muted)
                        .lineLimit(3).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if busy { ProgressView().controlSize(.small) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 12, radius: 9, fill: Palette.panelCard)
    }

    private var offlineState: (title: String, detail: String, busy: Bool) {
        let instance = model.currentInstance
        switch model.phase {
        case .connecting, .connected:
            return ("Connecting to \(instance.name)…", model.address(of: instance), true)
        case .startingServer:
            return ("Starting mirmir…", "The server on this Mac is loading. This takes a few seconds.", true)
        case .offline(let error):
            let detail = error.localizedDescription.replacingOccurrences(of: NSHomeDirectory(), with: "~")
            return (instance.isThisMac ? "mirmir is not running" : "\(instance.name) is offline", detail, false)
        }
    }

    @ViewBuilder private var sessions: some View {
        let active = model.activeOperations.prefix(4)
        if !active.isEmpty {
            Text("Active sessions")
                .font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.muted)
                .padding(EdgeInsets(top: 12, leading: 14, bottom: 4, trailing: 14))
            ForEach(Array(active)) { activity in
                ActivityRow(activity: activity).padding(.horizontal, 14).padding(.vertical, 4)
            }
        }
    }

    private var actions: some View {
        VStack(spacing: 0) {
            PanelAction(title: "New Chat", symbol: "bubble.left", key: "⌘N", prominent: true) {
                model.chat.newConversation(); show(.chat)
            }
            PanelAction(title: "Open Dashboard", symbol: "chart.bar.xaxis", key: "⌘1") { show(.overview) }
            PanelAction(title: "Models…", symbol: "shippingbox", key: "⌘2") { show(.models) }
            PanelAction(title: "Instances…", symbol: "server.rack", key: "⌘3") { show(.instances) }
            PanelAction(title: "Download a Model…", symbol: "arrow.down.to.line") {
                model.presentingDownload = true
                show(.models)
            }
            .disabled(model.connection == nil)
        }
    }

    private var footer: some View {
        HStack {
            ServerToggle()
            Spacer()
            Button("Quit Mirmir  ⌘Q") { NSApp.terminate(nil) }
                .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Palette.muted)
                .keyboardShortcut("q")
        }
        .padding(EdgeInsets(top: 8, leading: 14, bottom: 12, trailing: 14))
    }

    private func show(_ section: SidebarSection) {
        MainWindow.show(section, model: model, openWindow: openWindow)
    }
}

/// Pause or start the server this app owns. Disabled for an attached server,
/// which the protocol cannot stop.
struct ServerToggle: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.supervisor.ownership.isStarting {
            Button { model.pauseServer() } label: { Label("Pause Server", systemImage: "pause.fill") }
                .controlSize(.small)
        } else if model.currentInstance.isThisMac, model.connection == nil {
            Button { model.resumeServer() } label: { Label("Start Server", systemImage: "play.fill") }
                .controlSize(.small)
        } else {
            Button {} label: { Label("Pause Server", systemImage: "pause.fill") }
                .controlSize(.small)
                .disabled(true)
                .help(ServerSupervisor.unverifiedServerAdvice)
        }
    }
}

private struct PanelAction: View {
    let title: String
    let symbol: String
    var key = ""
    var prominent = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: symbol).frame(width: 16)
                Text(title)
                Spacer()
                Text(key).font(.system(size: 12)).opacity(0.7)
            }
            .font(.system(size: 13))
            .padding(.horizontal, 8)
            .frame(height: 28)
            .foregroundStyle(prominent ? Palette.onSignal : Palette.ink)
            .background(prominent ? Palette.signal : .clear, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#if DEBUG
#Preview("Panel — connected") { MenuBarPanel().previewModel() }
#Preview("Panel — dark") { MenuBarPanel().previewModel().preferredColorScheme(.dark) }
#Preview("Panel — generating") { MenuBarPanel().previewModel(.preview(.generating)) }
#Preview("Panel — starting server") { MenuBarPanel().previewModel(.preview(.startingServer)) }
#Preview("Panel — offline") { MenuBarPanel().previewModel(.preview(.offline)) }
#endif
