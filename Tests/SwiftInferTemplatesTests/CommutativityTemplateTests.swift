import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

@Suite("CommutativityTemplate — type pattern")
struct CommutativityTemplateTypePatternTests {

    @Test("B24 — a bare (T, T) -> T shape with no commutative name is suppressed, not Possible")
    func typeShapeAloneIsSuppressed() {
        // `blend` has no curated/vocabulary commutative name and is not `+`/`*`,
        // so the shape alone no longer surfaces commutativity: a correct
        // non-commutative `(T,T)->T` (backoffDelay) matches the same shape. The
        // shape signal still contributes +30, but the B24 counter (-20) drops
        // the net below the Possible floor.
        let summary = makeCommutativitySummary(
            name: "blend",
            paramTypes: ("Color", "Color"),
            returnType: "Color"
        )
        #expect(CommutativityTemplate.suggest(for: summary) == nil)
        let signals = CommutativityTemplate.accumulatedSignals(
            for: summary,
            vocabulary: .empty,
            inheritedTypesByName: [:]
        )
        #expect(signals.contains { $0.kind == .typeSymmetrySignature && $0.weight == 30 })
        #expect(signals.contains { $0.kind == .unsupportedAlgebraicShape && $0.weight == -20 })
    }

    @Test("SetAlgebra combination verbs intersection / symmetricDifference score 70 (Likely)")
    func setCombinationVerbsFireCommutativity() {
        // Regression for the swift-collections `876177db` backtest: `intersection`
        // and `symmetricDifference` are genuinely commutative but were missing from
        // curatedVerbs (only the stale stem `intersect` and `union` were present),
        // so commutativity never surfaced on them — and the pre-fix
        // `symmetricDifference` (which was `subtracting` in disguise) went uncaught.
        for verb in ["intersection", "symmetricDifference"] {
            let summary = makeCommutativitySummary(
                name: verb,
                paramTypes: ("Set", "Set"),
                returnType: "Set"
            )
            let suggestion = CommutativityTemplate.suggest(for: summary)
            #expect(suggestion?.score.total == 70, "\(verb) should score 70 (Likely)")
            #expect(suggestion?.score.tier == .likely)
        }
    }

    @Test("Semilattice verbs gcd / lcm / min / max / join / meet score 70 (Likely) for commutativity")
    func semilatticeVerbsFireCommutativity() {
        // Regression for the swift-numerics gcd backtest recall gap: gcd / lcm / min /
        // max / join / meet are commutative AND associative by definition, so they
        // already earned Likely 70 for ASSOCIATIVITY but surfaced commutativity only at
        // Possible 30 (name +0, shape +30). `CommutativityTemplate.nameSignal` now reads
        // `AssociativityTemplate.commutativeAssociativeVerbs`, closing the asymmetry.
        for verb in AssociativityTemplate.commutativeAssociativeVerbs.sorted() {
            let summary = makeCommutativitySummary(
                name: verb,
                paramTypes: ("Int", "Int"),
                returnType: "Int"
            )
            let suggestion = CommutativityTemplate.suggest(for: summary)
            #expect(suggestion?.score.total == 70, "\(verb) should score 70 (Likely)")
            #expect(suggestion?.score.tier == .likely, "\(verb) should be Likely")
        }
    }

    @Test("Curated commutativity verb on (T, T) -> T scores 70 (Likely)")
    func curatedVerbAdds40() {
        let summary = makeCommutativitySummary(
            name: "merge",
            paramTypes: ("Set", "Set"),
            returnType: "Set"
        )
        let suggestion = CommutativityTemplate.suggest(for: summary)
        #expect(suggestion?.score.total == 70)
        #expect(suggestion?.score.tier == .likely)
    }

    // MARK: - B29 — order-sensitive carrier veto

    @Test("B29 — union commutativity is vetoed on an order-sensitive carrier (OrderedSet)")
    func orderSensitiveCarrierVetoesUnionCommutativity() {
        // `OrderedSet.union` scores 70 (curated 'union' +40, shape +30) but its
        // `==` compares element order, so commutativity is FALSE — veto it.
        let summary = makeCommutativitySummary(
            name: "union",
            paramTypes: ("OrderedSet", "OrderedSet"),
            returnType: "OrderedSet",
            containingType: "OrderedSet"
        )
        #expect(CommutativityTemplate.suggest(for: summary) == nil)
        let signals = CommutativityTemplate.accumulatedSignals(
            for: summary,
            vocabulary: .empty,
            inheritedTypesByName: [:]
        )
        let veto = signals.first { $0.kind == .orderSensitiveCarrier }
        #expect(veto?.isVeto == true)
        #expect(veto?.detail.contains("isEqualSet") == true)
    }

    @Test("B29 — a generic OrderedSet<Int> carrier still vetoes (generics stripped)")
    func orderSensitiveCarrierVetoStripsGenerics() {
        let summary = makeCommutativitySummary(
            name: "union",
            paramTypes: ("OrderedSet<Int>", "OrderedSet<Int>"),
            returnType: "OrderedSet<Int>",
            containingType: "OrderedSet<Int>"
        )
        #expect(CommutativityTemplate.suggest(for: summary) == nil)
    }

    @Test("B29 — stdlib Set.union is NOT vetoed — its == is order-insensitive")
    func stdlibSetUnionNotVetoed() {
        let summary = makeCommutativitySummary(
            name: "union",
            paramTypes: ("Set", "Set"),
            returnType: "Set",
            containingType: "Set"
        )
        let suggestion = CommutativityTemplate.suggest(for: summary)
        #expect(suggestion?.score.tier == .likely)
        #expect(suggestion?.score.total == 70)
    }

    @Test("B29 — a union on a carrier NOT on the denylist still fires (guard is carrier-specific)")
    func nonDenylistCarrierUnionStillFires() {
        let summary = makeCommutativitySummary(
            name: "union",
            paramTypes: ("Bag", "Bag"),
            returnType: "Bag",
            containingType: "Bag"
        )
        #expect(CommutativityTemplate.suggest(for: summary)?.score.tier == .likely)
    }

    @Test("B29 — a non-set verb on an order-sensitive carrier is untouched by the veto")
    func nonSetVerbOnOrderSensitiveCarrierUnaffected() {
        // `merge` is not a set-combination verb, so the veto does not fire even
        // on an order-sensitive carrier; it keeps its normal curated-verb score.
        let summary = makeCommutativitySummary(
            name: "merge",
            paramTypes: ("OrderedSet", "OrderedSet"),
            returnType: "OrderedSet",
            containingType: "OrderedSet"
        )
        let signals = CommutativityTemplate.accumulatedSignals(
            for: summary,
            vocabulary: .empty,
            inheritedTypesByName: [:]
        )
        #expect(!signals.contains { $0.kind == .orderSensitiveCarrier })
    }

    @Test("Single-parameter function never matches the commutativity pattern")
    func singleParamDoesNotMatch() {
        let summary = makeCommutativitySummary(
            name: "merge",
            parameters: [Parameter(label: nil, internalName: "x", typeText: "Set", isInout: false)],
            returnType: "Set"
        )
        #expect(CommutativityTemplate.suggest(for: summary) == nil)
    }

    @Test("Three-parameter function never matches the commutativity pattern")
    func threeParamDoesNotMatch() {
        let summary = makeCommutativitySummary(
            name: "merge",
            parameters: [
                Parameter(label: nil, internalName: "a", typeText: "Set", isInout: false),
                Parameter(label: nil, internalName: "b", typeText: "Set", isInout: false),
                Parameter(label: nil, internalName: "c", typeText: "Set", isInout: false)
            ],
            returnType: "Set"
        )
        #expect(CommutativityTemplate.suggest(for: summary) == nil)
    }

    @Test("Mismatched parameter types do not match")
    func mismatchedParamTypesDoNotMatch() {
        let summary = makeCommutativitySummary(
            name: "merge",
            paramTypes: ("Set", "Array"),
            returnType: "Set"
        )
        #expect(CommutativityTemplate.suggest(for: summary) == nil)
    }

    @Test("Return type that doesn't match params does not match")
    func mismatchedReturnTypeDoesNotMatch() {
        let summary = makeCommutativitySummary(
            name: "merge",
            paramTypes: ("Set", "Set"),
            returnType: "Bool"
        )
        #expect(CommutativityTemplate.suggest(for: summary) == nil)
    }

    @Test("inout on either parameter disqualifies")
    func inoutDisqualifies() {
        let summary = makeCommutativitySummary(
            name: "merge",
            parameters: [
                Parameter(label: nil, internalName: "a", typeText: "Set", isInout: true),
                Parameter(label: nil, internalName: "b", typeText: "Set", isInout: false)
            ],
            returnType: "Set"
        )
        #expect(CommutativityTemplate.suggest(for: summary) == nil)
    }

    @Test("mutating disqualifies")
    func mutatingDisqualifies() {
        let summary = makeCommutativitySummary(
            name: "merge",
            paramTypes: ("Set", "Set"),
            returnType: "Set",
            isMutating: true
        )
        #expect(CommutativityTemplate.suggest(for: summary) == nil)
    }

    @Test("Void return is rejected")
    func voidReturnRejected() {
        let summary = makeCommutativitySummary(
            name: "merge",
            paramTypes: ("Void", "Void"),
            returnType: "Void"
        )
        #expect(CommutativityTemplate.suggest(for: summary) == nil)
    }
}

@Suite("CommutativityTemplate — anti-commutativity, vocabulary, vetoes")
struct CommutativityTemplateBehaviorTests {

    // MARK: - Anti-commutativity counter-signal

    @Test("Curated anti-commutativity verb collapses score to suppressed")
    func antiCommutativitySuppresses() {
        let summary = makeCommutativitySummary(
            name: "concatenate",
            paramTypes: ("Array", "Array"),
            returnType: "Array"
        )
        // 30 type-symmetry + (-30) anti-commutativity = 0 → suppressed.
        #expect(CommutativityTemplate.suggest(for: summary) == nil)
    }

    @Test("Curated anti-commutativity for `subtract` suppresses")
    func subtractAntiCommutativitySuppresses() {
        let summary = makeCommutativitySummary(
            name: "subtract",
            paramTypes: ("Vector", "Vector"),
            returnType: "Vector"
        )
        #expect(CommutativityTemplate.suggest(for: summary) == nil)
    }

    @Test("Project-vocabulary anti-commutativity verb suppresses too")
    func projectVocabAntiCommutativitySuppresses() {
        let summary = makeCommutativitySummary(
            name: "concatenateOrdered",
            paramTypes: ("Array", "Array"),
            returnType: "Array"
        )
        let vocabulary = Vocabulary(antiCommutativityVerbs: ["concatenateOrdered"])
        #expect(CommutativityTemplate.suggest(for: summary, vocabulary: vocabulary) == nil)
    }

    @Test("Anti-commutativity counter-signal renders with the project-vocab detail line")
    func projectVocabAntiCommutativityDetailLineIfVisible() throws {
        // Pathological scenario where the score doesn't collapse: type-symmetry (+30)
        // plus a project-vocab COMMUTATIVITY verb (+40) plus a curated
        // anti-commutativity (-30) on a function whose name happens to
        // be in the project's commutativity list. Net: 40, Possible.
        let summary = makeCommutativitySummary(
            name: "subtract",
            paramTypes: ("T", "T"),
            returnType: "T"
        )
        let vocabulary = Vocabulary(commutativityVerbs: ["subtract"])
        let suggestion = try #require(CommutativityTemplate.suggest(for: summary, vocabulary: vocabulary))
        // Score should be 30 + 40 - 30 = 40 → Possible.
        #expect(suggestion.score.total == 40)
        let counterLine = suggestion.explainability.whySuggested.first { line in
            line.contains("anti-commutativity")
        }
        #expect(counterLine == "Curated anti-commutativity verb match: 'subtract' (-30)")
    }

    // MARK: - Project vocabulary (commutativity verbs)

    @Test("Project-vocabulary verb on (T, T) -> T scores 70 (Likely)")
    func projectVocabularyVerb() {
        let summary = makeCommutativitySummary(
            name: "unionGraphs",
            paramTypes: ("Graph", "Graph"),
            returnType: "Graph"
        )
        let vocabulary = Vocabulary(commutativityVerbs: ["unionGraphs"])
        let suggestion = CommutativityTemplate.suggest(for: summary, vocabulary: vocabulary)
        #expect(suggestion?.score.total == 70)
        #expect(suggestion?.score.tier == .likely)
    }

    @Test("Curated verb wins over project-vocabulary when both list the same name")
    func curatedTakesPrecedenceOverProjectVocabulary() throws {
        let summary = makeCommutativitySummary(
            name: "merge",
            paramTypes: ("Set", "Set"),
            returnType: "Set"
        )
        let vocabulary = Vocabulary(commutativityVerbs: ["merge"])
        let suggestion = try #require(CommutativityTemplate.suggest(for: summary, vocabulary: vocabulary))
        #expect(suggestion.score.total == 70)
        let nameLine = suggestion.explainability.whySuggested.first { line in
            line.contains("verb match")
        }
        #expect(nameLine == "Curated commutativity verb match: 'merge' (+40)")
    }

    @Test("Empty vocabulary leaves curated behaviour unchanged")
    func emptyVocabularyLeavesCuratedAlone() {
        let summary = makeCommutativitySummary(
            name: "merge",
            paramTypes: ("Set", "Set"),
            returnType: "Set"
        )
        let suggestion = CommutativityTemplate.suggest(for: summary, vocabulary: .empty)
        #expect(suggestion?.score.total == 70)
    }

    // MARK: - Vetoes

    @Test("Non-deterministic body veto suppresses regardless of name signal")
    func nonDeterministicVetoSuppresses() {
        let summary = makeCommutativitySummary(
            name: "merge",
            paramTypes: ("Set", "Set"),
            returnType: "Set",
            bodySignals: BodySignals(
                hasNonDeterministicCall: true,
                hasSelfComposition: false,
                nonDeterministicAPIsDetected: ["Date"]
            )
        )
        #expect(CommutativityTemplate.suggest(for: summary) == nil)
    }
}
