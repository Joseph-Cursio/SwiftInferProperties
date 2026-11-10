import PropertyLawCore
import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

/// V1.31.B — `EqualityKind` parameter on `LiftedTestEmitter`'s three
/// unary-property arms (round-trip, idempotent, inverse-pair). Closes
/// the 13-cycle carry-forward "FP approximate-equality template arm"
/// (cycle-14 priority #4). The current strict `==` assertion fails
/// under IEEE 754 rounding even on canonical inverse pairs like
/// `log(exp(z))`; the `.approximate` variant emits
/// a relative-tolerance comparison for FP-equatable types.
///
/// ⚠ **These assertions pinned `lhs.isApproximatelyEqual(to: rhs)` and were green for the whole
/// life of a defect.** That method is swift-numerics; `PropertyLawKit` links only
/// `PropertyBased`, so no emitted file could ever reach it and the arm had never produced a
/// compiling stub since V1.31.A (#454). A codegen test comparing text to text can have both
/// sides wrong together — SwiftPropertyLaws recorded four golden tests doing exactly this for
/// its `.caseIterable` arm, and these were five more.
///
/// The strings below are updated, and they remain the *readable* record. The **executable** one
/// is `ApproximateEqualityHelperTests`, which runs a live copy of the emitted helper.
@Suite("LiftedTestEmitter — V1.31.B EqualityKind dispatch")
struct LiftedTestEmitterApproxEqualityTests {

    private static let dummySeed = SamplingSeed.Value(
        stateA: 0xAAAA_BBBB_CCCC_DDDD,
        stateB: 0x1111_2222_3333_4444,
        stateC: 0x5555_6666_7777_8888,
        stateD: 0x9999_AAAA_BBBB_CCCC
    )

    // MARK: - Round-trip

    @Test("V1.31.B — round-trip with .strict emits canonical `lhs == rhs`")
    func roundTripStrictPreservesCurrentEmit() {
        let source = LiftedTestEmitter.roundTrip(
            forward: "encode",
            inverse: "decode",
            seed: Self.dummySeed,
            generator: "IntGenerator"
        )
        #expect(source.contains("decode(encode(value)) == value"))
        #expect(!source.contains("isApproximatelyEqual"))
    }

    @Test("V1.31.B — round-trip with .approximate emits the tolerance comparison")
    func roundTripApproximateEmitsApproximateEquality() {
        let source = LiftedTestEmitter.roundTrip(
            forward: "exp",
            inverse: "log",
            seed: Self.dummySeed,
            generator: "ComplexGenerator",
            equalityKind: .approximate
        )
        #expect(source.contains("approximatelyEqual(log(exp(value)), value)"))
        #expect(!source.contains("log(exp(value)) == value"))
    }

    @Test("V1.31.B — round-trip default is .strict (backward compatibility)")
    func roundTripDefaultIsStrict() {
        let withDefault = LiftedTestEmitter.roundTrip(
            forward: "encode",
            inverse: "decode",
            seed: Self.dummySeed,
            generator: "IntGenerator"
        )
        let withStrict = LiftedTestEmitter.roundTrip(
            forward: "encode",
            inverse: "decode",
            seed: Self.dummySeed,
            generator: "IntGenerator",
            equalityKind: .strict
        )
        #expect(withDefault == withStrict)
    }

    // MARK: - Idempotent

    @Test("V1.31.B — idempotent with .strict emits `f(f(value)) == f(value)`")
    func idempotentStrictPreservesCurrentEmit() {
        let source = LiftedTestEmitter.idempotent(
            callee: "normalize",
            typeName: "String",
            seed: Self.dummySeed,
            generator: "StringGenerator"
        )
        #expect(source.contains("normalize(normalize(value)) == normalize(value)"))
        #expect(!source.contains("isApproximatelyEqual"))
    }

    @Test("V1.31.B — idempotent with .approximate emits approximate equality")
    func idempotentApproximateEmitsApproximateEquality() {
        let source = LiftedTestEmitter.idempotent(
            callee: "clamp",
            typeName: "Double",
            seed: Self.dummySeed,
            generator: "DoubleGenerator",
            equalityKind: .approximate
        )
        #expect(source.contains("approximatelyEqual(clamp(clamp(value)), clamp(value))"))
        #expect(!source.contains("clamp(clamp(value)) == clamp(value)"))
    }

    @Test("V1.31.B — idempotent default is .strict (backward compatibility)")
    func idempotentDefaultIsStrict() {
        let withDefault = LiftedTestEmitter.idempotent(
            callee: "sort",
            typeName: "Array",
            seed: Self.dummySeed,
            generator: "ArrayGenerator"
        )
        let withStrict = LiftedTestEmitter.idempotent(
            callee: "sort",
            typeName: "Array",
            seed: Self.dummySeed,
            generator: "ArrayGenerator",
            equalityKind: .strict
        )
        #expect(withDefault == withStrict)
    }

    // MARK: - Inverse-pair

    @Test("V1.31.B — inverse-pair with .strict emits canonical `lhs == rhs`")
    func inversePairStrictPreservesCurrentEmit() {
        let source = LiftedTestEmitter.inversePair(
            forward: "transform",
            inverse: "untransform",
            typeName: "MyToken",
            seed: Self.dummySeed,
            generator: "TokenGenerator"
        )
        #expect(source.contains("untransform(transform(value)) == value"))
        #expect(!source.contains("isApproximatelyEqual"))
    }

    @Test("V1.31.B — inverse-pair with .approximate emits approximate equality")
    func inversePairApproximateEmitsApproximateEquality() {
        let source = LiftedTestEmitter.inversePair(
            forward: "sinh",
            inverse: "asinh",
            typeName: "Complex",
            seed: Self.dummySeed,
            generator: "ComplexGenerator",
            equalityKind: .approximate
        )
        #expect(source.contains("approximatelyEqual(asinh(sinh(value)), value)"))
        #expect(!source.contains("asinh(sinh(value)) == value"))
    }

    @Test("V1.31.B — inverse-pair default is .strict (backward compatibility)")
    func inversePairDefaultIsStrict() {
        let withDefault = LiftedTestEmitter.inversePair(
            forward: "transform",
            inverse: "untransform",
            typeName: "MyToken",
            seed: Self.dummySeed,
            generator: "TokenGenerator"
        )
        let withStrict = LiftedTestEmitter.inversePair(
            forward: "transform",
            inverse: "untransform",
            typeName: "MyToken",
            seed: Self.dummySeed,
            generator: "TokenGenerator",
            equalityKind: .strict
        )
        #expect(withDefault == withStrict)
    }

    // MARK: - Helper

    @Test("V1.31.B — equalityExpression helper produces canonical shapes")
    func equalityExpressionHelper() {
        #expect(
            LiftedTestEmitter.equalityExpression(lhs: "a", rhs: "b", kind: .strict)
                == "a == b"
        )
        #expect(
            LiftedTestEmitter.equalityExpression(lhs: "f(x)", rhs: "y", kind: .approximate)
                == "approximatelyEqual(f(x), y)"
        )
    }
}
