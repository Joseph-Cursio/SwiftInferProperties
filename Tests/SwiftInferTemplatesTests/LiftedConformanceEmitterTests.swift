import Testing
import SwiftInferCore
@testable import SwiftInferTemplates

@Suite("LiftedConformanceEmitter — pure-function conformance source emit (M7.4 + M7.5.a aliasing)")
struct LiftedConformanceEmitterTests {

    // MARK: - semigroup(...) byte-stable golden — aliasing combine witness

    @Test
    func semigroupEmitsAliasingExtensionByteStable() {
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
            combineWitness: "merge",
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
            extension Money: Semigroup {
                public static func combine(_ lhs: Money, _ rhs: Money) -> Money {
                    Self.merge(lhs, rhs)
                }
            }
            """
        #expect(source == expected)
    }

    // MARK: - semigroup(...) when witness is already named "combine"

    @Test
    func semigroupOmitsAliasingWhenWitnessIsCombine() {
        let explainability = ExplainabilityBlock(whySuggested: [], whyMightBeWrong: [])
        let source = LiftedConformanceEmitter.semigroup(
            typeName: "Tally",
            combineWitness: "combine",
            explainability: explainability
        )
        // Bare extension — user's existing static func combine(_:_:)
        // satisfies the requirement; emitting Self.combine(lhs, rhs)
        // would recurse infinitely.
        #expect(source.contains("extension Tally: Semigroup {}"))
        #expect(source.contains("public static func combine") == false)
    }

    // MARK: - monoid(...) byte-stable golden — aliasing combine + identity

    @Test
    func monoidEmitsAliasingExtensionByteStable() {
        let explainability = ExplainabilityBlock(
            whySuggested: [
                "merge(_:_:) (Tally, Tally) -> Tally — Sources/Tally.swift:8",
                "Identity element: Tally.empty (+30)"
            ],
            whyMightBeWrong: [
                "Identity element must satisfy `combine(a, .empty) == a == combine(.empty, a)`.",
                "SwiftInfer does not verify the law — apply the conformance and run the kit's check."
            ]
        )
        let source = LiftedConformanceEmitter.monoid(
            typeName: "Tally",
            combineWitness: "merge",
            identityWitness: "empty",
            explainability: explainability
        )
        let expected = """

            // SwiftInfer RefactorBridge — Tally: Monoid
            //
            // Why suggested:
            //   - merge(_:_:) (Tally, Tally) -> Tally — Sources/Tally.swift:8
            //   - Identity element: Tally.empty (+30)
            //
            // Why this might be wrong:
            //   - Identity element must satisfy `combine(a, .empty) == a == combine(.empty, a)`.
            //   - SwiftInfer does not verify the law — apply the conformance and run the kit's check.
            extension Tally: Monoid {
                public static func combine(_ lhs: Tally, _ rhs: Tally) -> Tally {
                    Self.merge(lhs, rhs)
                }
                public static var identity: Tally { Self.empty }
            }
            """
        #expect(source == expected)
    }

    // MARK: - monoid(...) when both witnesses match the protocol's required identifiers

    @Test
    func monoidEmitsBareExtensionWhenWitnessesMatchProtocol() {
        let explainability = ExplainabilityBlock(whySuggested: [], whyMightBeWrong: [])
        let source = LiftedConformanceEmitter.monoid(
            typeName: "Bag",
            combineWitness: "combine",
            identityWitness: "identity",
            explainability: explainability
        )
        #expect(source.contains("extension Bag: Monoid {}"))
        #expect(source.contains("public static func combine") == false)
        #expect(source.contains("public static var identity") == false)
    }

    @Test
    func monoidEmitsOnlyIdentityWhenCombineWitnessIsCombine() {
        let explainability = ExplainabilityBlock(whySuggested: [], whyMightBeWrong: [])
        let source = LiftedConformanceEmitter.monoid(
            typeName: "Bag",
            combineWitness: "combine",
            identityWitness: "empty",
            explainability: explainability
        )
        #expect(source.contains("public static func combine") == false)
        #expect(source.contains("public static var identity: Bag { Self.empty }"))
    }

    // MARK: - Empty-explainability rendering

    @Test
    func emptyExplainabilityRendersExplicitNoEntriesLines() {
        let explainability = ExplainabilityBlock(whySuggested: [], whyMightBeWrong: [])
        let source = LiftedConformanceEmitter.semigroup(
            typeName: "Empty",
            combineWitness: "merge",
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
        let first = LiftedConformanceEmitter.semigroup(
            typeName: "T",
            combineWitness: "op",
            explainability: explainability
        )
        let second = LiftedConformanceEmitter.semigroup(
            typeName: "T",
            combineWitness: "op",
            explainability: explainability
        )
        #expect(first == second)
    }

    // MARK: - Cross-arm independence

    @Test
    func semigroupAndMonoidProduceDistinctSource() {
        let explainability = ExplainabilityBlock(whySuggested: [], whyMightBeWrong: [])
        let semigroupSource = LiftedConformanceEmitter.semigroup(
            typeName: "Money",
            combineWitness: "merge",
            explainability: explainability
        )
        let monoidSource = LiftedConformanceEmitter.monoid(
            typeName: "Money",
            combineWitness: "merge",
            identityWitness: "zero",
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
