import MirmirKit
import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            Sidebar()
                .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 260)
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Palette.canvas)
        }
        .overlay(alignment: .bottom) { NoticeBanner() }
        .toolbarBackground(Palette.toolbar, for: .windowToolbar)
        .toolbarBackgroundVisibility(.visible, for: .windowToolbar)
        .tint(Palette.signal)
    }

    @ViewBuilder private var detail: some View {
        switch model.section {
        case .overview: ConnectedOr { OverviewView() }
        case .chat: ConnectedOr { ChatView() }
        case .models: ConnectedOr { ModelsView() }
        case .instances: InstancesView()
        case .sessions: ConnectedOr { SessionsView() }
        case .logs: LogsView()
        }
    }
}

/// Shows the screen when connected, else what the connection is doing.
struct ConnectedOr<Content: View>: View {
    @Environment(AppModel.self) private var model
    @ViewBuilder let content: () -> Content

    var body: some View {
        switch model.phase {
        case .connected:
            content()
        case .connecting:
            ProgressView("Connecting to \(model.currentInstance.name)…")
        case .startingServer:
            ProgressView("Starting mirmir on this Mac…")
        case .offline(let error):
            OfflineView(error: error)
        }
    }
}

struct OfflineView: View {
    @Environment(AppModel.self) private var model
    let error: ConnectionError

    var body: some View {
        ContentUnavailableView {
            Label("\(model.currentInstance.name) is offline", systemImage: "bolt.horizontal.circle")
        } description: {
            Text(error.localizedDescription)
            if case .unavailable(let reason) = model.supervisor.ownership, model.currentInstance.isThisMac {
                Text(reason)
            }
        } actions: {
            if model.currentInstance.isThisMac {
                Button("Start Server") { model.resumeServer() }
                    .buttonStyle(.borderedProminent)
            }
            Button("Choose Another Instance") { model.section = .instances }
        }
    }
}

struct NoticeBanner: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let notice = model.notice {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Palette.warning)
                Text(notice).font(.system(size: 12)).lineLimit(3)
                Spacer()
                Button("Dismiss") { model.notice = nil }.controlSize(.small)
            }
            .padding(12)
            .frame(maxWidth: 640)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Palette.border, lineWidth: 0.5))
            .padding(16)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

#if DEBUG
#Preview("Window — Overview", traits: .fixedLayout(width: 1280, height: 800)) {
    RootView().previewModel(AppModel.preview().showing(.overview))
}
#Preview("Window — Overview, dark", traits: .fixedLayout(width: 1280, height: 800)) {
    RootView().previewModel(AppModel.preview().showing(.overview)).preferredColorScheme(.dark)
}
#Preview("Window — Models", traits: .fixedLayout(width: 1280, height: 800)) {
    RootView().previewModel(AppModel.preview().showing(.models))
}
#Preview("Window — Chat", traits: .fixedLayout(width: 1280, height: 800)) {
    RootView().previewModel(AppModel.preview(.generating).showing(.chat))
}
#Preview("Window — Instances", traits: .fixedLayout(width: 1280, height: 800)) {
    RootView().previewModel(AppModel.preview().showing(.instances))
}
#Preview("Window — Sessions", traits: .fixedLayout(width: 1280, height: 800)) {
    RootView().previewModel(AppModel.preview().showing(.sessions))
}
#Preview("Window — Logs", traits: .fixedLayout(width: 1280, height: 800)) {
    RootView().previewModel(AppModel.preview().showing(.logs))
}
#Preview("Window — offline", traits: .fixedLayout(width: 1280, height: 800)) {
    RootView().previewModel(AppModel.preview(.offline).showing(.overview))
}
#endif
