@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// `empty-range` (#701) built and run against a planted subject, in both directions.
///
/// The unit suite (`EmptyRangeVerifySupportTests`) inspects the emitted text. This one compiles
/// it, because the claim that matters is that the resolver's label trampoline,
/// `{ Planted.select(from: $0, to: $1) }`, applied to one value twice, type-checks against a real
/// labelled static and fails on the right subject. `role-postcondition` found its missing second
/// gate only by a run like this.
///
/// The calls come from `resolveFunctionCalls` over an index entry, not from a hand-written
/// closure, so a resolver that dropped the labels would fail to build here.
///
/// Spawns real `swift build`s; tagged `.subprocess` and placed in batch 3 by the `VerifyPipeline`
/// name.
@Suite("Verify pipeline — empty-range on a planted subject", .tags(.subprocess))
struct VerifyPipelineEmptyRangeTests {

    private static let entry = SemanticIndexEntry(
        identityHash: "0xEMPTYRANGE0001",
        templateName: "empty-range",
        score: 45,
        tier: "Likely",
        primaryFunctionName: "select(from:to:)",
        location: "/Planted.swift:1",
        firstSeenAt: "2026-11-13T00:00:00Z",
        lastSeenAt: "2026-11-13T00:00:00Z",
        typeName: "Planted",
        carrierTypeName: "Int",
        parameterTypeNames: ["Int", "Int"]
    )

    private static func run(subjectBody: String) throws -> VerifyOutcome {
        let calls = try SwiftInferCommand.Verify.resolveFunctionCalls(for: entry)
        return try VerifyPipelineIntegrationFixture.runStrategistPipeline(
            functionCalls: calls.expressions,
            carrier: "Int",
            template: "empty-range",
            preamble: """
                enum Planted {
                    static func select(from lo: Int, to hi: Int) -> [Int] {
                \(subjectBody)
                    }
                }
                """
        )
    }

    /// `to:` exclusive, as Swift's convention has it: one value as both ends selects nothing, at
    /// the ordinary draws and at the boundary values alike.
    @Test("a half-open selection holds the law in both passes")
    func halfOpenSelectionPasses() throws {
        let outcome = try Self.run(subjectBody: """
                    guard lo < hi else { return [] }
                    return Array(lo ..< hi)
            """)
        guard case let .bothPass(defaultTrials, edgeTrials, _) = outcome else {
            Issue.record("expected .bothPass; got \(outcome)")
            return
        }
        #expect(defaultTrials > 0)
        #expect(edgeTrials > 0, "the boundary pass must run the law, not the zero-trial sentinel")
    }

    /// The mutant that treats `to:` as inclusive selects `v` itself. The law refutes it at the
    /// first trial, by assertion, with the non-empty result as the counterexample.
    @Test("an inclusive selection is refuted, with its non-empty result shown")
    func inclusiveSelectionFails() throws {
        let outcome = try Self.run(subjectBody: """
                    guard lo <= hi else { return [] }
                    return Array(lo ... hi)
            """)
        guard case let .defaultFails(detail) = outcome else {
            Issue.record("expected .defaultFails; got \(outcome)")
            return
        }
        #expect(detail.trial == 0)
        #expect(detail.forwardResult == "[\(detail.input)]")
        #expect(detail.inverseResult == "<empty>")
    }
}
