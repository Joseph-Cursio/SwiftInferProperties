import ArgumentParser
import Foundation
import SwiftInferCore
import SwiftInferTemplates

/// Root command for the `swift-infer` executable. v1.2.0 ships
/// `discover` + `drift` + `convert-counterexample` (subcommand surface
/// unchanged from v1.1; v1.2 widens the M13 + M14 generalized-partition
/// + N-class enum-coverage surface and closes the M15 `Float`/`Double`
/// numerical-bound preconditions). The remaining post-v1.2 subcommand
/// surface (`metrics`, `apply`) is sketched in PRD §17 + §20.6 under the
/// PRD's "v1.1+ trajectory" heading.
public struct SwiftInferCommand: AsyncParsableCommand {

    public static let configuration = CommandConfiguration(
        commandName: "swift-infer",
        abstract: "Type-directed property inference for Swift.",
        discussion: """
        Surfaces idempotence, round-trip, and algebraic-structure candidates \
        from function signatures, cross-function pairs, and existing tests. \
        All output is suggestions for human review; nothing auto-executes. \
        See `docs/SwiftInferProperties PRD v1.0.md` for the full design.
        """,
        version: "1.116.0",
        subcommands: [
            Discover.self,
            Drift.self,
            ConvertCounterexample.self,
            Metrics.self,
            Index.self,
            Query.self,
            SuggestRefactors.self,
            Verify.self,
            AcceptCheck.self,
            DiscoverReducers.self,
            VerifyInteraction.self,
            DiscoverInteraction.self,
            DriftInteraction.self,
            AcceptInteraction.self,
            AcceptCheckInteraction.self,
            MetricsInteraction.self,
            AcceptBridge.self
        ],
        defaultSubcommand: Discover.self
    )

    public init() { /* no-op */ }
}

extension SwiftInferCommand {

    /// `swift-infer discover` — scan a target for inferred property
    /// candidates. M1.3 wires the idempotence template; M1.4 wires
    /// round-trip + cross-function pairing.
    public struct Discover: AsyncParsableCommand {

        public static let configuration = CommandConfiguration(
            commandName: "discover",
            abstract: "Scan a target for inferred property candidates."
        )

        @Option(
            name: .long,
            help: "Name of the SwiftPM target to scan. Resolved to Sources/<target>/ relative to the working directory."
        )
        public var target: String

        @Flag(
            name: .long,
            inversion: .prefixedNo,
            help: """
            Include `Possible` tier suggestions (score 20–39). Hidden by \
            default per PRD §4.2. Pass --include-possible / \
            --no-include-possible to override the project's \
            .swiftinfer/config.toml setting.
            """
        )
        public var includePossible: Bool?

        @Option(
            name: .long,
            help: """
            Path to a vocabulary file (PRD §4.5). When omitted, swift-infer \
            falls back to the path in .swiftinfer/config.toml's \
            [discover].vocabularyPath, then to the conventional \
            .swiftinfer/vocabulary.json next to Package.swift.
            """
        )
        public var vocabulary: String?

        @Option(
            name: .long,
            help: """
            Path to a config file. When omitted, swift-infer walks up \
            from the target directory to the package root and looks for \
            .swiftinfer/config.toml.
            """
        )
        public var config: String?

        @Option(
            name: .long,
            help: """
            Comma-separated list of template packs to enable: \
            numeric, serialization, collections, algebraic, concurrency \
            (PRD §20.3). When omitted, all packs are enabled (the v1 \
            monolithic-registry default). Falls back to the path in \
            .swiftinfer/config.toml's [discover].packs string when set. \
            Unknown pack names emit a diagnostic warning and are ignored.
            """
        )
        public var packs: String?

        @Flag(
            name: .long,
            help: """
            Render a per-template / per-tier summary block instead of \
            the full §4.5 explainability blocks. Useful for CI \
            dashboards tracking suggestion-count regressions over time. \
            (M5.4, PRD v0.4 §5.8.)
            """
        )
        public var statsOnly: Bool = false

        @Flag(
            name: .long,
            help: """
            Suppress writes during --interactive triage. Accept (A) \
            gestures show the would-be file path on stdout but skip \
            both the file write and the .swiftinfer/decisions.json \
            update. Without --interactive there are no writes to \
            suppress, so --dry-run is a no-op. (M5.5 + M6.4, PRD v0.4 \
            §5.8.)
            """
        )
        public var dryRun: Bool = false

        @Flag(
            name: .long,
            help: """
            Walk surviving suggestions one at a time, prompting \
            [A/s/n/?]: Accept writes a property-test stub to \
            Tests/Generated/SwiftInfer/<TemplateName>/<FunctionName>.swift \
            and records the decision; Skip / Reject record the decision \
            without writing files. (M6.4, PRD v0.4 §5.8.)
            """
        )
        public var interactive: Bool = false

        @Flag(
            name: .long,
            help: """
            Snapshot the current run's surface-suggestion identities to \
            .swiftinfer/baseline.json. Used by `swift-infer drift` to \
            compute "what's new since the last snapshot" — only Strong-tier \
            suggestions added after this snapshot (and lacking a recorded \
            decision) earn a drift warning. Mutually exclusive with \
            --interactive in v1: triage and snapshot are different gestures. \
            Honors --dry-run by skipping the write. (M6.5, PRD v0.4 §5.8.)
            """
        )
        public var updateBaseline: Bool = false

        @Option(
            name: .long,
            help: """
            Path to the directory TestLifter scans for tests. When omitted, \
            swift-infer walks up from the --target directory to find \
            Package.swift, then scans <package-root>/Tests/ if it exists. \
            When the explicit path is missing, swift-infer warns and falls \
            back to the walk-up resolver. (TestLifter M6.0, PRD v0.4 §7.9.)
            """
        )
        public var testDir: String?

        public init() { /* no-op */ }

        public func run() async throws {
            let directory = URL(fileURLWithPath: "Sources").appendingPathComponent(target)
            let explicitVocabularyPath = vocabulary.map { URL(fileURLWithPath: $0) }
            let explicitConfigPath = config.map { URL(fileURLWithPath: $0) }
            let explicitTestDirPath = testDir.map { URL(fileURLWithPath: $0) }
            try Self.run(
                directory: directory,
                includePossible: includePossible,
                explicitVocabularyPath: explicitVocabularyPath,
                explicitConfigPath: explicitConfigPath,
                explicitTestDirectory: explicitTestDirPath,
                packsOverride: packs,
                statsOnly: statsOnly,
                dryRun: dryRun,
                interactive: interactive,
                updateBaseline: updateBaseline,
                output: PrintOutput(),
                diagnostics: PrintDiagnosticOutput()
            )
        }

        /// Pure pipeline — exposed at the type level so tests exercise
        /// discovery without going through ArgumentParser or stdout.
        ///
        /// Precedence per the M2 plan: CLI > config > defaults. A `nil`
        /// `includePossible` means "no CLI flag passed; let config (or
        /// the default) decide". A non-nil value wins over both. Same
        /// shape for `explicitVocabularyPath`: when nil, the CLI looks
        /// at `[discover].vocabularyPath` in config; when also unset
        /// there, falls back to the conventional walk-up location.
        public static func run(
            directory: URL,
            includePossible: Bool? = nil,
            explicitVocabularyPath: URL? = nil,
            explicitConfigPath: URL? = nil,
            explicitTestDirectory: URL? = nil,
            packsOverride: String? = nil,
            statsOnly: Bool = false,
            dryRun: Bool = false,
            interactive: Bool = false,
            updateBaseline: Bool = false,
            promptInput: any PromptInput = StdinPromptInput(),
            output: any DiscoverOutput,
            diagnostics: any DiagnosticOutput = PrintDiagnosticOutput()
        ) throws {
            let evidenceByIdentity = loadVerifyEvidenceMap(
                directory: directory,
                diagnostics: diagnostics
            )
            let pipeline = try collectVisibleSuggestions(
                directory: directory,
                includePossible: includePossible,
                explicitVocabularyPath: explicitVocabularyPath,
                explicitConfigPath: explicitConfigPath,
                explicitTestDirectory: explicitTestDirectory,
                packsOverride: packsOverride,
                verifyEvidenceByIdentity: evidenceByIdentity,
                diagnostics: diagnostics
            )
            let visible = pipeline.suggestions

            if interactive, updateBaseline {
                diagnostics.writeDiagnostic(
                    "warning: --interactive and --update-baseline are mutually exclusive; "
                        + "--update-baseline ignored for this run"
                )
            }
            if interactive {
                try runInteractiveBranch(
                    visible: visible,
                    pipeline: pipeline,
                    directory: directory,
                    triageIO: DiscoverInteractiveIO(
                        prompt: promptInput,
                        output: output,
                        diagnostics: diagnostics,
                        dryRun: dryRun
                    ),
                    evidenceByIdentity: evidenceByIdentity
                )
                return
            }
            if updateBaseline {
                try runUpdateBaseline(
                    suggestions: visible,
                    packageRoot: pipeline.packageRoot ?? directory,
                    dryRun: dryRun,
                    output: output
                )
            }
            renderAndWrite(
                visible: visible,
                statsOnly: statsOnly,
                evidenceByIdentity: evidenceByIdentity,
                output: output
            )
        }

        /// V1.89 lint pass — render branch extracted from `Discover.run`
        /// so the orchestrator body stays under SwiftLint's 50-line cap.
        /// V1.64.C annotation behavior unchanged: when `evidenceByIdentity`
        /// is empty, blocks render byte-identically to the pre-v1.64 output.
        private static func renderAndWrite(
            visible: [Suggestion],
            statsOnly: Bool,
            evidenceByIdentity: [String: VerifyEvidence],
            output: any DiscoverOutput
        ) {
            let rendered: String
            if statsOnly {
                rendered = SuggestionRenderer.renderStats(visible)
            } else {
                rendered = SuggestionRenderer.render(
                    visible,
                    verifyEvidenceByIdentity: evidenceByIdentity
                )
            }
            output.write(rendered)
        }

        /// V1.67 — load persisted `swift-infer verify` evidence so it
        /// feeds the pipeline's scoring AND its visibility filter:
        /// `bothPass` raises the score (and can lift a pick past the
        /// visibility threshold), `defaultFails` vetoes → `.suppressed`
        /// → dropped by the pipeline's own filter. The returned map
        /// is reused for the V1.64.C render-time annotation.
        ///
        /// V1.89 lint pass — extracted from `Discover.run` so the
        /// orchestrator body stays under SwiftLint's 50-line cap.
        private static func loadVerifyEvidenceMap(
            directory: URL,
            diagnostics: any DiagnosticOutput
        ) -> [String: VerifyEvidence] {
            let evidenceResult = VerifyEvidenceStore.load(startingFrom: directory)
            for warning in evidenceResult.warnings {
                diagnostics.writeDiagnostic("warning: \(warning)")
            }
            return Dictionary(
                evidenceResult.log.records.map { ($0.identityHash, $0) }
            ) { _, latest in latest }
        }

        /// V1.89 lint pass — extracted from `Discover.run`. Builds the
        /// `InteractiveTriage.Context` and hands off to `runInteractive`.
        /// Same control flow as before the extraction.
        private static func runInteractiveBranch(
            visible: [Suggestion],
            pipeline: PipelineResult,
            directory: URL,
            triageIO: DiscoverInteractiveIO,
            evidenceByIdentity: [String: VerifyEvidence]
        ) throws {
            let packageRoot = pipeline.packageRoot ?? directory
            let context = InteractiveTriage.Context(
                prompt: triageIO.prompt,
                output: triageIO.output,
                diagnostics: triageIO.diagnostics,
                outputDirectory: packageRoot,
                dryRun: triageIO.dryRun,
                proposalsByType: RefactorBridgeOrchestrator.proposals(
                    from: visible,
                    inverseElementPairs: pipeline.inverseElementPairs
                ),
                equivalenceClassHintsByIdentity: pipeline.equivalenceClassHintsByIdentity,
                consumerProducerChainHintsByIdentity: pipeline.consumerProducerChainHintsByIdentity,
                verifyEvidenceByIdentity: evidenceByIdentity
            )
            try runInteractive(suggestions: visible, packageRoot: packageRoot, context: context)
        }
    }
}

/// V1.89 lint pass — small I/O bundle for the interactive-triage path,
/// lifted from the four individual `Discover.run` params (`promptInput`,
/// `output`, `diagnostics`, `dryRun`) so `runInteractiveBranch` stays
/// at 5 params. File-scope rather than nested under `Discover` to keep
/// SwiftLint's nesting cap satisfied.
struct DiscoverInteractiveIO {
    let prompt: any PromptInput
    let output: any DiscoverOutput
    let diagnostics: any DiagnosticOutput
    let dryRun: Bool
}

/// Sink for `Discover.run(directory:output:)`. Production code uses
/// `PrintOutput`; tests use a recording sink so they can match the rendered
/// text byte-for-byte.
public protocol DiscoverOutput {
    func write(_ text: String)
}

public struct PrintOutput: DiscoverOutput {
    public init() { /* no-op */ }
    public func write(_ text: String) {
        print(text)
    }
}

/// Sink for diagnostic warnings (vocabulary load failures, etc.). Kept
/// separate from `DiscoverOutput` so warnings reach stderr without
/// disturbing the byte-stable suggestion stream on stdout — PRD §16's
/// reproducibility guarantee depends on stdout being a function of
/// (target sources, vocabulary, config) only.
public protocol DiagnosticOutput {
    func writeDiagnostic(_ text: String)
}

public struct PrintDiagnosticOutput: DiagnosticOutput {
    public init() { /* no-op */ }
    public func writeDiagnostic(_ text: String) {
        FileHandle.standardError.write(Data((text + "\n").utf8))
    }
}
