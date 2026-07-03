import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

// V2.0 M4.E — CLI surface + pipeline tests for discover-interaction.
// Argument parsing covers the standard flag shape; pipeline tests
// drive `runPipeline` against fixture directories containing
// hand-authored reducer + State + Action sources.

@Suite("DiscoverInteraction — V2.0 M4.E CLI surface + pipeline")
struct DiscoverInteractionCommandTests {

    private typealias Command = SwiftInferCommand.DiscoverInteraction

    private let firstSeenAt = ISO8601DateFormatter().date(from: "2026-05-15T10:00:00Z")!

    // MARK: - CLI registration + argument parsing

    @Test("DiscoverInteraction is registered in SwiftInferCommand subcommands")
    func subcommandIsRegistered() {
        let registered = SwiftInferCommand.configuration.subcommands
        let names = registered.map { $0.configuration.commandName ?? "" }
        #expect(names.contains("discover-interaction"))
    }

    @Test("--target is required; absent --target is a parse error")
    func targetIsRequired() {
        #expect(throws: (any Error).self) {
            _ = try Command.parse([])
        }
    }

    @Test("--reducer + --include-possible parse correctly")
    func parsesAllFlags() throws {
        let parsed = try Command.parse([
            "--target", "MyApp",
            "--reducer", "Inbox.body",
            "--include-possible"
        ])
        #expect(parsed.target == "MyApp")
        #expect(parsed.reducer == "Inbox.body")
        #expect(parsed.includePossible == true)
    }

    @Test("--include-possible defaults to false")
    func includePossibleDefaultsToFalse() throws {
        let parsed = try Command.parse(["--target", "MyApp"])
        #expect(parsed.includePossible == false)
    }

    // MARK: - filterCandidates

    @Test("filterCandidates returns all when pinRaw is nil")
    func filterPassesThroughWithoutPin() throws {
        let candidates = [
            candidate(functionName: "reduceA"),
            candidate(functionName: "reduceB")
        ]
        let filtered = try Command.filterCandidates(candidates, pinRaw: nil)
        #expect(filtered.count == 2)
    }

    @Test("filterCandidates narrows to matching candidates when pin is supplied")
    func filterByPin() throws {
        let candidates = [
            candidate(functionName: "reduceA"),
            candidate(functionName: "reduceB", enclosingTypeName: "Inbox")
        ]
        let filtered = try Command.filterCandidates(candidates, pinRaw: "Inbox.reduceB")
        #expect(filtered.count == 1)
        #expect(filtered[0].functionName == "reduceB")
    }

    @Test("filterCandidates throws noMatchingReducer when pin matches zero candidates")
    func filterNoMatchThrows() {
        let candidates = [candidate(functionName: "reduce")]
        #expect(throws: DiscoverInteractionError.noMatchingReducer(pin: "Missing.body")) {
            _ = try Command.filterCandidates(candidates, pinRaw: "Missing.body")
        }
    }

    // MARK: - runPipeline end-to-end

    @Test("runPipeline against a fixture with Conservation witness surfaces a suggestion")
    func runPipelineConservation() throws {
        let directory = try makeFixtureDirectory(name: "PipelineConservation")
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeFile(
            in: directory,
            relativePath: "Sources/MyApp",
            named: "Inbox.swift",
            contents: """
            struct Inbox {
                struct State {
                    var count: Int
                    var items: [String]
                }
                enum Action { case other }
                static func reduce(_ s: State, _ a: Action) -> State { return s }
            }
            """
        )
        let rendered = try Command.runPipeline(
            target: "MyApp",
            includePossible: true,
            workingDirectory: directory,
            firstSeenAt: firstSeenAt
        )
        #expect(rendered.contains("Family:    conservation"))
        #expect(rendered.contains("state.count == state.items.count"))
    }

    @Test("runPipeline against a fixture with Idempotence witness surfaces a suggestion")
    func runPipelineIdempotence() throws {
        let directory = try makeFixtureDirectory(name: "PipelineIdempotence")
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeFile(
            in: directory,
            relativePath: "Sources/MyApp",
            named: "Inbox.swift",
            contents: """
            struct Inbox {
                struct State {}
                enum Action {
                    case refresh
                    case other
                }
                static func reduce(_ s: State, _ a: Action) -> State { return s }
            }
            """
        )
        let rendered = try Command.runPipeline(
            target: "MyApp",
            includePossible: true,
            workingDirectory: directory,
            firstSeenAt: firstSeenAt
        )
        #expect(rendered.contains("Family:    idempotence"))
        #expect(rendered.contains("Predicate: .refresh"))
    }

    @Test("runPipeline default (no --include-possible) hides a still-.possible family")
    func runPipelineHidesPossibleByDefault() throws {
        // Cycle 107: idempotence promoted to `.likely` (surfaces by
        // default), so the hide-by-default sentinel must be exercised with
        // a family that is still `.possible` — here cardinality (two
        // presentation-shaped Bool flags), with a non-idempotent action
        // (`tick`) so no `.likely` idempotence suggestion is also emitted.
        let directory = try makeFixtureDirectory(name: "PipelineHidePossible")
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeFile(
            in: directory,
            relativePath: "Sources/MyApp",
            named: "Modal.swift",
            contents: """
            struct Modal {
                struct State {
                    var isShowingSheet: Bool
                    var isShowingAlert: Bool
                }
                enum Action { case tick }
                static func reduce(_ s: State, _ a: Action) -> State { return s }
            }
            """
        )
        let rendered = try Command.runPipeline(
            target: "MyApp",
            workingDirectory: directory,
            firstSeenAt: firstSeenAt
        )
        #expect(rendered.contains("--include-possible"))
        #expect(!rendered.contains("[Interaction-Invariant Suggestion]"))
    }

    @Test("runPipeline default surfaces promoted .likely idempotence without the flag (cycle 107)")
    func runPipelineShowsLikelyIdempotenceByDefault() throws {
        // Cycle 107 promotion payoff: an idempotence suggestion now lands
        // at `.likely` and is visible in the default view (no
        // `--include-possible` required).
        let directory = try makeFixtureDirectory(name: "PipelineShowLikely")
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeFile(
            in: directory,
            relativePath: "Sources/MyApp",
            named: "Inbox.swift",
            contents: """
            struct Inbox {
                struct State {
                    var count: Int
                    var items: [String]
                }
                enum Action { case refresh }
                static func reduce(_ s: State, _ a: Action) -> State { return s }
            }
            """
        )
        let rendered = try Command.runPipeline(
            target: "MyApp",
            workingDirectory: directory,
            firstSeenAt: firstSeenAt
        )
        #expect(rendered.contains("[Interaction-Invariant Suggestion]"))
        #expect(rendered.contains("Family:    idempotence"))
        #expect(rendered.contains("Score:     40 (Likely)"))
        // Idempotence surfaces at .likely without the flag. Determinism
        // (Phase 2 Redux) also surfaces for this reducer but at .possible, so
        // it is silently filtered when a visible suggestion exists — the
        // hidden-count sentinel (which names --include-possible) is emitted
        // only when EVERY suggestion is hidden, so it stays absent here.
        #expect(rendered.contains("Family:    determinism") == false)
        #expect(!rendered.contains("--include-possible"))
    }

    @Test("runPipeline against an empty target returns the 0-suggestions sentinel")
    func runPipelineEmptyTarget() throws {
        let directory = try makeFixtureDirectory(name: "PipelineEmpty")
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeFile(
            in: directory,
            relativePath: "Sources/MyApp",
            named: "Empty.swift",
            contents: "// no reducers"
        )
        let rendered = try Command.runPipeline(
            target: "MyApp",
            includePossible: true,
            workingDirectory: directory,
            firstSeenAt: firstSeenAt
        )
        #expect(rendered.contains("0 interaction-invariant suggestions"))
    }

    // MARK: - Helpers

    private func candidate(
        functionName: String,
        enclosingTypeName: String? = nil
    ) -> ReducerCandidate {
        ReducerCandidate(
            location: "Sources/T.swift:1",
            enclosingTypeName: enclosingTypeName,
            functionName: functionName,
            signatureShape: .stateActionReturnsState,
            stateTypeName: "S",
            actionTypeName: "A",
            carrierKind: enclosingTypeName == nil ? .elmStyle : .generic
        )
    }

    private func makeFixtureDirectory(name: String) throws -> URL {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("DiscoverInteractionTests-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    private func writeFile(
        in directory: URL,
        relativePath: String,
        named name: String,
        contents: String
    ) throws {
        let dir = directory.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: dir.appendingPathComponent(name))
    }
}
