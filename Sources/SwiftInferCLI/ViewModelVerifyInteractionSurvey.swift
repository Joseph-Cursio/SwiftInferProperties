import Foundation
import SwiftInferCore

/// PROTOTYPE — survey the `@Observable` carriers in a target and run each
/// resolvable (candidate × family) interaction invariant through the M1′
/// execution-backed pipeline (Observable Carrier milestone, Slice 4).
///
/// This is the ViewModel counterpart to `VerifyInteractionSurvey`: it maps a
/// `ViewModelCandidate`'s statically-surfaced invariants (the same predicates
/// `mergedWithViewModels` renders at `.possible`) to a *measured* verdict —
/// `VERIFIED` when the multi-step run holds, `REFUTED` with a counterexample
/// when a sequence breaks it. Rendering a `VERIFIED` verdict is the render-level
/// `.possible → .verified` promotion the milestone calls for.
///
/// The build+run step is the injected `VerifyRunner`, so the survey logic is
/// unit-testable without a real build; `ViewModelVerifyInteractionPipeline
/// .liveRunner()` is the production seam.
enum ViewModelVerifyInteractionSurvey {

    struct Entry: Equatable, Sendable {
        let typeName: String
        let family: String
        let result: ViewModelVerifyInteractionPipeline.StepResult
    }

    /// One (family name, resolved predicate) per invariant a candidate exposes.
    /// A `nil` predicate means the family doesn't apply — omitted, not surveyed.
    static func resolvedFamilies(for candidate: ViewModelCandidate) -> [(family: String, predicate: String)] {
        let raw: [(String, String?)] = [
            ("referential-integrity", ViewModelRefintResolver.resolve(candidate)?.predicate),
            ("cardinality", ViewModelCardinalityResolver.resolve(candidate)),
            ("biconditional", ViewModelBiconditionalResolver.resolve(candidate)),
            ("conservation", ViewModelConservationResolver.resolve(candidate))
        ]
        return raw.compactMap { family, predicate in
            predicate.map { (family, $0) }
        }
    }

    /// Verify every resolvable (candidate × family) through the M1′ pipeline.
    /// Deterministic order: candidate name, then family.
    static func run(
        candidates: [ViewModelCandidate],
        sourceFiles: [CorpusPackager.SourceFile],
        workdir: URL,
        runner: ViewModelVerifyInteractionPipeline.VerifyRunner
    ) -> [Entry] {
        var entries: [Entry] = []
        for candidate in candidates.sorted(by: { $0.typeName < $1.typeName }) {
            for (family, predicate) in resolvedFamilies(for: candidate) {
                let result = ViewModelVerifyInteractionPipeline.verify(
                    candidate: candidate,
                    predicate: predicate,
                    sourceFiles: sourceFiles,
                    workdir: workdir,
                    runner: runner
                )
                entries.append(Entry(typeName: candidate.typeName, family: family, result: result))
            }
        }
        return entries
    }

    /// The render-level verdict for one entry (`VERIFIED` = promoted).
    static func verdict(_ result: ViewModelVerifyInteractionPipeline.StepResult) -> String {
        switch result {
        case let .ran(outcome):
            switch outcome {
            case let .bothPass(defaultTrials, _, _):
                return "VERIFIED (\(defaultTrials) trials)"

            case let .edgeCaseAdvisory(defaultTrials, _):
                return "ADVISORY (\(defaultTrials) trials)"

            case let .defaultFails(detail):
                return "REFUTED (trial \(detail.trial))"

            case let .error(reason):
                return "ERROR (\(reason))"
            }

        case let .skipped(reason):
            return "skipped — \(reason)"
        }
    }

    /// A deterministic per-entry summary for the CLI.
    static func render(target: String, entries: [Entry]) -> String {
        guard !entries.isEmpty else {
            return "ViewModel interaction verify — \(target)\n  (no verifiable @Observable carriers)\n"
        }
        var lines = ["ViewModel interaction verify — \(target)"]
        for entry in entries {
            lines.append("  \(entry.typeName).\(entry.family): \(verdict(entry.result))")
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
