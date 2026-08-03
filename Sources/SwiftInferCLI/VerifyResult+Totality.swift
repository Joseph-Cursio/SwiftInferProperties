import Foundation
import SwiftInferCore

/// The trap branch: recovering a **totality** counterexample from a run that died.
///
/// Split out of `VerifyResult.swift` when that file crossed SwiftLint's 400-line cap. The seam is
/// natural — every other rule in `parse` decodes markers from a run that *finished*, and this one
/// alone reconstructs a verdict from a run that did not.
extension VerifyResultParser {

    /// A trap that the **totality** law was hunting — a refutation, not an instrument failure.
    ///
    /// Every other verifiable law fails by assertion, so a trap in one of them means the generator
    /// drove the code somewhere the law was never evaluated: evidence about the domain, not about
    /// the property. `trapReason` says exactly that, and it is right for those twelve.
    ///
    /// The `predicate` law inverts it. Totality *is* "does not trap", so a trap is the counterexample
    /// — and reporting it as `.error` would file this composer's only real finding in the same bucket
    /// as a broken build. `composePredicatePass` prints the input before each call precisely so the
    /// last one survives; this reads it back.
    ///
    /// **Gated on the marker, not on the template.** `parse` is given no template, and threading one
    /// in to reach a single branch would couple the shared verdict decoder to the catalog. The
    /// marker is emitted by exactly one composer, so its presence is the same fact — and a stub that
    /// does not hunt traps cannot accidentally claim one.
    ///
    /// **And gated on the CARRIER, which is the narrower and more important condition.** A trap only
    /// refutes totality when the generated value was one the type genuinely admits. On an `Int` it
    /// was: the function was handed a number and `Int` has no invariants beyond being one. On a
    /// memberwise-derived struct it usually was not — the generator assembles a value no code path
    /// could construct, so the trap says the generator left the domain, which is exactly what
    /// `trapReason` already says and why non-scalars fall through to it.
    ///
    /// This branch first shipped without the carrier gate and the first live run showed the cost:
    /// `isWorthSurfacingBelowCut` reported a refutation on a `Suggestion` with
    /// `score.total: 2524929203861660948` and a negative source column. A structurally impossible
    /// value, reported as a finding. The carrier is printed by the stub rather than threaded in,
    /// so this decoder still learns everything it knows from markers.
    ///
    /// `inverseResult` carries the runtime's own message when it reached stderr, because "which
    /// trap" is the first thing a reader asks and the generic reason string would otherwise be the
    /// only place it appeared.
    static func totalityRefutation(
        from output: VerifierSubprocess.Output,
        lines: [String]
    ) -> VerifyOutcome? {
        guard trapReason(from: output) != nil,
              let input = value(forMarker: "VERIFY_TRIAL_INPUT:", in: lines),
              let carrier = value(forMarker: "VERIFY_TRIAL_CARRIER:", in: lines),
              FixedWidthIntegerNames.domainCompleteScalars.contains(carrier)
        else { return nil }

        let trial = Int(value(forMarker: "VERIFY_TRIAL_INDEX:", in: lines) ?? "") ?? -1
        let runtimeMessage = output.stderr
            .split(separator: "\n")
            .first { $0.contains("Swift runtime failure") || $0.contains("Fatal error") }
            .map { $0.trimmingCharacters(in: .whitespaces) }
        return .defaultFails(
            trial: trial,
            input: input,
            forwardResult: "trapped",
            inverseResult: runtimeMessage ?? "(runtime message not captured)",
            shrunk: nil,
            shrinkSteps: 0
        )
    }
}
