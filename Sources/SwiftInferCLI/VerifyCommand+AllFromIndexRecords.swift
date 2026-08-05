import Foundation
import SwiftInferCore

/// Turning a verify outcome into a `SurveyRecord` — split from
/// `VerifyCommand+AllFromIndex.swift` when it hit SwiftLint's 400-line cap.
///
/// The seam is *driving the survey* versus *classifying what came back*. Every
/// function here answers the same question — given what happened, which of the
/// five outcomes is it, and what should the detail say — and that question is
/// where this survey's reporting defects have lived: an entry declining for a
/// reason it does not have reads as a coverage gap, and the census then points
/// work at the wrong constraint.
extension SwiftInferCommand.Verify {

    /// Build a `SurveyRecord` for an error/architectural-pending outcome from
    /// the entry's context. Extracted so `surveyRecord(for:…)` stays under the
    /// function-body-length cap.
    static func surveyErrorRecord(
        _ context: RecordContext,
        _ outcome: SurveyOutcome,
        _ detail: String?
    ) -> SurveyRecord {
        SurveyRecord(
            identityHash: context.identityHash,
            templateName: context.templateName,
            primaryFunctionName: context.primaryFunctionName,
            carrier: context.carrier,
            outcome: outcome,
            outcomeDetail: detail
        )
    }

    /// Decline an entry a DISCOVERY signal already knew could not type-check.
    ///
    /// Trying it would report whichever error the composer reaches first, and that
    /// error names the carrier — which is not the reason. Measured 2026-08-05: all
    /// 45 cross-module round-trip pairs in this repo's index were filed as
    /// `unsupported-carrier`, i.e. as a carrier-reach gap they are not.
    ///
    /// **Saves no build in the general case** — `buildStubBundle` throws before
    /// `runSwiftBuild` for an underivable carrier, so these already declined for
    /// free. What changes is the census. (It did save one: the single cross-type
    /// entry whose carrier *was* derivable reached the compiler and failed there,
    /// which is 46s of the round-trip arm's 46.5s.)
    static func structurallyBlockedRecord(
        for entry: SemanticIndexEntry,
        context: RecordContext
    ) -> SurveyRecord? {
        guard let blocker = entry.structuralBlocker else { return nil }
        return surveyErrorRecord(context, .architecturalCoveragePending, "not-a-candidate: \(blocker)")
    }

    /// V1.89 lint pass — extracted from `surveyRecord(for:…)` so the
    /// per-entry survey worker stays under SwiftLint's 50-line cap.
    /// Classifies a non-zero `swift build` exit into either
    /// `.architecturalCoveragePending` (when the build output matches a
    /// known signature like "no such module" or "compiler crash") or
    /// `.measuredError` (everything else).
    static func surveyRecordForBuildFailure(
        buildOutput: VerifierSubprocess.Output,
        context: RecordContext
    ) -> SurveyRecord {
        if let detail = Self.architecturalPendingDetail(
            buildStdout: buildOutput.stdout,
            buildStderr: buildOutput.stderr
        ) {
            return SurveyRecord(
                identityHash: context.identityHash,
                templateName: context.templateName,
                primaryFunctionName: context.primaryFunctionName,
                carrier: context.carrier,
                outcome: .architecturalCoveragePending,
                outcomeDetail: detail
            )
        }
        return SurveyRecord(
            identityHash: context.identityHash,
            templateName: context.templateName,
            primaryFunctionName: context.primaryFunctionName,
            carrier: context.carrier,
            outcome: .measuredError,
            outcomeDetail: BuildDiagnostics.surveyDetail(from: buildOutput)
        )
    }

    /// V1.142.C — survey-mode auto-bridge (opt-in via `--emit-regression`):
    /// write a regression test per counterexample. Off by default so a
    /// full-index survey doesn't flood `Tests/Generated/`.
    static func emitSurveyRegression(
        _ parsed: VerifyOutcome,
        entry: SemanticIndexEntry,
        packageRoot: URL,
        enabled: Bool
    ) {
        guard enabled, case let .defaultFails(detail) = parsed else { return }
        _ = emitRegressionTest(entry: entry, detail: detail, packageRoot: packageRoot)
    }

    /// Translate the `VerifyOutcome` (from the parser) into a
    /// `SurveyRecord`'s outcome + detail.
    static func surveyRecord(
        from parsed: VerifyOutcome,
        context: RecordContext
    ) -> SurveyRecord {
        let outcome: SurveyOutcome
        let detail: String?
        var counterexample: String?
        var shrunkCounterexample: String?
        switch parsed {
        case let .bothPass(defaultTrials, edgeTrials, edgeSampled):
            outcome = .measuredBothPass
            detail = "defaultTrials=\(defaultTrials) edgeTrials=\(edgeTrials) edgeSampled=\(edgeSampled)"

        case .edgeCaseAdvisory:
            outcome = .measuredEdgeCaseAdvisory
            detail = nil

        case let .defaultFails(failure):
            outcome = .measuredDefaultFails
            detail = "trial=\(failure.trial)"
            counterexample = failure.input
            shrunkCounterexample = failure.shrink?.minimal

        case let .error(reason):
            outcome = .measuredError
            detail = "parse-error: \(reason)"
        }
        return SurveyRecord(
            identityHash: context.identityHash,
            templateName: context.templateName,
            primaryFunctionName: context.primaryFunctionName,
            carrier: context.carrier,
            outcome: outcome,
            outcomeDetail: detail,
            counterexample: counterexample,
            shrunkCounterexample: shrunkCounterexample
        )
    }

    /// Map a `VerifyError` to a short human-readable detail string.
    static func detail(for error: VerifyError) -> String {
        switch error {
        case let .unsupportedCarrier(carrier, _):
            return "unsupported-carrier: \(carrier)"

        case let .unsupportedTemplate(template, _):
            return "unsupported-template: \(template)"

        case let .unsupportedPair(forward, _):
            return "unsupported-pair: \(forward)"

        case let .monotonicityDomainNotComparable(domain):
            return "monotonicity-domain-not-comparable: \(domain)"

        default:
            return error.description
        }
    }

    /// Per-entry context bundle to keep the worker signatures lean.
    struct RecordContext {
        let identityHash: String
        let templateName: String
        let primaryFunctionName: String
        let carrier: String?
    }

    static func recordContext(for entry: SemanticIndexEntry) -> RecordContext {
        RecordContext(
            identityHash: entry.identityHash,
            templateName: entry.templateName,
            primaryFunctionName: entry.primaryFunctionName,
            carrier: entry.typeName
        )
    }

    /// JSON-encode a single record and print it to stdout. One
    /// line per record — concat with `jq -s` to produce a top-level
    /// array.
    static func emit(_ record: SurveyRecord) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = (try? encoder.encode(record)) ?? Data()
        if let line = String(data: data, encoding: .utf8) {
            print(line)
        }
    }
}
