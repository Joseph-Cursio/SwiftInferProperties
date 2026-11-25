import Foundation

// The two runners `execute(workingDirectory:runners:)` dispatches to, split out so a test can
// substitute them. What they cover is the WIRING: that a parsed flag reaches the runner and that
// the exit gate reads what the runner returned. The runners themselves and the gate's rule are
// tested on their own; with only those tests, dropping `persistEvidence:` from the `--suggestion`
// call, or deleting either gate call, left the fast suite green.
extension SwiftInferCommand.Verify {

    /// What `execute` hands the `--suggestion` runner: exactly `runPipeline`'s arguments.
    struct SuggestionRequest: Equatable {
        var suggestionPrefix: String
        var indexPathOverride: String?
        var budgetString: String
        var workingDirectory: URL
        var emitRegression: Bool
        var target: String?
        var persistEvidence: Bool
    }

    /// What `execute` hands the `--all-from-index` runner: exactly `runAllFromIndex`'s arguments.
    struct SurveyRequest: Equatable {
        var indexPathOverride: String?
        var budgetString: String
        var workingDirectory: URL
        var maxParallel: Int
        var templateFilter: String?
        var persistEvidence: Bool
        var scanDependencies: Bool
        var corpusModuleName: String?
        var emitRegression: Bool
    }

    struct Runners {
        var suggestion: (SuggestionRequest) throws -> VerifyRun
        var survey: (SurveyRequest) throws -> [SurveyRecord]

        /// The real pipeline and survey. `run()` always uses these. Computed, not stored: a
        /// stored static of a non-`Sendable` closure pair is a Swift 6 error.
        static var live: Self {
            Self(
                suggestion: { request in
                    try SwiftInferCommand.Verify.runPipeline(
                        suggestionPrefix: request.suggestionPrefix,
                        indexPathOverride: request.indexPathOverride,
                        budgetString: request.budgetString,
                        workingDirectory: request.workingDirectory,
                        emitRegression: request.emitRegression,
                        target: request.target,
                        persistEvidence: request.persistEvidence
                    )
                },
                survey: { request in
                    try SwiftInferCommand.Verify.runAllFromIndex(
                        indexPathOverride: request.indexPathOverride,
                        budgetString: request.budgetString,
                        workingDirectory: request.workingDirectory,
                        maxParallel: request.maxParallel,
                        templateFilter: request.templateFilter,
                        persistEvidence: request.persistEvidence,
                        scanDependencies: request.scanDependencies,
                        corpusModuleName: request.corpusModuleName,
                        emitRegression: request.emitRegression
                    )
                }
            )
        }
    }
}
