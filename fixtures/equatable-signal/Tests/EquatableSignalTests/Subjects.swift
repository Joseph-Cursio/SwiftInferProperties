import ComplexModule
import PropertyBased

// MARK: - Complex reproductions
//
// swift-numerics' `Complex` is the ONLY Equatable conformance in the whole
// package (Complex+Hashable.swift:16). Its `==` is not componentwise: every
// value with a non-finite component is identified as a single "point at
// infinity". These reproductions let us ask the refutability question — would
// an Equatable law suite reject a plausible-but-wrong `==`?

/// Faithful reproduction of `Complex`'s shipped `==` / `hash(into:)`. Control arm.
struct FaithfulComplex: Hashable, Sendable, CustomStringConvertible {
    var x: Double
    var y: Double

    var isFinite: Bool { x.isFinite && y.isFinite }

    static func == (a: Self, b: Self) -> Bool {
        guard a.isFinite || b.isFinite else { return true }
        return a.x == b.x && a.y == b.y
    }

    func hash(into hasher: inout Hasher) {
        if isFinite {
            hasher.combine(x)
            hasher.combine(y)
        } else {
            hasher.combine(Double.infinity)
        }
    }

    var description: String { "(\(x), \(y))" }
}

/// Mutant 1 — the *obvious* componentwise `==`, i.e. exactly what the compiler
/// would synthesize for a two-`Double` struct. Drops the point-at-infinity guard.
struct ComponentwiseComplex: Hashable, Sendable, CustomStringConvertible {
    var x: Double
    var y: Double

    static func == (a: Self, b: Self) -> Bool {
        a.x == b.x && a.y == b.y
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(x)
        hasher.combine(y)
    }

    var description: String { "(\(x), \(y))" }
}

/// Mutant 2 — shipped `==`, but the `hash(into:)` normalisation for non-finite
/// values is dropped. `==` and `hash` now disagree.
struct NaiveHashComplex: Hashable, Sendable, CustomStringConvertible {
    var x: Double
    var y: Double

    var isFinite: Bool { x.isFinite && y.isFinite }

    static func == (a: Self, b: Self) -> Bool {
        guard a.isFinite || b.isFinite else { return true }
        return a.x == b.x && a.y == b.y
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(x)
        hasher.combine(y)
    }

    var description: String { "(\(x), \(y))" }
}

// MARK: - DoubleWidth reproductions
//
// `DoubleWidth: Equatable` (_TestSupport/DoubleWidth.swift:123) is a pure
// memberwise delegation: `lhs.low == rhs.low && lhs.high == rhs.high`. Same
// question, opposite expected answer.

/// Faithful reproduction of `DoubleWidth`'s `==`.
struct FaithfulWidePair: Equatable, Sendable, CustomStringConvertible {
    var high: Int64
    var low: UInt64

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.low == rhs.low && lhs.high == rhs.high
    }

    var description: String { "(\(high), \(low))" }
}

/// Mutant A — forgot the high word entirely. Semantically catastrophic for a
/// double-width integer: `(0, 5) == (1, 5)` reports true.
struct LowWordOnlyPair: Equatable, Sendable, CustomStringConvertible {
    var high: Int64
    var low: UInt64

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.low == rhs.low
    }

    var description: String { "(\(high), \(low))" }
}

/// Mutant B — compared the wrong pair of fields (a real copy-paste shape:
/// `lhs.low == rhs.high`).
struct CrossedFieldsPair: Equatable, Sendable, CustomStringConvertible {
    var high: Int64
    var low: UInt64

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.low == rhs.low && Int64(bitPattern: lhs.low) == rhs.high
    }

    var description: String { "(\(high), \(low))" }
}

/// Mutant C — `<=` slipped in for `==` on the high word.
struct OrderedLeakPair: Equatable, Sendable, CustomStringConvertible {
    var high: Int64
    var low: UInt64

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.low == rhs.low && lhs.high <= rhs.high
    }

    var description: String { "(\(high), \(low))" }
}

// MARK: - Generators

/// The kit's 12 curated `Complex` edge cases, as raw component pairs so the
/// same distribution can drive every reproduction above.
let edgeComponents: [(Double, Double)] = [
    (.nan, .nan),
    (.nan, 0),
    (0, .nan),
    (.infinity, 0),
    (-.infinity, 0),
    (0, .infinity),
    (0, -.infinity),
    (.infinity, .infinity),
    (0, 0),
    (-0.0, 0),
    (.greatestFiniteMagnitude, 0),
    (.leastNonzeroMagnitude, 0)
]

/// 90/10 edge-biased components, mirroring `Gen<Complex<Double>>.edgeCaseBiased()`.
func edgeBiasedComponents() -> Generator<(Double, Double), some SendableSequenceType> {
    zip(Gen<Int>.int(in: 0 ..< 120), Gen<Double>.double(in: -1e6 ... 1e6), Gen<Double>.double(in: -1e6 ... 1e6))
        .map { tag, real, imaginary -> (Double, Double) in
            tag < edgeComponents.count ? edgeComponents[tag] : (real, imaginary)
        }
}

/// A "realistic domain" generator: finite components only, which is what a
/// derived `Gen<Double>` for a two-field struct gives you by default.
func finiteComponents() -> Generator<(Double, Double), some SendableSequenceType> {
    zip(Gen<Double>.double(in: -1e6 ... 1e6), Gen<Double>.double(in: -1e6 ... 1e6))
        .map { real, imaginary -> (Double, Double) in (real, imaginary) }
}

func widePairComponents() -> Generator<(Int64, UInt64), some SendableSequenceType> {
    zip(Gen<Int>.int(in: -4 ... 4), Gen<Int>.int(in: 0 ... 8))
        .map { high, low -> (Int64, UInt64) in (Int64(high), UInt64(low)) }
}
