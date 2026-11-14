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
    let save: () -> Void
    let reload: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Context").font(.system(size: 12, weight: .semibold))
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Automatic", isOn: automatic).toggleStyle(.switch).controlSize(.small).font(.system(size: 12))
                Slider(value: position, in: 0...1).labelsHidden().controlSize(.small).disabled(choice == .automatic)
                HStack(spacing: 6) {
                    Text(readout).font(.mono(11, weight: .medium))
                    Spacer(minLength: 8)
                    if let resident = context.residentTokens {
                        Text("Loaded with \(Format.grouped(resident))").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
                Text("\(Format.grouped(context.scale.lower)) to \(Format.grouped(context.scale.upper)) tokens")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .disabled(busy)
            .card(padding: 12)
            if unsaved { pendingChange }
        }
    }

    private var pendingChange: some View {
        HStack(spacing: 8) {
            Text(loaded ? "Applies on the next load." : "Load saves it, or save it now.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            if loaded { Button("Reload", action: reload).disabled(busy) }
            Button("Save", action: save).disabled(busy)
        }
    }

    private var readout: String {
        switch choice {
        case .automatic: "Automatic · \(Format.grouped(context.automaticTokens)) tokens now"
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
