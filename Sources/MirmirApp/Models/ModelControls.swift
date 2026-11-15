import MirmirKit
import SwiftUI

/// A model's context, memory estimate, generation defaults and actions. The
/// inspector creates one per model (`.id(selector)`), so an unsaved context
/// and its estimate never carry over to another model.
struct ModelControls: View {
    @Environment(AppModel.self) private var model
    let local: LocalModel
    /// The inspection at the saved context; nil until it arrives.
    let inspection: ModelInspection?
    /// The context chosen here; nil follows the saved one.
    @State private var edited: ContextChoice?
    /// The estimate for `edited`, once the server answered for it.
    @State private var candidate: CandidateEstimate?
    @State private var saving = false

    private struct CandidateEstimate {
        let choice: ContextChoice
        let memory: MemoryEstimate
    }

    private var state: LocalModelState { model.displayState(of: local) }
    private var context: ModelContext? { inspection?.context }
    /// The context Load sends: only to a server that reports one.
    private var choice: ContextChoice? { context.map { edited ?? $0.saved } }
    private var busy: Bool { saving || model.loads[local.selector] != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            actions
            if let context {
                ContextSection(
                    context: context, choice: choiceBinding(context), unsaved: edited != nil,
                    loaded: state == .loaded, busy: busy, memory: memory, pendingEstimate: pendingEstimate,
                    save: save, reload: reload
                )
            } else if let memory {
                InspectorSection("Memory") { MemoryEstimateView(memory: memory) }
            }
            if let inspection, inspection.task.generates {
                GenerationDefaultsForm(selector: local.selector, saved: inspection.settings, maxTokensLimit: maxTokensLimit(inspection))
            }
        }
        // Debounced: a drag re-inspects once it rests, and a newer choice
        // cancels the older request, so a stale estimate is never shown.
        .task(id: edited) {
            guard let edited else {
                candidate = nil
                return
            }
            do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
            guard let memory = await model.estimate(local.selector, context: edited), !Task.isCancelled else { return }
            candidate = CandidateEstimate(choice: edited, memory: memory)
        }
        // A save or load that stored this choice makes it the saved one.
        .onChange(of: context?.saved) { _, saved in
            if edited == saved { edited = nil }
        }
    }

    /// The estimate to show: an unsaved choice shows the last estimate,
    /// dimmed, until its own arrives.
    private var memory: MemoryEstimate? {
        guard let saved = inspection?.memory else { return nil }
        return edited == nil ? saved : candidate?.memory ?? saved
    }

    private var pendingEstimate: Bool { edited != nil && candidate?.choice != edited }

    private func choiceBinding(_ context: ModelContext) -> Binding<ContextChoice> {
        Binding(
            get: { edited ?? context.saved },
            set: { edited = $0 == context.saved ? nil : $0 }
        )
    }

    /// Up to the context the model gets and the longest input it takes.
    private func maxTokensLimit(_ inspection: ModelInspection) -> UInt64 {
        let contextTokens = context.map { $0.tokens(for: choice ?? $0.saved) }
        let input = inspection.maxInputTokens > 0 ? inspection.maxInputTokens : nil
        return [contextTokens, input].compactMap(\.self).min() ?? max(inspection.settings.maxTokens, 1)
    }

    private func save() {
        guard let edited else { return }
        saving = true
        Task {
            await model.updateSettings(local.selector, nil, context: edited)
            saving = false
        }
    }

    private func reload() {
        guard let edited else { return }
        model.reload(local.selector, serving: model.servingSelector(for: local), context: edited)
    }

    @ViewBuilder private var actions: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if state == .loaded {
                    Button("Unload") { model.unload(model.servingSelector(for: local)) }
                        .disabled(busy)
                } else {
                    Button("Load") { model.load(local.selector, context: choice) }
                        .buttonStyle(.borderedProminent)
                        .disabled(local.loadability != .loadable || busy)
                }
                if let load = model.loads[local.selector] {
                    ProgressView(value: load.fraction).frame(maxWidth: 90)
                    Text(load.phase.replacingOccurrences(of: "_", with: " ").capitalized)
                        .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                if local.managed, state != .loaded, !local.repoID.isEmpty {
                    Menu {
                        Button("Remove from Disk", role: .destructive) { model.removeCheckpoint(local.repoID) }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("More")
                    .disabled(busy)
                }
            }
            if case .unavailable(let reason) = local.loadability, !reason.isEmpty {
                InspectorNote(reason, color: Palette.danger)
            }
        }
    }
}
