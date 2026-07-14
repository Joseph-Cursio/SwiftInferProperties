import Foundation
import Testing

@testable import SwiftInferCore

/// **A copy of a `Suggestion` must change the field it means to change, and NOTHING ELSE.**
///
/// ## The bug these tests exist to pin
///
/// `Suggestion` was reconstructed argument-by-argument in eight places. Its initialiser has
/// defaulted parameters — `liftedOrigin`, `mockGenerator`, `carrier`, `carrierTypeName`,
/// `generatorRecipes` all default — so a rebuild that **forgot** an argument did not fail to
/// compile. It produced a value that rendered correctly in every visible respect and was quietly
/// missing part of itself.
///
/// It happened three times, and each fix patched the instance and re-armed the trap:
///
/// | when | site | field silently lost |
/// |---|---|---|
/// | V1.151 | `GeneratorSelection.rebuild` | `carrierTypeName` — the index/verify path fell back to the owner type |
/// | (later) | `TemplateRegistry+CrossValidation` | `carrier`, `carrierTypeName`, `liftedOrigin`, `mockGenerator` |
/// | now | **all eight sites** | `generatorRecipes` — the partition law reached the reader with no generator |
///
/// The last one is the sharpest: `generatorRecipes` is the half of a law that decides whether it can
/// **fail at all**. A law whose counterexamples live in collisions passes vacuously under a uniform
/// generator, so a suggestion that loses its recipes is a suggestion that has quietly stopped being
/// able to find the bug — while still printing a confident score.
///
/// ## Why these tests are written the way they are
///
/// The obvious test — *"does the copy carry `generatorRecipes`?"* — pins today's field and nothing
/// else. The next field added would be dropped exactly as the last three were, and the suite would
/// stay green.
///
/// So each test instead asserts the **invariant**: take a suggestion with *every* field set to a
/// non-default value, apply the transform, then **undo the one change the transform is allowed to
/// make** — and require the result to equal the original. Any field the copy dropped shows up as an
/// inequality. **A field added in future needs no new test; it is covered the day it is added.**
@Suite("A Suggestion copy loses nothing")
struct SuggestionCopyTests {

    /// Every field set, and every field set to something a default would NOT produce.
    ///
    /// The optionals must be non-`nil` and the arrays non-empty, because the whole failure mode is a
    /// dropped argument silently taking `nil` or `[]`. A fixture that left them at their defaults
    /// would pass against the very bug it is meant to catch.
    private func populated() -> Suggestion {
        Suggestion(
            templateName: "partition",
            evidence: [
                Evidence(
                    displayName: "chunk(of:at:)",
                    signature: "(Data, Int) -> Data",
                    location: SourceLocation(file: "ChunkPlan.swift", line: 12, column: 5)
                )
            ],
            score: Score(signals: [
                Signal(kind: .indexToRangeSignature, weight: 40, detail: "a partition")
            ]),
            generator: GeneratorMetadata(
                source: .derivedMemberwise,
                confidence: .medium,
                sampling: .notRun
            ),
            explainability: ExplainabilityBlock(
                whySuggested: ["it tiles"],
                whyMightBeWrong: ["unless it does not"]
            ),
            identity: SuggestionIdentity(canonicalInput: "partition|ChunkPlan|chunk"),
            liftedOrigin: LiftedOrigin(
                testMethodName: "testChunking",
                sourceLocation: SourceLocation(file: "ChunkPlanTests.swift", line: 3, column: 1)
            ),
            mockGenerator: MockGenerator(
                typeName: "ChunkPlan",
                argumentSpec: [
                    MockGenerator.Argument(
                        label: "byteCount",
                        swiftTypeName: "Int",
                        observedLiterals: ["1024"]
                    )
                ],
                siteCount: 3
            ),
            carrier: "ChunkPlan",
            carrierTypeName: "Data",
            generatorRecipes: [CollisionBias.outOfRangeIndex(subject: "index")]
        )
    }

    // MARK: - The invariant, per transform

    /// `withGenerator` may change `generator`. It may change nothing else.
    ///
    /// This is the transform `GeneratorSelection` performs on **every** suggestion in `discover`, and
    /// the one whose field-by-field rebuild dropped `carrierTypeName` in V1.151 and `generatorRecipes`
    /// today.
    @Test("withGenerator changes the generator and nothing else")
    func withGeneratorLosesNothing() {
        let original = populated()
        let replacement = GeneratorMetadata(
            source: .derivedCodableRoundTrip,
            confidence: .high,
            sampling: .passed(trials: 100)
        )

        var restored = original.withGenerator(replacement)
        #expect(restored.generator == replacement, "the transform must actually do its job")

        // Undo the ONE change it was allowed to make. Everything else must be untouched — and any
        // field a rebuild dropped is now `nil`/`[]` on `restored` and populated on `original`.
        restored.generator = original.generator
        #expect(restored == original)
    }

    /// `withExplainability` may change `explainability`. It may change nothing else.
    @Test("withExplainability changes the explainability and nothing else")
    func withExplainabilityLosesNothing() {
        let original = populated()
        let replacement = ExplainabilityBlock(
            whySuggested: ["a stdlib analog holds"],
            whyMightBeWrong: ["a known trap"]
        )

        var restored = original.withExplainability(replacement)
        #expect(restored.explainability == replacement)

        restored.explainability = original.explainability
        #expect(restored == original)
    }

    /// `withAdditionalSignal` may change `score` and `explainability`. It may change nothing else.
    @Test("withAdditionalSignal changes the score and explainability, and nothing else")
    func withAdditionalSignalLosesNothing() {
        let original = populated()
        let signal = Signal(kind: .verifyBothPass, weight: 15, detail: "verified")
        let explainability = ExplainabilityBlock(
            whySuggested: original.explainability.whySuggested,
            whyMightBeWrong: original.explainability.whyMightBeWrong + [signal.formattedLine]
        )

        var restored = original.withAdditionalSignal(signal, explainability: explainability)
        #expect(restored.score.signals.contains(signal))

        restored.score = original.score
        restored.explainability = original.explainability
        #expect(restored == original)
    }

    // MARK: - The pipeline stage that actually shipped the bug

    /// `VerifyEvidenceScoring` folds a verify outcome into the score of every suggestion in
    /// `discover`. Its rebuild dropped **both** `carrierTypeName` and `generatorRecipes`.
    @Test("the verify-evidence post-pass preserves every other field")
    func verifyEvidenceScoringLosesNothing() {
        let original = populated()
        let evidence = VerifyEvidence(
            identityHash: original.identity.normalized,
            template: original.templateName,
            outcome: .measuredBothPass,
            detail: "property held at execution",
            capturedAt: Date(timeIntervalSince1970: 0),
            swiftInferVersion: "test"
        )

        let graded = VerifyEvidenceScoring.applied(
            to: [original],
            evidenceByIdentity: [original.identity.normalized: evidence]
        )

        guard var restored = graded.first else {
            Issue.record("the pass returned nothing")
            return
        }
        #expect(restored.score.total != original.score.total, "the pass must actually re-grade")

        restored.score = original.score
        restored.explainability = original.explainability
        #expect(restored == original)
    }

    // MARK: - The field whose loss is worst

    /// `generatorRecipes` is not one field among eleven. **It is the half of a law that decides
    /// whether the law can fail at all**: a law whose counterexamples live in collisions passes
    /// vacuously under a uniform generator, so a suggestion that has lost its recipes still prints a
    /// confident score while having quietly stopped being able to find the bug.
    ///
    /// The other fields degrade the output. This one inverts it.
    @Test("a copy that loses the generator recipes is a law that can no longer fail")
    func generatorRecipesSurviveEveryTransform() {
        let original = populated()
        #expect(original.generatorRecipes.isEmpty == false, "the fixture must actually populate them")

        let transformed = [
            original.withGenerator(.m1Placeholder),
            original.withExplainability(ExplainabilityBlock(whySuggested: [], whyMightBeWrong: [])),
            original.withAdditionalSignal(
                Signal(kind: .verifyBothPass, weight: 15, detail: ""),
                explainability: original.explainability
            )
        ]

        for suggestion in transformed {
            #expect(suggestion.generatorRecipes == original.generatorRecipes)
        }
    }
}
