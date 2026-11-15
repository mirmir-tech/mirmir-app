import Foundation
import MirmirRPC

extension ContextChoice {
    /// An unset choice is the server's default, automatic sizing.
    init(_ wire: Mirmir_V1_ModelContextChoice) {
        switch wire.choice {
        case .tokens(let tokens): self = .tokens(tokens)
        case .automatic, nil: self = .automatic
        }
    }

    var wire: Mirmir_V1_ModelContextChoice {
        var value = Mirmir_V1_ModelContextChoice()
        switch self {
        case .automatic: value.automatic = true
        case .tokens(let tokens): value.tokens = tokens
        }
        return value
    }
}

extension ModelContext {
    init(_ wire: Mirmir_V1_ModelContext) {
        self.init(
            blockTokens: wire.blockTokens, minTokens: wire.minTokens, maxTokens: wire.maxTokens,
            saved: ContextChoice(wire.saved), automaticTokens: wire.automaticTokens,
            residentTokens: wire.hasResidentTokens ? wire.residentTokens : nil
        )
    }
}
