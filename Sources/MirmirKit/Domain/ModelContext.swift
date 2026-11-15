import Foundation

/// The K/V capacity a model loads with, decoded from `ModelContextChoice`.
public enum ContextChoice: Hashable, Sendable {
    /// Sized by the server from the memory budget when the model loads.
    case automatic
    /// A token count; the server rounds it up to whole K/V blocks.
    case tokens(UInt64)
}

/// The context a model can be given before it loads, decoded from
/// `InspectModelResponse.context`. Absent for models without a K/V cache and
/// from servers before 0.6.1, which would drop a chosen context.
public struct ModelContext: Hashable, Sendable {
    public let blockTokens: UInt64
    public let minTokens: UInt64
    /// The model's own context length.
    public let maxTokens: UInt64
    /// The choice saved for the model and used by every load.
    public let saved: ContextChoice
    /// What automatic sizing would give the model now.
    public let automaticTokens: UInt64
    /// The capacity it serves with while loaded.
    public let residentTokens: UInt64?

    public init(
        blockTokens: UInt64, minTokens: UInt64, maxTokens: UInt64, saved: ContextChoice,
        automaticTokens: UInt64, residentTokens: UInt64?
    ) {
        self.blockTokens = blockTokens
        self.minTokens = minTokens
        self.maxTokens = maxTokens
        self.saved = saved
        self.automaticTokens = automaticTokens
        self.residentTokens = residentTokens
    }

    /// The slider's range: whole blocks from the minimum to the model's own
    /// context length.
    public var scale: LogScale { LogScale(lower: minTokens, upper: maxTokens, step: blockTokens) }

    /// The tokens `choice` gives the model if it loaded now.
    public func tokens(for choice: ContextChoice) -> UInt64 {
        switch choice {
        case .automatic: automaticTokens
        case .tokens(let tokens): tokens
        }
    }

    /// Where a switch from automatic to a token count starts: the capacity
    /// the model serves with, else what automatic sizing would give, within
    /// the scale.
    public var initialTokens: UInt64 { scale.snapped(residentTokens ?? automaticTokens) }
}

/// A logarithmic slider scale over whole steps: positions in `0...1` map to
/// values in `lower...upper`, rounded to a multiple of `step` (the bounds
/// themselves are always reachable).
public struct LogScale: Hashable, Sendable {
    public let lower: UInt64
    public let upper: UInt64
    public let step: UInt64

    public init(lower: UInt64, upper: UInt64, step: UInt64 = 1) {
        self.lower = max(1, lower)
        self.upper = max(self.lower, upper)
        self.step = max(1, step)
    }

    /// The value at `position`, snapped to the scale.
    public func value(at position: Double) -> UInt64 {
        let clamped = min(1, max(0, position.isFinite ? position : 0))
        let low = log(Double(lower))
        let raw = exp(low + clamped * (log(Double(upper)) - low))
        return snapped(raw >= Double(UInt64.max) ? .max : UInt64(raw.rounded()))
    }

    /// The position of `value` (clamped to the bounds) on the scale.
    public func position(of value: UInt64) -> Double {
        guard upper > lower else { return 0 }
        let low = log(Double(lower))
        let clamped = min(upper, max(lower, value))
        return (log(Double(clamped)) - low) / (log(Double(upper)) - low)
    }

    /// The nearest multiple of `step` within the bounds.
    public func snapped(_ value: UInt64) -> UInt64 {
        let (quotient, remainder) = value.quotientAndRemainder(dividingBy: step)
        let down = quotient * step
        let up = remainder >= step - remainder
        let (sum, overflow) = down.addingReportingOverflow(step)
        let nearest = up ? (overflow ? .max : sum) : down
        return min(upper, max(lower, nearest))
    }
}
