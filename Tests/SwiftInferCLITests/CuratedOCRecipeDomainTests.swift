@testable import SwiftInferCLI
import Testing

/// Ties the emitted curated recipes to the domain
/// `fixtures/ordered-set-generator` measures.
///
/// That fixture models each domain as a hand-rolled reachable value set driven
/// by a seeded LCG rather than the literal `Gen` pipeline — a deliberate
/// modelling choice (its §6 states the cost). The risk it buys is **drift**: the
/// fixture could keep reporting 0 of 3 → 3 of 3 for a domain the emitter no
/// longer produces, which is the measurement equivalent of a stale summary.
///
/// So the properties the fixture's `Domain.widened` relies on are asserted here,
/// against the real expression strings. This is not a restatement of the
/// expression — it pins the three properties the mutant table is *about*, and
/// nothing else, so ordinary edits to the recipes stay free.
@Suite("Curated OC recipes — the domain the fixture measures")
struct CuratedOCRecipeDomainTests {

    private typealias Emitter = StrategistDispatchEmitter

    private static let collectionCarriers = Emitter.curatedOCRecipeCarriers

    @Test("every curated collection recipe draws from the signed element range", arguments: collectionCarriers)
    func drawsFromSignedRange(carrier: String) {
        let expression = Emitter.curatedOCRecipe(carrier: carrier)?.expression ?? ""
        #expect(
            expression.contains("in: -100 ... 100"),
            """
            \(carrier) no longer draws from `-100 ... 100`, so the fixture's `nonNegativeAssumption` \
            mutant result does not describe the shipped recipe. Expression: \(expression)
            """
        )
    }

    @Test("every curated collection recipe varies arity with a floor of 1", arguments: collectionCarriers)
    func variesArityAboveEmpty(carrier: String) {
        let expression = Emitter.curatedOCRecipe(carrier: carrier)?.expression ?? ""
        #expect(
            expression.contains("array(of: 1 ... 6)"),
            """
            \(carrier) no longer draws a variable-length array with a floor of 1. The floor is not \
            cosmetic: these recipes serve `index(after:)` / `index(before:)` monotonicity picks and \
            an empty receiver has no valid index to advance from. Expression: \(expression)
            """
        )
    }

    /// The regression this one guards is a **trap**, not a wrong answer.
    /// `OrderedDictionary(uniqueKeysWithValues:)` requires distinct keys and
    /// traps otherwise; a drawn array can repeat where the old single-seed
    /// arithmetic form could not.
    @Test("every OrderedDictionary recipe deduplicates its keys before pairing")
    func dictionaryRecipesDeduplicateKeys() {
        let dictionaryCarriers = Self.collectionCarriers.filter { $0.hasPrefix("OrderedDictionary") }
        #expect(!dictionaryCarriers.isEmpty, "no OrderedDictionary carriers — this guard covers nothing")
        for carrier in dictionaryCarriers {
            let expression = Emitter.curatedOCRecipe(carrier: carrier)?.expression ?? ""
            #expect(
                expression.contains("uniqueKeysWithValues"),
                "\(carrier) no longer builds via uniqueKeysWithValues; re-check this guard's premise"
            )
            #expect(
                expression.contains("OrderedSet(seeds)"),
                """
                \(carrier) feeds `uniqueKeysWithValues:` without deduplicating first. A repeated \
                drawn key TRAPS, and `InteractionVerifyOutcomeParser` maps a non-zero exit to \
                `.measuredDefaultFails` — so this would surface as the subject being refuted \
                rather than as a broken generator. Expression: \(expression)
                """
            )
        }
    }

    /// The old domain, pinned as *absent*. Without this the suite passes if a
    /// recipe reverts, since the assertions above only check the carriers that
    /// still match.
    @Test("no curated recipe still uses the fixed four-consecutive-element form", arguments: collectionCarriers)
    func oldFixedArityFormIsGone(carrier: String) {
        let expression = Emitter.curatedOCRecipe(carrier: carrier)?.expression ?? ""
        #expect(
            !expression.contains("$0 + 1, $0 + 2, $0 + 3"),
            """
            \(carrier) reverted to the fixed `{n, n+1, n+2, n+3}` form. That domain has 101 \
            reachable values and three mutants survive it exhaustively — see \
            fixtures/ordered-set-generator/README.md §3.
            """
        )
    }
}
