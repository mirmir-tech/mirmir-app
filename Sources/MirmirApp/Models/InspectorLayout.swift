import MirmirKit
import SwiftUI

/// The inspector's title block: name, repository and what the model can do.
struct InspectorHeader: View {
    let title: String
    let subtitle: String
    let features: ModelFeatures
    var state: (label: String, color: Color)?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 17, weight: .semibold)).lineLimit(2).textSelection(.enabled)
            if !subtitle.isEmpty {
                Text(subtitle).font(.mono(11)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    .help(subtitle).textSelection(.enabled)
            }
            if state != nil || !features.isEmpty {
                HStack(spacing: 6) {
                    if let state { Pill(text: state.label, color: state.color) }
                    FeatureChips(features: features, long: true)
                }
                .padding(.top, 2)
            }
        }
    }
}

/// A titled card; `accessory` sits at the title's trailing edge.
struct InspectorSection<Accessory: View, Content: View>: View {
    let title: String
    var padding: CGFloat = 12
    @ViewBuilder let accessory: () -> Accessory
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center) {
                Text(title.uppercased()).sectionLabel()
                Spacer(minLength: 8)
                accessory()
            }
            .frame(minHeight: 20)
            VStack(alignment: .leading, spacing: 8) { content() }
                .frame(maxWidth: .infinity, alignment: .leading)
                .card(padding: padding)
        }
    }
}

extension InspectorSection where Accessory == EmptyView {
    init(_ title: String, padding: CGFloat = 12, @ViewBuilder content: @escaping () -> Content) {
        self.init(title: title, padding: padding, accessory: { EmptyView() }, content: content)
    }
}

/// A label and its value on one line; a long value wraps under its label.
struct InspectorRow: View {
    let label: String
    let value: String
    var color: Color?

    init(_ label: String, value: String, color: Color? = nil) {
        self.label = label
        self.value = value
        self.color = color
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label).font(.system(size: 12)).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value.isEmpty ? "—" : value)
                .font(.mono(12, weight: .medium))
                .foregroundStyle(color ?? .primary)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }
}

/// Secondary text inside a section.
struct InspectorNote: View {
    let text: String
    var color: Color = .secondary

    init(_ text: String, color: Color = .secondary) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text).font(.system(size: 11)).foregroundStyle(color).fixedSize(horizontal: false, vertical: true)
    }
}
