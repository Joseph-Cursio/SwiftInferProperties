import ArgumentParser
import Foundation
import SwiftInferCore

/// V2.0 M1.A — `swift-infer discover-reducers` subcommand surface.
///
/// **What it does.** Scans `Sources/<target>/` for functions whose
/// signature matches one of the three canonical reducer shapes (PRD
/// §6.2). Prints one line per detected reducer plus a tail summary.
/// The list is sorted by `(location, functionName)` for byte-stable
/// output across runs.
///
/// **V2.0 M1.A scope.** Listing only — no interactive triage, no
/// scoring, no verify, no persistence. Downstream pipelines (M2's
/// Action-sequence generator, M3's in-process verify, M4–M7's
/// interaction-template families) consume the candidate list via
/// `ReducerDiscoverer.discover(directory:)` directly; the subcommand
/// is the human-driven gesture for "what does the tool see?".
///
/// **Why a separate subcommand rather than `discover --reducers`.**
/// The §3.6 framing suggests folding into the existing `discover`
/// subcommand. M1.A picks a separate subcommand because:
///   - `discover` is rooted around algebraic-suggestion emission; a
///     `--reducers` mode that produces a structurally-different
///     output type (a flat candidate list, not scored suggestions)
///     would force a branch deep in `Discover.run`.
///   - Discovery and template-scoring naturally separate as v2.0
///     matures (M4+ scoring runs against the discovery output —
///     two stages, not one).
/// Folding into `discover` later, if desired, is non-breaking — the
/// hyphenated form can stay as an alias.
extension SwiftInferCommand {

    public struct DiscoverReducers: AsyncParsableCommand {

        public static let configuration = CommandConfiguration(
            commandName: "discover-reducers",
            abstract: "List functions matching the three canonical "
                + "reducer signatures (PRD v2.0 §6.2) under "
                + "Sources/<target>/. Opt-in / human-driven; foundation "
                + "for v2.0 M2+ interaction-invariant inference."
        )

        @Option(
            name: .long,
            help: """
            Name of the SwiftPM target to scan. Resolved to \
            Sources/<target>/ relative to the working directory — \
            mirrors `swift-infer discover --target`.
            """
        )
        public var target: String

        public init() {}

        public func run() async throws {
            let directory = URL(fileURLWithPath: "Sources").appendingPathComponent(target)
            let rendered = try Self.runPipeline(directory: directory)
            print(rendered, terminator: "")
        }

        /// V2.0 M1.A — pure-ish pipeline entry. Tests drive it without
        /// going through the AsyncParsableCommand shell. Returns the
        /// rendered summary string; the CLI's `run()` just prints it.
        static func runPipeline(directory: URL) throws -> String {
            let candidates = try ReducerDiscoverer.discover(directory: directory)
            return renderSummary(candidates: candidates)
        }

        /// V2.0 M1.A — summary text emitted to stdout. One line per
        /// reducer plus a tail summary. Byte-stable for tests:
        /// candidates are sorted by `(location, functionName)`, and
        /// the location uses the file path verbatim from
        /// `ReducerDiscoverer`.
        static func renderSummary(candidates: [ReducerCandidate]) -> String {
            if candidates.isEmpty {
                return "swift-infer discover-reducers: no reducer-shaped functions detected.\n"
            }
            let sorted = candidates.sorted { lhs, rhs in
                if lhs.location != rhs.location { return lhs.location < rhs.location }
                return lhs.functionName < rhs.functionName
            }
            var lines: [String] = []
            let suffix = sorted.count == 1 ? "" : "s"
            lines.append(
                "swift-infer discover-reducers — detected \(sorted.count) "
                    + "reducer-shaped function\(suffix):"
            )
            lines.append("")
            for candidate in sorted {
                lines.append(
                    "  \(candidate.location)  \(candidate.qualifiedName)  "
                        + "signature:\(candidate.signatureShape.rawValue)  "
                        + "state:\(candidate.stateTypeName)  action:\(candidate.actionTypeName)"
                )
            }
            return lines.joined(separator: "\n") + "\n"
        }
    }
}
