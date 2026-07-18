import SwiftInferCore

// Corroborate-only docstring signal for round-trip. Either half of the pair may
// carry the assertion ("round-trip", "recovers the original", "losslessly", …),
// so both docstrings are checked; +15 on the first hit. Deliberately does NOT
// override the cross-type counter — a documented cross-type pair keeps its
// structural -25 (the cycle-4 over-generation filter dominates prose). The clean
// win is a documented free-function / same-carrier codec pair: 30 + 15 = 45,
// Likely. Negation-gated; the pair shape still gates.
extension RoundTripTemplate {

    static func docstringCorroborationSignal(for pair: FunctionPair) -> Signal? {
        let corroboration =
            DocstringPropertyCorroborator.corroboration(for: .roundTrip, in: pair.forward.docComment)
            ?? DocstringPropertyCorroborator.corroboration(for: .roundTrip, in: pair.reverse.docComment)
        guard let corroboration else { return nil }
        return Signal(
            kind: .docstringCorroboration,
            weight: 15,
            detail: "Docstring corroborates round-trip: '\(corroboration.matchedPhrase)'"
        )
    }
}
