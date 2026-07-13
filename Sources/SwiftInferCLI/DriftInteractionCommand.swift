import ArgumentParser
import Foundation
import SwiftInferCore

/// V2.0 M10 — `swift-infer drift-interaction` subcommand. Diff
/// current interaction-invariant suggestions against a previously-
/// snapshotted `.swiftinfer/interaction-baseline.json` and warn on
/// new Strong-tier candidates per PRD §3.6 step 7 + §16 #3.
///
/// **Non-fatal by design.** Exit code is always 0 — drift is the
/// advisory surface (failing trace replays in
/// `Tests/Generated/SwiftInferTraces/` fail the build instead).
/// CI dashboards tracking drift should grep stderr for `warning:
/// drift:` rather than chase a non-zero exit.
///
/// **Why a separate subcommand vs `drift --interaction`.** PRD §3.6
/// step 7 uses the flag form, but v2.0 has settled on parallel
/// subcommands (`discover-reducers`, `discover-interaction`,
/// `verify-interaction`); `drift-interaction` continues that
/// pattern so the discover/verify/drift triplet has the same
/// shape on both surfaces.
extension SwiftInferCommand {

    public struct DriftInteraction: AsyncParsableCommand {

        public static let configuration = CommandConfiguration(
            commandName: "drift-interaction",
            abstract: "Diff current interaction-invariant suggestions "
                + "against an interaction-baseline; warn (non-fatally) "
                + "on new Strong-tier candidates."
        )

        @Option(
            name: .long,
            help: """
            Name of the SwiftPM target containing reducer-shaped \
            functions. Resolved to Sources/<target>/ relative to the \
            working directory — mirrors `swift-infer \
            discover-interaction` and `verify-interaction`.
            """
        )
        public var target: String

        @Option(
            name: .long,
            help: """
            Path to the interaction-baseline file. When omitted, \
            drift walks up from the target directory to the package \
            root and looks for .swiftinfer/interaction-baseline.json.
            """
        )
        public var baseline: String?

        @Option(
            name: .long,
            help: """
            Optional `<typeName>.<funcName>` (or `<funcName>`) pin \
            selecting which reducer to diff. When omitted, drift \
            runs against every detected reducer in the target.
            """
        )
        public var reducer: String?

        public init() { /* no-op */ }

        public func run() async throws {
            let directory = try TargetDirectory.resolve(target)
            let explicitBaselinePath = baseline.map { URL(fileURLWithPath: $0) }
            let workingDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            try Self.run(
                target: target,
                workingDirectory: workingDirectory,
                directory: directory,
                pinRaw: reducer,
                explicitBaselinePath: explicitBaselinePath,
                output: PrintOutput(),
                diagnostics: PrintDiagnosticOutput()
            )
        }

        /// V2.0 M10 — pure pipeline exposed at the type level so tests
        /// drive drift end-to-end without going through ArgumentParser
        /// or stderr. Loads baseline → runs `discover-interaction`'s
        /// `collectSuggestions` → hands the pair to
        /// `InteractionDriftDetector` → prints warnings to
        /// `diagnostics`. `output` carries the summary line ("N drift
        /// warnings emitted" / "No drift detected.").
        public static func run(
            target: String,
            workingDirectory: URL,
            directory: URL,
            pinRaw: String? = nil,
            explicitBaselinePath: URL? = nil,
            output: any DiscoverOutput,
            diagnostics: any DiagnosticOutput = PrintDiagnosticOutput(),
            firstSeenAt: Date = Date()
        ) throws {
            let suggestions = try SwiftInferCommand.DiscoverInteraction.collectSuggestions(
                target: target,
                pinRaw: pinRaw,
                workingDirectory: workingDirectory,
                firstSeenAt: firstSeenAt
            )
            let baselineResult = InteractionBaselineLoader.load(
                startingFrom: directory,
                explicitPath: explicitBaselinePath
            )
            for warning in baselineResult.warnings {
                diagnostics.writeDiagnostic("warning: \(warning)")
            }
            let decisionsResult = InteractionDecisionsLoader.load(
                startingFrom: baselineResult.packageRoot ?? directory
            )
            for warning in decisionsResult.warnings {
                diagnostics.writeDiagnostic("warning: \(warning)")
            }
            let warnings = InteractionDriftDetector.warnings(
                currentSuggestions: suggestions,
                baseline: baselineResult.baseline,
                decisions: decisionsResult.decisions
            )
            for drift in warnings {
                diagnostics.writeDiagnostic(drift.renderedLine())
            }
            if warnings.isEmpty {
                output.write("No drift detected.")
            } else {
                let pluralS = warnings.count == 1 ? "" : "s"
                output.write("\(warnings.count) drift warning\(pluralS) emitted.")
            }
        }
    }
}
