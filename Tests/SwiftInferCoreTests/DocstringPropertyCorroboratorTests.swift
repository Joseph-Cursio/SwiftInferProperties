@testable import SwiftInferCore
import Testing

@Suite("DocstringPropertyCorroborator — corroborate-only prose matching")
struct DocstringPropertyCorroboratorTests {

    // MARK: - Positive corroboration

    @Test("The bare word 'idempotent' corroborates idempotence")
    func idempotentWordMatches() {
        let result = DocstringPropertyCorroborator.corroboration(
            for: .idempotence,
            in: "Normalizes the value. This operation is idempotent."
        )
        #expect(result?.matchedPhrase == "idempotent")
    }

    @Test("A 'no further effect' phrase corroborates idempotence")
    func noFurtherEffectMatches() {
        let result = DocstringPropertyCorroborator.corroboration(
            for: .idempotence,
            in: "Trims whitespace; applying it to trimmed input has no further effect."
        )
        #expect(result?.matchedPhrase == "no further effect")
    }

    @Test("'self-inverse' corroborates involution")
    func selfInverseMatchesInvolution() {
        let result = DocstringPropertyCorroborator.corroboration(
            for: .involution,
            in: "Reverses the sequence. The operation is self-inverse."
        )
        #expect(result?.matchedPhrase == "self-inverse")
    }

    @Test("'twice returns the original' corroborates involution")
    func twiceReturnsOriginalMatchesInvolution() {
        let result = DocstringPropertyCorroborator.corroboration(
            for: .involution,
            in: "Negates each element; applying it twice returns the original."
        )
        #expect(result?.matchedPhrase == "applying it twice returns the original")
    }

    // MARK: - Negation gate

    @Test("'not idempotent' does NOT corroborate idempotence")
    func negatedIdempotenceSuppressed() {
        let result = DocstringPropertyCorroborator.corroboration(
            for: .idempotence,
            in: "Advances the cursor. Note this is not idempotent."
        )
        #expect(result == nil)
    }

    @Test("'non-idempotent' does NOT corroborate idempotence")
    func nonPrefixNegationSuppressed() {
        let result = DocstringPropertyCorroborator.corroboration(
            for: .idempotence,
            in: "A non-idempotent accumulator."
        )
        #expect(result == nil)
    }

    @Test("'isn't self-inverse' does NOT corroborate involution")
    func negatedInvolutionSuppressed() {
        let result = DocstringPropertyCorroborator.corroboration(
            for: .involution,
            in: "A rotation that isn't self-inverse in general."
        )
        #expect(result == nil)
    }

    // MARK: - Discrimination (no cross-property leakage)

    @Test("Idempotence prose does not corroborate involution")
    func idempotenceDoesNotLeakToInvolution() {
        let doc = "This operation is idempotent — no further effect on a normalized value."
        #expect(DocstringPropertyCorroborator.corroboration(for: .involution, in: doc) == nil)
    }

    @Test("Involution prose does not corroborate idempotence")
    func involutionDoesNotLeakToIdempotence() {
        let doc = "Self-inverse: applying it twice returns the original."
        #expect(DocstringPropertyCorroborator.corroboration(for: .idempotence, in: doc) == nil)
    }

    @Test("A bare 'applying twice' (ambiguous) corroborates neither")
    func ambiguousApplyingTwiceMatchesNeither() {
        let doc = "Applying twice does something interesting."
        #expect(DocstringPropertyCorroborator.corroboration(for: .idempotence, in: doc) == nil)
        #expect(DocstringPropertyCorroborator.corroboration(for: .involution, in: doc) == nil)
    }

    // MARK: - Absence

    @Test("nil docstring corroborates nothing")
    func nilDocComment() {
        #expect(DocstringPropertyCorroborator.corroboration(for: .idempotence, in: nil) == nil)
    }

    @Test("Unrelated prose corroborates nothing")
    func unrelatedProse() {
        let doc = "Returns the user's display name, or an empty string when unset."
        #expect(DocstringPropertyCorroborator.corroboration(for: .idempotence, in: doc) == nil)
        #expect(DocstringPropertyCorroborator.corroboration(for: .involution, in: doc) == nil)
    }
}

@Suite("DocstringPropertyCorroborator — binary + projection families")
struct DocstringPropertyCorroboratorBinaryTests {

    @Test("'commutative' corroborates commutativity only")
    func commutativeMatches() {
        let doc = "Merges two sets. The operation is commutative."
        let hit = DocstringPropertyCorroborator.corroboration(for: .commutativity, in: doc)
        #expect(hit?.matchedPhrase == "commutative")
        #expect(DocstringPropertyCorroborator.corroboration(for: .associativity, in: doc) == nil)
    }

    @Test("'order of the arguments doesn't matter' corroborates commutativity")
    func argumentOrderMatches() {
        let doc = "Combines the two inputs; the order of the arguments doesn't matter."
        let result = DocstringPropertyCorroborator.corroboration(for: .commutativity, in: doc)
        #expect(result?.matchedPhrase == "order of the arguments doesn't matter")
    }

    @Test("'associative' corroborates associativity only")
    func associativeMatches() {
        let doc = "Folds the elements. This combine is associative."
        let hit = DocstringPropertyCorroborator.corroboration(for: .associativity, in: doc)
        #expect(hit?.matchedPhrase == "associative")
        #expect(DocstringPropertyCorroborator.corroboration(for: .commutativity, in: doc) == nil)
    }

    @Test("'grouping doesn't matter' corroborates associativity, not commutativity")
    func groupingDiscriminates() {
        let doc = "Concatenates; grouping doesn't matter."
        #expect(DocstringPropertyCorroborator.corroboration(for: .associativity, in: doc) != nil)
        #expect(DocstringPropertyCorroborator.corroboration(for: .commutativity, in: doc) == nil)
    }

    @Test("'round-trip' and 'recovers the original' corroborate round-trip")
    func roundTripMatches() {
        #expect(DocstringPropertyCorroborator.corroboration(
            for: .roundTrip, in: "Decodes a previously-encoded value in a round-trip."
        )?.matchedPhrase == "round-trip")
        #expect(DocstringPropertyCorroborator.corroboration(
            for: .roundTrip, in: "Parsing then printing recovers the original text."
        )?.matchedPhrase == "recovers the original")
    }

    @Test("'monotone' / 'order-preserving' / 'non-decreasing' corroborate monotonicity")
    func monotonicityMatches() {
        #expect(DocstringPropertyCorroborator.corroboration(for: .monotonicity, in: "A monotone score.") != nil)
        #expect(DocstringPropertyCorroborator.corroboration(for: .monotonicity, in: "An order-preserving map.") != nil)
        #expect(DocstringPropertyCorroborator.corroboration(for: .monotonicity, in: "A non-decreasing counter.") != nil)
    }

    @Test("Negation suppresses each binary/projection family")
    func negationGates() {
        #expect(DocstringPropertyCorroborator.corroboration(for: .commutativity, in: "This is not commutative.") == nil)
        #expect(DocstringPropertyCorroborator.corroboration(for: .associativity, in: "A non-associative fold.") == nil)
        let negatedMonotone = "This map is not order-preserving."
        #expect(DocstringPropertyCorroborator.corroboration(for: .monotonicity, in: negatedMonotone) == nil)
    }
}

@Suite("DocstringPropertyCorroborator — behavioral idempotence idioms (+ trap exclusion)")
struct DocstringBehavioralIdiomTests {

    @Test("'insert … if not already present' corroborates idempotence")
    func insertIfNotPresentMatches() {
        let doc = "Inserts the given element in the set if it is not already present."
        let hit = DocstringPropertyCorroborator.corroboration(for: .idempotence, in: doc)
        #expect(hit?.matchedPhrase == "not already present")
    }

    @Test("'if already present, this does nothing' corroborates idempotence")
    func alreadyPresentDoesNothingMatches() {
        let doc = "Marks the bucket occupied. If already present, this does nothing."
        #expect(DocstringPropertyCorroborator.corroboration(for: .idempotence, in: doc) != nil)
    }

    // The precision proof: the bare behavioral phrases swift-collections uses to
    // document index-limit and mutation behaviour must NOT corroborate — they are
    // not idempotence assertions, and matching them would flood false boosts.
    @Test("bare 'has no effect' (index-limit prose) does NOT corroborate")
    func bareNoEffectIsNotIdempotence() {
        let doc = "If `distance < 0`, a limit that is greater than `i` has no effect."
        #expect(DocstringPropertyCorroborator.corroboration(for: .idempotence, in: doc) == nil)
    }

    @Test("'in-place' does NOT corroborate")
    func inPlaceIsNotIdempotence() {
        let doc = "Sorts the elements of the collection in-place."
        #expect(DocstringPropertyCorroborator.corroboration(for: .idempotence, in: doc) == nil)
    }

    @Test("'noop in release builds' (debug-assertion prose) does NOT corroborate")
    func releaseNoopIsNotIdempotence() {
        let doc = "Validates internal invariants. Note that this is a noop in release builds."
        #expect(DocstringPropertyCorroborator.corroboration(for: .idempotence, in: doc) == nil)
    }

    @Test("degenerate 'same index … has no effect' does NOT corroborate")
    func degenerateArgumentNoEffectIsNotIdempotence() {
        let doc = "Exchanges the values at the given indices. Passing the same index as both `i` and `j` has no effect."
        #expect(DocstringPropertyCorroborator.corroboration(for: .idempotence, in: doc) == nil)
    }
}
