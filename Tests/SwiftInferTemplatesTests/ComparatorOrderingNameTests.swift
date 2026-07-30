import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

/// `comparator` requires an ordering NAME, not just the `(T, T) -> Bool` shape.
///
/// The shape is necessary and nowhere near sufficient, and the inconsistency was visible
/// in the catalog before it was measured: the sibling `equivalence-relation` template,
/// which makes the **weaker** claim, was already name-gated *"so it never fires on an
/// arbitrary `Bool`-returning binary method"* — while `comparator` asserted a strict weak
/// ordering from shape alone.
///
/// Measured on this repo: **11 of 22** shape matches were false, and the three already
/// visible at `Likely` (`areComplementary`, `isCanonicalInversePair`,
/// `initializerPairAdmissible` — internal or public, so shipping) were **all** false. The
/// fixtures below are those real functions, not invented ones.
///
/// Two distinct failure modes, neither visible to a shape test:
///
/// - **symmetric relations** — `sameType` is `lhs.trimmed == rhs.trimmed`,
///   `isCanonicalInversePair` tests both orientations, `areComplementary` documents itself
///   as *"Order-insensitive"*. A CORRECT implementation fails asymmetry.
/// - **role-carrying operands** — `matches(_ name:, _ stem:)` and
///   `curatedActiveToPresentParticiple(_ active:, _ ing:)` are positional but not
///   interchangeable. `isComparator`'s label test claims to catch this and does not; see
///   `roleCarryingOperandsAreStillAHole` below, which pins the gap rather than hiding it.
@Suite("Comparator — the shape alone cannot claim an ordering")
struct ComparatorOrderingNameTests {

    private func binary(
        _ name: String,
        _ type: String = "String",
        first: String = "lhs",
        second: String = "rhs"
    ) -> FunctionSummary {
        FunctionSummary(
            name: name,
            parameters: [
                Parameter(label: nil, internalName: first, typeText: type, isInout: false),
                Parameter(label: nil, internalName: second, typeText: type, isInout: false)
            ],
            returnTypeText: "Bool",
            isThrows: false,
            isAsync: false,
            isMutating: false,
            isStatic: false,
            location: SourceLocation(file: "Pairing.swift", line: 1, column: 1),
            containingTypeName: "Pairing",
            bodySignals: .empty
        )
    }

    // MARK: - The real false positives this fixed

    /// Every one of these is a function in this repo that the template claimed at `Likely`.
    @Test("the eleven measured false positives are suppressed", arguments: [
        "areComplementary",                   // docstring: "Order-insensitive"
        "isCanonicalInversePair",              // body tests both orientations
        "initializerPairAdmissible",           // admissibility over an unordered pair
        "sameType",                            // body is `==`
        "matches",                             // (_ name:, _ stem:) — roles, not operands
        "curatedActiveToPresentParticiple",    // (_ active:, _ ing:)
        "curatedActiveToPastParticiple",       // (_ active:, _ past:)
        "curatedFormPrefixToBare"              // (_ form:, _ bare:)
    ])
    func measuredFalsePositivesAreSuppressed(name: String) {
        let summary = binary(name)
        // The SHAPE still matches — that is why `predicate` still declines it, and why the
        // suppression is a scoring verdict rather than a gate change.
        #expect(ComparatorTemplate.isComparator(summary))
        #expect(ComparatorTemplate.hasOrderingName(name) == false)
        #expect(
            ComparatorTemplate.suggest(for: summary) == nil,
            "\(name) must not claim a strict weak ordering"
        )
    }

    @Test("the counter-signal drops 40 to 15 — below the Possible floor, not merely lower")
    func counterSignalFallsBelowThePossibleFloor() throws {
        let signals = ComparatorTemplate.signals(for: binary("sameType"))
        let counter = try #require(signals.first { $0.kind == .unsupportedComparatorShape })
        #expect(counter.weight == -25)
        #expect(!counter.isVeto, "this is a counter-signal, not a veto: the shape is real")
        let score = Score(signals: signals)
        #expect(score.total == 15)
        #expect(score.tier == .suppressed)
    }

    // MARK: - The true positives must survive

    /// The eleven that ARE genuinely owed. `lessThan(Suggestion, Suggestion)` compares
    /// location then template name — a real sort predicate, and a non-strict-weak-ordering
    /// there can take `sorted(by:)` out of bounds.
    @Test("ordering-named comparators still fire at full weight", arguments: [
        "lessThan", "locationLessThan", "sortCandidates", "precedes",
        "isOrderedBefore", "compare", "sortsBefore", "ranksBefore"
    ])
    func orderingNamesStillFire(name: String) throws {
        #expect(ComparatorTemplate.hasOrderingName(name))
        let suggestion = try #require(ComparatorTemplate.suggest(for: binary(name)))
        #expect(suggestion.templateName == "comparator")
        #expect(suggestion.score.total == 40)
        #expect(suggestion.score.tier == .likely)
        #expect(
            suggestion.explainability.whySuggested.contains { $0.contains("strict weak ordering") }
        )
    }

    @Test("the ordering-stem list is substring-matched, so compounds qualify")
    func stemsMatchAsSubstrings() {
        // `locationLessThan` and `sortCandidates` are the two real names that need this.
        #expect(ComparatorTemplate.hasOrderingName("locationLessThan"))
        #expect(ComparatorTemplate.hasOrderingName("sortCandidates"))
        #expect(ComparatorTemplate.hasOrderingName("compareByDepthThenName"))
    }

    // MARK: - What this does NOT fix, pinned so it is not mistaken for fixed

    /// The template's own docs say the label test separates a comparator from a
    /// role-carrying pair test, citing `isImmediateChild(_ path:, of parentPath:)`. That
    /// example works because it has a LABEL. Swift lets you write two positional operands
    /// with distinct roles and no labels, and then the test does nothing:
    /// `matches(_ name: String, _ stem: String)` is four of the eleven false positives.
    ///
    /// Today the ordering-name requirement happens to catch them, because none is named
    /// like an ordering. It would NOT catch a role-carrying pair test that is —
    /// `sortsBefore(_ item: T, _ pivot: T)` would pass both gates and still be no ordering.
    /// Recorded rather than closed: the fix is an operand-interchangeability test on
    /// internal names, and it is a separate change with its own corpus measurement.
    @Test("role-carrying positional operands remain a hole the label test does not close")
    func roleCarryingOperandsAreStillAHole() {
        let roleCarrying = binary("sortsBefore", first: "item", second: "pivot")
        #expect(ComparatorTemplate.isComparator(roleCarrying), "no labels, so the gate admits it")
        #expect(ComparatorTemplate.suggest(for: roleCarrying) != nil, "and the name lets it through")
    }
}
