import ArgumentParser
import Foundation
import SwiftInferCore

extension SwiftInferCommand {

    /// `swift-infer scaffold-kit-suites` — write out the PropertyLawKit conformance laws
    /// your types already owe.
    ///
    /// Measured on this repo: the kit's suites cover **996 laws over 299 carriers**, of which
    /// **5 execute**. Not because the laws are hard — because nothing wrote the calls.
    /// `ProtocolCoverageMap`'s veto suppresses each one during `discover` with a message that
    /// *names* `check<Protocol>PropertyLaws` and generates nothing, leaving ~299 call sites
    /// to type by hand.
    ///
    /// Read-only over your source; prints to stdout unless `--output` is given, and never
    /// writes into a build without being asked. Same posture as every other command here —
    /// the tool proposes, a human decides.
    public struct ScaffoldKitSuites: AsyncParsableCommand {

        public static let configuration = CommandConfiguration(
            commandName: "scaffold-kit-suites",
            abstract: "Emit the PropertyLawKit conformance-law tests your types already owe."
        )

        @Option(name: .long, help: "Name of the SwiftPM target to scan (Sources/<target>/).")
        public var target: String?

        @Option(
            name: .long,
            help: """
            Path to a source directory to scan directly, bypassing the \
            Sources/<target>/ convention. The Xcode escape hatch. Mutually \
            exclusive with --target; pass exactly one.
            """
        )
        public var sources: String?

        @Option(
            name: .long,
            help: """
            Module name for the emitted `@testable import`. Defaults to --target's \
            value; required when scanning with --sources, since a directory does not \
            name a module.
            """
        )
        public var module: String?

        @Option(name: .long, help: "Write to this path instead of stdout.")
        public var output: String?

        public init() { /* no-op */ }

        public func run() async throws {
            let directory = try TargetDirectory.resolveScan(target: target, sources: sources)
            guard let moduleName = module ?? target else {
                throw ValidationError(
                    "--module is required with --sources: the emitted file needs a module to "
                        + "`@testable import`, and a directory path does not name one."
                )
            }
            let diagnostics = PrintDiagnosticOutput()
            // Threaded rather than left at `.unrun`: the pipeline emits its own coverage
            // note, and without the evidence it announces "there is no kit evidence saying
            // it ran" on a project that has recorded some — a false statement, printed
            // immediately above this command's own correct counts.
            let evidence = SwiftInferCommand.Discover.loadEvidence(
                directory: directory, diagnostics: diagnostics
            )
            let pipeline = try SwiftInferCommand.Discover.collectVisibleSuggestions(
                directory: directory,
                includePossible: true,
                evidence: evidence,
                diagnostics: diagnostics
            )
            let shapes = pipeline.typeShapesByName
            let findings = ProtocolCoverageAudit.audit(
                inheritedTypesByName: pipeline.inheritedTypesByName,
                kitEvidence: evidence.kit
            )
            // Only consulted for `--target`, deliberately. `--sources` exists to bypass the
            // `Sources/<target>/` convention entirely — an Xcode app has no manifest target —
            // so attributing a manifest target's settings to an arbitrary directory would be a
            // guess, and `--module` names a module rather than necessarily a manifest target.
            // No answer beats a wrong one: `nil` here emits exactly as before.
            let defaultIsolation = target.flatMap { targetName in
                TargetIsolation.packageRoot(containing: directory).flatMap {
                    TargetIsolation.defaultIsolation(packageRoot: $0, targetName: targetName)
                }
            }
            let emission = KitSuiteEmitter.emit(
                findings: findings,
                shapes: shapes,
                moduleName: moduleName,
                genericParametersByName: pipeline.genericParametersByName,
                defaultIsolation: defaultIsolation
            )

            reportCounts(
                emission, defaultIsolation: defaultIsolation, diagnostics: diagnostics
            )
            if let output {
                let url = URL(fileURLWithPath: output)
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(), withIntermediateDirectories: true
                )
                try emission.source.write(to: url, atomically: true, encoding: .utf8)
                print("Wrote \(output)")
            } else {
                print(emission.source)
            }
        }

        /// The stderr summary. Extracted from `run()` on 2026-08-13, when the isolation note
        /// pushed that body past the 50-line cap.
        ///
        /// Goes to stderr so an `--output`-less run can be piped into a file without the
        /// counts landing inside the Swift source.
        private func reportCounts(
            _ emission: KitSuiteEmitter.Emission,
            defaultIsolation: String?,
            diagnostics: PrintDiagnosticOutput
        ) {
            // **Cause-neutral wording, because there are four blocking gates and this line
            // used to name one.** It read "commented out pending a hand-written `gen()`",
            // which is true only of the `.todo` gate — a carrier blocked on instantiation, on
            // type-check overrun, or on target isolation is not waiting for a `gen()`, and
            // writing one changes nothing. Each block carries its own reason; this line
            // reports the count and stops claiming to know why.
            diagnostics.writeDiagnostic(
                "note: \(emission.liveCarriers) carrier(s) / \(emission.liveLaws) law(s) "
                    + "emitted live; \(emission.blockedCarriers) carrier(s) / "
                    + "\(emission.blockedLaws) law(s) commented out, each with its reason. "
                    + "Nothing was written into your build."
            )
            // Surfaced separately because it is the one blocking cause that is a single
            // setting rather than a per-carrier gap: it explains EVERY block in the run, and
            // a reader who fixes it gets all of them back at once.
            guard let defaultIsolation else { return }
            diagnostics.writeDiagnostic(
                "note: every carrier is blocked by one setting — target `\(target ?? "")` "
                    + "sets `.defaultIsolation(\(defaultIsolation).self)`, so its conformances "
                    + "are \(defaultIsolation)-isolated and cannot satisfy "
                    + "`check<Protocol>PropertyLaws`' `Value: Sendable` requirement. Types "
                    + "declared `nonisolated` are exempt, and this gate cannot see that — it "
                    + "blocks the whole target, so re-run after changing it."
            )
        }
    }
}
