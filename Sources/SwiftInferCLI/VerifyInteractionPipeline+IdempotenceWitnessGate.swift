import Foundation
import SwiftInferCore

/// Idempotence payload-bearing-witness constructibility gate — sibling to the
/// cycle-139 refint Identifiable gate. A payload-bearing idempotence witness
/// (`case select(Int)`) has its payload synthesized (`.select(0)`, x-curried);
/// but when the payload type isn't cheaply defaultable (`case select(Item)` /
/// `setColor(Color)`) the emitter falls back to the bare `.select`, which fails
/// to `swift build` and surfaces as `architectural-coverage-pending` only
/// *after* a wasted (~minute-long, cold-TCA) build. This gate detects that case
/// **before** building and returns a clean, disclosed skip.
///
/// Conservative, mirroring the refint gate: it skips only when the witness is
/// *positively* payload-bearing with a non-constructible payload (the case is
/// found in the scanned Action alphabet with a non-defaultable parameter). An
/// unknown / unscannable alphabet → the build proceeds (no regression), and a
/// constructible or payload-free witness → the build proceeds (it verifies).
extension VerifyInteractionPipeline {

    /// Apply the gate: when it fires, record the disclosed skip (if persisting)
    /// and return it so the caller short-circuits before the build; otherwise
    /// `nil` so the caller proceeds. Mirrors `applyRefintIdentifiabilityGate`.
    static func applyIdempotenceWitnessConstructibilityGate(
        invariant: InteractionInvariantSuggestion,
        candidate: ReducerCandidate,
        target: String,
        persistEvidence: Bool,
        workingDirectory: URL
    ) -> InteractionVerifyOutcomeParser.Result? {
        guard let skip = idempotenceWitnessConstructibilitySkip(
            invariant: invariant, candidate: candidate,
            target: target, workingDirectory: workingDirectory
        ) else { return nil }
        if persistEvidence {
            recordEvidence(invariant: invariant, result: skip, workingDirectory: workingDirectory)
        }
        return skip
    }

    /// Returns a pre-build `architectural-coverage-pending` skip when the
    /// idempotence witness is payload-bearing with a non-constructible payload;
    /// `nil` for non-idempotence invariants, payload-free / constructible
    /// witnesses, or an unknown alphabet (the build proceeds).
    static func idempotenceWitnessConstructibilitySkip(
        invariant: InteractionInvariantSuggestion,
        candidate: ReducerCandidate,
        target: String,
        workingDirectory: URL
    ) -> InteractionVerifyOutcomeParser.Result? {
        guard invariant.family == .idempotence, invariant.predicate.hasPrefix(".") else {
            return nil
        }
        let caseName = String(invariant.predicate.dropFirst())
        let sourcesDir = workingDirectory
            .appendingPathComponent("Sources")
            .appendingPathComponent(target)
        let alphabet = ActionAlphabetScanner.scan(
            directory: sourcesDir,
            actionTypeName: candidate.actionTypeName
        )
        // Unknown case (external / unscannable) or payload-free / constructible
        // → let the build proceed (matches the refint gate's `.unknown` posture).
        guard let spec = alphabet.first(where: { $0.name == caseName }),
              !spec.isPayloadFree,
              spec.constructibleExpression() == nil else {
            return nil
        }
        let payload = spec.parameters.map(\.type).joined(separator: ", ")
        return InteractionVerifyOutcomeParser.Result(
            outcome: .architecturalCoveragePending,
            detail: "idempotence verify skipped: witness `.\(caseName)` has a non-constructible "
                + "payload (\(payload)) — the verifier can't synthesize a value to apply it twice"
        )
    }
}
