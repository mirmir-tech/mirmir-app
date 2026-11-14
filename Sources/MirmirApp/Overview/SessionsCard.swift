import MirmirKit
import SwiftUI

/// Recent server operations, newest first, with their state.
struct SessionsCard: View {
    @Environment(AppModel.self) private var model
    let activities: [Activity]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Sessions").font(.system(size: 13, weight: .semibold))
                Spacer()
                Button("Show all") { model.section = .sessions }.buttonStyle(.link)
            }
            if activities.isEmpty {
                Text("No activity in the last hour.").font(.system(size: 12)).foregroundStyle(Palette.muted)
                    .padding(.vertical, 12)
            } else {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                    GridRow {
                        header("Operation"); header("Target"); header("Stage"); header("Started"); header("State")
                    }
                    Divider().gridCellUnsizedAxes(.horizontal)
                    ForEach(activities) { activity in
                        GridRow {
                            Text(activity.kind.label)
                            Text(model.displayTarget(of: activity)).lineLimit(1).truncationMode(.middle)
                            Text(activity.stage).font(.mono(12))
                            Text(Format.relative(activity.startedAt)).foregroundStyle(Palette.muted)
                            ActivityStatePill(state: activity.state, prefill: activity.isPrefill)
                        }
                        .font(.system(size: 12))
                    }
                }
            }
        }
        .card()
    }

    private func header(_ text: String) -> some View {
        Text(text).font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.muted)
    }
}

struct ActivityStatePill: View {
    let state: ActivityState
    var prefill = false

    var body: some View {
        switch state {
        case .queued: Pill(text: "queued", color: Palette.muted)
        case .running: Pill(text: prefill ? "prefill" : "running", color: prefill ? Palette.warning : Palette.signal)
        case .cancelling: Pill(text: "cancelling", color: Palette.warning)
        case .completed: Pill(text: "completed", color: Palette.success)
        case .failed: Pill(text: "failed", color: Palette.danger)
        case .cancelled: Pill(text: "cancelled", color: Palette.muted)
        case .unrecognized(let value): Pill(text: value, color: Palette.muted)
        }
    }
}
