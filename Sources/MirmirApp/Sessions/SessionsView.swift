import MirmirKit
import SwiftUI

/// Every operation the server reported in the last hour, cancellable ones
/// with a Cancel action.
struct SessionsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let activities = model.recentOperations
        Table(activities) {
            TableColumn("Operation") { activity in Text(activity.kind.label) }
                .width(90)
            TableColumn("Target") { activity in
                Text(model.displayTarget(of: activity)).lineLimit(1).truncationMode(.middle)
            }
            TableColumn("Stage") { activity in Text(activity.stage).font(.mono(12)) }
                .width(110)
            TableColumn("Progress") { activity in
                if let fraction = activity.progress?.fraction, activity.state.isActive {
                    ProgressView(value: fraction)
                } else if let current = activity.progress?.current {
                    Text(Format.grouped(current)).font(.mono(12))
                }
            }
            .width(110)
            TableColumn("Started") { activity in
                Text(activity.startedAt, style: .time).foregroundStyle(.secondary)
            }
            .width(80)
            TableColumn("State") { activity in ActivityStatePill(state: activity.state, prefill: activity.isPrefill) }
                .width(100)
            TableColumn("") { activity in
                if activity.cancellable, activity.state.isActive {
                    Button("Cancel") { model.cancel(activity) }.controlSize(.small)
                }
            }
            .width(70)
        }
        .alternatingRowBackgrounds(.disabled)
        .paletteBackground()
        .overlay {
            if activities.isEmpty {
                EmptyState(title: "No sessions", message: "Generations, loads and downloads appear here as they run.", symbol: "list.bullet")
            }
        }
        .navigationTitle("Sessions")
        .navigationSubtitle("\(model.currentInstance.name) · \(model.activeOperations.count) active")
    }
}

#if DEBUG
#Preview("Sessions", traits: .fixedLayout(width: 1070, height: 800)) {
    NavigationStack { SessionsView() }.previewModel()
}
#endif
