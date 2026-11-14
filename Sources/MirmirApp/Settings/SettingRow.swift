import Foundation
import MirmirKit
import SwiftUI

/// One server setting in a category card: title and help on the left, the
/// control on the right, and underneath the key with where its value comes
/// from. An overridden setting carries the card's accent on its edge.
struct SettingRow: View {
    let entry: ConfigurationEntry
    let accent: Color
    let busy: Bool
    let apply: (String) -> Void

    @State private var draft = ""
    @FocusState private var editing: Bool

    private var description: SettingDescription { SettingCatalog.describe(entry.key) }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(description.title).font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.ink)
                if !description.help.isEmpty {
                    Text(description.help).font(.system(size: 11.5)).foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                footer
            }
            Spacer(minLength: 12)
            control.frame(width: 250, alignment: .trailing)
        }
        .padding(.vertical, 12)
        .padding(.leading, 14)
        .padding(.trailing, 16)
        .overlay(alignment: .leading) {
            if entry.isOverridden { Rectangle().fill(accent).frame(width: 2.5).padding(.vertical, 10) }
        }
        .onAppear { draft = shown(entry.value) }
        .onChange(of: entry.value) { _, value in draft = shown(value) }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text(entry.key).font(.mono(10)).foregroundStyle(Palette.muted.opacity(0.8)).textSelection(.enabled)
            if entry.isOverridden {
                Text("OVERRIDDEN").font(.mono(9, weight: .semibold)).tracking(0.6).foregroundStyle(accent)
            } else if case .environment = entry.source {
                Text("ENVIRONMENT").font(.mono(9, weight: .semibold)).tracking(0.6).foregroundStyle(Palette.brass)
            }
            if !entry.restartRequired, entry.access.isEditable {
                Text("APPLIES AT ONCE").font(.mono(9, weight: .semibold)).tracking(0.6).foregroundStyle(Palette.success)
            }
            if case .managedByApp(let reason) = entry.access {
                Label("Set by Mirmir", systemImage: "lock.fill").labelStyle(.titleAndIcon)
                    .font(.system(size: 10.5)).foregroundStyle(Palette.brass).help(reason)
            } else if entry.access == .serverReadOnly {
                Label("Read only", systemImage: "lock.fill").labelStyle(.titleAndIcon)
                    .font(.system(size: 10.5)).foregroundStyle(Palette.muted)
            }
        }
        .padding(.top, 2)
    }

    @ViewBuilder private var control: some View {
        if !entry.access.isEditable {
            Text(entry.value.isEmpty ? "—" : entry.value)
                .font(.mono(12)).foregroundStyle(Palette.muted)
                .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Palette.raised.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
        } else {
            switch description.control {
            case .toggle:
                Toggle("", isOn: Binding(get: { entry.value == "true" }, set: { apply($0 ? "true" : "false") }))
                    .labelsHidden().toggleStyle(.switch).controlSize(.small).disabled(busy)
            case .choice(let choices):
                Picker("", selection: Binding(get: { entry.value }, set: { apply($0) })) {
                    ForEach(offered(choices), id: \.value) { Text($0.label).tag($0.value) }
                }
                .labelsHidden().pickerStyle(.menu).frame(width: 200).disabled(busy)
            case .number(let unit, let automatic):
                field(unit: unit, automatic: automatic, width: 110)
            case .text(let automatic):
                field(unit: nil, automatic: automatic, width: 220)
            }
        }
    }

    private func field(unit: SettingUnit?, automatic: Bool, width: CGFloat) -> some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: 6) {
                TextField("", text: $draft, prompt: Text(automatic ? "Automatic" : "None"))
                    .font(.mono(12)).monospacedDigit().multilineTextAlignment(.trailing)
                    .textFieldStyle(.roundedBorder).frame(width: width)
                    .focused($editing)
                    .onSubmit { commit(automatic: automatic) }
                if let unit { Text(unit.label).font(.system(size: 11)).foregroundStyle(Palette.muted) }
            }
            HStack(spacing: 10) {
                if let readable = readableSize(unit) {
                    Text(readable).font(.mono(10)).foregroundStyle(Palette.muted)
                }
                if draft != shown(entry.value) {
                    Button("Revert") { draft = shown(entry.value) }.buttonStyle(.link).font(.system(size: 11))
                    Button("Apply") { commit(automatic: automatic) }
                        .buttonStyle(.borderedProminent).controlSize(.mini).disabled(busy)
                } else if automatic, entry.isOverridden {
                    Button("Use default") { apply("auto") }.buttonStyle(.link).font(.system(size: 11)).disabled(busy)
                }
            }
        }
    }

    /// `29360128 bytes` also reads as `28 MiB`.
    private func readableSize(_ unit: SettingUnit?) -> String? {
        guard case .bytes = unit, let bytes = Int64(draft), bytes >= 1024 else { return nil }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .memory)
    }

    /// The documented choices, plus the current value when it was set to
    /// something else, such as an explicit backend default.
    private func offered(_ choices: [SettingChoice]) -> [SettingChoice] {
        choices.contains { $0.value == entry.value } ? choices : choices + [SettingChoice(value: entry.value, label: entry.value)]
    }

    /// `auto` shows as an empty field with the Automatic prompt.
    private func shown(_ value: String) -> String {
        value == "auto" ? "" : value
    }

    /// An emptied field sends `auto` to an optional setting, which removes
    /// the override; any other setting gets the empty value itself.
    private func commit(automatic: Bool) {
        let value = draft.trimmingCharacters(in: .whitespaces)
        guard value != shown(entry.value) else { return }
        editing = false
        apply(value.isEmpty && automatic ? "auto" : value)
    }
}
