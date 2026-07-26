import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

/// The conformance-caveat filter — drops "T must conform to Equatable" where the corpus proves the
/// carrier conforms, and keeps it everywhere the question is open.
///
/// The caveat is emitted by fifteen templates. It is right for a type the scan never saw declare a
/// conformance and noise when the suggestion has already resolved the carrier to `String` in its
/// own signal line. Only `EquatableResolver` can tell those apart, and it needs the corpus — hence
/// a post-pass rather than fifteen edits.
@Suite("Conformance caveat filter")
struct ConformanceCaveatFilterTests {

    private static let conformanceCaveat =
        "T must conform to Equatable for the emitted property to compile. This tool does not "
            + "verify protocol conformance — confirm before applying."
    private static let otherCaveat =
        "If T is a class with a custom ==, the property is over value equality as T.== defines it."

    private func suggestion(
        carrierType: String?,
        caveats: [String] = [conformanceCaveat, otherCaveat]
    ) -> Suggestion {
        let evidence = Evidence(
            displayName: "f(_:)",
            signature: "(String) -> String",
            location: SourceLocation(file: "/a/B.swift", line: 1, column: 1)
        )
        let signal = Signal(kind: .typeSymmetrySignature, weight: 30, detail: "shape")
        return Suggestion(
            templateName: "idempotence",
            evidence: [evidence],
            score: Score(signals: [signal]),
            generator: GeneratorMetadata(source: .derivedComposite, confidence: .high, sampling: .notRun),
            explainability: ExplainabilityBlock(whySuggested: ["why"], whyMightBeWrong: caveats),
            identity: SuggestionIdentity(canonicalInput: "idempotence|f"),
            carrier: nil,
            carrierTypeName: carrierType
        )
    }

    private func filtered(_ input: Suggestion, typeDecls: [TypeDecl] = []) -> [String] {
        ConformanceCaveatFilter.apply(
            to: [input],
            resolver: EquatableResolver(typeDecls: typeDecls),
            carrierTypeByIdentity: [:]
        )[0].explainability.whyMightBeWrong
    }

    private func typeDecl(_ name: String, inherits: [String]) -> TypeDecl {
        TypeDecl(
            name: name,
            kind: .struct,
            inheritedTypes: inherits,
            location: SourceLocation(file: "/a/B.swift", line: 1, column: 1)
        )
    }

    // MARK: - Suppressed where the answer is known

    @Test("a stdlib carrier drops the conformance caveat and keeps the rest")
    func stdlibCarrierSuppresses() {
        let caveats = filtered(suggestion(carrierType: "String"))
        #expect(caveats.contains(Self.conformanceCaveat) == false)
        #expect(caveats.contains(Self.otherCaveat), "unrelated caveats must survive")
    }

    /// The reason a hardcoded stdlib list was thrown away: a project type whose declaration says
    /// `: Hashable` is just as known, and it is the case an adopter meets most.
    @Test("a corpus type declaring Hashable also suppresses")
    func corpusCarrierSuppresses() {
        let caveats = filtered(
            suggestion(carrierType: "Rule"),
            typeDecls: [typeDecl("Rule", inherits: ["Hashable"])]
        )
        #expect(caveats.contains(Self.conformanceCaveat) == false)
    }

    // MARK: - Kept where it is open

    /// `.unknown` keeps the caveat — the whole point of the resolver's three-valued answer.
    @Test("an unproven corpus carrier keeps the caveat")
    func unknownCarrierKeeps() {
        let caveats = filtered(suggestion(carrierType: "Mystery"))
        #expect(caveats.contains(Self.conformanceCaveat))
    }

    /// A carrier the resolver can prove is NOT Equatable keeps it too. Silencing the warning would
    /// be the wrong way to surface a suggestion whose carrier cannot host value equality.
    @Test("a provably non-Equatable carrier keeps the caveat")
    func nonEquatableCarrierKeeps() {
        #expect(filtered(suggestion(carrierType: "(Int) -> Int")).contains(Self.conformanceCaveat))
        #expect(filtered(suggestion(carrierType: "Any")).contains(Self.conformanceCaveat))
    }

    @Test("no resolvable carrier keeps the caveat")
    func missingCarrierKeeps() {
        #expect(filtered(suggestion(carrierType: nil)).contains(Self.conformanceCaveat))
    }

    // MARK: - Only the conformance caveats are touched

    @Test("a suggestion with no conformance caveat is returned unchanged")
    func unrelatedCaveatsUntouched() {
        let caveats = filtered(suggestion(carrierType: "String", caveats: ["something else entirely"]))
        #expect(caveats == ["something else entirely"])
    }

    @Test(
        "each template's phrasing of the caveat is recognised",
        arguments: [
            "T must conform to Equatable for the emitted property to compile.",
            "X must conform to Equatable for the emitted property to compile.",
            "The element type must be Equatable (or Hashable) for the membership check to compile;",
            "The element type must be Hashable for `Set` / `isDisjoint`; this tool does not verify"
        ]
    )
    func everyPhrasingIsRecognised(caveat: String) {
        #expect(ConformanceCaveatFilter.isConformanceCaveat(caveat))
    }

    @Test("an unrelated caveat is not mistaken for a conformance one")
    func unrelatedIsNotMatched() {
        #expect(ConformanceCaveatFilter.isConformanceCaveat("THIS LAW IS A CONJECTURE — read off") == false)
    }
}
