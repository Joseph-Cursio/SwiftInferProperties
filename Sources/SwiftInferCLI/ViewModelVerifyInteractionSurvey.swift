import Foundation
import SwiftInferCore
import SwiftInferTemplates

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
    /// Deterministic order: candidate name, then family. `userModuleName` is
    /// forwarded to the pipeline (`nil` inlined / a module for imported).
    static func run(
        candidates: [ViewModelCandidate],
        sourceFiles: [CorpusPackager.SourceFile],
        userModuleName: String? = nil,
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
                    userModuleName: userModuleName,
                    workdir: workdir,
                    runner: runner
                )
                entries.append(Entry(typeName: candidate.typeName, family: family, result: result))
            }
        }
        return entries
    }

    /// Discover the `@Observable` carriers under `sourceDirectory` and verify
    /// each against `packageRoot`'s library product for `userModuleName` (the
    /// *imported* path — the model stays in its own module). Returns `""` when
    /// there are no carriers, so the caller appends nothing.
    /// `runner` is injected (defaulting to the production imported seam) for
    /// the same reason the pipeline injects one: without it the only way to
    /// reach this function is a real `swift build`, and the fold-back step
    /// below went unwritten for two months precisely because nothing cheap
    /// could drive the whole chain. A test passes a canned outcome and asserts
    /// the store afterwards.
    static func runLive(
        sourceDirectory: URL,
        userModuleName: String,
        packageRoot: URL,
        workdirRoot: URL,
        runner: ViewModelVerifyInteractionPipeline.VerifyRunner? = nil
    ) throws -> String {
        let candidates = try ViewModelDiscoverer.discover(directory: sourceDirectory)
        guard !candidates.isEmpty else { return "" }
        let product = PackageProductResolver.libraryProduct(
            exposingModule: userModuleName,
            packageRoot: packageRoot
        ) ?? userModuleName
        let userPackage = VerifierWorkdir.UserPackageReference(
            packagePath: packageRoot,
            productNames: [product]
        )
        let workdir = workdirRoot
            .appendingPathComponent(".swiftinfer")
            .appendingPathComponent("vm-verify-workdir")
            .appendingPathComponent(userModuleName.replacingOccurrences(of: ".", with: "_"))
        let entries = run(
            candidates: candidates,
            sourceFiles: [],
            userModuleName: userModuleName,
            workdir: workdir,
            runner: runner ?? ViewModelVerifyInteractionPipeline.importedRunner(userPackage: userPackage)
        )
        // The fold-back this survey existed without until 2026-08-12: persist
        // what was measured so `discover-interaction` re-tiers it. Without this
        // the promotion was render-only — it lived in the terminal and died
        // there. Best-effort by design (a store failure must not fail a verify
        // run), which is also why the warnings are surfaced rather than dropped.
        let folded = foldBack(candidates: candidates, entries: entries)
        let warnings = ViewModelVerifyEvidence.recordBatch(folded.paired, packageRoot: packageRoot)
        return render(target: userModuleName, entries: entries, folded: folded, warnings: warnings)
    }

    /// A verdict paired with the *discover-side* suggestion it measured, plus
    /// the entries that could not be paired.
    /// A verdict deliberately not recorded because the key would be a guess.
    /// `matches == 0` = discover surfaces no such suggestion; `> 1` = it
    /// surfaces several and this survey verified one predicate.
    struct UnpairableVerdict: Equatable {
        let typeName: String
        let family: String
        let matches: Int
    }

    struct FoldBack {
        var paired: [(suggestion: InteractionInvariantSuggestion, outcome: VerifyOutcome)] = []
        var unpairable: [UnpairableVerdict] = []
    }

    /// Pair each *ran* verdict with the suggestion whose identity it measured.
    ///
    /// **Why this cannot just record what it verified.** Evidence is keyed by
    /// `SuggestionIdentity`, whose canonical input is
    /// `family::reducerQualifiedName::subjects` — so a record only joins if it
    /// carries the identity `discover-interaction` will compute. This survey
    /// resolves an *executable* predicate (`ViewModelCardinalityResolver` et al.
    /// render a Swift expression over `probe`), which is a different string from
    /// the analyzer's subject list; re-deriving the identity here would be a
    /// fifth enumeration of the same fact, and this repo has already paid for
    /// enumerations that must agree. So the suggestions are asked for, not
    /// reconstructed.
    ///
    /// **The exactly-one rule is a soundness gate, not caution.**
    /// `referentialIntegrity`, `conservation` and `biconditional` may each
    /// surface *several* suggestions for one candidate, while the resolvers
    /// return at most one predicate per family — so `(type, family)` does not
    /// identify an invariant. Recording under an ambiguous key would attach a
    /// measured verdict to a law that was never run, promoting it to
    /// `.verified` on someone else's evidence. Withholding under-claims; the
    /// alternative over-claims, and only one of those is recoverable.
    static func foldBack(
        candidates: [ViewModelCandidate],
        entries: [Entry],
        firstSeenAt: Date = Date()
    ) -> FoldBack {
        let byName = Dictionary(uniqueKeysWithValues: candidates.map { ($0.typeName, $0) })
        var out = FoldBack()
        for entry in entries {
            guard case let .ran(outcome) = entry.result else { continue }
            guard let candidate = byName[entry.typeName] else {
                out.unpairable.append(.init(typeName: entry.typeName, family: entry.family, matches: 0))
                continue
            }
            let matches = ViewModelInteractionAnalyzer
                .suggestions(for: candidate, firstSeenAt: firstSeenAt)
                .filter { $0.family.rawValue == entry.family && $0.reducerQualifiedName == entry.typeName }
            guard matches.count == 1, let suggestion = matches.first else {
                out.unpairable.append(.init(typeName: entry.typeName, family: entry.family, matches: matches.count))
                continue
            }
            out.paired.append((suggestion, outcome))
        }
        return out
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

    /// A deterministic per-entry summary for the CLI. `folded` is optional so
    /// the pre-fold-back callers (and the unit tests that only exercise
    /// rendering) keep working unchanged.
    static func render(
        target: String,
        entries: [Entry],
        folded: FoldBack? = nil,
        warnings: [String] = []
    ) -> String {
        guard !entries.isEmpty else {
            return "ViewModel interaction verify — \(target)\n  (no verifiable @Observable carriers)\n"
        }
        var lines = ["ViewModel interaction verify — \(target)"]
        for entry in entries {
            lines.append("  \(entry.typeName).\(entry.family): \(verdict(entry.result))")
        }
        if let folded {
            if !folded.paired.isEmpty {
                lines.append(
                    "  evidence: recorded \(folded.paired.count) verdict(s) — "
                        + "discover-interaction will re-tier them"
                )
            }
            // Disclosed, never silent: a verdict that was measured and then
            // dropped is the one a reader would otherwise assume was folded in.
            for item in folded.unpairable {
                let why = item.matches == 0
                    ? "discover surfaces no suggestion for it"
                    : "discover surfaces \(item.matches) suggestions for it and this run verified one predicate"
                lines.append("  evidence: \(item.typeName).\(item.family) NOT recorded — \(why)")
            }
        }
        for warning in warnings {
            lines.append("  evidence: \(warning)")
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
