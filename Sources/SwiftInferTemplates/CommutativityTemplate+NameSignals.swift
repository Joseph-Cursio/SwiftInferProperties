import SwiftInferCore

/// The name-side signals for commutativity: the positive curated / semilattice /
/// project-vocabulary verb match, and the negative anti-commutativity match.
/// Split out of `CommutativityTemplate.swift` to keep that file under the
/// `file_length` cap; both read only the `public` verb sets on the main type.
extension CommutativityTemplate {

    static func nameSignal(
        for summary: FunctionSummary,
        vocabulary: Vocabulary
    ) -> Signal? {
        if curatedVerbs.contains(summary.name) {
            return Signal(
                kind: .exactNameMatch,
                weight: 40,
                detail: "Curated commutativity verb match: '\(summary.name)'"
            )
        }
        // The semilattice / commutative-monoid verbs (`join`/`meet`/`min`/`max`/
        // `gcd`/`lcm`) are commutative AND associative by definition, so they earn
        // the same +40 name signal here that they already earn in
        // `AssociativityTemplate`. Without this they surfaced associativity at
        // Likely but commutativity only at Possible — the asymmetry the
        // swift-numerics gcd backtest exposed. Not set-combination verbs, so the
        // B29 order-sensitive-carrier veto does not apply.
        if AssociativityTemplate.commutativeAssociativeVerbs.contains(summary.name) {
            return Signal(
                kind: .exactNameMatch,
                weight: 40,
                detail: "Commutative-associative (semilattice) verb match: '\(summary.name)'"
            )
        }
        if vocabulary.commutativityVerbs.contains(summary.name) {
            return Signal(
                kind: .exactNameMatch,
                weight: 40,
                detail: "Project-vocabulary commutativity verb match: '\(summary.name)'"
            )
        }
        return nil
    }

    static func antiCommutativitySignal(
        for summary: FunctionSummary,
        vocabulary: Vocabulary
    ) -> Signal? {
        if curatedAntiCommutativityVerbs.contains(summary.name) {
            return Signal(
                kind: .antiCommutativityNaming,
                weight: -30,
                detail: "Curated anti-commutativity verb match: '\(summary.name)'"
            )
        }
        if vocabulary.antiCommutativityVerbs.contains(summary.name) {
            return Signal(
                kind: .antiCommutativityNaming,
                weight: -30,
                detail: "Project-vocabulary anti-commutativity verb match: '\(summary.name)'"
            )
        }
        return nil
    }
}
