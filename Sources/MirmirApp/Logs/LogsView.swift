import MirmirKit
import SwiftUI

/// Output of the server this app started. An attached server's logs are not
/// reachable over the protocol yet.
struct LogsView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""

    var body: some View {
        let lines = model.supervisor.logs.lines.filter { query.isEmpty || $0.text.localizedCaseInsensitiveContains(query) }
        Group {
            if model.supervisor.logs.lines.isEmpty {
                EmptyState(title: "No server output", message: emptyMessage, symbol: "doc.text")
            } else {
                ScrollViewReader { proxy in
                    List(lines) { line in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(line.date, format: .dateTime.hour().minute().second())
                                .foregroundStyle(.secondary)
                            Text(line.text)
                                .foregroundStyle(line.stream == .supervisor ? Palette.signal : Palette.ink)
                                .textSelection(.enabled)
                        }
                        .font(.mono(11))
                        .id(line.id)
                    }
                    .listStyle(.plain)
                    .paletteBackground(Palette.canvas)
                    .onChange(of: model.supervisor.logs.lines.last?.id) { _, id in
                        if let id, query.isEmpty { proxy.scrollTo(id, anchor: .bottom) }
                    }
                }
            }
        }
        .navigationTitle("Logs")
        .searchable(text: $query, placement: .toolbar, prompt: "Filter")
        .toolbar {
            ToolbarItem {
                Button { model.supervisor.logs.clear() } label: { Label("Clear", systemImage: "trash") }
            }
        }
    }

    private var emptyMessage: String {
        if model.currentInstance.isThisMac, !model.supervisor.ownership.isRunning, model.connection != nil {
            return "This Mac's server was started outside the app (CLI, TUI or launchd), so its output is not captured here."
        }
        return "Logs appear when the app starts mirmir on this Mac."
    }
}
