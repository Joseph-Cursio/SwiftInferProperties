/// Aggregated score for a single suggestion. Built from a bag of `Signal`s
/// per PRD v0.3 §4 — the total is the sum of non-veto weights, and any
/// vetoed signal collapses the tier to `.suppressed` regardless of total.
public struct Score: Sendable, Equatable {

    /// Signals in the order the template added them. Order is preserved so
    /// the renderer (§4.5) can present them in a stable, template-defined
    /// sequence rather than alphabetically.
    public let signals: [Signal]

    /// Sum of non-veto signal weights. `0` when there are no non-veto
    /// signals (e.g. a vetoed suggestion).
    public let total: Int

    /// `true` when at least one signal is a veto. A vetoed score always
    /// maps to `.suppressed` regardless of `total`.
    public let isVetoed: Bool

    /// Tier the score lands in per §4.2 — `.suppressed` if vetoed.
    public let tier: Tier

    public init(signals: [Signal]) {
        self.signals = signals
        let vetoed = signals.contains(where: \.isVeto)
        let total = signals
            .filter { !$0.isVeto }
            .map(\.weight)
            .reduce(0, +)
        self.total = total
        self.isVetoed = vetoed
        self.tier = vetoed ? .suppressed : Tier(score: total)
    }
}
