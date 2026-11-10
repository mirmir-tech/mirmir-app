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
            Button { openSettings(); NSApp.activate() } label: {
                Image(systemName: "gearshape").foregroundStyle(Palette.muted)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
        }
        .padding(EdgeInsets(top: 14, leading: 14, bottom: 12, trailing: 14))
    }

    private var offline: some View {
        VStack(alignment: .leading, spacing: 6) {
            switch model.phase {
            case .offline(let error): Text(error.localizedDescription)
            case .startingServer: Text("Starting mirmir on this Mac…")
            default: Text("Connecting…")
            }
        }
        .font(.system(size: 12))
        .foregroundStyle(Palette.muted)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 12, radius: 9, fill: Palette.panelCard)
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
        model.section = section
        openWindow(id: WindowID.main)
        NSApp.activate()
    }
}

/// Pause or start the server this app owns. Disabled for an attached server,
/// which the protocol cannot stop.
struct ServerToggle: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.supervisor.ownership.isRunning {
            Button { model.pauseServer() } label: { Label("Pause Server", systemImage: "pause.fill") }
                .controlSize(.small)
        } else if model.currentInstance.isThisMac, model.connection == nil {
            Button { model.resumeServer() } label: { Label("Start Server", systemImage: "play.fill") }
                .controlSize(.small)
        } else {
            Button {} label: { Label("Pause Server", systemImage: "pause.fill") }
                .controlSize(.small)
                .disabled(true)
                .help("This server was started outside the app. Stop it where it was started.")
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
