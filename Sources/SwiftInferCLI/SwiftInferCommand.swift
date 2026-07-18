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
        version: "1.148.0",
        subcommands: [
            Discover.self,
            Scaffold.self,
            Drift.self,
            ConvertCounterexample.self,
            Metrics.self,
            Index.self,
            Query.self,
            Docc.self,
            Insights.self,
            ProveThenShow.self,
            KnownProperties.self,
            Report.self,
            SuggestRefactors.self,
            Verify.self,
            AcceptCheck.self,
            DiscoverReducers.self,
            VerifyValueSemantics.self,
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
            help: """
            Name of the SwiftPM target to scan. Resolved to Sources/<target>/ \
            relative to the working directory. Mutually exclusive with \
            --sources; pass exactly one.
            """
        )
        public var target: String?

        @Option(
            name: .long,
            help: """
            Path to a source directory to scan directly, bypassing the \
            Sources/<target>/ convention. The Xcode escape hatch: an app has no \
            SwiftPM target, so point this at the folder your .swift files live \
            in. Mutually exclusive with --target; pass exactly one.
            """
        )
        public var sources: String?

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
            (M5.4, PRD §5.8.)
            """
        )
        public var statsOnly: Bool = false

        @Flag(
            name: .long,
            help: """
            Append a "Pure-effect annotations" advisory section recommending a \
            `/// @lint.effect pure` line for each function SoundPurity infers \
            referentially transparent. Off by default; the advice is separate \
            from property-test suggestions and never enters accept / verify.
            """
        )
        public var effectAnnotations: Bool = false

        @Flag(
            name: .long,
            help: """
            Append a "Reference definitions from docstrings" advisory section. For \
            a documented function whose doc states a checkable contract, it pairs \
            that sentence with the law it defines — the reference definition a \
            `predicate` law openly owes, the spec a lifted example test needs, or \
            the only refutable contract on a function the templates could offer \
            nothing owed for. Off by default; the advice is separate from \
            property-test suggestions and never enters accept / verify.
            """
        )
        public var docstringAdvice: Bool = false

        @Flag(
            name: .long,
            help: """
            Suppress writes during --interactive triage. Accept (A) \
            gestures show the would-be file path on stdout but skip \
            both the file write and the .swiftinfer/decisions.json \
            update. Without --interactive there are no writes to \
            suppress, so --dry-run is a no-op. (M5.5 + M6.4, PRD \
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
            without writing files. (M6.4, PRD §5.8.)
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
            Honors --dry-run by skipping the write. (M6.5, PRD §5.8.)
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
            back to the walk-up resolver. (TestLifter M6.0, PRD §7.9.)
            """
        )
        public var testDir: String?

        @Option(
            name: .long,
            help: """
            Path to a JSON seed manifest (the `pbt-seeds` output of an external \
            linter, e.g. `swiftprojectlint … --format pbt-seeds`). When set, \
            discovery still scans the whole target but the surfaced suggestions \
            are FOCUSED to functions named in the manifest — the consumer side \
            of the lint → infer pipeline. A seeded pure function that no template \
            matched still earns the generic determinism law (f(x) == f(x)). A \
            missing or malformed file is an error; an empty manifest focuses to \
            zero suggestions.
            """
        )
        public var seeds: String?

        public init() { /* no-op */ }
    }
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
