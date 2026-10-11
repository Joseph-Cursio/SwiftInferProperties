import Foundation
import PropertyLawKit
import Testing

// A COMPILED witness for the determinism stubs accept writes. `DeterminismStubCompiledWitnessTests`
// scans the subjects below out of this very file, has accept write each stub, and checks this file
// holds that text byte for byte — so the test target building is the proof the emitted text
// compiles, and the stubs running green is the proof the law passes a deterministic subject. Keep
// the subjects at the top, and add new ones after the old: the seed is derived from the law's
// identity, which names the subject's location.

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

// The two above used to be written and could not compile. The ones below compile, and
// `UnequatableResultGate` used to withdraw them — each a result whose `==` the gate misread.

/// A scanned type with no `Equatable`, named only as a `KeyPath` root and a phantom tag.
struct DeterminismWitnessRow {
    let name: String
    let title: String
}

/// `Hashable` whatever its phantom tag is.
struct DeterminismWitnessTagged<Tag, Raw: Hashable>: Hashable {
    let raw: Raw
}

/// `KeyPath<Row, String>` and `Tagged<Row, Int>` used to decline on `Row`.
enum DeterminismWitnessColumns {
    static func sortKey(_ index: Int) -> KeyPath<DeterminismWitnessRow, String> {
        index.isMultiple(of: 2) ? \.name : \.title
    }

    static func rowID(_ raw: Int) -> DeterminismWitnessTagged<DeterminismWitnessRow, Int> {
        DeterminismWitnessTagged(raw: raw)
    }
}

/// `Equatable` reached through a superclass the subclass names by its qualified, nested spelling.
enum DeterminismWitnessLedger {
    class Entry: Equatable {
        let amount: Int

        init(amount: Int) { self.amount = amount }

        static func == (lhs: Entry, rhs: Entry) -> Bool { lhs.amount == rhs.amount }
    }
}

final class DeterminismWitnessCredit: DeterminismWitnessLedger.Entry {}

/// A hand-written `==` and no `Equatable`: operator lookup finds the member.
struct DeterminismWitnessReading {
    let value: Int

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.value == rhs.value }
}

/// The superclass link and the hand-written `==` used to decline too.
enum DeterminismWitnessBank {
    static func credit(_ amount: Int) -> DeterminismWitnessCredit { DeterminismWitnessCredit(amount: amount) }

    static func read(_ raw: Int) -> DeterminismWitnessReading { DeterminismWitnessReading(value: raw) }
}

// WITNESS-BEGIN — emitted text, verbatim; the rules below are the ones it trips.
// swiftlint:disable closure_end_indentation identical_operands line_length type_name
struct DeterminismWitnessGaugeScaleDeterminismTests {

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

struct DeterminismWitnessPointMergeDeterminismTests {

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

struct DeterminismWitnessColumnsSortKeyDeterminismTests {

    @Test func sortKey_isDeterministic() async {
        let backend = SwiftPropertyBasedBackend()
        let seed = Seed(
            stateA: 0xD7271E13E6E9C14D,
            stateB: 0x766AC1594948DF51,
            stateC: 0x8046983798D6D2E5,
            stateD: 0x1BEB2C74A8445C8D
        )
        let result = await backend.check(
            trials: 100,
            seed: seed,
            sample: { rng in (Gen<Int>.int(in: -10_000 ... 10_000)).run(using: &rng) },
            property: { value in DeterminismWitnessColumns.sortKey(value) == DeterminismWitnessColumns.sortKey(value) }
        )
        if case let .failed(_, _, input, error) = result {
            Issue.record(
                "DeterminismWitnessColumns.sortKey(_:) is not deterministic — same input produced different output at input \(input). \(error?.message ?? "")"
            )
        }
    }
}

struct DeterminismWitnessColumnsRowIDDeterminismTests {

    @Test func rowID_isDeterministic() async {
        let backend = SwiftPropertyBasedBackend()
        let seed = Seed(
            stateA: 0x00C91CBAB9BD7C6E,
            stateB: 0x96CC85781051F7E5,
            stateC: 0x590A3CD028F0AD94,
            stateD: 0x4004B8B8658AC410
        )
        let result = await backend.check(
            trials: 100,
            seed: seed,
            sample: { rng in (Gen<Int>.int(in: -10_000 ... 10_000)).run(using: &rng) },
            property: { value in DeterminismWitnessColumns.rowID(value) == DeterminismWitnessColumns.rowID(value) }
        )
        if case let .failed(_, _, input, error) = result {
            Issue.record(
                "DeterminismWitnessColumns.rowID(_:) is not deterministic — same input produced different output at input \(input). \(error?.message ?? "")"
            )
        }
    }
}

struct DeterminismWitnessBankCreditDeterminismTests {

    @Test func credit_isDeterministic() async {
        let backend = SwiftPropertyBasedBackend()
        let seed = Seed(
            stateA: 0xEB60D1CD37CB0FD6,
            stateB: 0x165DEE3FF7080F7A,
            stateC: 0x1E81C7EC7BAE245B,
            stateD: 0xA6EBDF23F5894CDE
        )
        let result = await backend.check(
            trials: 100,
            seed: seed,
            sample: { rng in (Gen<Int>.int(in: -10_000 ... 10_000)).run(using: &rng) },
            property: { value in DeterminismWitnessBank.credit(value) == DeterminismWitnessBank.credit(value) }
        )
        if case let .failed(_, _, input, error) = result {
            Issue.record(
                "DeterminismWitnessBank.credit(_:) is not deterministic — same input produced different output at input \(input). \(error?.message ?? "")"
            )
        }
    }
}

struct DeterminismWitnessBankReadDeterminismTests {

    @Test func read_isDeterministic() async {
        let backend = SwiftPropertyBasedBackend()
        let seed = Seed(
            stateA: 0x50F1DAC950B3EFAF,
            stateB: 0xC293B5C4484143DC,
            stateC: 0x71E90C4082A73335,
            stateD: 0x7F018C27BF71F770
        )
        let result = await backend.check(
            trials: 100,
            seed: seed,
            sample: { rng in (Gen<Int>.int(in: -10_000 ... 10_000)).run(using: &rng) },
            property: { value in DeterminismWitnessBank.read(value) == DeterminismWitnessBank.read(value) }
        )
        if case let .failed(_, _, input, error) = result {
            Issue.record(
                "DeterminismWitnessBank.read(_:) is not deterministic — same input produced different output at input \(input). \(error?.message ?? "")"
            )
        }
    }
}
// swiftlint:enable closure_end_indentation identical_operands line_length type_name
// WITNESS-END
