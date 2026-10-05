import Foundation
import PropertyLawKit
import Testing

// The second half of the reference-oracle witness: cases W6 to W11 of
// `ReferenceOracleWitnessCases.shapes`, split from `ReferenceOracleScaffoldWitness.swift` for
// SwiftLint's file-length cap. Same contract: the region after WITNESS-BEGIN is the emitter's text
// with its `fatalError(...)` line filled in, generated, never edited by hand.

/// W6 — an operator, called infix and compared with a named static reference.
struct OracleWitnessMoney: Equatable, Sendable {
    let cents: Int

    static func + (lhs: Self, rhs: Self) -> Self { Self(cents: lhs.cents &+ rhs.cents) }
}

/// W7 — a `-> Self?` factory with four parameters, two of them Optional.
struct OracleWitnessWindow: Equatable, Sendable {
    let start: Int
    let count: Int

    static func resolve(lineCount: Int, startLine: Int?, maxLines: Int?, cap: Int) -> Self? {
        let start = Swift.max(startLine ?? 1, 1)
        guard start <= lineCount else { return nil }
        let count = Swift.min(Swift.min(maxLines ?? cap, cap), lineCount - start + 1)
        return count > 0 ? Self(start: start, count: count) : nil
    }
}

/// W8 — a free function over two `String`s, drawn from the real `String` generator: the shape
/// that hit *unable to type-check this expression in reasonable time* on SwiftAssist.
func oracleWitnessHasPrefix(_ name: String, matching pattern: String) -> Bool { name.hasPrefix(pattern) }

/// W9 — a method on a standard-library type, returning a labelled tuple.
extension String {
    func oracleWitnessClipped(toLength limit: Int) -> (text: String, didTruncate: Bool) {
        let kept = String(prefix(Swift.max(0, limit)))
        return (kept, kept.count < count)
    }
}

/// W10 — a floating-point result, compared approximately.
enum OracleWitnessGeometry {
    static func scaled(_ length: Double, by factor: Double) -> Double { abs(length * factor) }
}

/// W11 — a non-`Sendable` class receiver, made a check's input by the scaffold's shim line.
final class OracleWitnessTally {
    var total: Int

    init(total: Int) {
        self.total = total
    }

    func adding(_ amount: Int) -> Int { total &+ amount }
}

// WITNESS-BEGIN — emitted text, verbatim; the rules below are the ones it trips.
// swiftlint:disable closure_end_indentation identifier_name large_tuple line_length
// W6
// Fill in the reference definition below — your docstring already states it:
//   "Returns the sum of both amounts, in cents."
// Then run the test: the generator finds the input where the code disagrees
// with its own documentation.
// (the return type Self must be Equatable for this to compile)
extension OracleWitnessMoney {
    static func plus_reference(_ lhs: Self, _ rhs: Self) -> Self {
        Self(cents: rhs.cents &+ lhs.cents)
    }
}

@Test func OracleWitnessMoney_plus_matchesReferenceDefinition() async {
    let backend = SwiftPropertyBasedBackend()
    let seed = Seed(
        stateA: 0x0000000000005EED,
        stateB: 0x0000000000C0FFEE,
        stateC: 0x000000000000BEEF,
        stateD: 0x000000000000F00D
    )
    let result = await backend.check(
        trials: 100,
        seed: seed,
        sample: { rng in
                    let arg0 = (Gen<Int>.int().map { OracleWitnessMoney(cents: $0) }).run(using: &rng)
                    let arg1 = (Gen<Int>.int().map { OracleWitnessMoney(cents: $0) }).run(using: &rng)
                    return (arg0, arg1)
                },
        property: { (args: (OracleWitnessMoney, OracleWitnessMoney)) in (args.0 + args.1) == OracleWitnessMoney.plus_reference(args.0, args.1) }
    )
    if case let .failed(_, _, input, error) = result {
        Issue.record(
            "OracleWitnessMoney.+(lhs:rhs:) disagrees with its documented reference definition at input \(input). \(error?.message ?? "")"
        )
    }
}

// W7
// Fill in the reference definition below — your docstring already states it:
//   "Returns the window starting at the start line, at most the cap long, or nil when it is empty."
// Then run the test: the generator finds the input where the code disagrees
// with its own documentation.
// (the return type Self? must be Equatable for this to compile)
extension OracleWitnessWindow {
    static func resolve_reference(lineCount: Int, startLine: Int?, maxLines: Int?, cap: Int) -> Self? {
        let first = Swift.max(startLine ?? 1, 1); guard first <= lineCount else { return nil }; let size = Swift.min(maxLines ?? cap, cap, lineCount - first + 1); return size > 0 ? Self(start: first, count: size) : nil
    }
}

@Test func OracleWitnessWindow_resolve_matchesReferenceDefinition() async {
    let backend = SwiftPropertyBasedBackend()
    let seed = Seed(
        stateA: 0x0000000000005EED,
        stateB: 0x0000000000C0FFEE,
        stateC: 0x000000000000BEEF,
        stateD: 0x000000000000F00D
    )
    let result = await backend.check(
        trials: 100,
        seed: seed,
        sample: { rng in
                    let arg0 = (Gen.frequency((3.0, Gen<Int>.boundedForArithmetic()), (2.0, Gen<Int?>.element(of: [0, -1, 1] as [Int]).map { $0! }))).run(using: &rng)
                    let arg1 = (Gen<Int>.int().optional).run(using: &rng)
                    let arg2 = (Gen<Int>.int().optional).run(using: &rng)
                    let arg3 = (Gen.frequency((3.0, Gen<Int>.boundedForArithmetic()), (2.0, Gen<Int?>.element(of: [0, -1, 1] as [Int]).map { $0! }))).run(using: &rng)
                    return (arg0, arg1, arg2, arg3)
                },
        property: { (args: (Int, Int?, Int?, Int)) in OracleWitnessWindow.resolve(lineCount: args.0, startLine: args.1, maxLines: args.2, cap: args.3) == OracleWitnessWindow.resolve_reference(lineCount: args.0, startLine: args.1, maxLines: args.2, cap: args.3) }
    )
    if case let .failed(_, _, input, error) = result {
        Issue.record(
            "OracleWitnessWindow.resolve(lineCount:startLine:maxLines:cap:) disagrees with its documented reference definition at input \(input). \(error?.message ?? "")"
        )
    }
}

// W8
// Fill in the reference definition below — your docstring already states it:
//   "Returns whether the name starts with the pattern."
// Then run the test: the generator finds the input where the code disagrees
// with its own documentation.
func oracleWitnessHasPrefix_reference(_ name: String, matching pattern: String) -> Bool {
    name.starts(with: pattern)
}

@Test func oracleWitnessHasPrefix_matchesReferenceDefinition() async {
    let backend = SwiftPropertyBasedBackend()
    let seed = Seed(
        stateA: 0x0000000000005EED,
        stateB: 0x0000000000C0FFEE,
        stateC: 0x000000000000BEEF,
        stateD: 0x000000000000F00D
    )
    let result = await backend.check(
        trials: 100,
        seed: seed,
        sample: { rng in
                    let arg0 = (Gen.frequency((3.0, Gen<Character>.letterOrNumber.string(of: 0...8)), (1.0, Gen<String?>.element(of: ["", " ", "  ", "\n", "\t", "-", "- ", "  -", "- x", "a\n- b", ":", "#", "# ", "/"] as [String]).map { $0! }), (3.0, Gen<String?>.element(of: ["", " ", "  ", "\n", "\t", "-", "- ", "  -", "- x", "a\n- b", ":", "#", "# ", "/"] as [String]).map { $0! }.map { $0 + $0 }), (1.0, zip(Gen<String?>.element(of: ["", " ", "  ", "\n", "\t", "-", "- ", "  -", "- x", "a\n- b", ":", "#", "# ", "/"] as [String]).map { $0! }, Gen<Character>.letterOrNumber.string(of: 0...4)).map { $0 + $1 }))).run(using: &rng)
                    let arg1 = (Gen.frequency((3.0, Gen<Character>.letterOrNumber.string(of: 0...8)), (1.0, Gen<String?>.element(of: ["", " ", "  ", "\n", "\t", "-", "- ", "  -", "- x", "a\n- b", ":", "#", "# ", "/"] as [String]).map { $0! }), (3.0, Gen<String?>.element(of: ["", " ", "  ", "\n", "\t", "-", "- ", "  -", "- x", "a\n- b", ":", "#", "# ", "/"] as [String]).map { $0! }.map { $0 + $0 }), (1.0, zip(Gen<String?>.element(of: ["", " ", "  ", "\n", "\t", "-", "- ", "  -", "- x", "a\n- b", ":", "#", "# ", "/"] as [String]).map { $0! }, Gen<Character>.letterOrNumber.string(of: 0...4)).map { $0 + $1 }))).run(using: &rng)
                    return (arg0, arg1)
                },
        property: { (args: (String, String)) in oracleWitnessHasPrefix(args.0, matching: args.1) == oracleWitnessHasPrefix_reference(args.0, matching: args.1) }
    )
    if case let .failed(_, _, input, error) = result {
        Issue.record(
            "oracleWitnessHasPrefix(_:matching:) disagrees with its documented reference definition at input \(input). \(error?.message ?? "")"
        )
    }
}

// W9
// Fill in the reference definition below — your docstring already states it:
//   "Returns the prefix that fits in the length budget, and whether anything was cut."
// Then run the test: the generator finds the input where the code disagrees
// with its own documentation.
// (every element of the returned tuple must be Equatable for this to compile — Swift defines `==` on tuples of two to six Equatable elements, though a tuple itself never conforms to Equatable)
extension String {
    func oracleWitnessClipped_reference(toLength limit: Int) -> (text: String, didTruncate: Bool) {
        let kept = String(prefix(Swift.max(limit, 0))); return (kept, kept.count < count)
    }
}

@Test func String_oracleWitnessClipped_matchesReferenceDefinition() async {
    let backend = SwiftPropertyBasedBackend()
    let seed = Seed(
        stateA: 0x0000000000005EED,
        stateB: 0x0000000000C0FFEE,
        stateC: 0x000000000000BEEF,
        stateD: 0x000000000000F00D
    )
    let result = await backend.check(
        trials: 100,
        seed: seed,
        sample: { rng in
                    let arg0 = (Gen<Character>.letterOrNumber.string(of: 0...8)).run(using: &rng)
                    let arg1 = (Gen.frequency((3.0, Gen<Int>.boundedForArithmetic()), (2.0, Gen<Int?>.element(of: [0, -1, 1] as [Int]).map { $0! }))).run(using: &rng)
                    return (arg0, arg1)
                },
        property: { (args: (String, Int)) in args.0.oracleWitnessClipped(toLength: args.1) == args.0.oracleWitnessClipped_reference(toLength: args.1) }
    )
    if case let .failed(_, _, input, error) = result {
        Issue.record(
            "String.oracleWitnessClipped(toLength:) disagrees with its documented reference definition at input \(input). \(error?.message ?? "")"
        )
    }
}

// W10
// Fill in the reference definition below — your docstring already states it:
//   "Returns the length scaled by the factor, never negative."
// Then run the test: the generator finds the input where the code disagrees
// with its own documentation.
// (the return type Double must be Equatable for this to compile)
extension OracleWitnessGeometry {
    static func scaled_reference(_ length: Double, by factor: Double) -> Double {
        abs(factor * length)
    }
}

@Test func OracleWitnessGeometry_scaled_matchesReferenceDefinition() async {
    let backend = SwiftPropertyBasedBackend()
    let seed = Seed(
        stateA: 0x0000000000005EED,
        stateB: 0x0000000000C0FFEE,
        stateC: 0x000000000000BEEF,
        stateD: 0x000000000000F00D
    )
    let result = await backend.check(
        trials: 100,
        seed: seed,
        sample: { rng in
                    let arg0 = (Gen.frequency((3.0, Gen<Double>.double(in: -1_000_000...1_000_000)), (2.0, Gen<Double?>.element(of: [0.0, -1.0, 1.0] as [Double]).map { $0! }))).run(using: &rng)
                    let arg1 = (Gen.frequency((3.0, Gen<Double>.double(in: -1_000_000...1_000_000)), (2.0, Gen<Double?>.element(of: [0.0, -1.0, 1.0] as [Double]).map { $0! }))).run(using: &rng)
                    return (arg0, arg1)
                },
        property: { (args: (Double, Double)) in approximatelyEqual(OracleWitnessGeometry.scaled(args.0, by: args.1), OracleWitnessGeometry.scaled_reference(args.0, by: args.1)) }
    )
    if case let .failed(_, _, input, error) = result {
        Issue.record(
            "OracleWitnessGeometry.scaled(_:by:) disagrees with its documented reference definition at input \(input). \(error?.message ?? "")"
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

// W11
// Fill in the reference definition below — your docstring already states it:
//   "Returns the total plus the amount, and leaves the tally unchanged."
// Then run the test: the generator finds the input where the code disagrees
// with its own documentation.
// (the return type Int must be Equatable for this to compile)
// Inputs must be Sendable. Declare each of these once per test target, and delete it if SwiftInferSendableShims.swift or another scaffold already does:
extension OracleWitnessTally: @unchecked Sendable {}
extension OracleWitnessTally {
    func adding_reference(_ amount: Int) -> Int {
        amount &+ total
    }
}

@Test func OracleWitnessTally_adding_matchesReferenceDefinition() async {
    let backend = SwiftPropertyBasedBackend()
    let seed = Seed(
        stateA: 0x0000000000005EED,
        stateB: 0x0000000000C0FFEE,
        stateC: 0x000000000000BEEF,
        stateD: 0x000000000000F00D
    )
    let result = await backend.check(
        trials: 100,
        seed: seed,
        sample: { rng in
                    let arg0 = (Gen<Int>.int(in: -99...99).map { OracleWitnessTally(total: $0) }).run(using: &rng)
                    let arg1 = (Gen.frequency((3.0, Gen<Int>.boundedForArithmetic()), (2.0, Gen<Int?>.element(of: [0, -1, 1] as [Int]).map { $0! }))).run(using: &rng)
                    return (arg0, arg1)
                },
        property: { (args: (OracleWitnessTally, Int)) in args.0.adding(args.1) == args.0.adding_reference(args.1) }
    )
    if case let .failed(_, _, input, error) = result {
        Issue.record(
            "OracleWitnessTally.adding(_:) disagrees with its documented reference definition at input \(input). \(error?.message ?? "")"
        )
    }
}
// swiftlint:enable closure_end_indentation identifier_name large_tuple line_length
