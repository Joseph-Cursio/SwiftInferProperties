import ArgumentParser
import Foundation
import SwiftInferCore

/// V1.144 — `swift-infer prove-then-show`. The one-shot inversion of the
/// conservative default: instead of *hiding* low-confidence `Possible` picks
/// to avoid false positives, it **tests** them and shows what survives.
///
/// Three steps: (1) index the target WITH Possible-tier picks included, (2)
/// run the measured verify survey over every pick, (3) render the classified
/// result — Proven (surface), Disproven (drop), Unverifiable (couldn't be
/// tested — explicitly NOT a pass), Inconclusive.
///
/// Bounded by carrier constructibility — the Unverifiable bucket is honest
/// about what execution could not reach.
///
/// **`--corpus-module` was required, and requiring it was the single largest
/// source of false coverage limits this command had.** The flag selects the
/// curated-corpus wiring, which imports the module *plainly* on purpose — a
/// corpus is consumed as a library, not opened up (see `surveyWiring`). Point
/// that at the package you are standing in and every `internal` symbol becomes
/// invisible, so entries fail to compile with *cannot find 'X' in scope* and
/// land in Inconclusive, which reads as a tooling error rather than as the
/// access-control boundary it is.
///
/// Measured on `SwiftProjectLintRules` (2026-08-05, 26 picks): **with**
/// `--corpus-module`, 0 Proven / 18 build-failed; **without** it, 18 executed
/// and passed, 0 build failures — the same binary, the same index, one flag.
/// Omitting it routes to the per-entry derivation that emits
/// `@testable import <Module>`, which `VerifierSubprocess.runSwiftBuild` has
/// been able to honour since V1.149 (it passes `-Xswiftc -enable-testing` on
/// every build). Nothing needed building; the capability was already there and
/// the flag was suppressing it.
extension SwiftInferCommand {

    public struct ProveThenShow: AsyncParsableCommand {

        public static let configuration = CommandConfiguration(
            commandName: "prove-then-show",
            abstract: "Verify every pick (incl. Possible-tier) and show what survives: "
                + "Proven / Disproven / Unverifiable. The test-then-surface inversion of the "
                + "hide-Possible default."
        )

        @Option(name: .long, help: "Override the working directory (defaults to the current dir).")
        public var directory: String?

        @Option(name: .long, help: "SwiftPM target to index + verify (resolved to Sources/<target>).")
        public var target: String?

        @Option(
            name: .long,
            help: """
            Survey a registered corpus by id (see `swift-infer corpus`), resolving the tree, \
            the target and the run label out of \(CorpusManifest.relativePath) instead of the \
            prompt. Mutually exclusive with --target and --directory: two sources of truth for \
            which tree was surveyed is the defect this flag exists to remove. Warns, loudly and \
            in the retained label, when the checkout has moved off the revision its baseline \
            was measured at.
            """
        )
        public var corpus: String?

        @Option(
            name: .long,
            help: """
            CURATED-CORPUS module name: a separate package consumed as a \
            library, imported plainly. Omit when proving the package you are \
            standing in — the survey then derives the module per entry and \
            imports it `@testable`, which is what reaches `internal` symbols.
            """
        )
        public var corpusModule: String?

        @Option(name: .long, help: "Max concurrent verifier builds (default 4).")
        public var maxParallel: Int = 4

        @Option(name: .long, help: "Trial budget: small | medium | large (default small).")
        public var budget: String = "standard"

        @Option(name: .long, help: "Only verify picks from this template (e.g. 'commutativity').")
        public var template: String?

        @Option(
            name: .long,
            help: "Which surface to prove: algebraic (default) or interaction (reducer/MVVM invariants)."
        )
        public var surface: String = "algebraic"

        @Option(
            name: .long,
            help: "Interaction only: restrict to one invariant family (e.g. 'idempotence')."
        )
        public var family: String?

        @Option(
            name: .long,
            help: """
            Retain this run's per-pick records to a JSON file so a later run can be diffed \
            against it with `swift-infer survey-diff`. Write it somewhere COMMITTED — \
            `fixtures/verify-runs/` — because `.swiftinfer/` is swept by `make clean-temp` \
            and that is how the last four surveys were lost.
            """
        )
        public var retainRun: String?

        @Option(
            name: .long,
            help: """
            Human-readable name for the retained run, recorded in the file. Defaults to \
            '<target> @ <revision>'. Names the ARM, not the file — a reader comparing two \
            runs months apart needs to know what differed.
            """
        )
        public var retainLabel: String?

        public init() { /* no-op */ }

        @Flag(
            name: .long,
            help: """
            Record type shapes for types declared in a DEPENDENCY, not just
            this package. Off by default for the reason `IndexCommand` gives:
            it took this repo's index from 283 shapes to 2,313 and 3.4 MB, and
            the index keys on the BARE type name, so a wider population is where
            a name collision starts to matter. Turn it on when a survey declines
            `unsupported-carrier` for a type the package does not declare.
            """
        )
        public var scanDependencies: Bool = false

        /// Resolve the survey, and emit any corpus warnings **before** the work starts.
        ///
        /// Before, not after: a survey is minutes to tens of minutes, and a caveat printed at
        /// the end arrives after the reader has already started reading the report.
        func resolveSurvey() throws -> ResolvedSurvey {
            guard let corpus else {
                guard let target else {
                    throw VerifyError.invalidArguments(
                        reason: "pass --target <name>, or --corpus <id> to survey a registered "
                            + "corpus (see `swift-infer corpus`)"
                    )
                }
                return ResolvedSurvey(
                    directory: URL(fileURLWithPath: directory ?? "."),
                    target: target,
                    derivedLabel: nil
                )
            }
            guard target == nil, directory == nil else {
                throw VerifyError.invalidArguments(
                    reason: "--corpus is mutually exclusive with --target and --directory; the "
                        + "manifest supplies both. Two sources of truth for which tree was "
                        + "surveyed is the defect --corpus exists to remove."
                )
            }
            let plan = try CorpusRunPlan.resolve(
                corpusID: corpus, manifestRoot: URL(fileURLWithPath: ".")
            )
            for warning in plan.warnings {
                FileHandle.standardError.write(Data("warning: \(warning)\n".utf8))
            }
            return ResolvedSurvey(
                directory: plan.directory, target: plan.target, derivedLabel: plan.label
            )
        }

        public func run() async throws {
            let survey = try resolveSurvey()

            if surface == "interaction" {
                guard let corpusModule else {
                    throw VerifyError.invalidArguments(
                        reason: "--surface interaction requires --corpus-module "
                            + "(the interaction survey has no per-entry derivation)"
                    )
                }
                let entries = try await VerifyInteractionSurvey.collectEntries(
                    targets: [survey.target],
                    familyFilter: family,
                    userModuleName: corpusModule,
                    maxParallel: maxParallel,
                    workingDirectory: survey.directory
                )
                print(ProveThenShowRenderer.render(interactionEntries: entries), terminator: "")
                return
            }
            if surface != "algebraic" {
                FileHandle.standardError.write(
                    Data("warning: unknown --surface '\(surface)'; using algebraic\n".utf8)
                )
            }
            try await runAlgebraic(survey: survey)
        }

        /// Pre-verify tier per identity hash, read back off the index written in step 1.
        ///
        /// Best-effort: an unreadable index yields an empty map, and an empty map leaves
        /// every refutation in DISPROVEN. That is the conservative direction — a missing
        /// tier must never promote a row into a section headed "read these first".
        private func loadPreVerifyTiers(workingDirectory: URL) -> [String: Tier] {
            let packageRoot = SwiftInferCommand.Verify
                .findPackageRoot(startingFrom: workingDirectory) ?? workingDirectory
            let index: IndexStore.Index
            do {
                index = try SwiftInferCommand.Verify.loadIndex(
                    indexPathOverride: nil, packageRoot: packageRoot
                )
            } catch {
                // The conservative direction is argued above and is unchanged. What was
                // missing is that the degradation is invisible: step 1 wrote this index
                // moments ago, so failing to read it back is anomalous, and every row
                // silently loses the tier that decides whether it is worth reading first.
                FileHandle.standardError.write(Data(
                    ("warning: could not read back the index just written at \(packageRoot.path)"
                        + " — \(error). Every refutation will render without its pre-verify"
                        + " tier, which is conservative but means the ranking is absent"
                        + " rather than computed.\n").utf8
                ))
                return [:]
            }
            var tiers: [String: Tier] = [:]
            for entry in index.entries {
                tiers[entry.identityHash] = Tier(rawValue: entry.tier.lowercased())
            }
            return tiers
        }

        private func runAlgebraic(survey: ResolvedSurvey) async throws {
            let workingDirectory = survey.directory
            let target = survey.target

            // 1. Index WITH Possible — the whole point is to test the
            //    low-confidence picks the default view hides.
            // `Sources/<target>` is SwiftPM's DEFAULT, not a rule. GRDB declares
            // `path: "GRDB"` and was unreachable entirely — see
            // `TargetIsolation.sourceDirectory`, which falls back to exactly this path
            // whenever the manifest cannot answer.
            let scanDirectory = TargetIsolation.sourceDirectory(
                packageRoot: SwiftInferCommand.Verify
                    .findPackageRoot(startingFrom: workingDirectory) ?? workingDirectory,
                targetName: target
            )
            _ = try SwiftInferCommand.Index.performIndex(
                IndexInputs(
                    scanDirectory: scanDirectory,
                    includePossible: true,
                    explicitVocabularyPath: nil,
                    explicitConfigPath: nil,
                    explicitTestDirPath: nil,
                    packsOverride: nil,
                    dryRun: false,
                    targetName: target,
                    workingDirectory: workingDirectory,
                    // Without this the dependency shape is never recorded, and a carrier
                    // the package does not declare declines `unsupported-carrier` — which
                    // reads as "no generator exists" when the truth is "no shape was
                    // scanned". `DependencyTypeShapes` exists for exactly this and was
                    // reachable only from `index` and `verify`, never from here.
                    scanDependencies: scanDependencies
                ),
                diagnostics: StderrDiagnosticOutput()
            )

            // 2. Prove — run the survey quietly (no JSON stream); keep the
            //    live records (they carry the Unverifiable outcome that the
            //    persisted evidence collapses away).
            let records = try await SwiftInferCommand.Verify.runAllFromIndex(
                indexPathOverride: nil,
                budgetString: budget,
                workingDirectory: workingDirectory,
                maxParallel: maxParallel,
                templateFilter: template,
                corpusModuleName: corpusModule,
                quiet: true
            )

            // 3. Show. The PRE-verify tier comes from the index just built, keyed by
            //    identity: `SurveyRecord` does not carry one, and the effective tier after
            //    verify would be the wrong input — `Tier.promoted(byVerifyOutcome:)` only
            //    moves on a pass, but reading a post-verify tier here would invite that
            //    confusion the first time it does move.
            let tiers = loadPreVerifyTiers(workingDirectory: workingDirectory)
            print(ProveThenShowRenderer.render(records, tiers: tiers), terminator: "")
            retainIfRequested(records: records, tiers: tiers, survey: survey)
        }

        /// Write the retained run, when `--retain-run` asked for one.
        ///
        /// **Best-effort, and it warns rather than throwing** — the report on stdout is the
        /// primary output and a 12-minute survey must not fail at the last step because a
        /// directory is not writable. That is the same posture `VerifyEvidenceRecorder` takes
        /// for the evidence side file, for the same reason.
        private func retainIfRequested(
            records: [SwiftInferCommand.Verify.SurveyRecord],
            tiers: [String: Tier],
            survey: ResolvedSurvey
        ) {
            guard let retainRun else { return }
            let target = survey.target
            let packageRoot = SwiftInferCommand.Verify
                .findPackageRoot(startingFrom: survey.directory) ?? survey.directory
            let run = RetainedSurveyRun.capturing(
                records: records,
                tiers: tiers,
                context: RetainedSurveyRun.Context(
                    // An explicit --retain-label still wins: the manifest removes the NEED to
                    // hand-type one, not the ability to say what an unusual arm was.
                    label: retainLabel
                        ?? survey.derivedLabel
                        ?? "\(target) @ \(CorpusProvenance.describe(packageRoot))",
                    target: target,
                    packageRoot: packageRoot,
                    capturedAt: Date()
                )
            )
            let destination = URL(fileURLWithPath: retainRun)
            do {
                try run.write(to: destination)
                FileHandle.standardError.write(Data(
                    ("retained \(records.count) record(s) to \(destination.path) — diff a later "
                        + "run with `swift-infer survey-diff --before \(retainRun) "
                        + "--after <next>`\n").utf8
                ))
            } catch {
                FileHandle.standardError.write(Data(
                    ("warning: could not retain this run to \(destination.path) — \(error). "
                        + "The report above is unaffected, but there is now no artifact to "
                        + "compare the next run against.\n").utf8
                ))
            }
        }
    }
}

/// Routes indexer diagnostics to stderr so they don't pollute the
/// prove-then-show report on stdout.
private struct StderrDiagnosticOutput: DiagnosticOutput {
    func writeDiagnostic(_ text: String) {
        FileHandle.standardError.write(Data("\(text)\n".utf8))
    }
}
