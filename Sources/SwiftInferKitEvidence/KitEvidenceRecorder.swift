import Foundation
import PropertyLawKit
import SwiftInferCore

/// **The cable between PropertyLawKit and `swift-infer`.**
///
/// The toolchain was described as one-way — `discover` proposes, the kit runs, nothing comes
/// back — and `KitEvidence` / `KitEvidenceScoring` / `KitEvidenceStore` were built to close
/// that loop. They closed the *reading* half. Nothing wrote the file:
///
/// - `KitEvidenceStore.write` shipped with **zero callers**, in `Sources` or `Tests`.
/// - No subcommand exported kit results.
/// - PropertyLawKit has never heard of `kit-evidence.json`.
///
/// So the file could only exist if a user hand-authored JSON matching `KitEvidenceLog`'s
/// `Codable` shape — undocumented — while the tool's own diagnostic told them to "export
/// results to `.swiftinfer/kit-evidence.json`", an action with no supported path. The
/// `-45` demotion for a refuted equality oracle had never fired and could not fire.
///
/// This is the missing half. A suite that already calls `checkHashablePropertyLaws` has
/// `[CheckResult]` in hand; one call persists it.
///
/// ```swift
/// let results = try await checkHashablePropertyLaws(for: Money.self, using: gen)
/// try KitEvidenceRecorder.record(results, for: "Money", packageRoot: packageRoot)
/// ```
///
/// ## Why a separate target
///
/// `SwiftInferCore` deliberately takes no `PropertyLawKit` dependency — `KitLawOutcome`
/// spells its outcome and tier as `String`-backed enums precisely so Core stays kit-free,
/// and the CLI executable should not pull the kit's transitive swift-testing footprint
/// either. Isolating the adapter in a leaf library keeps both properties and gives a user's
/// test target one honest import.
public enum KitEvidenceRecorder {

    /// Translate the kit's results into the shape inference reads.
    ///
    /// - Parameter typeName: the carrier, generics stripped — `"Box"`, not `"Box<Int>"`.
    ///   `KitEvidenceScoring` keys on the bare name, so a generic spelling here would simply
    ///   never match a suggestion.
    public static func outcomes(
        from results: [CheckResult],
        for typeName: String
    ) -> [KitLawOutcome] {
        results.map { result in
            KitLawOutcome(
                typeName: typeName,
                law: canonicalLawName(result.protocolLaw),
                outcome: outcome(from: result.outcome),
                tier: tier(from: result.tier),
                counterexample: counterexample(from: result.outcome)
            )
        }
    }

    /// Persist results for one carrier, merged with whatever is already recorded.
    ///
    /// Merging rather than replacing, because a project checks several types across several
    /// suites and each call sees only its own. Replacing would make the last suite to run the
    /// only one on record — and the failure would be silent, since a *smaller* evidence log
    /// still reads as valid and simply demotes fewer things.
    ///
    /// Entries for `typeName` are replaced wholesale: a re-run of the same suite is the
    /// current truth about that carrier, so stale outcomes from a previous run must not
    /// survive alongside it.
    public static func record(
        _ results: [CheckResult],
        for typeName: String,
        packageRoot: URL
    ) throws {
        let url = packageRoot.appendingPathComponent(KitEvidenceStore.conventionalRelativePath)
        let existing = KitEvidenceStore.load(startingFrom: packageRoot)
        let kept = existing.outcomes.filter { $0.typeName != typeName }
        let merged = KitEvidenceLog(outcomes: kept + outcomes(from: results, for: typeName))
        try KitEvidenceStore.write(merged, to: url)
    }

    // MARK: - Translation

    /// Strip the backend suffix the runner appends — `Codable.roundTripFidelity[JSON]`.
    ///
    /// **This is load-bearing, and getting it wrong would have made the wiring inert while
    /// looking correct.** `KitEvidenceLog.equalityOracleLaws` matches on exact qualified
    /// names (`"Hashable.equalityConsistency"`), and `LawIdentifier.matches` splits on `[`
    /// for the same reason. An adapter that passed `protocolLaw` through unchanged would
    /// record laws that never match, and the symptom would be indistinguishable from the kit
    /// simply having passed.
    static func canonicalLawName(_ protocolLaw: String) -> String {
        String(protocolLaw.split(separator: "[", maxSplits: 1).first ?? "")
    }

    static func outcome(from checkOutcome: CheckResult.Outcome) -> KitLawOutcome.Outcome {
        switch checkOutcome {
        case .passed:
            return .passed

        case .failed:
            return .failed

        case .suppressed:
            return .suppressed

        // NOT `.failed`. The author used the kit's own `.intentionalViolation` to say the
        // failure is the documented design, and `refutedEqualityOracle` excludes this case
        // on purpose — demoting here would punish someone for documenting a known deviation.
        case .expectedViolation:
            return .expectedViolation
        }
    }

    static func tier(from strictness: StrictnessTier) -> KitLawOutcome.Tier {
        switch strictness {
        case .strict:
            return .strict

        case .conventional:
            return .conventional

        case .heuristic:
            return .heuristic
        }
    }

    static func counterexample(from checkOutcome: CheckResult.Outcome) -> String? {
        switch checkOutcome {
        case .failed(let counterexample):
            return counterexample

        case .expectedViolation(_, let counterexample):
            return counterexample

        case .passed, .suppressed:
            return nil
        }
    }
}
