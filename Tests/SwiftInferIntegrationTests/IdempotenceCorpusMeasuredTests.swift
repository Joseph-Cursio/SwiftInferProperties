import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// Cycle 113 — the full A1 campaign loop, end-to-end, over a *packaged
/// corpus*: `CorpusPackager` scaffolds a standalone module-named SwiftPM
/// package from verify-ready idempotence reducers, then
///
///   discover-interaction → verify-interaction (measured) → evidence → discover-interaction
///
/// proves a `.likely` idempotence identity is promoted to `.verified` by
/// *executed* evidence — not re-triage. This is the capstone that ties
/// cycles 110 (measured execution) + 111 (producer) + 112 (consumer) +
/// 113 (corpus packaging) together.
///
/// Spawns a real `swift build` + verifier run (kit-resolving; tens of
/// seconds) — tagged `.subprocess` like the other measured suites.
@Suite("Idempotence corpus — packaged, measured, promoted to Verified", .tags(.subprocess))
struct IdempotenceCorpusMeasuredTests {

    private typealias Discover = SwiftInferCommand.DiscoverInteraction

    /// Two verify-ready idempotence reducers: a curated-idempotent witness
    /// action (`refresh` / `reset`), a non-idempotent driver to vary state,
    /// `noop`, `Equatable` + zero-arg-constructible `State`, `CaseIterable`
    /// `Action`. This is the shape the stub requires.
    private static let counterSource = """
    public struct CounterReducer {
        public struct State: Equatable, Sendable {
            public var count: Int
            public init(count: Int = 0) { self.count = count }
        }
        public enum Action: CaseIterable, Sendable { case refresh, increment, noop }
        public static func reduce(_ s: State, _ a: Action) -> State {
            switch a {
            case .refresh: return State(count: 0)
            case .increment: return State(count: s.count + 1)
            case .noop: return s
            }
        }
    }
    """

    private static let settingsSource = """
    public struct SettingsReducer {
        public struct State: Equatable, Sendable {
            public var theme: Int
            public init(theme: Int = 0) { self.theme = theme }
        }
        public enum Action: CaseIterable, Sendable { case reset, bump, noop }
        public static func reduce(_ s: State, _ a: Action) -> State {
            switch a {
            case .reset: return State(theme: 0)
            case .bump: return State(theme: s.theme + 1)
            case .noop: return s
            }
        }
    }
    """

    @Test("packaged corpus: a discovered idempotence identity verifies measured-bothPass and renders Verified")
    func packagedCorpusVerifyPromotesToVerified() throws {
        // A unique parent so the module-named root (parent/IdempotenceCorpus)
        // is collision-free across runs.
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent("idempotence-corpus-measured")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: parent) }

        // 1. Package the loose reducer sources into a standalone package.
        let root = try CorpusPackager.package(
            moduleName: "IdempotenceCorpus",
            sourceFiles: [
                .init(name: "Counter.swift", contents: Self.counterSource),
                .init(name: "Settings.swift", contents: Self.settingsSource)
            ],
            into: parent
        )
        #expect(root.lastPathComponent == "IdempotenceCorpus")

        // 2. Discover — the packaged corpus yields idempotence identities.
        let suggestions = try Discover.collectSuggestions(
            target: "IdempotenceCorpus",
            workingDirectory: root
        )
        let refresh = try #require(
            suggestions.first {
                $0.family == .idempotence
                    && $0.reducerQualifiedName == "CounterReducer.reduce"
                    && $0.predicate == ".refresh"
            },
            "discovery should surface the CounterReducer .refresh idempotence identity"
        )
        #expect(refresh.tier == .likely)   // base, pre-verify tier

        // 3. Verify (measured) — builds + runs the corpus, records evidence.
        let outcome = try VerifyInteractionPipeline.runWithInvariant(
            target: "IdempotenceCorpus",
            invariant: refresh,
            workingDirectory: root
        )
        #expect(outcome.outcome == .measuredBothPass)

        // 4. Discover again — the consumer reads the recorded evidence and
        //    promotes the identity past .likely to .verified.
        let rendered = try Discover.runPipeline(
            target: "IdempotenceCorpus",
            workingDirectory: root
        )
        #expect(rendered.contains("Reducer:   CounterReducer.reduce"))
        #expect(rendered.contains("(Verified)"))
        #expect(rendered.contains("bothPass"))
    }
}
