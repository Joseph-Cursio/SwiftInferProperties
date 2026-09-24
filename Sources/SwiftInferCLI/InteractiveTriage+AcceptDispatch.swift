import Foundation
import PropertyLawCore
import SwiftInferCore
import SwiftInferTemplates

/// Which arm writes a suggestion's stub.
///
/// Extracted from `InteractiveTriage+Accept.swift` when it reached SwiftLint's 400-line
/// cap. Dispatch is a seam of its own: the arms live in their own files already, and this is the
/// switch that chooses between them.
extension InteractiveTriage {

    /// ⚠ **Reaching `default` is a GAP, not a design.** This said *"every shipped template has a
    /// stub arm — `default` is a defensive fallback"* until the corpus funnel census measured it
    /// as the path taken by 244 refutable suggestions (#468). Several arms have landed since, so
    /// that count is history, not the gap.
    ///
    /// **The gap is a list, and it lives in `StubWriterCoverageTests.noWriterYet`** (#479): every
    /// template something emits and no arm here writes, each with its measured size. That suite
    /// fails when a new template joins the gap unlisted, and when an arm is written without its
    /// entry being removed — so add the arm, then delete the entry, and the test says when both
    /// are done.
    ///
    /// `customGenerator` derives a generator expression for a custom type name
    /// (from the project's parsed type shapes); it's currently wired into the
    /// determinism path — the lint → infer pipeline's output — so a seeded
    /// function over a custom struct/enum compiles drop-in. The signature-pattern
    /// stubs still use the `Type.gen()` fallback (a fast-follow).
    static func liftedTestStub(
        for suggestion: Suggestion,
        customGenerator: ((String) -> String?)? = nil,
        receiverExpression: ((String) -> String?)? = nil
    ) -> String? {
        // M5.5 — lifted-only fast path for countInvariance + reduce-
        // Equivalence: emit what the test body actually claimed rather
        // than the stronger algebraic shape. Production-side suggestions
        // (no `liftedOrigin`) continue through the existing switch.
        if let liftedOnly = liftedOnlyTestStub(for: suggestion, customGenerator: customGenerator) {
            return liftedOnly
        }
        // Determinism is the seed-driven generic law (not a signature template),
        // so it dispatches ahead of the template switch.
        if suggestion.templateName == "determinism" {
            return deterministicStub(for: suggestion, customGenerator: customGenerator)
        }
        return templateStub(
            for: suggestion,
            customGenerator: customGenerator,
            receiverExpression: receiverExpression
        )
    }

    /// Dispatches a signature-pattern template suggestion to its stub emitter.
    static func templateStub(
        for suggestion: Suggestion,
        customGenerator: ((String) -> String?)? = nil,
        receiverExpression: ((String) -> String?)? = nil
    ) -> String? {
        // The role-entailed arms are consulted first and live in their own file. Keeping them out
        // of this switch is what holds it under SwiftLint's cyclomatic ceiling, and it groups the
        // laws a correct implementation cannot fail rather than scattering them among the
        // conjectures.
        if let entailed = entailedTemplateStub(
            for: suggestion,
            customGenerator: customGenerator,
            receiverExpression: receiverExpression
        ) {
            return entailed
        }
        if let law = entailedLawStub(for: suggestion, customGenerator: customGenerator) { return law }
        let algebraic = algebraicTemplateStub(for: suggestion, customGenerator: customGenerator)
        if let algebraic { return algebraic }
        // ⚠ **These arms dropped `customGenerator` and so could derive nothing.** Measured over
        // seven repositories: templates reached through a threading call site derive project
        // types (`predicate` 40), those reached through one that did not derive **zero**
        // (`idempotence` 0 of 42). It also left their `.todo` markers unexplainable, since a
        // reason needs the same closure — `generator-blocker-reasons.md`.
        switch suggestion.templateName {
        case "idempotence":
            return idempotentStub(for: suggestion, customGenerator: customGenerator)

        case "replay-idempotence":
            // No closure: this arm emits a scaffold rather than a generated value, so it has
            // nothing to derive. Threading it here would be an unused parameter, not a fix.
            return replayIdempotentStub(for: suggestion)

        case "round-trip":
            return roundTripStub(for: suggestion, customGenerator: customGenerator)

        case "monotonicity":
            return monotonicStub(for: suggestion, customGenerator: customGenerator)

        case "invariant-preservation":
            return invariantPreservingStub(for: suggestion, customGenerator: customGenerator)

        default:
            return nil
        }
    }
}
