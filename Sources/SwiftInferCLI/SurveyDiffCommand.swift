import ArgumentParser
import Foundation

/// `swift-infer survey-diff --before <run.json> --after <run.json>` — compare two runs
/// retained by `prove-then-show --retain-run`.
///
/// Read `RetainedSurveyRun`'s doc for why the retained artifact is the survey stream rather
/// than `.swiftinfer/verify-evidence.json`, and `SurveyRunDiff`'s for why a change of decline
/// *cause* inside one bucket is reported as loudly as a change of bucket.
extension SwiftInferCommand {

    public struct SurveyDiff: ParsableCommand {

        public static let configuration = CommandConfiguration(
            commandName: "survey-diff",
            abstract: "Compare two retained prove-then-show runs row by row: which picks "
                + "changed bucket, which changed only their decline cause, which came and went."
        )

        @Option(name: .long, help: "Path to the earlier retained run (JSON).")
        public var before: String

        @Option(name: .long, help: "Path to the later retained run (JSON).")
        public var after: String

        public init() { /* no-op */ }

        public func run() throws {
            let earlier = try load(before, side: "--before")
            let later = try load(after, side: "--after")
            print(
                SurveyRunDiffRenderer.render(
                    SurveyRunDiff.compare(before: earlier, after: later),
                    before: earlier,
                    after: later
                ),
                terminator: ""
            )
        }

        /// Failure names the flag and the path, because the two runs are read one after the
        /// other and "no such file" alone does not say which side is missing.
        private func load(_ path: String, side: String) throws -> RetainedSurveyRun {
            do {
                return try RetainedSurveyRun.read(from: URL(fileURLWithPath: path))
            } catch {
                throw VerifyError.invalidArguments(
                    reason: "\(side) could not be read as a retained survey run at '\(path)': "
                        + "\(error). Retained runs are written by "
                        + "`prove-then-show --retain-run <path>`."
                )
            }
        }
    }
}
