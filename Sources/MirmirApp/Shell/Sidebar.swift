import MirmirKit
import SwiftUI

struct Sidebar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        List(selection: $model.section) {
            Section("Mirmir") {
                ForEach(SidebarSection.allCases) { section in
                    // Icons follow the design, not the system accent: the text
                    // colour, the accent for the current section. The system
                    // tint depends on window activation and differs between
                    // a key window, an inactive one and a rendered one.
                    Label {
                        Text(section.title)
                    } icon: {
                        Image(systemName: section.symbol)
                            .foregroundStyle(section == model.section ? Palette.signal : Palette.ink)
                    }
                    .badge(badge(for: section))
                    .tag(section)
                }
            }
        }
        .listStyle(.sidebar)
        .paletteBackground(Palette.sidebar)
        .safeAreaInset(edge: .bottom) {
            ServerSwitcher().padding(10).background(Palette.sidebar)
        }
    }

    private func badge(for section: SidebarSection) -> Int {
        switch section {
        case .chat: model.chat.visibleConversations.count
        case .models: model.models.count
        case .instances: model.instances.count
        case .sessions: model.activeOperations.count
        case .overview, .logs: 0
        }
    }
}

extension SidebarSection {
    var symbol: String {
        switch self {
        case .overview: "chart.bar.xaxis"
        case .chat: "bubble.left"
        case .models: "shippingbox"
        case .instances: "server.rack"
        case .sessions: "list.bullet"
        case .logs: "doc.text"
        }
    }
}
