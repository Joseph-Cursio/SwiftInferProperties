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
