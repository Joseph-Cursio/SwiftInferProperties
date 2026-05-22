import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

// V2.0 accept-check follow-up — `accept-interaction` recorder. Uses
// a fixture package + a real discover-interaction run to find the
// identity hash, then verifies the decision lands in
// `.swiftinfer/interaction-decisions.json`.

@Suite("AcceptInteraction — V2.0 accept-flow recorder")
struct AcceptInteractionCommandTests {

    private func makeFixturePackage(name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AcceptInteractionTests-\(name)-\(UUID().uuidString)")
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

    @Test("unknown decision string surfaces .unknownDecision")
    func unknownDecisionRejected() throws {
        let root = try makeFixturePackage(name: "UnknownDecision")
        defer { try? FileManager.default.removeItem(at: root) }
        try writeSource(in: root, target: "MyApp", contents: """
        struct InboxState { var count: Int = 0; var items: [Int] = [] }
        enum InboxAction: CaseIterable { case noop }
        func reduce(_ state: InboxState, _ action: InboxAction) -> InboxState { state }
        """)
        let directory = root.appendingPathComponent("Sources").appendingPathComponent("MyApp")
        do {
            try SwiftInferCommand.AcceptInteraction.run(
                target: "MyApp",
                workingDirectory: root,
                directory: directory,
                request: AcceptInteractionRequest(
                    identity: "0000000000000000",
                    decisionRaw: "bogus"
                ),
                output: AIRecordingOutput()
            )
            Issue.record("expected .unknownDecision")
        } catch let error as AcceptInteractionError {
            switch error {
            case .unknownDecision: break
            default: Issue.record("expected .unknownDecision; got \(error)")
            }
        }
    }

    @Test("unknown identity hash surfaces .unknownIdentity")
    func unknownIdentityRejected() throws {
        let root = try makeFixturePackage(name: "UnknownIdentity")
        defer { try? FileManager.default.removeItem(at: root) }
        try writeSource(in: root, target: "MyApp", contents: """
        struct InboxState { var count: Int = 0; var items: [Int] = [] }
        enum InboxAction: CaseIterable { case noop }
        func reduce(_ state: InboxState, _ action: InboxAction) -> InboxState { state }
        """)
        let directory = root.appendingPathComponent("Sources").appendingPathComponent("MyApp")
        do {
            try SwiftInferCommand.AcceptInteraction.run(
                target: "MyApp",
                workingDirectory: root,
                directory: directory,
                request: AcceptInteractionRequest(
                    identity: "DEADBEEFDEADBEEF",
                    decisionRaw: "accepted"
                ),
                output: AIRecordingOutput()
            )
            Issue.record("expected .unknownIdentity")
        } catch let error as AcceptInteractionError {
            switch error {
            case .unknownIdentity: break
            default: Issue.record("expected .unknownIdentity; got \(error)")
            }
        }
    }

    @Test("matching identity writes a decision record to interaction-decisions.json")
    func validDecisionPersisted() throws {
        let root = try makeFixturePackage(name: "ValidDecision")
        defer { try? FileManager.default.removeItem(at: root) }
        try writeSource(in: root, target: "MyApp", contents: """
        struct InboxState { var count: Int = 0; var items: [Int] = [] }
        enum InboxAction: CaseIterable { case noop }
        func reduce(_ state: InboxState, _ action: InboxAction) -> InboxState { state }
        """)
        let directory = root.appendingPathComponent("Sources").appendingPathComponent("MyApp")
        let suggestions = try SwiftInferCommand.DiscoverInteraction.collectSuggestions(
            target: "MyApp",
            workingDirectory: root
        )
        guard let first = suggestions.first else {
            Issue.record("fixture must produce at least one suggestion")
            return
        }
        try SwiftInferCommand.AcceptInteraction.run(
            target: "MyApp",
            workingDirectory: root,
            directory: directory,
            request: AcceptInteractionRequest(
                identity: first.identity.normalized,
                decisionRaw: "accepted"
            ),
            output: AIRecordingOutput()
        )
        let path = root.appendingPathComponent(".swiftinfer/interaction-decisions.json")
        let data = try Data(contentsOf: path)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decisions = try decoder.decode(InteractionDecisions.self, from: data)
        #expect(decisions.records.count == 1)
        #expect(decisions.records[0].identityHash == first.identity.normalized)
        #expect(decisions.records[0].decision == .accepted)
    }
}

private final class AIRecordingOutput: DiscoverOutput, @unchecked Sendable {
    private(set) var lines: [String] = []
    func write(_ text: String) {
        lines.append(text)
    }
}
