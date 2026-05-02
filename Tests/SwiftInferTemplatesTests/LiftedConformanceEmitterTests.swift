import Testing
import SwiftInferCore
@testable import SwiftInferTemplates

@Suite("LiftedConformanceEmitter — pure-function conformance source emit (M7.4)")
struct LiftedConformanceEmitterTests {

    // MARK: - semigroup(...) byte-stable golden

    @Test
    func semigroupEmitsByteStableExtension() {
        let explainability = ExplainabilityBlock(
            whySuggested: [
                "merge(_:_:) (Money, Money) -> Money — Sources/Money.swift:14",
                "Type-symmetry signature: (T, T) -> T (T = Money) (+30)",
                "Curated commutativity verb match: 'merge' (+40)"
            ],
            whyMightBeWrong: [
                "User-supplied combine witness must satisfy associativity.",
                "SwiftInfer does not run the laws — `swift package protolawcheck` does."
            ]
        )
        let source = LiftedConformanceEmitter.semigroup(
            typeName: "Money",
            explainability: explainability
        )
        let expected = """

            // SwiftInfer RefactorBridge — Money: Semigroup
            //
            // Why suggested:
            //   - merge(_:_:) (Money, Money) -> Money — Sources/Money.swift:14
            //   - Type-symmetry signature: (T, T) -> T (T = Money) (+30)
            //   - Curated commutativity verb match: 'merge' (+40)
            //
            // Why this might be wrong:
            //   - User-supplied combine witness must satisfy associativity.
            //   - SwiftInfer does not run the laws — `swift package protolawcheck` does.
            extension Money: Semigroup {}
            """
        #expect(source == expected)
    }

    // MARK: - monoid(...) byte-stable golden

    @Test
    func monoidEmitsByteStableExtension() {
        let explainability = ExplainabilityBlock(
            whySuggested: [
                "combine(_:_:) (Tally, Tally) -> Tally — Sources/Tally.swift:8",
                "Identity element: Tally.empty (+30)"
            ],
            whyMightBeWrong: [
                "Identity element must satisfy `combine(a, .empty) == a == combine(.empty, a)`.",
                "SwiftInfer does not verify the law — apply the conformance and run the kit's check."
            ]
        )
        let source = LiftedConformanceEmitter.monoid(
            typeName: "Tally",
            explainability: explainability
        )
        let expected = """

            // SwiftInfer RefactorBridge — Tally: Monoid
            //
            // Why suggested:
            //   - combine(_:_:) (Tally, Tally) -> Tally — Sources/Tally.swift:8
            //   - Identity element: Tally.empty (+30)
            //
            // Why this might be wrong:
            //   - Identity element must satisfy `combine(a, .empty) == a == combine(.empty, a)`.
            //   - SwiftInfer does not verify the law — apply the conformance and run the kit's check.
            extension Tally: Monoid {}
            """
        #expect(source == expected)
    }

    // MARK: - Empty-explainability rendering

    @Test
    func emptyExplainabilityRendersExplicitNoEntriesLines() {
        let explainability = ExplainabilityBlock(whySuggested: [], whyMightBeWrong: [])
        let source = LiftedConformanceEmitter.semigroup(
            typeName: "Empty",
            explainability: explainability
        )
        #expect(source.contains("//   (no signals recorded)"))
        #expect(source.contains("//   (no caveats recorded)"))
    }

    // MARK: - Determinism

    @Test
    func sameInputsProduceByteIdenticalSource() {
        let explainability = ExplainabilityBlock(
            whySuggested: ["op match"],
            whyMightBeWrong: ["assoc not verified"]
        )
        let first = LiftedConformanceEmitter.semigroup(typeName: "T", explainability: explainability)
        let second = LiftedConformanceEmitter.semigroup(typeName: "T", explainability: explainability)
        #expect(first == second)
    }

    // MARK: - Cross-arm independence

    @Test
    func semigroupAndMonoidProduceDistinctSource() {
        let explainability = ExplainabilityBlock(whySuggested: [], whyMightBeWrong: [])
        let semigroupSource = LiftedConformanceEmitter.semigroup(
            typeName: "Money",
            explainability: explainability
        )
        let monoidSource = LiftedConformanceEmitter.monoid(
            typeName: "Money",
            explainability: explainability
        )
        #expect(semigroupSource != monoidSource)
        #expect(semigroupSource.contains("Money: Semigroup"))
        #expect(monoidSource.contains("Money: Monoid"))
    }

    // MARK: - Path convention (PRD §16 #1 allowlist)

    @Test
    func writeoutPathPrefixIsStable() {
        #expect(LiftedConformanceEmitter.writeoutPathPrefix == "Tests/Generated/SwiftInferRefactors")
    }

    @Test
    func relativePathComposesTypeAndProtocol() {
        let path = LiftedConformanceEmitter.relativePath(typeName: "Money", protocolName: "Semigroup")
        #expect(path == "Tests/Generated/SwiftInferRefactors/Money/Semigroup.swift")
    }

    @Test
    func relativePathHandlesGenericLikeTypeNamesByPassingThrough() {
        // The emitter does not validate type-name shape — that's the
        // orchestrator's job (M7.5). Probes that exercising bracket
        // characters survives the path composition; M7.6's hard-
        // guarantee tests pin the actual filesystem write to the
        // SwiftInferRefactors/ allowlist.
        let path = LiftedConformanceEmitter.relativePath(
            typeName: "Box<Int>",
            protocolName: "Semigroup"
        )
        #expect(path == "Tests/Generated/SwiftInferRefactors/Box<Int>/Semigroup.swift")
    }
}
