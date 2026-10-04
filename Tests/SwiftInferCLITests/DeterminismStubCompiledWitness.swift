import Foundation
import PropertyLawKit
import Testing

// A COMPILED witness for the determinism stubs accept now writes where it used to write ones that
// could not compile. `DeterminismStubCompiledWitnessTests` scans the two subjects below out of this
// very file, has accept write each stub, and checks this file holds that text byte for byte — so
// the test target building is the proof the emitted text compiles, and the stubs running green is
// the proof the law passes a deterministic subject. Keep the subjects at the top: the seed is
// derived from the law's identity, which names the subject's location.

/// `approximatelyEqual` used to be called and never declared: *cannot find 'approximatelyEqual'
/// in scope*.
enum DeterminismWitnessGauge {
    static func scale(_ factor: Double) -> Double { factor * 3 }
}

/// `(args: (Self, Self))` and `Self.gen()` used to be written at file scope, where there is no
/// `Self`.
struct DeterminismWitnessPoint: Equatable {
    let value: Int

    static func merge(_ lhs: Self, _ rhs: Self) -> Self { Self(value: Swift.max(lhs.value, rhs.value)) }
}

// WITNESS-BEGIN — emitted text, verbatim; the rules below are the ones it trips.
// swiftlint:disable closure_end_indentation identical_operands line_length type_name
struct DeterminismWitnessGauge_scale_determinismTests {

    @Test func scale_isDeterministic() async {
        let backend = SwiftPropertyBasedBackend()
        let seed = Seed(
            stateA: 0xF0A41D3886A1C0A6,
            stateB: 0xEECB1A53B0AA4E22,
            stateC: 0xF16713FC264E7912,
            stateD: 0x6B55A2016CEB6CAE
        )
        let result = await backend.check(
            trials: 100,
            seed: seed,
            sample: { rng in (Gen<Double>.double(in: -1_000_000...1_000_000)).run(using: &rng) },
            property: { value in approximatelyEqual(DeterminismWitnessGauge.scale(value), DeterminismWitnessGauge.scale(value)) }
        )
        if case let .failed(_, _, input, error) = result {
            Issue.record(
                "DeterminismWitnessGauge.scale(_:) is not deterministic — same input produced different output at input \(input). \(error?.message ?? "")"
            )
        }
    }

    /// Relative-tolerance equality, emitted inline so this file needs no swift-numerics
    /// dependency. Tolerance matches that library's default (`ulpOfOne.squareRoot()`).
    private func approximatelyEqual<Value: FloatingPoint>(_ lhs: Value, _ rhs: Value) -> Bool {
        if lhs == rhs { return true }
        if lhs.isNaN, rhs.isNaN { return true }
        let delta = (lhs - rhs).magnitude
        let scale = Swift.max(lhs.magnitude, rhs.magnitude)
        return delta.isFinite && delta <= scale * Value.ulpOfOne.squareRoot()
    }
}

struct DeterminismWitnessPoint_merge_determinismTests {

    @Test func merge_isDeterministic() async {
        let backend = SwiftPropertyBasedBackend()
        let seed = Seed(
            stateA: 0x6D33E7351283AE43,
            stateB: 0xFD9B5076DD4F8379,
            stateC: 0x3EB93870160B6DFE,
            stateD: 0xB506C56F81971C03
        )
        let result = await backend.check(
            trials: 100,
            seed: seed,
            sample: { rng in
                        let arg0 = (Gen<Int>.int().map { DeterminismWitnessPoint(value: $0) }).run(using: &rng)
                        let arg1 = (Gen<Int>.int().map { DeterminismWitnessPoint(value: $0) }).run(using: &rng)
                        return (arg0, arg1)
                    },
            property: { (args: (DeterminismWitnessPoint, DeterminismWitnessPoint)) in DeterminismWitnessPoint.merge(args.0, args.1) == DeterminismWitnessPoint.merge(args.0, args.1) }
        )
        if case let .failed(_, _, input, error) = result {
            Issue.record(
                "DeterminismWitnessPoint.merge(_:_:) is not deterministic — same input produced different output at input \(input). \(error?.message ?? "")"
            )
        }
    }
}
// swiftlint:enable closure_end_indentation identical_operands line_length type_name
// WITNESS-END
