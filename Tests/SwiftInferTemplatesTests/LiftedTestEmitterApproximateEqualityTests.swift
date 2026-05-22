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
/// `isApproximatelyEqual(to:)` for FP-equatable types.
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
            forwardName: "encode",
            inverseName: "decode",
            seed: Self.dummySeed,
            generator: "IntGenerator"
        )
        #expect(source.contains("decode(encode(value)) == value"))
        #expect(!source.contains("isApproximatelyEqual"))
    }

    @Test("V1.31.B — round-trip with .approximate emits `lhs.isApproximatelyEqual(to: rhs)`")
    func roundTripApproximateEmitsApproximateEquality() {
        let source = LiftedTestEmitter.roundTrip(
            forwardName: "exp",
            inverseName: "log",
            seed: Self.dummySeed,
            generator: "ComplexGenerator",
            equalityKind: .approximate
        )
        #expect(source.contains("log(exp(value)).isApproximatelyEqual(to: value)"))
        #expect(!source.contains("log(exp(value)) == value"))
    }

    @Test("V1.31.B — round-trip default is .strict (backward compatibility)")
    func roundTripDefaultIsStrict() {
        let withDefault = LiftedTestEmitter.roundTrip(
            forwardName: "encode",
            inverseName: "decode",
            seed: Self.dummySeed,
            generator: "IntGenerator"
        )
        let withStrict = LiftedTestEmitter.roundTrip(
            forwardName: "encode",
            inverseName: "decode",
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
            funcName: "normalize",
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
            funcName: "clamp",
            typeName: "Double",
            seed: Self.dummySeed,
            generator: "DoubleGenerator",
            equalityKind: .approximate
        )
        #expect(source.contains("clamp(clamp(value)).isApproximatelyEqual(to: clamp(value))"))
        #expect(!source.contains("clamp(clamp(value)) == clamp(value)"))
    }

    @Test("V1.31.B — idempotent default is .strict (backward compatibility)")
    func idempotentDefaultIsStrict() {
        let withDefault = LiftedTestEmitter.idempotent(
            funcName: "sort",
            typeName: "Array",
            seed: Self.dummySeed,
            generator: "ArrayGenerator"
        )
        let withStrict = LiftedTestEmitter.idempotent(
            funcName: "sort",
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
            forwardName: "transform",
            inverseName: "untransform",
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
            forwardName: "sinh",
            inverseName: "asinh",
            typeName: "Complex",
            seed: Self.dummySeed,
            generator: "ComplexGenerator",
            equalityKind: .approximate
        )
        #expect(source.contains("asinh(sinh(value)).isApproximatelyEqual(to: value)"))
        #expect(!source.contains("asinh(sinh(value)) == value"))
    }

    @Test("V1.31.B — inverse-pair default is .strict (backward compatibility)")
    func inversePairDefaultIsStrict() {
        let withDefault = LiftedTestEmitter.inversePair(
            forwardName: "transform",
            inverseName: "untransform",
            typeName: "MyToken",
            seed: Self.dummySeed,
            generator: "TokenGenerator"
        )
        let withStrict = LiftedTestEmitter.inversePair(
            forwardName: "transform",
            inverseName: "untransform",
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
                == "f(x).isApproximatelyEqual(to: y)"
        )
    }
}
