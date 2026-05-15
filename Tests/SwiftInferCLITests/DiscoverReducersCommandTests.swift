import Foundation
import SwiftInferCore
import Testing
@testable import SwiftInferCLI

// V2.0 M1.A — CLI surface tests for DiscoverReducers. The pipeline
// path is integration-tested via `runPipeline(directory:)` against a
// temporary fixture directory; `renderSummary(candidates:)` is exercised
// purely with hand-built candidates.

@Suite("DiscoverReducers — V2.0 M1.A CLI surface")
struct DiscoverReducersCommandTests {

    private typealias Command = SwiftInferCommand.DiscoverReducers

    private func candidate(
        location: String = "Sources/T.swift:1",
        enclosingTypeName: String? = nil,
        functionName: String = "reduce",
        signatureShape: ReducerSignatureShape = .stateActionReturnsState,
        stateTypeName: String = "S",
        actionTypeName: String = "A"
    ) -> ReducerCandidate {
        ReducerCandidate(
            location: location,
            enclosingTypeName: enclosingTypeName,
            functionName: functionName,
            signatureShape: signatureShape,
            stateTypeName: stateTypeName,
            actionTypeName: actionTypeName
        )
    }

    // MARK: - renderSummary

    @Test("empty candidates yields a 'no reducers detected' line")
    func renderEmpty() {
        let rendered = Command.renderSummary(candidates: [])
        #expect(rendered == "swift-infer discover-reducers: no reducer-shaped functions detected.\n")
    }

    @Test("singular vs plural reducer count in the header")
    func renderHeaderPluralization() {
        let one = Command.renderSummary(candidates: [candidate()])
        #expect(one.contains("detected 1 reducer-shaped function:"))
        let two = Command.renderSummary(candidates: [
            candidate(location: "Sources/A.swift:1"),
            candidate(location: "Sources/B.swift:1")
        ])
        #expect(two.contains("detected 2 reducer-shaped functions:"))
    }

    @Test("per-record line carries location, qualified name, signature, state, action")
    func renderPerRecordLine() {
        let rendered = Command.renderSummary(candidates: [
            candidate(
                location: "Sources/MyApp/Inbox.swift:42",
                enclosingTypeName: "Inbox",
                functionName: "reduce",
                signatureShape: .inoutStateActionReturnsVoid,
                stateTypeName: "Inbox.State",
                actionTypeName: "Inbox.Action"
            )
        ])
        #expect(rendered.contains("Sources/MyApp/Inbox.swift:42"))
        #expect(rendered.contains("Inbox.reduce"))
        #expect(rendered.contains("signature:inout-state-action-returns-void"))
        #expect(rendered.contains("state:Inbox.State"))
        #expect(rendered.contains("action:Inbox.Action"))
    }

    @Test("candidates sort by (location, functionName) — byte-stable across input order")
    func renderSortsBy() {
        let lhsOrdering = Command.renderSummary(candidates: [
            candidate(location: "Sources/B.swift:1", functionName: "reduce"),
            candidate(location: "Sources/A.swift:1", functionName: "reduce")
        ])
        let rhsOrdering = Command.renderSummary(candidates: [
            candidate(location: "Sources/A.swift:1", functionName: "reduce"),
            candidate(location: "Sources/B.swift:1", functionName: "reduce")
        ])
        #expect(lhsOrdering == rhsOrdering)
        // The A-located one comes first.
        guard let aIndex = lhsOrdering.range(of: "Sources/A.swift:1") else {
            Issue.record("expected Sources/A.swift:1 in output")
            return
        }
        guard let bIndex = lhsOrdering.range(of: "Sources/B.swift:1") else {
            Issue.record("expected Sources/B.swift:1 in output")
            return
        }
        #expect(aIndex.lowerBound < bIndex.lowerBound)
    }

    // MARK: - runPipeline against a fixture directory

    @Test("runPipeline walks Sources/ tree and surfaces all reducer-shaped functions")
    func runPipelineEndToEnd() throws {
        let directory = try makeFixtureDirectory(name: "RunPipelineEndToEnd")
        defer { try? FileManager.default.removeItem(at: directory) }
        // Two reducer-shaped files, one non-reducer file.
        try writeFile(
            in: directory,
            named: "A.swift",
            contents: """
            func reduceA(_ state: StateA, _ action: ActionA) -> StateA { return state }
            """
        )
        try writeFile(
            in: directory,
            named: "B.swift",
            contents: """
            struct Inbox {
                func reduce(_ state: inout State, _ action: Action) {}
            }
            """
        )
        try writeFile(
            in: directory,
            named: "C.swift",
            contents: """
            func unrelated(_ s: String, _ a: Int, _ b: Double) -> Bool { return true }
            """
        )
        let rendered = try Command.runPipeline(directory: directory)
        #expect(rendered.contains("detected 2 reducer-shaped functions:"))
        #expect(rendered.contains("reduceA"))
        #expect(rendered.contains("Inbox.reduce"))
        #expect(!rendered.contains("unrelated"))
    }

    @Test("runPipeline on an empty directory returns the 'no reducers' sentinel")
    func runPipelineEmpty() throws {
        let directory = try makeFixtureDirectory(name: "RunPipelineEmpty")
        defer { try? FileManager.default.removeItem(at: directory) }
        let rendered = try Command.runPipeline(directory: directory)
        #expect(rendered.contains("no reducer-shaped functions detected"))
    }

    // MARK: - Helpers

    private func makeFixtureDirectory(name: String) throws -> URL {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("DiscoverReducersTests-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    private func writeFile(in directory: URL, named name: String, contents: String) throws {
        try Data(contents.utf8).write(to: directory.appendingPathComponent(name))
    }
}
