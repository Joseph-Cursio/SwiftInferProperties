import Foundation
import SwiftInferCore
import Testing
@testable import SwiftInferCLI

// V2.0 accept-check follow-up — accept-check-interaction subcommand.
// Tests focus on the classification logic + the no-accepted-decisions
// fast path, since the full rerun pipeline depends on a synthesized
// SwiftPM workdir (covered separately by integration tests once the
// v2.3.0 kit pin lands in synthesized workdirs).

@Suite("AcceptCheckInteraction — V2.0 accept-flow rerun")
struct AcceptCheckInteractionCommandTests {

    private func makeFixturePackage(name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AcceptCheckInteractionTests-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("// swift-tools-version: 6.1\n".utf8).write(
            to: root.appendingPathComponent("Package.swift")
        )
        return root
    }

    private func writeSource(in root: URL, target: String, contents: String) throws {
        let dir = root.appendingPathComponent("Sources").appendingPathComponent(target)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: dir.appendingPathComponent("Reducer.swift"))
    }

    // MARK: - Verify-outcome → classification mapping

    @Test("classify(verifyOutcome:) measuredBothPass → stillPasses")
    func classifyBothPass() {
        let result = InteractionVerifyOutcomeParser.Result(
            outcome: .measuredBothPass,
            totalRuns: 1024,
            cleanRuns: 1024
        )
        let classified = SwiftInferCommand.AcceptCheckInteraction.classify(
            verifyOutcome: result
        )
        #expect(classified.kind == .stillPasses)
    }

    @Test("classify(verifyOutcome:) measuredDefaultFails → nowFails (regression signal)")
    func classifyDefaultFails() {
        let result = InteractionVerifyOutcomeParser.Result(
            outcome: .measuredDefaultFails,
            detail: "trap at sequence 7"
        )
        let classified = SwiftInferCommand.AcceptCheckInteraction.classify(
            verifyOutcome: result
        )
        #expect(classified.kind == .nowFails)
        #expect(classified.detail?.contains("sequence 7") == true)
    }

    @Test("classify(verifyOutcome:) measuredError → error")
    func classifyMeasuredError() {
        let result = InteractionVerifyOutcomeParser.Result(
            outcome: .measuredError,
            detail: "missing marker"
        )
        let classified = SwiftInferCommand.AcceptCheckInteraction.classify(
            verifyOutcome: result
        )
        #expect(classified.kind == .error)
    }

    @Test("classify(verifyOutcome:) architecturalCoveragePending → error")
    func classifyArchitecturalPending() {
        let result = InteractionVerifyOutcomeParser.Result(
            outcome: .architecturalCoveragePending,
            detail: "swift build failed"
        )
        let classified = SwiftInferCommand.AcceptCheckInteraction.classify(
            verifyOutcome: result
        )
        #expect(classified.kind == .error)
    }

    @Test("classify(record:matching:) obsolete when no current suggestion matches")
    func classifyObsoleteWhenNoMatch() {
        let record = InteractionDecisionRecord(
            identityHash: "DEADBEEFDEADBEEF",
            family: .cardinality,
            scoreAtDecision: 80,
            tier: .strong,
            reducerQualifiedName: "Inbox.body",
            decision: .accepted,
            timestamp: Date()
        )
        let classified = SwiftInferCommand.AcceptCheckInteraction.classify(
            record: record,
            matching: nil,
            target: "MyApp",
            workingDirectory: URL(fileURLWithPath: "/tmp")
        )
        #expect(classified.kind == .obsolete)
    }

    // MARK: - Empty decisions fast path

    @Test("no accepted decisions: writes empty outcomes log + summary line")
    func noAcceptedDecisions() throws {
        let root = try makeFixturePackage(name: "EmptyDecisions")
        defer { try? FileManager.default.removeItem(at: root) }
        try writeSource(in: root, target: "MyApp", contents: """
        struct InboxState { var count: Int = 0 }
        enum InboxAction: CaseIterable { case noop }
        func reduce(_ state: InboxState, _ action: InboxAction) -> InboxState { state }
        """)
        let directory = root.appendingPathComponent("Sources").appendingPathComponent("MyApp")
        let output = ACRecordingOutput()
        try SwiftInferCommand.AcceptCheckInteraction.run(
            target: "MyApp",
            workingDirectory: root,
            directory: directory,
            output: output
        )
        #expect(output.lines.contains("No accepted interaction decisions to check."))
        let outcomesPath = root.appendingPathComponent(
            ".swiftinfer/interaction-post-acceptance-outcomes.json"
        )
        #expect(FileManager.default.fileExists(atPath: outcomesPath.path))
    }

    // MARK: - Unknown family filter

    @Test("unknown --family value surfaces .unknownFamily")
    func unknownFamilyRejected() throws {
        let root = try makeFixturePackage(name: "UnknownFamily")
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("Sources").appendingPathComponent("MyApp")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            try SwiftInferCommand.AcceptCheckInteraction.run(
                target: "MyApp",
                workingDirectory: root,
                directory: directory,
                familyFilterRaw: "bogus-family",
                output: ACRecordingOutput()
            )
            Issue.record("expected .unknownFamily")
        } catch let error as AcceptCheckInteractionError {
            switch error {
            case .unknownFamily: break
            }
        }
    }
}

private final class ACRecordingOutput: DiscoverOutput, @unchecked Sendable {
    private(set) var lines: [String] = []
    func write(_ text: String) {
        lines.append(text)
    }
}
