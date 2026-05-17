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
            Walk surviving suggestions one at a time, prompting \
            [A/C/s/n/?]: Accept records `accepted` in \
            .swiftinfer/interaction-decisions.json; Conformance \
            records `accepted-as-conformance` (signals the invariant \
            should be expressed as a SwiftPropertyLaws-side protocol); \
            Skip / Reject behave as in v1 (skip re-surfaces, reject \
            hides from future drift warnings). Mutually exclusive \
            with --update-baseline; honors --dry-run by skipping the \
            decisions write. (V1.98 cycle-95, PRD §9.4 per-suggestion \
            form.)
            """
        )
        public var interactive: Bool = false

        @Flag(
            name: .long,
            help: """
            Suppress writes during --update-baseline or --interactive. \
            For --update-baseline the would-be file path is reported \
            on stdout; for --interactive the triage loop runs but the \
            decisions JSON write is skipped. No-op without either \
            flag.
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
                interactive: interactive,
                dryRun: dryRun,
                workingDirectory: workingDirectory,
                output: PrintOutput(),
                diagnostics: PrintDiagnosticOutput()
            )
        }

        /// V1.89 — full orchestrator. Drives `collectSuggestions`,
        /// optionally writes the M10 interaction-baseline (v1.89) or
        /// runs the per-suggestion interactive triage (v1.98), then
        /// renders the suggestion stream to `output`. Tests use a
        /// recording sink for byte-stable assertions.
        ///
        /// V1.98 — `--interactive` and `--update-baseline` are
        /// mutually exclusive (different gestures); if both are set,
        /// the orchestrator emits a warning and ignores
        /// `--update-baseline`. The render pass still runs after
        /// either branch — both are additive to the suggestion
        /// stream output.
        ///
        /// `runPipeline` (which only renders) is kept for callers
        /// that don't need the baseline-write / triage leg.
        public static func run(
            target: String,
            pinRaw: String? = nil,
            includePossible: Bool = false,
            updateBaseline: Bool = false,
            interactive: Bool = false,
            dryRun: Bool = false,
            workingDirectory: URL,
            promptInput: any PromptInput = StdinPromptInput(),
            output: any DiscoverOutput,
            diagnostics: any DiagnosticOutput = PrintDiagnosticOutput(),
            firstSeenAt: Date = Date()
        ) throws {
            let suggestions = try collectSuggestions(
                target: target,
                pinRaw: pinRaw,
                workingDirectory: workingDirectory,
                firstSeenAt: firstSeenAt
            )
            if interactive, updateBaseline {
                diagnostics.writeDiagnostic(
                    "warning: --interactive and --update-baseline are mutually exclusive; "
                        + "--update-baseline ignored for this run"
                )
            }
            if interactive {
                try runInteractiveBranch(
                    suggestions: suggestions,
                    workingDirectory: workingDirectory,
                    target: target,
                    triageIO: InteractionInteractiveTriage.Inputs(
                        prompt: promptInput,
                        output: output,
                        diagnostics: diagnostics,
                        dryRun: dryRun
                    )
                )
            } else if updateBaseline {
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
