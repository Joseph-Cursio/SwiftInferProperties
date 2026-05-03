import Testing
import SwiftInferCore
@testable import SwiftInferTemplates

@Suite("LiftedConformanceEmitter — M8.5 kit-protocol arms")
struct LiftedConformanceEmitterM8Tests {

    @Test
    func commutativeMonoidEmitsAliasingExtensionByteStable() {
        let explainability = ExplainabilityBlock(
            whySuggested: [
                "RefactorBridge claim: Tally → CommutativeMonoid",
                "from associativity: merge(_:_:)"
            ],
            whyMightBeWrong: [
                "Commutativity is a Strict law per kit v1.9.0 — "
                    + "`combine(a, b) == combine(b, a)` must hold for every (a, b)."
            ]
        )
        let source = LiftedConformanceEmitter.commutativeMonoid(
            typeName: "Tally",
            combineWitness: "merge",
            identityWitness: "empty",
            explainability: explainability
        )
        let expected = """

            // SwiftInfer RefactorBridge — Tally: CommutativeMonoid
            //
            // Why suggested:
            //   - RefactorBridge claim: Tally → CommutativeMonoid
            //   - from associativity: merge(_:_:)
            //
            // Why this might be wrong:
            //   - Commutativity is a Strict law per kit v1.9.0 — \
            `combine(a, b) == combine(b, a)` must hold for every (a, b).
            extension Tally: CommutativeMonoid {
                public static func combine(_ lhs: Tally, _ rhs: Tally) -> Tally {
                    Self.merge(lhs, rhs)
                }
                public static var identity: Tally { Self.empty }
            }
            """
        #expect(source == expected)
    }

    @Test
    func groupEmitsAliasingExtensionByteStable() {
        let explainability = ExplainabilityBlock(
            whySuggested: [
                "RefactorBridge claim: AdditiveInt → Group",
                "from associativity: plus(_:_:)",
                "from inverse-element pairing: negate(_:) -> AdditiveInt"
            ],
            whyMightBeWrong: [
                "Inverse witness must satisfy both Strict laws."
            ]
        )
        let source = LiftedConformanceEmitter.group(
            typeName: "AdditiveInt",
            combineWitness: "plus",
            identityWitness: "zero",
            inverseWitness: "negate",
            explainability: explainability
        )
        let expected = """

            // SwiftInfer RefactorBridge — AdditiveInt: Group
            //
            // Why suggested:
            //   - RefactorBridge claim: AdditiveInt → Group
            //   - from associativity: plus(_:_:)
            //   - from inverse-element pairing: negate(_:) -> AdditiveInt
            //
            // Why this might be wrong:
            //   - Inverse witness must satisfy both Strict laws.
            extension AdditiveInt: Group {
                public static func combine(_ lhs: AdditiveInt, _ rhs: AdditiveInt) -> AdditiveInt {
                    Self.plus(lhs, rhs)
                }
                public static var identity: AdditiveInt { Self.zero }
                public static func inverse(_ value: AdditiveInt) -> AdditiveInt {
                    Self.negate(value)
                }
            }
            """
        #expect(source == expected)
    }

    @Test
    func semilatticeEmitsAliasingExtensionByteStable() {
        let explainability = ExplainabilityBlock(
            whySuggested: [
                "RefactorBridge claim: MaxInt → Semilattice"
            ],
            whyMightBeWrong: [
                "Idempotence is a Strict law per kit v1.9.0."
            ]
        )
        let source = LiftedConformanceEmitter.semilattice(
            typeName: "MaxInt",
            combineWitness: "maximum",
            identityWitness: "minValue",
            explainability: explainability
        )
        let expected = """

            // SwiftInfer RefactorBridge — MaxInt: Semilattice
            //
            // Why suggested:
            //   - RefactorBridge claim: MaxInt → Semilattice
            //
            // Why this might be wrong:
            //   - Idempotence is a Strict law per kit v1.9.0.
            extension MaxInt: Semilattice {
                public static func combine(_ lhs: MaxInt, _ rhs: MaxInt) -> MaxInt {
                    Self.maximum(lhs, rhs)
                }
                public static var identity: MaxInt { Self.minValue }
            }
            """
        #expect(source == expected)
    }

    @Test
    func groupSkipsAllAliasingWhenAllThreeWitnessesAreCanonical() {
        let explainability = ExplainabilityBlock(whySuggested: [], whyMightBeWrong: [])
        let source = LiftedConformanceEmitter.group(
            typeName: "Bag",
            combineWitness: "combine",
            identityWitness: "identity",
            inverseWitness: "inverse",
            explainability: explainability
        )
        #expect(source.contains("extension Bag: Group {}"))
        #expect(source.contains("public static func combine") == false)
        #expect(source.contains("public static var identity") == false)
        #expect(source.contains("public static func inverse") == false)
    }

    @Test
    func groupSkipsOnlyMatchingWitnessesIndependently() {
        // Mixed canonicality — combine is canonical, identity + inverse
        // need aliasing. Each aliasing helper returns nil independently,
        // so the body should contain identity + inverse stubs only.
        let explainability = ExplainabilityBlock(whySuggested: [], whyMightBeWrong: [])
        let source = LiftedConformanceEmitter.group(
            typeName: "Mixed",
            combineWitness: "combine",
            identityWitness: "zero",
            inverseWitness: "negate",
            explainability: explainability
        )
        #expect(source.contains("public static func combine") == false)
        #expect(source.contains("public static var identity: Mixed { Self.zero }"))
        #expect(source.contains("public static func inverse(_ value: Mixed)"))
    }

    @Test
    func commutativeMonoidAndSemilatticeAndMonoidProduceDistinctSource() {
        // Three arms, identical witness inputs — the only diff is the
        // protocol name in the extension declaration.
        let explainability = ExplainabilityBlock(whySuggested: [], whyMightBeWrong: [])
        let monoid = LiftedConformanceEmitter.monoid(
            typeName: "T",
            combineWitness: "op",
            identityWitness: "id",
            explainability: explainability
        )
        let cmon = LiftedConformanceEmitter.commutativeMonoid(
            typeName: "T",
            combineWitness: "op",
            identityWitness: "id",
            explainability: explainability
        )
        let semilattice = LiftedConformanceEmitter.semilattice(
            typeName: "T",
            combineWitness: "op",
            identityWitness: "id",
            explainability: explainability
        )
        #expect(monoid != cmon)
        #expect(monoid != semilattice)
        #expect(cmon != semilattice)
        #expect(monoid.contains("T: Monoid"))
        #expect(cmon.contains("T: CommutativeMonoid"))
        #expect(semilattice.contains("T: Semilattice"))
    }
}

@Suite("LiftedConformanceEmitter — M8.4.b stdlib arms (Numeric, SetAlgebra)")
struct LiftedConformanceEmitterStdlibTests {

    @Test
    func numericEmitsBareExtensionByteStable() {
        // Numeric is the Ring arm — bare extension because the user's
        // existing operator implementations satisfy stdlib Numeric's
        // requirement set.
        let explainability = ExplainabilityBlock(
            whySuggested: [
                "RefactorBridge claim: Money → Ring (stdlib Numeric)",
                "additive op: plus(_:_:) with identity zero",
                "multiplicative op: times(_:_:) with identity one"
            ],
            whyMightBeWrong: [
                "Distributivity is NOT sample-verified.",
                "FloatingPoint caveat: don't conform Double / Float."
            ]
        )
        let source = LiftedConformanceEmitter.numeric(
            typeName: "Money",
            explainability: explainability
        )
        let expected = """

            // SwiftInfer RefactorBridge — Money: Numeric
            //
            // Why suggested:
            //   - RefactorBridge claim: Money → Ring (stdlib Numeric)
            //   - additive op: plus(_:_:) with identity zero
            //   - multiplicative op: times(_:_:) with identity one
            //
            // Why this might be wrong:
            //   - Distributivity is NOT sample-verified.
            //   - FloatingPoint caveat: don't conform Double / Float.
            extension Money: Numeric {}
            """
        #expect(source == expected)
    }

    @Test
    func setAlgebraEmitsBareExtensionByteStable() {
        // SetAlgebra is the secondary arm to a primary Semilattice
        // claim — the emitter produces a bare `extension T: SetAlgebra {}`
        // because the user's existing methods satisfy the protocol.
        let explainability = ExplainabilityBlock(
            whySuggested: [
                "RefactorBridge claim: Bag → SetAlgebra"
            ],
            whyMightBeWrong: [
                "stdlib SetAlgebra requires insert / remove / contains."
            ]
        )
        let source = LiftedConformanceEmitter.setAlgebra(
            typeName: "Bag",
            explainability: explainability
        )
        let expected = """

            // SwiftInfer RefactorBridge — Bag: SetAlgebra
            //
            // Why suggested:
            //   - RefactorBridge claim: Bag → SetAlgebra
            //
            // Why this might be wrong:
            //   - stdlib SetAlgebra requires insert / remove / contains.
            extension Bag: SetAlgebra {}
            """
        #expect(source == expected)
    }
}
