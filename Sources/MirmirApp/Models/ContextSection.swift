import MirmirKit
import SwiftUI

/// The K/V capacity a model loads with: automatic sizing or a token count on
/// a logarithmic slider snapped to whole K/V blocks. An unsaved choice is
/// saved here, or by Load.
struct ContextSection: View {
    let context: ModelContext
    @Binding var choice: ContextChoice
    /// The choice differs from the saved one.
    let unsaved: Bool
    let loaded: Bool
    /// A load or save is under way.
    let busy: Bool
    /// The memory the choice needs; `pendingEstimate` while it is on its way.
    let memory: MemoryEstimate?
    let pendingEstimate: Bool
    let save: () -> Void
    let reload: () -> Void

    var body: some View {
        InspectorSection(title: "Context") {
            Toggle("Automatic", isOn: automatic).toggleStyle(.switch).controlSize(.mini).font(.system(size: 11))
                .disabled(busy)
        } content: {
            HStack(alignment: .firstTextBaseline) {
                Text(readout).font(.mono(13, weight: .semibold))
                Spacer(minLength: 8)
                if let resident = context.residentTokens {
                    Text("loaded with \(Format.grouped(resident))").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            VStack(spacing: 2) {
                Slider(value: position, in: 0...1).labelsHidden().controlSize(.small).disabled(choice == .automatic || busy)
                HStack {
                    Text(Format.grouped(context.scale.lower))
                    Spacer()
                    Text(Format.grouped(context.scale.upper))
                }
                .font(.mono(10)).foregroundStyle(.tertiary)
            }
            if let memory {
                Divider().padding(.vertical, 2)
                MemoryEstimateView(memory: memory, context: context, pending: pendingEstimate)
            }
            if unsaved {
                Divider().padding(.vertical, 2)
                pendingChange
            }
        }
    }

    private var pendingChange: some View {
        HStack(spacing: 8) {
            InspectorNote(loaded ? "Applies on the next load." : "Load saves it, or save it now.")
            Spacer(minLength: 8)
            if loaded { Button("Reload", action: reload).controlSize(.small).disabled(busy) }
            Button("Save", action: save).controlSize(.small).disabled(busy)
        }
    }

    private var readout: String {
        switch choice {
        case .automatic: "\(Format.grouped(context.automaticTokens)) tokens (automatic)"
        case .tokens(let tokens): "\(Format.grouped(tokens)) tokens"
        }
    }

    private var automatic: Binding<Bool> {
        Binding(
            get: { choice == .automatic },
            set: { on in
                if on {
                    choice = .automatic
                } else if case .tokens(let saved) = context.saved {
                    choice = .tokens(saved)
                } else {
                    choice = .tokens(context.initialTokens)
                }
            }
        )
    }

    /// The slider's position; automatic shows where its tokens fall.
    private var position: Binding<Double> {
        Binding(
            get: { context.scale.position(of: context.tokens(for: choice)) },
            set: { choice = .tokens(context.scale.value(at: $0)) }
        )
    }
}
