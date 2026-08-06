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
        public var target: String

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
        public var budget: String = "small"

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

        public init() { /* no-op */ }

        public func run() async throws {
            let workingDirectory = URL(fileURLWithPath: directory ?? ".")

            if surface == "interaction" {
                guard let corpusModule else {
                    throw VerifyError.invalidArguments(
                        reason: "--surface interaction requires --corpus-module "
                            + "(the interaction survey has no per-entry derivation)"
                    )
                }
                let entries = try await VerifyInteractionSurvey.collectEntries(
                    targets: [target],
                    familyFilter: family,
                    userModuleName: corpusModule,
                    maxParallel: maxParallel,
                    workingDirectory: workingDirectory
                )
                print(ProveThenShowRenderer.render(interactionEntries: entries), terminator: "")
                return
            }
            if surface != "algebraic" {
                FileHandle.standardError.write(
                    Data("warning: unknown --surface '\(surface)'; using algebraic\n".utf8)
                )
            }
            try await runAlgebraic(workingDirectory: workingDirectory)
        }

        private func runAlgebraic(workingDirectory: URL) async throws {

            // 1. Index WITH Possible — the whole point is to test the
            //    low-confidence picks the default view hides.
            let scanDirectory = workingDirectory
                .appendingPathComponent("Sources")
                .appendingPathComponent(target)
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
                    workingDirectory: workingDirectory
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

            // 3. Show.
            print(ProveThenShowRenderer.render(records), terminator: "")
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
