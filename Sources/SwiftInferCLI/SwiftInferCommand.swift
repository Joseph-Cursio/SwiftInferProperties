import ArgumentParser
import Foundation
import SwiftInferCore

/// Sink for `Discover.run(directory:output:)`. Production code uses
/// `PrintOutput`; tests use a recording sink so they can match the rendered
/// text byte-for-byte.
public protocol DiscoverOutput {
    /// Emits one chunk of rendered `discover` output.
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
    /// Emits one diagnostic line, out of band from the suggestion stream.
    func writeDiagnostic(_ text: String)
}

public struct PrintDiagnosticOutput: DiagnosticOutput {
    public init() { /* no-op */ }
    public func writeDiagnostic(_ text: String) {
        FileHandle.standardError.write(Data((text + "\n").utf8))
    }
}

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
        version: BuildIdentity.versionString("1.160.0"),
        subcommands: [
            Discover.self,
            Scaffold.self,
            ScaffoldKitSuites.self,
            Drift.self,
            ConvertCounterexample.self,
            Metrics.self,
            Index.self,
            Query.self,
            Docc.self,
            Insights.self,
            ProveThenShow.self,
            SurveyDiff.self,
            Corpus.self,
            Census.self,
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
            AcceptBridge.self,
        ],
        defaultSubcommand: Discover.self
    )

    public init() { /* no-op */ }
}
