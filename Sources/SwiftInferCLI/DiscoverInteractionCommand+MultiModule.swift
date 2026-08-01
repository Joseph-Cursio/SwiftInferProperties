import Foundation
import SwiftInferCore
import SwiftInferTemplates

// Multi-module reducer discovery — lifted out of DiscoverInteractionCommand.swift
// via extension so the primary file stays under SwiftLint's file-length /
// type-body-length caps (same split pattern as +ViewModels.swift /
// +SideOrchestrators.swift).

extension SwiftInferCommand.DiscoverInteraction {

    /// V2.0 M10 — pure pipeline leg that stops before rendering. Exposed for
    /// `swift-infer drift-interaction` which needs the raw suggestion list to
    /// diff against the baseline, not a rendered string. Single-target wrapper
    /// over the multi-module `collectSuggestions(targets:)`.
    static func collectSuggestions(
        target: String,
        pinRaw: String? = nil,
        workingDirectory: URL,
        firstSeenAt: Date = Date()
    ) throws -> [InteractionInvariantSuggestion] {
        try collectSuggestions(
            targets: [target],
            pinRaw: pinRaw,
            workingDirectory: workingDirectory,
            firstSeenAt: firstSeenAt
        )
    }

    /// Multi-module discovery. Scans each `--target`'s `Sources/<target>/` and
    /// tags candidates with their module — but only when more than one target is
    /// given, so a single-target run leaves candidates untagged and a
    /// module-qualified pin stays a redundant qualifier (backward compatible).
    /// The `--reducer` pin is applied across the *aggregate* (so a
    /// `Bar.Counter.reduce` pin matches in Bar without erroring on Foo), dedupe
    /// is module-aware (same-named reducers in different modules are kept
    /// distinct), and the template engine runs per module so the witness
    /// detectors walk the correct sources directory.
    static func collectSuggestions(
        targets: [String],
        pinRaw: String? = nil,
        workingDirectory: URL,
        firstSeenAt: Date = Date()
    ) throws -> [InteractionInvariantSuggestion] {
        try collectSuggestions(
            roots: targets.map { name in
                TargetDirectory.ScanRoot(
                    label: name,
                    directory: workingDirectory
                        .appendingPathComponent("Sources")
                        .appendingPathComponent(name)
                )
            },
            pinRaw: pinRaw,
            firstSeenAt: firstSeenAt
        )
    }

    /// The directory-level form. Everything below the CLI works on **directories**; only the
    /// label needs to know whether it came from `--target` (a module name) or `--sources` (an
    /// Xcode source folder, which has no module name to read).
    ///
    /// Splitting this out is what let `--sources` reach the interaction families at all. They
    /// are the surface built for SwiftUI MVVM apps, and SwiftUI MVVM apps are overwhelmingly
    /// Xcode projects — so until this existed, the one command aimed at app code was the one
    /// that could not open it. Measured on `MacCloud_client_iOS`: the command exited with an
    /// argument error, and the same 22 files staged into a `Sources/<target>/` shim produced 4
    /// suggestions on an `@Observable` view model. The gate was never the problem.
    static func collectSuggestions(
        roots: [TargetDirectory.ScanRoot],
        pinRaw: String? = nil,
        firstSeenAt: Date = Date()
    ) throws -> [InteractionInvariantSuggestion] {
        let tagModule = roots.count > 1
        // 1. Discover across all roots; tag by module in multi-root runs.
        var allCandidates: [ReducerCandidate] = []
        for root in roots {
            var found = try ReducerDiscoverer.discover(directory: root.directory)
            if tagModule {
                for index in found.indices { found[index].moduleName = root.label }
            }
            allCandidates.append(contentsOf: found)
        }
        // 2. Pin filter once across the aggregate; 3. module-aware dedupe.
        let deduped = dedupedByStateAndAction(
            try filterCandidates(allCandidates, pinRaw: pinRaw)
        )
        // 4. Engine per module — witness detectors need the module's own
        // sources directory to resolve State/Action source.
        var reducerSuggestions: [InteractionInvariantSuggestion] = []
        for root in roots {
            let forModule = tagModule
                ? deduped.filter { $0.moduleName == root.label }
                : deduped
            guard !forModule.isEmpty else { continue }
            reducerSuggestions.append(contentsOf: try InteractionTemplateEngine.analyze(
                candidates: forModule,
                sourcesDirectory: root.directory,
                firstSeenAt: firstSeenAt
            ))
        }
        // Productionization — merge SwiftUI MVVM view-model invariants (gated to
        // the no-pin path; `--reducer` is reducer-targeted), one fold per target.
        guard pinRaw == nil else { return reducerSuggestions }
        var merged = reducerSuggestions
        for root in roots {
            merged = try mergedWithViewModels(
                merged,
                directory: root.directory,
                firstSeenAt: firstSeenAt
            )
            merged = try mergedWithConventionRoles(
                merged,
                directory: root.directory,
                firstSeenAt: firstSeenAt
            )
        }
        return merged
    }

    /// V1.107 (cycle-103 Finding F fix) — dedupe candidates before the
    /// interaction template engine runs. `ReduceClosureWalker` emits one
    /// `ReducerCandidate` per `Reduce { ... }` closure, but the templates are
    /// State+Action shape-driven, so multiple closures with the same State and
    /// Action produce identical suggestions. Module-aware: same-named reducers
    /// in two modules stay distinct (a `nil` module — single-target run —
    /// collapses to a constant prefix, so single-module behaviour is unchanged).
    /// First-seen wins. `discover-reducers` output is unaffected.
    static func dedupedByStateAndAction(
        _ candidates: [ReducerCandidate]
    ) -> [ReducerCandidate] {
        var seen: Set<String> = []
        var result: [ReducerCandidate] = []
        for candidate in candidates {
            let key = (candidate.moduleName ?? "") + "|"
                + candidate.stateQualifiedName + "|" + candidate.actionQualifiedName
            if seen.insert(key).inserted {
                result.append(candidate)
            }
        }
        return result
    }
}
