import Foundation
import Testing
@testable import SwiftInferCLI
@testable import SwiftInferCore

@Suite("VerifyEvidenceRecorder — outcome mapping + best-effort persistence (V1.64.B)")
struct VerifyEvidenceRecorderTests {

    // MARK: - Single-suggestion VerifyOutcome mapping

    @Test
    func bothPassMapsToMeasuredBothPassWithTrialDetail() {
        let (outcome, detail) = VerifyEvidenceRecorder.evidence(
            for: .bothPass(defaultTrials: 100, edgeTrials: 100, edgeSampled: 6)
        )
        #expect(outcome == .measuredBothPass)
        #expect(detail == "defaultTrials=100 edgeTrials=100 edgeSampled=6")
    }

    @Test
    func edgeCaseAdvisoryMapsToMeasuredEdgeCaseAdvisoryWithNilDetail() {
        let (outcome, detail) = VerifyEvidenceRecorder.evidence(
            for: .edgeCaseAdvisory(
                defaultTrials: 100,
                edgeTrial: 3,
                edgeInput: "x",
                edgeForward: "y",
                edgeInverse: "z",
                edgeCaseIndex: 0
            )
        )
        #expect(outcome == .measuredEdgeCaseAdvisory)
        #expect(detail == nil)
    }

    @Test
    func defaultFailsMapsToMeasuredDefaultFailsWithTrialDetail() {
        let (outcome, detail) = VerifyEvidenceRecorder.evidence(
            for: .defaultFails(trial: 7, input: "a", forwardResult: "b", inverseResult: "c")
        )
        #expect(outcome == .measuredDefaultFails)
        #expect(detail == "trial=7")
    }

    @Test
    func errorMapsToMeasuredErrorWithParseErrorDetail() {
        let (outcome, detail) = VerifyEvidenceRecorder.evidence(for: .error(reason: "no markers"))
        #expect(outcome == .measuredError)
        #expect(detail == "parse-error: no markers")
    }

    // MARK: - Survey SurveyOutcome mapping (rawValue round-trip totality)

    @Test
    func everySurveyOutcomeMapsToTheSameRawValueEvidenceOutcome() {
        let pairs: [(SwiftInferCommand.Verify.SurveyOutcome, VerifyEvidenceOutcome)] = [
            (.measuredBothPass, .measuredBothPass),
            (.measuredEdgeCaseAdvisory, .measuredEdgeCaseAdvisory),
            (.measuredDefaultFails, .measuredDefaultFails),
            (.measuredError, .measuredError),
            (.architecturalCoveragePending, .architecturalCoveragePending)
        ]
        for (survey, expected) in pairs {
            #expect(VerifyEvidenceRecorder.evidenceOutcome(for: survey) == expected)
            #expect(VerifyEvidenceRecorder.evidenceOutcome(for: survey).rawValue == survey.rawValue)
        }
    }

    // MARK: - Version stamp

    @Test
    func swiftInferVersionTracksTheCommandConfiguration() {
        #expect(VerifyEvidenceRecorder.swiftInferVersion == SwiftInferCommand.configuration.version)
        #expect(!VerifyEvidenceRecorder.swiftInferVersion.isEmpty)
    }

    // MARK: - record (single upsert)

    @Test
    func recordWritesAnEvidenceFileAtThePackageRoot() throws {
        let directory = try makeFixtureDirectory(name: "RecordWrites")
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("// swift-tools-version: 6.1\n".utf8)
            .write(to: directory.appendingPathComponent("Package.swift"))

        let warnings = VerifyEvidenceRecorder.record(
            makeEvidence(identity: "AAA1111111111111", outcome: .measuredBothPass),
            packageRoot: directory
        )
        #expect(warnings.isEmpty)

        let reloaded = VerifyEvidenceStore.load(startingFrom: directory)
        #expect(reloaded.log.records.count == 1)
        #expect(reloaded.log.record(for: "AAA1111111111111")?.outcome == .measuredBothPass)
    }

    @Test
    func recordUpsertsOverAPriorOutcomeForTheSameIdentity() throws {
        let directory = try makeFixtureDirectory(name: "RecordUpserts")
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("// swift-tools-version: 6.1\n".utf8)
            .write(to: directory.appendingPathComponent("Package.swift"))

        _ = VerifyEvidenceRecorder.record(
            makeEvidence(identity: "AAA1111111111111", outcome: .architecturalCoveragePending),
            packageRoot: directory
        )
        _ = VerifyEvidenceRecorder.record(
            makeEvidence(identity: "AAA1111111111111", outcome: .measuredBothPass),
            packageRoot: directory
        )

        let reloaded = VerifyEvidenceStore.load(startingFrom: directory)
        #expect(reloaded.log.records.count == 1)
        #expect(reloaded.log.record(for: "AAA1111111111111")?.outcome == .measuredBothPass)
    }

    // MARK: - recordBatch

    @Test
    func recordBatchWritesEveryRecord() throws {
        let directory = try makeFixtureDirectory(name: "BatchWrites")
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("// swift-tools-version: 6.1\n".utf8)
            .write(to: directory.appendingPathComponent("Package.swift"))

        let warnings = VerifyEvidenceRecorder.recordBatch(
            [
                makeEvidence(identity: "AAA1111111111111", outcome: .measuredBothPass),
                makeEvidence(identity: "BBB2222222222222", outcome: .measuredDefaultFails)
            ],
            packageRoot: directory
        )
        #expect(warnings.isEmpty)

        let reloaded = VerifyEvidenceStore.load(startingFrom: directory)
        #expect(reloaded.log.records.count == 2)
    }

    @Test
    func recordBatchLeavesPriorEvidenceForPicksNotInTheBatch() throws {
        // A --template-filtered survey only re-verifies a subset; picks
        // outside the filter must keep their prior evidence.
        let directory = try makeFixtureDirectory(name: "BatchPreserves")
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("// swift-tools-version: 6.1\n".utf8)
            .write(to: directory.appendingPathComponent("Package.swift"))

        _ = VerifyEvidenceRecorder.record(
            makeEvidence(identity: "OLD0000000000000", outcome: .measuredBothPass),
            packageRoot: directory
        )
        _ = VerifyEvidenceRecorder.recordBatch(
            [makeEvidence(identity: "NEW1111111111111", outcome: .measuredDefaultFails)],
            packageRoot: directory
        )

        let reloaded = VerifyEvidenceStore.load(startingFrom: directory)
        #expect(reloaded.log.records.count == 2)
        #expect(reloaded.log.record(for: "OLD0000000000000")?.outcome == .measuredBothPass)
        #expect(reloaded.log.record(for: "NEW1111111111111")?.outcome == .measuredDefaultFails)
    }

    @Test
    func recordBatchWithEmptyBatchIsANoOpAndWritesNothing() throws {
        let directory = try makeFixtureDirectory(name: "BatchEmpty")
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("// swift-tools-version: 6.1\n".utf8)
            .write(to: directory.appendingPathComponent("Package.swift"))

        let warnings = VerifyEvidenceRecorder.recordBatch([], packageRoot: directory)
        #expect(warnings.isEmpty)
        #expect(
            !FileManager.default.fileExists(
                atPath: VerifyEvidenceStore.defaultPath(for: directory).path
            )
        )
    }

    // MARK: - Helpers

    private func makeEvidence(
        identity: String,
        outcome: VerifyEvidenceOutcome
    ) -> VerifyEvidence {
        VerifyEvidence(
            identityHash: identity,
            template: "round-trip",
            outcome: outcome,
            detail: nil,
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
            swiftInferVersion: "1.64.0"
        )
    }

    private func makeFixtureDirectory(name: String) throws -> URL {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("VerifyEvidenceRecorderTests-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }
}
