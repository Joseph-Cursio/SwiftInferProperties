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
            let emission = KitSuiteEmitter.emit(
                findings: findings, shapes: shapes, moduleName: moduleName
            )

            // The summary goes to stderr so `--output`-less runs can be piped into a file
            // without the counts landing inside the Swift source.
            diagnostics.writeDiagnostic(
                "note: \(emission.liveCarriers) carrier(s) / \(emission.liveLaws) law(s) "
                    + "emitted live; \(emission.blockedCarriers) carrier(s) / "
                    + "\(emission.blockedLaws) law(s) commented out pending a hand-written "
                    + "`gen()`. Nothing was written into your build."
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
    }
}
