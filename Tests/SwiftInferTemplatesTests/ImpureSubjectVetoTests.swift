import Foundation
import SwiftEffectInference
import Testing

@testable import SwiftInferCore
@testable import SwiftInferTemplates

/// **The impure-subject veto — that it fires, that it fires only where it should, and that
/// it says why.**
///
/// Scope and cost were measured before the veto shipped
/// (`docs/measurements/purity-veto-precision.md`): 0 laws that found a counterexample
/// removed at either scope, 10 passing laws removed by a naive `.refuted` veto against 2
/// by the witness-scoped one. This suite guards the rule that measurement chose.
///
/// ## The negative case is the load-bearing one
///
/// A veto that fires on every `.refuted` subject would remove `encode(to:)` under
/// `codable-round-trip` — the one template measured at 100% yield — because it throws and
/// propagates a `try`. `propagatedTry` is the analyzer failing to see past a `try`, not
/// evidence of an impurity. ``throwingSubjectIsNotVetoed()`` is what stops that
/// regression, and it would pass just as well if the veto never fired at all — which is
/// why ``markerSubjectIsVetoed()`` runs beside it as the positive control.
@Suite("Veto — a law is withheld when its subject is impure with a witness")
struct ImpureSubjectVetoTests {

    /// A `.pure` subject, so nothing here is vetoed for its own sake.
    static func summary(
        name: String,
        line: Int,
        verdict: PurityVerdict = .pure,
        isThrows: Bool = false,
        calls: [String] = [],
        analysed: Bool = true
    ) -> FunctionSummary {
        FunctionSummary(
            name: name,
            parameters: [],
            returnTypeText: "Bool",
            isThrows: isThrows,
            isAsync: false,
            isMutating: false,
            isStatic: false,
            location: SourceLocation(file: "F.swift", line: line, column: 1),
            containingTypeName: "Carrier",
            bodySignals: .empty,
            isInferredPure: verdict == .pure,
            purityVerdict: verdict,
            bodyFingerprint: analysed ? "FEEDFACE" : nil,
            calledFreeFunctionNames: calls
        )
    }

    /// A suggestion whose single evidence row points at `subject`.
    static func suggestion(on subject: FunctionSummary) -> Suggestion {
        Suggestion(
            templateName: "predicate",
            evidence: [
                Evidence(
                    displayName: subject.name,
                    signature: "() -> Bool",
                    location: subject.location
                )
            ],
            score: Score(signals: [Signal(kind: .predicateSignature, weight: 30, detail: "predicate shape")]),
            generator: GeneratorMetadata(source: .derivedComposite, confidence: .high, sampling: .notRun),
            explainability: ExplainabilityBlock(whySuggested: ["predicate shape (+30)"], whyMightBeWrong: []),
            identity: SuggestionIdentity(canonicalInput: "predicate::\(subject.name)")
        )
    }

    static func apply(_ subject: FunctionSummary) -> Suggestion {
        TemplateRegistry.applyImpureSubjectVeto(to: [suggestion(on: subject)], summaries: [subject])[0]
    }

    // MARK: - Positive

    @Test("a marker-refuted subject is vetoed, and the tier collapses")
    func markerSubjectIsVetoed() {
        let vetoed = Self.apply(Self.summary(name: "directoryExists", line: 10, verdict: .refuted))

        #expect(vetoed.score.signals.contains { $0.kind == .impureSubject && $0.isVeto })
        #expect(vetoed.score.tier == .suppressed, "a veto must collapse the tier, not merely score against it")
    }

    /// **The veto names the subject.** A withheld law that cannot say why is the failure
    /// this repo files under *a vocabulary nobody reads* — and `Signal.formattedLine`
    /// carries it into `whyMightBeWrong` rather than dropping the row silently.
    @Test("the veto renders its reason, naming the subject")
    func theVetoSaysWhy() {
        let vetoed = Self.apply(Self.summary(name: "directoryExists", line: 10, verdict: .refuted))
        let caveats = vetoed.explainability.whyMightBeWrong

        #expect(caveats.contains { $0.contains("directoryExists") }, "the caveat does not name the subject")
        #expect(caveats.contains { $0.hasSuffix("(veto)") }, "the caveat does not mark itself a veto")
    }

    /// A throwing subject whose body reaches a settled-impure name carries a witness one
    /// hop away, which is the join's rule and therefore the veto's.
    @Test("a throwing subject that reaches a settled-impure callee is vetoed")
    func joinedSubjectIsVetoed() {
        let callee = Self.summary(name: "spawn", line: 5, verdict: .refuted)
        let caller = Self.summary(
            name: "drain", line: 20, verdict: .refuted, isThrows: true, calls: ["spawn"]
        )
        let vetoed = TemplateRegistry.applyImpureSubjectVeto(
            to: [Self.suggestion(on: caller)], summaries: [callee, caller]
        )[0]

        #expect(vetoed.score.signals.contains { $0.kind == .impureSubject })
    }

    // MARK: - Negative

    /// **The regression this veto's scope exists to avoid.** `encode(to:)` throws because
    /// `Encoder` throws; `propagatedTry` is ignorance, not evidence.
    @Test("a throwing subject refuted only by a propagated try is NOT vetoed")
    func throwingSubjectIsNotVetoed() {
        let subject = Self.summary(name: "encode", line: 30, verdict: .refuted, isThrows: true)
        let kept = Self.apply(subject)

        #expect(!kept.score.signals.contains { $0.kind == .impureSubject }, """
        A subject refuted only by `propagatedTry` was vetoed. On this repo that removes 8 \
        `encode(to:)` laws under `codable-round-trip`, the one template measured at 100% \
        yield — see `docs/measurements/purity-veto-precision.md`.
        """)
        #expect(kept.score.tier != .suppressed)
    }

    @Test("a pure subject is untouched")
    func pureSubjectIsUntouched() {
        let kept = Self.apply(Self.summary(name: "normalize", line: 40))

        #expect(!kept.score.signals.contains { $0.kind == .impureSubject })
        #expect(kept.score.signals.count == 1, "the veto pass altered a suggestion it should not have")
    }
}

extension ImpureSubjectVetoTests {

    /// **`.refuted` is `FunctionSummary.init`'s default**, so on a summary nothing analysed
    /// it means *not computed*. Reading that as evidence is item 40's finding — a verdict
    /// that is an initialiser default — arriving at a consumer instead of an advisory.
    ///
    /// **Watched failing.** Before the body-fingerprint gate existed, this veto suppressed
    /// six unrelated suites whose fixtures build summaries by hand: monotonicity
    /// cross-validation, the counter-signal seam, `value-round-trip` end-to-end,
    /// associativity corpus aggregation, `normalize(_:)` at Likely, and the `encode/decode`
    /// pair. Every one of them passes a hand-built summary to `TemplateRegistry.discover`.
    @Test("a defaulted verdict is not evidence — an unanalysed summary is never vetoed")
    func defaultedVerdictIsNotEvidence() {
        let handBuilt = Self.summary(name: "combine", line: 50, verdict: .refuted, analysed: false)
        let kept = Self.apply(handBuilt)

        #expect(!kept.score.signals.contains { $0.kind == .impureSubject }, """
        A summary with no body fingerprint was vetoed. `.refuted` is the initialiser \
        default, so that reads "nobody computed a verdict" as "the verdict is refuted" — \
        and it suppresses every hand-built fixture in the suite.
        """)
        #expect(kept.score.tier != .suppressed)
    }
}
