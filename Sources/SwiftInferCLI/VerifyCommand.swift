import ArgumentParser
import Foundation
import SwiftInferCore

/// V1.42.B — `swift-infer verify` subcommand surface declaration.
///
/// **v1.42 status: argument surface only.** The actual compile-and-run
/// pipeline (subprocess workdir synthesis, stub emission, result
/// rendering) lands in V1.42.C. Running `swift-infer verify` against the
/// V1.42.B build returns a clear "not yet wired" diagnostic rather than
/// silently doing nothing.
///
/// **Phase 1 across cycles** — see `docs/v1.42 Calibration Plan.md`:
///   - **v1.42** (this cycle): subprocess-based round-trip verify on
///     `Complex<Double>` carriers, default-generator single pass,
///     3-way pass/fail/error reporting.
///   - **v1.43**: layers `Gen<Complex<Double>>.edgeCaseBiased()` from
///     `PropertyLawComplex` for the two-pass design + 4-outcome table.
///   - **v1.44**: extends template coverage (idempotence + commutativity
///     + dual-style) and carrier coverage beyond `Complex<Double>`.
///
/// **Opt-in posture.** `verify` is a separate human gesture from
/// `discover` / `drift` / `accept`. Nothing in those pipelines changes.
/// Verified suggestions don't flow into `decisions.json` in v1.42 — the
/// accept-flow integration is deferred to Phase 4 of the rollout.
extension SwiftInferCommand {

    public struct Verify: AsyncParsableCommand {

        public static let configuration = CommandConfiguration(
            commandName: "verify",
            abstract: "Compile and run a candidate property test (PRD §20.2 follow-up). "
                + "Opt-in; nothing in discover/drift/accept changes. "
                + "v1.42 supports round-trip suggestions on Complex<Double> carriers."
        )

        @Option(
            name: .long,
            help: """
            Hash prefix of the suggestion to verify. Matches the prefix \
            of `SuggestionIdentity.hash` shown in the `discover` \
            explainability block. If the prefix matches multiple \
            suggestions an ambiguity error names the candidates; if it \
            matches none an error names the closest few.
            """
        )
        public var suggestion: String

        @Option(
            name: .long,
            help: """
            SwiftPM target containing the suggestion's source. When \
            omitted, swift-infer walks up from the working directory to \
            find Package.swift and resolves the target from the \
            SemanticIndex entry. Override is useful for multi-target \
            packages where the same hash prefix could live in multiple \
            targets (rare).
            """
        )
        public var target: String?

        @Option(
            name: .long,
            help: """
            Trial budget for the property check. `small` (N=100) is the \
            v1.42 default — single verify call typically completes in \
            ~5s on round-trip-on-Complex<Double>, matches the opt-in / \
            exploration posture of the verify gesture. `standard` \
            (N=1000) trades ~30-60s for higher statistical confidence; \
            this is the budget the v1.45+ accept-flow integration will \
            adopt. Unknown values emit a diagnostic and fall back to \
            `small`.
            """
        )
        public var budget: String = "small"

        @Option(
            name: .long,
            help: """
            Path to a specific index file. When omitted, swift-infer \
            walks up from the working directory to find Package.swift, \
            then reads `<package-root>/.swiftinfer/index.json`. If the \
            index is missing or stale (any tracked source's mtime is \
            newer than the index file's), v1.42 reindexes on demand \
            before the suggestion lookup — see the V1.42.C.1 design \
            note in `docs/v1.42 Calibration Plan.md`.
            """
        )
        public var indexPath: String?

        public init() {}

        public func run() async throws {
            // V1.42.B placeholder. The actual harness (subprocess
            // synthesis + stub emission + result rendering) lands in
            // V1.42.C; we surface a clear diagnostic here so anyone
            // running the subcommand against a V1.42.B build sees a
            // load-bearing error rather than a silent no-op.
            throw VerifyError.harnessNotYetWired
        }
    }
}

/// Errors surfaced by the `verify` subcommand. Hoisted to file scope
/// (rather than nested under `SwiftInferCommand.Verify`) to satisfy the
/// `nesting` lint rule's 1-level cap — `Verify` is already nested inside
/// `SwiftInferCommand` via the extension, so a third level here would
/// violate the rule. Public so tests can pattern-match on the case
/// rather than the rendered text.
///
/// **Cycle progression.** V1.42.B shipped `.harnessNotYetWired` only.
/// V1.42.C.1 adds `.suggestionNotFound`, `.ambiguousPrefix`,
/// `.indexMissing`, `.indexEmpty`. V1.42.C.2 adds `.unsupportedCarrier`.
/// V1.42.C.3 adds `.buildFailed`, `.runnerCrashed`.
public enum VerifyError: Error, CustomStringConvertible {
    case harnessNotYetWired
    case suggestionNotFound(prefix: String, closest: [String])
    case ambiguousPrefix(prefix: String, matches: [String])
    case indexMissing(expectedPath: URL)
    case indexEmpty(path: URL?)
    case unsupportedCarrier(carrier: String, expected: [String])
    case buildFailed(exitCode: Int32, stderr: String)
    case runnerCrashed(reason: String)

    public var description: String {
        switch self {
        case .harnessNotYetWired:
            return "swift-infer verify: V1.42.B argument surface is in place but "
                + "the harness pipeline lands in V1.42.C. Try again after the next "
                + "v1.42 deliverable."

        case let .suggestionNotFound(prefix, closest):
            let suffix = closest.isEmpty
                ? ""
                : ". Nearest known hashes: \(closest.joined(separator: ", "))"
            return "swift-infer verify: no suggestion found with identity-hash prefix '\(prefix)'\(suffix)"

        case let .ambiguousPrefix(prefix, matches):
            return "swift-infer verify: identity-hash prefix '\(prefix)' is ambiguous — "
                + "matches \(matches.count) entries: \(matches.joined(separator: ", ")). "
                + "Lengthen the prefix to disambiguate."

        case let .indexMissing(path):
            return "swift-infer verify: SemanticIndex not found at \(path.path). "
                + "Run `swift-infer index --target <X>` first to build it. "
                + "(V1.42.C.5 will reindex on demand; not yet wired.)"

        case let .indexEmpty(path):
            let location = path.map { "at \($0.path)" } ?? "(default path)"
            return "swift-infer verify: SemanticIndex \(location) has zero entries. "
                + "Run `swift-infer index --target <X>` to populate it."

        case let .unsupportedCarrier(carrier, expected):
            let expectedList = expected.joined(separator: ", ")
            return "swift-infer verify: carrier type '\(carrier)' is not supported in v1.42. "
                + "Supported carriers: \(expectedList). Wider carrier support lands in v1.44 "
                + "once the kit-side generators for additional carriers ship."

        case let .buildFailed(exitCode, stderr):
            let snippet = stderr.isEmpty
                ? "(no stderr captured)"
                : stderr.split(separator: "\n").suffix(20).joined(separator: "\n")
            return "swift-infer verify: `swift build` in the verifier workdir failed with "
                + "exit code \(exitCode). Last 20 lines of stderr:\n\(snippet)"

        case let .runnerCrashed(reason):
            return "swift-infer verify: verifier subprocess could not run: \(reason)"
        }
    }
}
