// The edge classes the two domains are scored against, and the mutant dividers
// that turn a coverage count into a refutability measurement.

/// A named subset of the division domain that some plausible implementation
/// gets wrong. Coverage of these is the "before/after" Q4 asks for.
public struct EdgeClass: Sendable {
    public let name: String
    public let matches: @Sendable (Trial) -> Bool

    public init(_ name: String, _ matches: @escaping @Sendable (Trial) -> Bool) {
        self.name = name
        self.matches = matches
    }
}

public enum EdgeClasses {

    /// Classes every correct domain for this law should reach.
    ///
    /// `divisor == 0` is **not** here: it traps, and the arm under measurement
    /// is the inbounds one. Excluding it is a statement about the contract,
    /// not a gap in the domain.
    public static let all: [EdgeClass] = [
        EdgeClass("divisor == Int64.min") { $0.divisor == Int64.min },
        EdgeClass("divisor == Int64.max") { $0.divisor == Int64.max },
        EdgeClass("divisor == 1") { $0.divisor == 1 },
        EdgeClass("divisor == -1") { $0.divisor == -1 },
        EdgeClass("|divisor| <= 2") { $0.divisor.magnitude <= 2 },
        EdgeClass("|divisor| <= 2^16") { $0.divisor.magnitude <= 65_536 },
        EdgeClass("quotient == Int64.min") { $0.quotient == Int64.min },
        EdgeClass("quotient == Int64.max") { $0.quotient == Int64.max },
        EdgeClass("quotient == 0") { $0.quotient == 0 },
        EdgeClass("quotient == 1") { $0.quotient == 1 },
        EdgeClass("quotient == -1") { $0.quotient == -1 },
        EdgeClass("|quotient| <= 2^16") { $0.quotient.magnitude <= 65_536 },
        EdgeClass("remainder == 0 (exact division)") { $0.remainder == 0 },
        EdgeClass("|remainder| == |divisor| - 1 (maximal)") {
            $0.divisor != 0 && $0.remainder.magnitude == $0.divisor.magnitude - 1
        },
        EdgeClass("|remainder| <= 2^16") { $0.remainder.magnitude <= 65_536 },
        EdgeClass("dividend fits 64 bits (high == 0)") { $0.high == 0 },
        EdgeClass("dividend fits signed 64 (high == 0 or -1)") { $0.high == 0 || $0.high == -1 }
    ]

    /// Sign quadrants — the one thing the original domain covers perfectly,
    /// because its top-byte stratification is built for exactly this. Kept as a
    /// separate list so the finding reads honestly: the corpus's generator is
    /// not careless, it is *stratified for sign and blind to magnitude*.
    public static let signQuadrants: [EdgeClass] = [
        EdgeClass("divisor > 0, quotient > 0") { $0.divisor > 0 && $0.quotient > 0 },
        EdgeClass("divisor > 0, quotient < 0") { $0.divisor > 0 && $0.quotient < 0 },
        EdgeClass("divisor < 0, quotient > 0") { $0.divisor < 0 && $0.quotient > 0 },
        EdgeClass("divisor < 0, quotient < 0") { $0.divisor < 0 && $0.quotient < 0 }
    ]
}

/// A wrong divider, modelled as a conditional corruption of the correct answer.
///
/// **Why the correct answer comes from the real standard library.** Findings
/// §4.4: *"a probe which substitutes something other than the real subject
/// proves nothing about the real subject."* That rule bites when the claim is
/// about `dividingFullWidth`. Here the claim is about the **domain** — "does
/// this set of inputs distinguish a correct divider from a buggy one" — so the
/// domain is the subject and the mutants are what it has to detect. Wrapping
/// the real answer in a conditional corruption models a buggy implementation
/// without pretending to be one.
///
/// **Limitation, stated rather than buried:** these mutants are hand-written.
/// They score the domain against *plausible* defects, not against the observed
/// defect distribution of real full-width dividers. `standsFor` names the
/// defect class each one represents so a reader can judge that for themselves.
public struct Mutant: Sendable {
    public let name: String
    public let standsFor: String
    /// `(trial, correctQuotient, correctRemainder) -> buggy answer`.
    public let corrupt: @Sendable (Trial, Int64, Int64) -> (quotient: Int64, remainder: Int64)

    public init(
        name: String,
        standsFor: String,
        corrupt: @escaping @Sendable (Trial, Int64, Int64) -> (quotient: Int64, remainder: Int64)
    ) {
        self.name = name
        self.standsFor = standsFor
        self.corrupt = corrupt
    }
}

public enum Mutants {

    /// Six boundary mutants and two interior controls.
    ///
    /// The controls matter as much as the boundary cases: without them a
    /// "converted domain wins 6–0" table would not show whether the edge budget
    /// was paid for out of interior coverage.
    public static let all: [Mutant] = [
        Mutant(
            name: "M1 exact-division off-by-one",
            standsFor: "a zero-remainder fast path that forgets to stop early"
        ) { _, quotient, remainder in
            remainder == 0 ? (quotient &+ 1, remainder) : (quotient, remainder)
        },
        Mutant(
            name: "M2 unit-divisor shortcut",
            standsFor: "a |divisor| == 1 shortcut that drops the sign"
        ) { trial, quotient, remainder in
            trial.divisor.magnitude == 1 ? (quotient &* -1, remainder) : (quotient, remainder)
        },
        Mutant(
            name: "M3 Int64.min divisor",
            standsFor: "negating the divisor to work unsigned — Int64.min has no positive"
        ) { trial, quotient, remainder in
            trial.divisor == Int64.min ? (quotient &+ 1, remainder) : (quotient, remainder)
        },
        Mutant(
            name: "M4 Int64.min quotient",
            standsFor: "an overflow guard written as `> Int64.max` that excludes the min"
        ) { _, quotient, remainder in
            quotient == Int64.min ? (quotient &+ 1, remainder) : (quotient, remainder)
        },
        Mutant(
            name: "M5 maximal remainder",
            standsFor: "a missing final correction step when |remainder| == |divisor| - 1"
        ) { trial, quotient, remainder in
            trial.divisor != 0 && remainder.magnitude == trial.divisor.magnitude - 1
                ? (quotient &+ 1, remainder &- trial.divisor)
                : (quotient, remainder)
        },
        Mutant(
            name: "M6 64-bit dividend path",
            standsFor: "a `high == 0` fast path delegating to single-width divide"
        ) { trial, quotient, remainder in
            trial.high == 0 ? (quotient &+ 1, remainder) : (quotient, remainder)
        },
        Mutant(
            name: "M7 interior, low-word bit 17",
            standsFor: "CONTROL — a common interior bug the ORIGINAL domain already catches"
        ) { trial, quotient, remainder in
            (Int64(bitPattern: trial.low) >> 17) & 1 == 1
                ? (quotient &+ 1, remainder)
                : (quotient, remainder)
        },
        Mutant(
            name: "M8 interior, 1-in-4096",
            standsFor: "CONTROL — a rare interior bug; shows whether the edge budget "
                + "costs interior detection"
        ) { trial, quotient, remainder in
            Int64(bitPattern: trial.low) & 0xFFF == 0x37B
                ? (quotient &+ 1, remainder)
                : (quotient, remainder)
        }
    ]
}
