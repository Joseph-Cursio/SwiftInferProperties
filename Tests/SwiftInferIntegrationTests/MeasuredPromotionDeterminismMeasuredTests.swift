import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// Cycle 118 — the end-to-end half of the A1 measured-promotion sign-off:
/// verifying the *same* idempotence identity twice yields a byte-identical
/// `Result`. Together with the deterministic seed
/// (`MeasuredPromotionDeterminismTests`) and pure reducers, this proves the
/// measured survey has zero cycle-to-cycle variance — so the measured
/// `.likely → .verified` promotion is reproducible, and a single confirmed
/// run stands in for the three-cycle calibration discipline (which exists
/// to absorb variance the measured path doesn't have).
///
/// Real `swift build` + two verifier runs (~25s) — tagged `.subprocess`.
@Suite("Measured-promotion determinism — end-to-end reproducibility", .tags(.subprocess))
struct MeasuredPromotionDeterminismMeasuredTests {

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

    @Test("two verify runs of the same identity produce an identical Result (reproducible promotion)")
    func verifyIsReproducible() throws {
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent("measured-promotion-determinism")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: parent) }

        let root = try CorpusPackager.package(
            moduleName: "IdempotenceCorpus",
            sourceFiles: [.init(name: "Counter.swift", contents: Self.counterSource)],
            into: parent
        )
        let refresh = try #require(
            try SwiftInferCommand.DiscoverInteraction
                .collectSuggestions(target: "IdempotenceCorpus", workingDirectory: root)
                .first { $0.family == .idempotence && $0.predicate == ".refresh" }
        )

        let first = try VerifyInteractionPipeline.runWithInvariant(
            target: "IdempotenceCorpus",
            invariant: refresh,
            workingDirectory: root
        )
        let second = try VerifyInteractionPipeline.runWithInvariant(
            target: "IdempotenceCorpus",
            invariant: refresh,
            workingDirectory: root
        )

        #expect(first.outcome == .measuredBothPass)
        #expect(first == second)  // byte-identical: same outcome, runs, detail
    }
}
