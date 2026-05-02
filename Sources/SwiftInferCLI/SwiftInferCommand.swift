import ArgumentParser
import Foundation
import SwiftInferCore
import SwiftInferTemplates

/// Root command for the `swift-infer` executable. Subcommand surface mirrors
/// the developer workflow described in PRD v0.3 §3.6:
///
/// - `discover`              — M1.3 wires it through TemplateEngine
///                             (idempotence). M1.4 adds round-trip pairing.
/// - `drift`                 — landing in M-post, see §9.
/// - `convert-counterexample` — landing in TestLifter M8, see §7.9.
/// - `metrics`               — landing alongside §17 adoption tracking.
/// - `apply`                 — v1.1+ ergonomics; see §20.6.
public struct SwiftInferCommand: AsyncParsableCommand {

    public static let configuration = CommandConfiguration(
        commandName: "swift-infer",
        abstract: "Type-directed property inference for Swift.",
        discussion: """
        Surfaces idempotence, round-trip, and algebraic-structure candidates \
        from function signatures, cross-function pairs, and existing tests. \
        All output is suggestions for human review; nothing auto-executes. \
        See `docs/SwiftInferProperties PRD v0.3.md` for the full design.
        """,
        version: "0.0.0-scaffold",
        subcommands: [Discover.self, Drift.self],
        defaultSubcommand: Discover.self
    )

    public init() {}
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

        public init() {}

        public func run() async throws {
            let directory = URL(fileURLWithPath: "Sources").appendingPathComponent(target)
            let explicitVocabularyPath = vocabulary.map { URL(fileURLWithPath: $0) }
            let explicitConfigPath = config.map { URL(fileURLWithPath: $0) }
            try Self.run(
                directory: directory,
                includePossible: includePossible,
                explicitVocabularyPath: explicitVocabularyPath,
                explicitConfigPath: explicitConfigPath,
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
            statsOnly: Bool = false,
            dryRun: Bool = false,
            interactive: Bool = false,
            updateBaseline: Bool = false,
            promptInput: any PromptInput = StdinPromptInput(),
            output: any DiscoverOutput,
            diagnostics: any DiagnosticOutput = PrintDiagnosticOutput()
        ) throws {
            let pipeline = try collectVisibleSuggestions(
                directory: directory,
                includePossible: includePossible,
                explicitVocabularyPath: explicitVocabularyPath,
                explicitConfigPath: explicitConfigPath,
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
                let packageRoot = pipeline.packageRoot ?? directory
                let context = InteractiveTriage.Context(
                    prompt: promptInput,
                    output: output,
                    diagnostics: diagnostics,
                    outputDirectory: packageRoot,
                    dryRun: dryRun
                )
                try runInteractive(
                    suggestions: visible,
                    packageRoot: packageRoot,
                    context: context
                )
                return
            }
            if updateBaseline {
                let packageRoot = pipeline.packageRoot ?? directory
                try runUpdateBaseline(
                    suggestions: visible,
                    packageRoot: packageRoot,
                    dryRun: dryRun,
                    output: output
                )
            }

            let rendered = statsOnly
                ? SuggestionRenderer.renderStats(visible)
                : SuggestionRenderer.render(visible)
            output.write(rendered)
        }

    }
}

/// Sink for `Discover.run(directory:output:)`. Production code uses
/// `PrintOutput`; tests use a recording sink so they can match the rendered
/// text byte-for-byte.
public protocol DiscoverOutput {
    func write(_ text: String)
}

public struct PrintOutput: DiscoverOutput {
    public init() {}
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
    public init() {}
    public func writeDiagnostic(_ text: String) {
        FileHandle.standardError.write(Data((text + "\n").utf8))
    }
}
