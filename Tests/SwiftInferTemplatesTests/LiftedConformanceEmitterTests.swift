import Testing
import SwiftInferCore
@testable import SwiftInferTemplates

// swiftlint:disable type_body_length file_length line_length
// M8.5 added three new arms (commutativeMonoid / group / semilattice)
// with byte-stable goldens, pushing this suite past the body / file
// length caps. line_length disabled because two golden lines render to
// 120+ chars from the §4.5 explainability text — byte-stability
// requires keeping the goldens in lockstep with the emitter output.

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

    // MARK: - M8.5 — commutativeMonoid byte-stable golden

    @Test
    func commutativeMonoidEmitsAliasingExtensionByteStable() {
        let explainability = ExplainabilityBlock(
            whySuggested: [
                "RefactorBridge claim: Tally → CommutativeMonoid",
                "from associativity: merge(_:_:)"
            ],
            whyMightBeWrong: [
                "Commutativity is a Strict law per kit v1.9.0 — `combine(a, b) == combine(b, a)` must hold for every (a, b)."
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
            //   - Commutativity is a Strict law per kit v1.9.0 — `combine(a, b) == combine(b, a)` must hold for every (a, b).
            extension Tally: CommutativeMonoid {
                public static func combine(_ lhs: Tally, _ rhs: Tally) -> Tally {
                    Self.merge(lhs, rhs)
                }
                public static var identity: Tally { Self.empty }
            }
            """
        #expect(source == expected)
    }

    // MARK: - M8.5 — group byte-stable golden (kit v1.9.0 inverse arm)

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

    // MARK: - M8.5 — semilattice byte-stable golden

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

    // MARK: - M8.5 — witness-already-canonical short-circuits

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
        // protocol name in the extension declaration. Disambiguates
        // the dispatch path: a writeout for the same witnesses under
        // a different protocol must not be byte-identical to another
        // arm's output.
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

    // MARK: - M8.4.b.1 — setAlgebra byte-stable golden

    @Test
    func setAlgebraEmitsBareExtensionByteStable() {
        // SetAlgebra is the secondary arm to a primary Semilattice
        // claim — the emitter produces a bare `extension T: SetAlgebra {}`
        // because the user's existing methods satisfy the protocol's
        // requirements (insert / remove / contains / etc.). Per M8.4.b.1
        // open decision #3 default `(a)`, the §4.5 caveat lists what's
        // not implied by the Semilattice signals.
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
// swiftlint:enable type_body_length file_length line_length
