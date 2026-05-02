import ArgumentParser
import Foundation
import SwiftInferCore

/// `swift-infer drift` — diff today's discover output against a
/// previously-snapshotted `.swiftinfer/baseline.json` (M6.5 + PRD
/// §9). Surfaces the §9 CI-annotation-friendly stderr warning for
/// each new Strong-tier suggestion that lacks a recorded decision in
/// `.swiftinfer/decisions.json` (M6.1).
///
/// Exit code is always 0 — drift is non-fatal per PRD §3 non-goals.
/// CI dashboards tracking trends should grep stderr for
/// `warning: drift:` rather than chase a non-zero code.
extension SwiftInferCommand {

    public struct Drift: AsyncParsableCommand {

        public static let configuration = CommandConfiguration(
            commandName: "drift",
            abstract: "Diff current suggestions against a baseline; warn on new Strong-tier candidates."
        )

        @Option(
            name: .long,
            help: "Name of the SwiftPM target to scan. Resolved to Sources/<target>/ relative to the working directory."
        )
        public var target: String

        @Option(
            name: .long,
            help: """
            Path to the baseline file. When omitted, drift walks up from \
            the target directory to the package root and looks for \
            .swiftinfer/baseline.json.
            """
        )
        public var baseline: String?

        @Option(
            name: .long,
            help: """
            Path to a vocabulary file. Same precedence as `discover`'s \
            --vocabulary flag.
            """
        )
        public var vocabulary: String?

        @Option(
            name: .long,
            help: """
            Path to a config file. Same precedence as `discover`'s \
            --config flag.
            """
        )
        public var config: String?

        public init() {}

        public func run() async throws {
            let directory = URL(fileURLWithPath: "Sources").appendingPathComponent(target)
            let explicitVocabularyPath = vocabulary.map { URL(fileURLWithPath: $0) }
            let explicitConfigPath = config.map { URL(fileURLWithPath: $0) }
            let explicitBaselinePath = baseline.map { URL(fileURLWithPath: $0) }
            try Self.run(
                directory: directory,
                explicitVocabularyPath: explicitVocabularyPath,
                explicitConfigPath: explicitConfigPath,
                explicitBaselinePath: explicitBaselinePath,
                output: PrintOutput(),
                diagnostics: PrintDiagnosticOutput()
            )
        }

        /// Pure pipeline — exposed at the type level so tests exercise
        /// drift end-to-end without going through ArgumentParser or
        /// stderr. Loads baseline + decisions, runs the same discover
        /// pipeline as `swift-infer discover`, hands the three to
        /// `DriftDetector`, prints warnings to `diagnostics`. `output`
        /// stays empty when no drift is detected — the CI-friendly
        /// "silent on no-changes" shape.
        public static func run(
            directory: URL,
            explicitVocabularyPath: URL? = nil,
            explicitConfigPath: URL? = nil,
            explicitBaselinePath: URL? = nil,
            output: any DiscoverOutput,
            diagnostics: any DiagnosticOutput = PrintDiagnosticOutput()
        ) throws {
            let pipeline = try SwiftInferCommand.Discover.collectVisibleSuggestions(
                directory: directory,
                explicitVocabularyPath: explicitVocabularyPath,
                explicitConfigPath: explicitConfigPath,
                diagnostics: diagnostics
            )
            let packageRoot = pipeline.packageRoot ?? directory
            let baselineResult = BaselineLoader.load(
                startingFrom: directory,
                explicitPath: explicitBaselinePath
            )
            for warning in baselineResult.warnings {
                diagnostics.writeDiagnostic("warning: \(warning)")
            }
            let decisionsResult = DecisionsLoader.load(startingFrom: packageRoot)
            for warning in decisionsResult.warnings {
                diagnostics.writeDiagnostic("warning: \(warning)")
            }
            let warnings = DriftDetector.warnings(
                currentSuggestions: pipeline.suggestions,
                baseline: baselineResult.baseline,
                decisions: decisionsResult.decisions
            )
            for drift in warnings {
                diagnostics.writeDiagnostic(drift.renderedLine())
            }
            if warnings.isEmpty {
                output.write("No drift detected.")
            } else {
                output.write("\(warnings.count) drift warning\(warnings.count == 1 ? "" : "s") emitted.")
            }
        }
    }
}
