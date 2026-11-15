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
        InspectorSection(title: "Generation defaults") {
            if bounded != saved {
                HStack(spacing: 6) {
                    Button("Revert") { draft = saved.boundingMaxTokens(by: maxTokensLimit) }
                    Button("Save", action: save).buttonStyle(.borderedProminent)
                }
                .controlSize(.small)
                .disabled(saving)
            }
        } content: {
            setting("Max tokens", value: Format.grouped(draft.maxTokens)) { maxTokensSlider }
            setting("Temperature", value: decimal(draft.temperature)) { slider($draft.temperature, in: 0...2, step: 0.05) }
            setting("Top P", value: decimal(draft.topP)) { slider($draft.topP, in: 0...1, step: 0.01) }
            setting("Top K", value: draft.topK == 0 ? "off" : "\(draft.topK)") { topKSlider }
            setting("Repetition penalty", value: decimal(draft.repetitionPenalty)) { slider($draft.repetitionPenalty, in: 0.5...2, step: 0.01) }
        }
        // A save that the server applied comes back as the new saved value.
        .onChange(of: saved) { _, newValue in draft = newValue.boundingMaxTokens(by: maxTokensLimit) }
        // A smaller context lowers the limit: the draft follows it at once.
        .onChange(of: maxTokensLimit) { _, limit in draft = draft.boundingMaxTokens(by: limit) }
    }

    private func save() {
        saving = true
        let settings = bounded
        draft = settings
        Task {
            await model.updateSettings(selector, settings)
            saving = false
        }
    }

    /// The setting's name and value above a full-width slider.
    private func setting<Control: View>(_ title: String, value: String, @ViewBuilder control: () -> Control) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.system(size: 12))
                Spacer(minLength: 8)
                Text(value).font(.mono(12, weight: .medium)).foregroundStyle(.secondary)
            }
            control()
        }
    }

    private func decimal(_ value: Float) -> String { String(format: "%.2f", value) }

    /// Logarithmic, so short replies get as much travel as long ones.
    private var maxTokensSlider: some View {
        let scale = LogScale(lower: 1, upper: maxTokensLimit)
        let position = Binding(
            get: { scale.position(of: draft.maxTokens) },
            set: { draft.maxTokens = scale.value(at: $0) }
        )
        return Slider(value: position, in: 0...1).labelsHidden().controlSize(.small)
    }

    private var topKSlider: some View {
        let value = Binding(get: { Double(draft.topK) }, set: { draft.topK = UInt64($0.rounded()) })
        return Slider(value: value, in: 0...200).labelsHidden().controlSize(.small)
    }

    /// `Slider(step:)` draws a tick per step, a dotted line at fine steps;
    /// snap the value in the binding instead.
    private func slider(_ value: Binding<Float>, in range: ClosedRange<Float>, step: Float) -> some View {
        let snapped = Binding(get: { value.wrappedValue }, set: { value.wrappedValue = ($0 / step).rounded() * step })
        return Slider(value: snapped, in: range).labelsHidden().controlSize(.small)
    }
}
