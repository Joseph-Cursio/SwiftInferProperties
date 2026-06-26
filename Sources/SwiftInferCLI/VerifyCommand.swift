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
            matches none an error names the closest few. \
            **V1.50.B**: mutually exclusive with `--all-from-index`; \
            exactly one of the two must be provided.
            """
        )
        public var suggestion: String?

        /// V1.50.B — survey-mode flag. When set, verify iterates
        /// every entry in the loaded `SemanticIndex` (or one matching
        /// the optional `--template` filter), runs the verify
        /// pipeline per-entry, and emits a per-line JSON record to
        /// stdout. The first full-surface verify measurement is
        /// driven by this flag.
        @Flag(
            name: .long,
            help: """
            Survey mode: load the SemanticIndex (default path or via \
            --index-path) and run verify against every entry, \
            emitting one JSON record per entry to stdout. Mutually \
            exclusive with --suggestion. Parallelism controlled via \
            --max-parallel.
            """
        )
        public var allFromIndex: Bool = false

        /// V1.50.B — parallelism cap for survey mode. Each verify
        /// call spawns a `swift build` of a synthesized workdir;
        /// concurrent builds compete for file descriptors + disk +
        /// network. Default 4 keeps headroom under macOS soft FD
        /// limits.
        @Option(
            name: .long,
            help: """
            Maximum concurrent verify subprocesses in --all-from-index \
            survey mode. Each subprocess runs a fresh `swift build` + \
            verifier-binary invocation; high parallelism saturates \
            disk + file descriptors. Default 4.
            """
        )
        public var maxParallel: Int = 4

        /// V1.50.B — optional template filter for survey mode.
        /// Limits `--all-from-index` to entries whose templateName
        /// matches. Useful for surveying a single template arm at a
        /// time without re-running the full 109-pick walk.
        @Option(
            name: .long,
            help: """
            Optional template-name filter for --all-from-index. \
            Entries whose `templateName` doesn't match are skipped \
            silently. Examples: round-trip, idempotence, commutativity, \
            associativity, idempotence-lifted, dual-style-consistency, \
            monotonicity.
            """
        )
        public var template: String?

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
            Trial budget for the property check. `small` (N=100) is the v1.42 \
            default (~5s on round-trip-on-Complex<Double>; matches the opt-in \
            exploration posture). `standard` (N=1000) trades ~30-60s for higher \
            confidence (the v1.45+ accept-flow budget). Unknown values warn and \
            fall back to `small`.
            """
        )
        public var budget: String = "small"

        @Option(
            name: .long,
            help: """
            Path to a specific index file. When omitted, swift-infer \
            walks up to find Package.swift and reads \
            `<package-root>/.swiftinfer/index.json` — reindexing it on \
            demand from a whole-`Sources/` discover pass if it's missing \
            or stale (V1.42.C.5). An explicit `--index-path` is used \
            as-is and never auto-rebuilt.
            """
        )
        public var indexPath: String?

        @Option(
            name: .long,
            help: """
            For `--all-from-index` over a CURATED corpus: the corpus's module \
            name — the verifier path-depends on the working-dir package + \
            imports it so the corpus's own types resolve as carriers. Omit for \
            library-carrier surveys (e.g. cycle27-surface).
            """
        )
        public var corpusModule: String?

        /// V1.142 — auto-bridge toggle. When verify finds a counterexample
        /// (`.defaultFails`), render + write a focused regression test from the
        /// minimal counterexample via `ConvertCounterexampleEngine`. Defaults
        /// ON for `--suggestion` runs (the user explicitly asked to verify one
        /// pick) and OFF for `--all-from-index` surveys (which would flood
        /// `Tests/Generated/`). `--no-emit-regression` / `--emit-regression`
        /// override per run.
        @Flag(
            inversion: .prefixedNo,
            help: """
            Auto-generate a focused regression test from the minimal \
            counterexample when verify finds one. Written to \
            Tests/Generated/SwiftInfer/<template>/. Default: on for \
            --suggestion, off for --all-from-index.
            """
        )
        public var emitRegression: Bool?

        public init() { /* no-op */ }

        public func run() async throws {
            let workingDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            if allFromIndex {
                if suggestion != nil {
                    throw VerifyError.invalidArguments(
                        reason: "--suggestion and --all-from-index are mutually exclusive"
                    )
                }
                try await Self.runAllFromIndex(
                    indexPathOverride: indexPath,
                    budgetString: budget,
                    workingDirectory: workingDirectory,
                    maxParallel: maxParallel,
                    templateFilter: template,
                    corpusModuleName: corpusModule
                )
                return
            }
            guard let suggestion else {
                throw VerifyError.invalidArguments(
                    reason: "either --suggestion <hash> or --all-from-index is required"
                )
            }
            let outcome = try Self.runPipeline(
                suggestionPrefix: suggestion,
                indexPathOverride: indexPath,
                budgetString: budget,
                workingDirectory: workingDirectory,
                emitRegression: emitRegression ?? true
            )
            print(outcome)
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
/// V1.42.C.3 adds `.buildFailed`, `.runnerCrashed`. V1.42.C.6 adds
/// `.unsupportedTemplate`, `.unsupportedPair`.
public enum VerifyError: Error, CustomStringConvertible {
    case harnessNotYetWired
    case suggestionNotFound(prefix: String, closest: [String])
    case ambiguousPrefix(prefix: String, matches: [String])
    case indexMissing(expectedPath: URL)
    case indexEmpty(path: URL?)
    case unsupportedCarrier(carrier: String, expected: [String])
    case buildFailed(exitCode: Int32, stderr: String)
    case runnerCrashed(reason: String)
    case unsupportedTemplate(template: String, expected: [String])
    case unsupportedPair(forward: String, supported: [String])
    /// V1.50.B — argument-validation error surfaced when the user
    /// passes a forbidden combination (e.g., `--suggestion` and
    /// `--all-from-index` together, or neither).
    case invalidArguments(reason: String)

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
                + "An explicit --index-path is used as-is. Run `swift-infer index "
                + "--target <X>` to build it (reindex-on-demand covers only the default path)."

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

        case let .unsupportedTemplate(template, expected):
            let expectedList = expected.joined(separator: ", ")
            return "swift-infer verify: suggestion template '\(template)' is not supported in v1.42. "
                + "Supported templates: \(expectedList). Wider template support lands in v1.44."

        case let .unsupportedPair(forward, supported):
            let supportedList = supported.joined(separator: ", ")
            return "swift-infer verify: forward-side function '\(forward)' is not in v1.42's "
                + "curated round-trip pair list. Supported forwards: \(supportedList). "
                + "Pair-list expansion lands in v1.43."

        case let .invalidArguments(reason):
            return "swift-infer verify: \(reason)"
        }
    }
}
