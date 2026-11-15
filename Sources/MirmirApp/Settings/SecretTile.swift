import MirmirKit
import SwiftUI

/// A secret the server stores, as a card: whether it is set and where from,
/// a field to replace it, and its actions. The value never comes back.
struct SecretTile: View {
    let label: String
    let symbol: String
    let help: String
    let state: SecretState
    let busy: Bool
    let save: (String) -> Void
    let remove: () -> Void
    /// Only the Hugging Face token can be tested, against the Hub.
    var test: (() -> Void)?

    @State private var value = ""
    @State private var replacing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.signal)
                Text(label).sectionLabel(Palette.signal)
                Spacer()
                status
            }
            Text(help).font(.system(size: 11.5)).foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            if replacing || !state.isConfigured {
                HStack(spacing: 6) {
                    SecureField("", text: $value, prompt: Text(state.isConfigured ? "New value" : "Paste the value"))
                        .textFieldStyle(.roundedBorder).font(.mono(12))
                        .onSubmit(commit)
                    Button("Save", action: commit)
                        .buttonStyle(.borderedProminent)
                        .disabled(busy || value.trimmingCharacters(in: .whitespaces).isEmpty)
                    if state.isConfigured {
                        Button("Cancel") { replacing = false; value = "" }
                    }
                }
                .controlSize(.small)
            } else {
                HStack(spacing: 8) {
                    Text("••••••••••••").font(.mono(13)).foregroundStyle(Palette.muted)
                    Spacer()
                    if let test { Button("Test", action: test).disabled(busy) }
                    Button("Replace…") { replacing = true }.disabled(busy)
                    if state == .configured(.secretsFile) {
                        Button(role: .destructive, action: remove) { Image(systemName: "trash") }
                            .disabled(busy).help("Remove the saved value")
                    }
                }
                .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .card()
    }

    private var status: some View {
        HStack(spacing: 5) {
            StatusDot(color: state.isConfigured ? Palette.success : Palette.muted, size: 6)
            Text(statusText).font(.system(size: 11, weight: .medium))
                .foregroundStyle(state.isConfigured ? Palette.success : Palette.muted)
        }
    }

    private var statusText: String {
        switch state {
        case .missing: "Not set"
        case .configured(.environment): "Set by the environment"
        case .configured: "Set"
        }
    }

    private func commit() {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        save(trimmed)
        value = ""
        replacing = false
    }
}
