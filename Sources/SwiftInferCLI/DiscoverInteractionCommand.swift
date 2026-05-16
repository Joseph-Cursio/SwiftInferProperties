import ArgumentParser
import Foundation
import SwiftInferCore
import SwiftInferTemplates

/// V2.0 M4.E — `swift-infer discover-interaction` subcommand.
///
/// **What it does.** Discovers reducer-shaped functions under
/// `Sources/<target>/` (same M1 surface that `discover-reducers`
/// uses), optionally filters by `--reducer <pin>`, runs the
/// `InteractionTemplateEngine` over the resulting candidates, and
/// renders the emitted suggestions via
/// `InteractionSuggestionRenderer`.
///
/// **What it surfaces.** Conservation (M4.B) + Idempotence (M4.C)
/// at v0.0 ship — both at default `.possible` visibility per PRD
/// §3.5. Calibration cycles will promote/demote these once real
/// corpora produce data. Cardinality / Referential integrity /
/// Biconditional families land at M5 / M6 / M7.
///
/// **Why a separate subcommand vs `discover --interaction`.**
/// v1's `discover` is rooted around algebraic-suggestion emission
/// (signature-pair detection + per-template scoring). `discover-
/// interaction` produces a structurally different output type
/// (interaction-invariant suggestions with predicate + family
/// fields). Separate subcommand keeps the boundaries clean —
/// same posture as `discover-reducers` and `verify-interaction`.
extension SwiftInferCommand {

    public struct DiscoverInteraction: AsyncParsableCommand {

        public static let configuration = CommandConfiguration(
            commandName: "discover-interaction",
            abstract: "Surface candidate interaction invariants on "
                + "reducer-shaped functions (PRD v2.0 §3.6 step 2). "
                + "Conservation + Idempotence at M4.0 ship — both "
                + "at default Possible visibility pending calibration "
                + "(see PRD §3.5)."
        )

        @Option(
            name: .long,
            help: """
            Name of the SwiftPM target containing reducer-shaped \
            functions. Resolved to Sources/<target>/ relative to \
            the working directory — mirrors `swift-infer \
            discover-reducers` and `verify-interaction`.
            """
        )
        public var target: String

        @Option(
            name: .long,
            help: """
            Optional `<typeName>.<funcName>` (or `<funcName>`) pin \
            selecting which reducer to analyze. When omitted, the \
            engine runs against every detected reducer in the \
            target. Module-prefixed pins (`MyModule.Inbox.body`) \
            defer to M2+ when multi-module plumbing lands.
            """
        )
        public var reducer: String?

        @Flag(
            name: .long,
            inversion: .prefixedNo,
            help: """
            Surface .possible-tier suggestions in the output \
            stream. PRD §3.5 corollary: every new family ships at \
            default Possible visibility through three calibration \
            cycles — pass --include-possible to see them before \
            calibration promotes them to .likely / .strong.
            """
        )
        public var includePossible: Bool = false

        @Flag(
            name: .long,
            help: """
            Snapshot the current run's Strong-tier-or-Verified \
            interaction-invariant suggestions to \
            .swiftinfer/interaction-baseline.json. Used by \
            `swift-infer drift-interaction` to compute "what's new \
            since the last snapshot" — only Strong-tier-or-Verified \
            suggestions added after this snapshot (and lacking a \
            recorded decision) earn a drift warning. Filter is \
            symmetric with InteractionDriftDetector + \
            InteractionInvariantBridge — Possible / Likely / \
            Suppressed are deliberately excluded so baseline + drift \
            stay aligned. Honors --dry-run by skipping the write. \
            Additive: the suggestion stream is still rendered.
            """
        )
        public var updateBaseline: Bool = false

        @Flag(
            name: .long,
            help: """
            Suppress writes during --update-baseline. The would-be \
            file path is reported on stdout and the .swiftinfer/ \
            update is skipped. Without --update-baseline there are \
            no writes to suppress, so --dry-run is a no-op.
            """
        )
        public var dryRun: Bool = false

        public init() {}

        public func run() async throws {
            let workingDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            try Self.run(
                target: target,
                pinRaw: reducer,
                includePossible: includePossible,
                updateBaseline: updateBaseline,
                dryRun: dryRun,
                workingDirectory: workingDirectory,
                output: PrintOutput()
            )
        }

        /// V1.89 — full orchestrator. Drives `collectSuggestions`,
        /// optionally writes the M10 interaction-baseline, then
        /// renders the suggestion stream to `output`. Tests use a
        /// recording sink for byte-stable assertions on both the
        /// baseline-write status line and the renderer output.
        ///
        /// `runPipeline` (which only renders) is kept for callers
        /// that don't need the baseline-write leg — primarily the
        /// existing pipeline tests pinning renderer output.
        public static func run(
            target: String,
            pinRaw: String? = nil,
            includePossible: Bool = false,
            updateBaseline: Bool = false,
            dryRun: Bool = false,
            workingDirectory: URL,
            output: any DiscoverOutput,
            firstSeenAt: Date = Date()
        ) throws {
            let suggestions = try collectSuggestions(
                target: target,
                pinRaw: pinRaw,
                workingDirectory: workingDirectory,
                firstSeenAt: firstSeenAt
            )
            if updateBaseline {
                try runUpdateBaseline(
                    suggestions: suggestions,
                    workingDirectory: workingDirectory,
                    target: target,
                    dryRun: dryRun,
                    output: output
                )
            }
            let rendered = InteractionSuggestionRenderer.render(
                suggestions,
                includePossible: includePossible
            )
            output.write(rendered)
        }

        /// V2.0 M4.E — pure-ish pipeline entry. Tests drive it
        /// without going through the AsyncParsableCommand shell.
        ///
        /// Pipeline steps:
        ///   1. Walk `Sources/<target>/` for reducer candidates
        ///      via `ReducerDiscoverer.discover`.
        ///   2. Apply optional `--reducer <pin>` filter via
        ///      `ReducerPin.parse + matches`.
        ///   3. Run `InteractionTemplateEngine.analyze` against
        ///      the filtered candidates + sources directory.
        ///   4. Render via `InteractionSuggestionRenderer`.
        ///
        /// `firstSeenAt` overrides the engine's wall-clock default
        /// — exists so unit tests can pin the rendered output
        /// byte-for-byte. The CLI invocation uses the default.
        static func runPipeline(
            target: String,
            pinRaw: String? = nil,
            includePossible: Bool = false,
            workingDirectory: URL,
            firstSeenAt: Date = Date()
        ) throws -> String {
            let suggestions = try collectSuggestions(
                target: target,
                pinRaw: pinRaw,
                workingDirectory: workingDirectory,
                firstSeenAt: firstSeenAt
            )
            return InteractionSuggestionRenderer.render(
                suggestions,
                includePossible: includePossible
            )
        }

        /// V2.0 M10 — pure pipeline leg that stops before rendering.
        /// Exposed for `swift-infer drift-interaction` which needs the
        /// raw suggestion list to diff against the baseline, not a
        /// rendered string. Same M1 discovery + pin filter + M4
        /// engine path as `runPipeline`.
        static func collectSuggestions(
            target: String,
            pinRaw: String? = nil,
            workingDirectory: URL,
            firstSeenAt: Date = Date()
        ) throws -> [InteractionInvariantSuggestion] {
            let directory = workingDirectory
                .appendingPathComponent("Sources")
                .appendingPathComponent(target)
            let allCandidates = try ReducerDiscoverer.discover(directory: directory)
            let candidates = try filterCandidates(allCandidates, pinRaw: pinRaw)
            return try InteractionTemplateEngine.analyze(
                candidates: candidates,
                sourcesDirectory: directory,
                firstSeenAt: firstSeenAt
            )
        }

        /// V2.0 M4.E — apply the `--reducer <pin>` filter when
        /// present. When `pinRaw` is `nil`, returns the candidates
        /// unchanged. When present, filters to candidates matching
        /// the pin and errors if zero match. Multiple matches are
        /// fine (the engine fires on each independently — discovery
        /// is a fan-out gesture, unlike verify which needs exactly
        /// one reducer).
        static func filterCandidates(
            _ candidates: [ReducerCandidate],
            pinRaw: String?
        ) throws -> [ReducerCandidate] {
            guard let pinRaw else { return candidates }
            let pin = try ReducerPin.parse(pinRaw)
            let matched = candidates.filter { pin.matches($0) }
            if matched.isEmpty {
                throw DiscoverInteractionError.noMatchingReducer(pin: pinRaw)
            }
            return matched
        }

        /// V1.89 — snapshot the current run's Strong-tier-or-Verified
        /// suggestions to `.swiftinfer/interaction-baseline.json`.
        /// Symmetric write side for M10's drift read. Honors `--dry-run`
        /// by reporting the would-be path on stdout and skipping the
        /// write.
        ///
        /// **Filter.** Strong + Verified only, matching
        /// `InteractionDriftDetector.warnings` and
        /// `InteractionInvariantBridge`. Persisting Possible / Likely
        /// would write entries that drift would never warn against —
        /// the two surfaces would silently desync. Today (pre-
        /// calibration) every M4–M7 family ships at default `.possible`
        /// so the snapshot is typically empty; that's correct (drift
        /// today warns on nothing, and the snapshot records that
        /// state).
        static func runUpdateBaseline(
            suggestions: [InteractionInvariantSuggestion],
            workingDirectory: URL,
            target: String,
            dryRun: Bool,
            output: any DiscoverOutput
        ) throws {
            let entries = suggestions
                .filter { $0.tier == .strong || $0.tier == .verified }
                .map { suggestion in
                    InteractionBaselineEntry(
                        identityHash: suggestion.identity.normalized,
                        family: suggestion.family,
                        scoreAtSnapshot: suggestion.score,
                        tier: suggestion.tier,
                        reducerQualifiedName: suggestion.reducerQualifiedName
                    )
                }
            let baseline = InteractionBaseline(entries: entries)
            let sourcesDirectory = workingDirectory
                .appendingPathComponent("Sources")
                .appendingPathComponent(target)
            let packageRoot = findPackageRoot(startingFrom: sourcesDirectory)
                ?? workingDirectory
            let path = InteractionBaselineLoader.defaultPath(for: packageRoot)
            if dryRun {
                output.write(
                    "[dry-run] would write interaction-baseline to "
                        + "\(path.path) (\(entries.count) entries)."
                )
                return
            }
            try InteractionBaselineLoader.write(baseline, to: path)
            output.write(
                "Wrote interaction-baseline to \(path.path) (\(entries.count) entries)."
            )
        }

        /// Walk up from `directory` looking for `Package.swift`. Same
        /// shape as `InteractionBaselineLoader.findPackageRoot` (kept
        /// private there); inlined here to keep the baseline-write
        /// helper self-contained without widening the loader's API.
        private static func findPackageRoot(startingFrom directory: URL) -> URL? {
            var current = directory.standardizedFileURL
            while true {
                let manifest = current.appendingPathComponent("Package.swift")
                if FileManager.default.fileExists(atPath: manifest.path) {
                    return current
                }
                let parent = current.deletingLastPathComponent().standardizedFileURL
                if parent == current {
                    return nil
                }
                current = parent
            }
        }
    }
}

/// V2.0 M4.E — errors thrown by the discover-interaction pipeline.
/// File-scope for the SwiftLint nesting cap; public so tests can
/// pattern-match on the case.
public enum DiscoverInteractionError: Error, CustomStringConvertible, Equatable {
    case noMatchingReducer(pin: String)

    public var description: String {
        switch self {
        case let .noMatchingReducer(pin):
            return "swift-infer discover-interaction: no reducer matches pin '\(pin)'."
        }
    }
}
