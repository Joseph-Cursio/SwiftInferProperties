import Foundation
@testable import SwiftInferCore
import Testing

/// A law read out of a test whose subject the scan never declared survives the seed focus
/// (issue #240).
///
/// A lifted suggestion records `location` as the literal placeholder `<test-body>:0`, so the
/// focus's `(file basename, symbol)` join can never match one — **every** lifted row is
/// dropped by any non-empty manifest, whatever its subject. Measured: a Strong-tier
/// `normalized(_:)` idempotence law, lifted from a property suite, vanished from a seeded
/// run with nothing said, while the role-entailed rescue beside it announced itself.
///
/// The exemption is per row, not per template, because liftedness is not a property of the
/// template — `idempotence` arises from source and from test bodies alike.
///
/// **The discriminating arm is `liftedSubjectTheScanDeclaresStaysFocused`.** Exempting
/// liftedness alone would be wrong in the other direction: a law lifted from
/// `#expect(mySort(input) == input.sorted())` names a production subject the manifest can and
/// should carry, and `SeedFocus`'s standing rule sends that case to the linter. Without that
/// arm, the blanket version passes every other test here.
@Suite("SeedFocus — lifted laws the manifest could never name")
struct SeedFocusLiftedExemptionTests {

    private func suggestion(subject: String, lifted: Bool) -> Suggestion {
        Suggestion(
            templateName: "idempotence",
            evidence: [
                Evidence(
                    displayName: subject,
                    signature: "(String) -> String",
                    // The placeholder a lifted row really carries. Deliberately used for both
                    // arms: it is the join failure, and it is identical whether or not the
                    // subject is production code — which is why the file cannot discriminate.
                    location: SourceLocation(
                        file: lifted ? "<test-body>" : "Config.swift", line: lifted ? 0 : 12, column: 1
                    )
                )
            ],
            score: Score(signals: []),
            generator: GeneratorMetadata(source: .notYetComputed, confidence: nil, sampling: .notRun),
            explainability: ExplainabilityBlock(whySuggested: [], whyMightBeWrong: []),
            identity: SuggestionIdentity(canonicalInput: "idempotence|\(subject)|\(lifted)"),
            liftedOrigin: lifted
                ? LiftedOrigin(
                    testMethodName: "aProperty",
                    sourceLocation: SourceLocation(file: "SomeTests.swift", line: 1, column: 1)
                )
                : nil
        )
    }

    /// A manifest that names something real, so the focus is active.
    private var manifest: SeedManifest {
        SeedManifest(seeds: [
            SeedManifest.Seed(
                file: "Config.swift", line: 12, symbol: "parse",
                rule: "Pure Function Property-Test Candidate", kind: .pureFunction
            )
        ])
    }

    @Test("a lifted law whose subject the scan never declared is kept")
    func unseedableLiftedSurvives() {
        let kept = SeedFocus.filter(
            [suggestion(subject: "normalized(_:)", lifted: true)],
            to: manifest,
            declaredSubjects: ["parse", "serialized"]
        )
        #expect(kept.count == 1)
    }

    @Test("a lifted law whose subject the scan DOES declare stays focused")
    func liftedSubjectTheScanDeclaresStaysFocused() {
        // The arm that separates this fix from exempting liftedness wholesale. `mySort` is
        // production code the manifest can name; that it went unseeded is a linter gap, and
        // `SeedFocus`'s own rule says the fix belongs there rather than here.
        let kept = SeedFocus.filter(
            [suggestion(subject: "mySort(_:)", lifted: true)],
            to: manifest,
            declaredSubjects: ["parse", "mySort"]
        )
        #expect(kept.isEmpty)
    }

    @Test("a non-lifted law is unaffected — the exemption is not a general escape hatch")
    func sourceRowStillFocused() {
        let kept = SeedFocus.filter(
            [suggestion(subject: "unseeded(_:)", lifted: false)],
            to: manifest,
            declaredSubjects: ["parse"]
        )
        #expect(kept.isEmpty)
    }

    @Test("with no declarations supplied, nothing is exempt")
    func absentDeclarationsExemptNothing() {
        // The conservative fallback. An empty set means the caller did not answer the
        // question; reading that as "the scan declares nothing, so every lifted row is
        // unnameable" would exempt them all on no evidence — the blanket version arriving
        // through a defaulted argument.
        let kept = SeedFocus.filter(
            [suggestion(subject: "normalized(_:)", lifted: true)],
            to: manifest,
            declaredSubjects: []
        )
        #expect(kept.isEmpty)
    }

    @Test("an empty manifest still does not focus, exemption or not")
    func emptyManifestUnchanged() {
        let kept = SeedFocus.filter(
            [suggestion(subject: "normalized(_:)", lifted: true)],
            to: SeedManifest(seeds: []),
            declaredSubjects: ["parse"]
        )
        #expect(kept.count == 1)
    }

    @Test("the kept rows are reportable, so the CLI can say why they survived")
    func rescuedRowsAreEnumerable() {
        let rows = [
            suggestion(subject: "normalized(_:)", lifted: true),
            suggestion(subject: "mySort(_:)", lifted: true)
        ]
        let rescued = SeedFocus.unseedableLifted(in: rows, declaredSubjects: ["mySort"])
        #expect(rescued.count == 1)
        #expect(rescued.first?.evidence.first?.displayName == "normalized(_:)")
    }
}
