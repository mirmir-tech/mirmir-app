import MirmirKit
import SwiftUI

/// A model's saved generation defaults, edited as a draft. The inspector
/// creates one per model (`.id(selector)`), so the draft is never shared
/// between models and is never read after its model's inspection is gone.
struct GenerationDefaultsForm: View {
    @Environment(AppModel.self) private var model
    let selector: String
    let saved: GenerationSettings
    /// The largest Max tokens: the model's context, within its input limit.
    let maxTokensLimit: UInt64
    @State private var draft: GenerationSettings
    @State private var saving = false

    init(selector: String, saved: GenerationSettings, maxTokensLimit: UInt64) {
        self.selector = selector
        self.saved = saved
        self.maxTokensLimit = maxTokensLimit
        _draft = State(initialValue: saved.boundingMaxTokens(by: maxTokensLimit))
    }

    /// The draft as it is saved: Max tokens within the current limit, even
    /// when the limit shrank after the value was chosen.
    private var bounded: GenerationSettings { draft.boundingMaxTokens(by: maxTokensLimit) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Generation defaults").font(.system(size: 12, weight: .semibold))
            // A card like the facts and memory above, not a grouped Form,
            // whose system background does not match the palette.
            VStack(spacing: 0) {
                row("Max tokens") { maxTokensSlider }
                Divider()
                row("Temperature") { slider($draft.temperature, in: 0...2, step: 0.05) }
                Divider()
                row("Top P") { slider($draft.topP, in: 0...1, step: 0.01) }
                Divider()
                row("Top K") {
                    Text("\(draft.topK)").font(.mono(11)).foregroundStyle(.secondary)
                    Stepper("Top K", value: $draft.topK, in: 0...200).labelsHidden()
                }
                Divider()
                row("Repetition penalty") { slider($draft.repetitionPenalty, in: 0.5...2, step: 0.01) }
            }
            .card(padding: 0)
            HStack {
                Spacer()
                Button("Save Defaults") {
                    saving = true
                    let settings = bounded
                    draft = settings
                    Task {
                        await model.updateSettings(selector, settings)
                        saving = false
                    }
                }
                .disabled(saving || bounded == saved)
            }
        }
        // A save that the server applied comes back as the new saved value.
        .onChange(of: saved) { _, newValue in draft = newValue.boundingMaxTokens(by: maxTokensLimit) }
        // A smaller context lowers the limit: the draft follows it at once.
        .onChange(of: maxTokensLimit) { _, limit in draft = draft.boundingMaxTokens(by: limit) }
    }

    private func row<Control: View>(_ title: String, @ViewBuilder control: () -> Control) -> some View {
        HStack(spacing: 10) {
            Text(title).font(.system(size: 12)).lineLimit(1).layoutPriority(1)
            Spacer(minLength: 8)
            control()
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 36)
    }

    /// Logarithmic, so short replies get as much travel as long ones.
    private var maxTokensSlider: some View {
        let scale = LogScale(lower: 1, upper: maxTokensLimit)
        let position = Binding(
            get: { scale.position(of: draft.maxTokens) },
            set: { draft.maxTokens = scale.value(at: $0) }
        )
        return HStack(spacing: 8) {
            Slider(value: position, in: 0...1).labelsHidden().controlSize(.small).frame(maxWidth: 120)
            Text(Format.grouped(draft.maxTokens)).font(.mono(11)).foregroundStyle(.secondary)
                .frame(width: 54, alignment: .trailing)
        }
    }

    /// `Slider(step:)` draws a tick per step, a dotted line at fine steps;
    /// snap the value in the binding instead.
    private func slider(_ value: Binding<Float>, in range: ClosedRange<Float>, step: Float) -> some View {
        let snapped = Binding(get: { value.wrappedValue }, set: { value.wrappedValue = ($0 / step).rounded() * step })
        return HStack(spacing: 8) {
            Slider(value: snapped, in: range).labelsHidden().controlSize(.small).frame(maxWidth: 140)
            Text(String(format: "%.2f", value.wrappedValue)).font(.mono(11)).foregroundStyle(.secondary).frame(width: 34, alignment: .trailing)
        }
    }
}
