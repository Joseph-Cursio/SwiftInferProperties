import SwiftInferCore
import Testing

/// A docstring **about** a property is not a docstring **claiming** it.
///
/// The negation gate already handled one way prose lies to a substring matcher — *"this is
/// not idempotent"*. This is the other: *"emits the round-trip stub"*. Both are the same
/// class of error, where the phrase is present and means something other than a claim.
///
/// **Measured on this repo, which is the worst case for it.** SwiftInferProperties generates
/// property tests, so "round-trip" appears throughout its prose as subject matter: **327 of
/// 438** `round-trip` suggestions on the private-function population were corroborated at
/// +15 by docstrings like `codableRoundTripGenerator`'s, which describes *emitting* a
/// round-trip test rather than being one. 147 matched `'round-trip'`, 91 `'roundtrip'`,
/// 89 `'round trip'`.
///
/// The gate is deliberately blunt — it rejects the whole docstring rather than reasoning
/// about which sentence the phrase sits in — and the bluntness is the safe direction.
/// Corroboration is by construction never the reason a law surfaces, only a tier raise, so
/// withholding it can lower confidence but never hide a candidate.
@Suite("Docstring corroboration — subject matter is not a claim")
struct DocstringSubjectMatterGateTests {

    // MARK: - Rejected: prose about generating or checking the property

    @Test("a docstring about EMITTING the property does not corroborate", arguments: [
        "Emits the round-trip stub for the given carrier.",
        "Renders a round-trip test body.",
        "The generator used by the round-trip template.",
        "Builds the harness that checks this round trip.",
        "Scaffold for a roundtrip property test.",
        "The verifier for round-trip laws."
    ])
    func subjectMatterProseDoesNotCorroborate(docComment: String) {
        #expect(
            DocstringPropertyCorroborator.corroboration(for: .roundTrip, in: docComment) == nil,
            "prose about the property must not read as a claim: \(docComment)"
        )
    }

    /// The real docstring from this repo that produced the measurement.
    @Test("the measured real case — codableRoundTripGenerator — does not corroborate")
    func measuredRealCaseDoesNotCorroborate() {
        let real = """
        The body uses `Foundation.JSONEncoder` / `JSONDecoder`; the writeout wrapper widens
        its imports list to include `Foundation` for this source so the rendered stub
        compiles.
        """
        #expect(DocstringPropertyCorroborator.corroboration(for: .roundTrip, in: real) == nil)
    }

    @Test("the gate applies to every property, not just round-trip", arguments: [
        DocstringPropertyCorroborator.Property.idempotence,
        .involution,
        .commutativity,
        .associativity,
        .roundTrip,
        .monotonicity
    ])
    func gateAppliesToEveryProperty(property: DocstringPropertyCorroborator.Property) {
        // One docstring naming every vocabulary at once, in emitter prose. Whatever the
        // property, the answer is "this is a template, not a claim".
        let prose = """
        Emits the stub asserting the function is idempotent, self-inverse, commutative,
        associative, a round-trip, and monotonic.
        """
        #expect(DocstringPropertyCorroborator.corroboration(for: property, in: prose) == nil)
    }

    // MARK: - Still accepted: prose that actually claims the property

    @Test("a genuine claim still corroborates")
    func genuineClaimStillCorroborates() throws {
        let claim = "Normalising an already-normalised path is idempotent."
        let result = try #require(
            DocstringPropertyCorroborator.corroboration(for: .idempotence, in: claim)
        )
        #expect(result.matchedPhrase == "idempotent")
    }

    @Test("the negation gate is unaffected — it was already right")
    func negationGateStillWorks() {
        let denial = "This is not idempotent: each call appends another suffix."
        #expect(DocstringPropertyCorroborator.corroboration(for: .idempotence, in: denial) == nil)
    }

    @Test("nil and empty docstrings are unchanged")
    func nilAndEmptyUnchanged() {
        #expect(DocstringPropertyCorroborator.corroboration(for: .roundTrip, in: nil) == nil)
        #expect(DocstringPropertyCorroborator.corroboration(for: .roundTrip, in: "") == nil)
    }

    // MARK: - The cost, stated rather than hidden

    /// The blunt gate has a price and it should be visible in a test rather than discovered:
    /// a genuine claim whose docstring merely *mentions* one of the markers loses its +15.
    /// That costs a tier on a candidate the shape already matched, which is recoverable —
    /// against a false law, which the catalog rates worse than proposing nothing.
    @Test("a genuine claim that also mentions a marker word loses corroboration — known cost")
    func knownFalseNegative() {
        let mixed = "Idempotent. See the template in Docs for the emitted stub."
        #expect(DocstringPropertyCorroborator.corroboration(for: .idempotence, in: mixed) == nil)
    }
}
