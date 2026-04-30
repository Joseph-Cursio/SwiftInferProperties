import Testing
@testable import SwiftInferCore

@Suite("SuggestionRenderer — byte-stable output for the §4.5 block")
struct SuggestionRendererTests {

    @Test("Empty suggestion list renders the zero-suggestions sentinel")
    func emptyList() {
        #expect(SuggestionRenderer.render([]) == "0 suggestions.")
    }

    @Test("Singular vs plural count header")
    func headerPlurality() {
        let suggestion = makeStrongSuggestion()
        let single = SuggestionRenderer.render([suggestion])
        let multiple = SuggestionRenderer.render([suggestion, suggestion])
        #expect(single.hasPrefix("1 suggestion.\n\n"))
        #expect(multiple.hasPrefix("2 suggestions.\n\n"))
    }

    @Test("Strong suggestion renders byte-for-byte against the golden")
    func strongSuggestionGolden() {
        let suggestion = makeStrongSuggestion()
        // Identity is the SHA256-derived display of canonical input
        // "renderer-golden-fixed", precomputed so the golden stays stable.
        let expected = """
[Suggestion]
Template: idempotence
Score:    90 (Strong)

Why suggested:
  ✓ normalize(_:) (String) -> String — Sanitizer.swift:7
  ✓ Type-symmetry signature: T -> T (T = String) (+30)
  ✓ Curated idempotence verb match: 'normalize' (+40)
  ✓ Self-composition detected in body: normalize(normalize(x)) (+20)

Why this might be wrong:
  ⚠ T must conform to Equatable for the emitted property to compile.

Generator: not yet computed (M3 prerequisite)
Sampling:  not run (M4 deferred)
Identity:  0x95BF4EDE0EEDECD6
Suppress:  // swiftinfer: skip 0x95BF4EDE0EEDECD6
"""
        #expect(SuggestionRenderer.render(suggestion) == expected)
    }

    @Test("Empty caveats render the explicit no-known-caveats line")
    func emptyCaveatsRenderExplicitLine() {
        let suggestion = Suggestion(
            templateName: "idempotence",
            evidence: [],
            score: Score(signals: [
                Signal(kind: .typeSymmetrySignature, weight: 30, detail: "T -> T"),
                Signal(kind: .exactNameMatch, weight: 40, detail: "normalize"),
                Signal(kind: .selfComposition, weight: 20, detail: "comp")
            ]),
            generator: .m1Placeholder,
            explainability: ExplainabilityBlock(
                whySuggested: ["evidence row", "Type-symmetry (+30)"],
                whyMightBeWrong: []
            ),
            identity: SuggestionIdentity(canonicalInput: "test|empty-caveats")
        )
        let rendered = SuggestionRenderer.render(suggestion)
        #expect(rendered.contains("  ✓ no known caveats for this template"))
    }

    @Test("M1 placeholder generator + sampling render the deferral footer")
    func m1PlaceholderFooter() {
        let suggestion = makeStrongSuggestion()
        let rendered = SuggestionRenderer.render(suggestion)
        #expect(rendered.contains("Generator: not yet computed (M3 prerequisite)"))
        #expect(rendered.contains("Sampling:  not run (M4 deferred)"))
    }

    @Test("Sampling.passed renders the trial count")
    func samplingPassedFooter() {
        let suggestion = Suggestion(
            templateName: "idempotence",
            evidence: [],
            score: Score(signals: [
                Signal(kind: .typeSymmetrySignature, weight: 30, detail: "T -> T")
            ]),
            generator: GeneratorMetadata(
                source: .derivedMemberwise,
                confidence: .high,
                sampling: .passed(trials: 25)
            ),
            explainability: ExplainabilityBlock(whySuggested: [], whyMightBeWrong: []),
            identity: SuggestionIdentity(canonicalInput: "test|sampling-passed")
        )
        let rendered = SuggestionRenderer.render(suggestion)
        #expect(rendered.contains("Generator: .derivedMemberwise, confidence: .high"))
        #expect(rendered.contains("Sampling:  25/25 passed"))
    }

    @Test("Identity + Suppress lines always appear in the footer")
    func identityFooter() {
        let suggestion = makeStrongSuggestion()
        let rendered = SuggestionRenderer.render(suggestion)
        #expect(rendered.contains("Identity:  0x"))
        #expect(rendered.contains("Suppress:  // swiftinfer: skip 0x"))
    }

    private func makeStrongSuggestion() -> Suggestion {
        Suggestion(
            templateName: "idempotence",
            evidence: [
                Evidence(
                    displayName: "normalize(_:)",
                    signature: "(String) -> String",
                    location: SourceLocation(file: "Sanitizer.swift", line: 7, column: 1)
                )
            ],
            score: Score(signals: [
                Signal(kind: .typeSymmetrySignature, weight: 30, detail: "T -> T"),
                Signal(kind: .exactNameMatch, weight: 40, detail: "normalize"),
                Signal(kind: .selfComposition, weight: 20, detail: "comp")
            ]),
            generator: .m1Placeholder,
            explainability: ExplainabilityBlock(
                whySuggested: [
                    "normalize(_:) (String) -> String — Sanitizer.swift:7",
                    "Type-symmetry signature: T -> T (T = String) (+30)",
                    "Curated idempotence verb match: 'normalize' (+40)",
                    "Self-composition detected in body: normalize(normalize(x)) (+20)"
                ],
                whyMightBeWrong: [
                    "T must conform to Equatable for the emitted property to compile."
                ]
            ),
            identity: SuggestionIdentity(canonicalInput: "renderer-golden-fixed")
        )
    }
}
