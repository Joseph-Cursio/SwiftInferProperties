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
/// **Phase 1 across cycles** — see
/// `git show c090031:'docs/v1.42 Calibration Plan.md'`:
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
            SwiftPM target containing the suggestion's source. The \
            verifier path-depends on that package and @testable-imports \
            the module, which is what lets a law reach carriers and \
            functions you defined. When omitted, it is derived from the \
            entry's own source path (Sources/<target>/…). Pass it \
            explicitly for a layout that derivation declines — a module \
            inside a nested package, or sources outside Sources/.
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

        /// V1.143.B — corpus-first regression gate. Re-checks every recorded
        /// counterexample in `.swiftinfer/verify-corpus.json` (re-verifying each
        /// identity, which reproduces the stored counterexample via the
        /// deterministic seed) and reports still-failing vs now-holding. Exits
        /// non-zero if any recorded counterexample still fails. Ignores
        /// `--suggestion` / `--all-from-index`.
        @Flag(
            name: .long,
            help: """
            Re-check every recorded counterexample in \
            .swiftinfer/verify-corpus.json (regression gate). Exits non-zero if \
            any still fail.
            """
        )
        public var replayOnly: Bool = false

        @Flag(
            name: .long,
            inversion: .prefixedNo,
            help: """
            Persist this run's verdicts to .swiftinfer/verify-evidence.json (and \
            the replay corpus). On by default. Pass --no-persist-evidence when \
            the run is being COMPARED against that file: persisting first makes \
            the comparison a comparison against this run's own output, which has \
            silently produced a false "0 drift" twice.
            """
        )
        public var persistEvidence: Bool = true

        @Flag(
            name: .long,
            help: """
            When verify reindexes on demand, also record shapes for types declared in \
            resolved dependencies. Off by default — see `index --scan-dependencies`. \
            Without it, a law whose carrier is declared in a dependency keeps declining \
            as `unsupported-carrier`.
            """
        )
        public var scanDependencies: Bool = false

        public init() { /* no-op */ }

        public func run() async throws {
            let workingDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            if replayOnly {
                try await Self.runReplayOnly(
                    indexPathOverride: indexPath,
                    budgetString: budget,
                    workingDirectory: workingDirectory
                )
                return
            }
            if allFromIndex {
                if suggestion != nil {
                    throw VerifyError.invalidArguments(
                        reason: "--suggestion and --all-from-index are mutually exclusive"
                    )
                }
                try await Self.runAllFromIndex(
                    persistEvidence: persistEvidence,
                    scanDependencies: scanDependencies,
                    indexPathOverride: indexPath,
                    budgetString: budget,
                    workingDirectory: workingDirectory,
                    maxParallel: maxParallel,
                    templateFilter: template,
                    corpusModuleName: corpusModule,
                    emitRegression: emitRegression ?? false
                )
                return
            }
            guard let suggestion else {
                throw VerifyError.invalidArguments(
                    reason: "either --suggestion <hash> or --all-from-index is required"
                )
            }
            let run = try Self.runPipeline(
                suggestionPrefix: suggestion,
                indexPathOverride: indexPath,
                budgetString: budget,
                workingDirectory: workingDirectory,
                emitRegression: emitRegression ?? true,
                target: target
            )
            // `.rendered`, not the value itself — printing the struct compiles fine and emits a
            // memberwise description, which is the same class of silent wrong answer #116 is about.
            print(run.rendered)
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
/// **On version numbers in these messages: don't.** Three of these refusals used to read "not
/// supported in v1.42 … wider support lands in v1.44", and a fourth case, `.harnessNotYetWired`,
/// told the reader to "try again after the next v1.42 deliverable". Pointing the tool at
/// SwiftProjectLint on 2026-08-11 surfaced all four from a **1.149.0** binary: the reader is
/// refused, and then told to wait for a release that shipped a hundred versions ago without
/// delivering the thing. A refusal is the one message a user is guaranteed to read closely, so it
/// must name the actual gate — what would have to be true — rather than a date.
///
/// `.harnessNotYetWired` was deleted in the same pass. Nothing had raised it since V1.42.C.6; its
/// only reference was a test asserting the description was "still load-bearing", which is the
/// `make dead-code` **test-only** verdict — a passing suite keeping dead code looking maintained.
///
/// `.missingPairedFunction` below is the shape to copy: it dates its claim ("before 2026-08-08")
/// and names the remedy, so it stays true or becomes visibly false.
public enum VerifyError: Error, CustomStringConvertible {
    case suggestionNotFound(prefix: String, closest: [String])
    case ambiguousPrefix(prefix: String, matches: [String])
    case indexMissing(expectedPath: URL)
    case indexEmpty(path: URL?)
    case unsupportedCarrier(carrier: String, expected: [String])
    case buildFailed(exitCode: Int32, stderr: String)
    case runnerCrashed(reason: String)
    case unsupportedTemplate(template: String, expected: [String])
    case unsupportedPair(forward: String, supported: [String])
    /// A two-function law whose entry carries only its primary half.
    ///
    /// Distinct from `.unsupportedPair`, which means *this function is not in
    /// the curated table*. `differential-equivalence` has no curated table by
    /// design — it reconstructs its pair from `secondaryFunctionName`, which the
    /// index populated for round-trip only until 2026-08-08. So the failure is
    /// a **stale entry**, and the remedy is re-indexing rather than expanding a
    /// list; saying "not in the curated pair list" would send the reader to fix
    /// the wrong thing.
    case missingPairedFunction(template: String, primary: String)
    /// Monotonicity pre-flight: the property `a ≤ b ⟹ f(a) ≤ f(b)` orders the
    /// input domain with `min`/`max`, so a non-`Comparable` domain can't be
    /// verified (the ordering is undefined). Thrown at emit so the doomed
    /// `swift build` is skipped; maps to architectural-coverage-pending.
    case monotonicityDomainNotComparable(domain: String)
    /// V1.50.B — argument-validation error surfaced when the user
    /// passes a forbidden combination (e.g., `--suggestion` and
    /// `--all-from-index` together, or neither).
    case invalidArguments(reason: String)

    public var description: String {
        switch self {
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
            return "swift-infer verify: no generator could be derived for carrier type "
                + "'\(carrier)', so there is no domain to quantify over. Carriers reachable "
                + "today: \(expectedList). The gate is a generator, not a release: this clears "
                + "when `DerivationStrategist` derives one for the type, or when the kit ships "
                + "it — for SwiftSyntax nodes, `PropertyLawSyntax` vends generators for the "
                + "erased base types and is opt-in via --extra-import."

        case let .buildFailed(exitCode, diagnostics):
            // `diagnostics` is already the extracted cause — see
            // `BuildDiagnostics`, and note that `swift build` puts compile
            // errors on *stdout*, which is why this used to print nothing.
            let snippet = diagnostics.isEmpty ? "(none captured)" : diagnostics
            return "swift-infer verify: `swift build` in the verifier workdir failed with "
                + "exit code \(exitCode). Compiler diagnosis:\n\(snippet)"

        case let .runnerCrashed(reason):
            return "swift-infer verify: verifier subprocess could not run: \(reason)"

        case let .unsupportedTemplate(template, expected):
            let expectedList = expected.joined(separator: ", ")
            return "swift-infer verify: template '\(template)' has no verify composer, so its "
                + "law is proposed but never executed. Templates that execute: \(expectedList). "
                + "The gate is a composer arm, not a release: a template becomes verifiable once "
                + "it is named in all of `TemplateName.verifiable`, the composer switch, "
                + "`resolveFunctionCalls` and `RenderShape.byTemplateName` — missing one is "
                + "silent, and differently silent each time."

        case let .unsupportedPair(forward, supported):
            let supportedList = supported.joined(separator: ", ")
            return "swift-infer verify: forward-side function '\(forward)' is not in the curated "
                + "round-trip pair list, so nothing names its inverse. Curated forwards: "
                + "\(supportedList). The list is curated because a round-trip pair cannot be "
                + "recovered from one entry — contrast `.missingPairedFunction`, where the pair "
                + "IS reconstructible and the remedy is re-indexing."

        case let .missingPairedFunction(template, primary):
            return "swift-infer verify: the '\(template)' entry for '\(primary)' records no "
                + "second function, so its law has nothing to compare against. This template "
                + "reconstructs its pair from the index rather than a curated list, and the "
                + "index persisted second-half names for round-trip only before 2026-08-08. "
                + "Re-run `swift-infer index` to repopulate the entry."

        case let .invalidArguments(reason):
            return "swift-infer verify: \(reason)"

        case let .monotonicityDomainNotComparable(domain):
            return "swift-infer verify: monotonicity domain '\(domain)' is not Comparable, so "
                + "`a ≤ b ⟹ f(a) ≤ f(b)` has no input ordering to quantify over. The "
                + "monotonicity stub orders the domain with `min`/`max`; a non-Comparable "
                + "domain is architecturally inapplicable, not a measurement gap."
        }
    }
}
