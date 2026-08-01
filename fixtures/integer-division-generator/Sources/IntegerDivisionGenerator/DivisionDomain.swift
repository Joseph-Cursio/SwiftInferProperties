// The two generated domains for the swift.org division law, side by side.
//
// Subject: `validation-test/stdlib/IntegerDivision.swift`, the
// "Int64 division inbounds" arm, at `swift` @ `408632e59834c1a5ee4166ff61dd2c8b0585a1c5`.
// Apache-2.0 with Runtime Library Exception; the original carries the Swift
// project's copyright header and is reproduced here only in the parts this
// measurement needs.
//
// THE LAW IS IDENTICAL IN BOTH DOMAINS AND VERBATIM FROM THE ORIGINAL:
// build a 128-bit dividend as `divisor * quotient + remainder`, divide it
// back, and require both components to come out unchanged. Only the *domain*
// differs. Q4's premise is that the human supplied the law and the generator
// is the mechanical part; this fixture is that premise made measurable.

/// The corpus's own PRNG, reproduced exactly. The original comments it as a
/// "dead-simple deterministic random source to ensure that we always test the
/// same 'random' values" — so both domains below are fully deterministic and
/// every number this fixture reports is exact rather than sampled.
public struct WyRand: RandomNumberGenerator {
    public var state: UInt64

    public init(state: UInt64) {
        self.state = state
    }

    public mutating func next() -> UInt64 {
        state &+= 0xa076_1d64_78bd_642f
        let product = state.multipliedFullWidth(by: state ^ 0xe703_7ed1_a0b4_28db)
        return product.high ^ product.low
    }
}

/// One generated trial: the three values the law quantifies over, plus the
/// 128-bit dividend they build.
public struct Trial: Sendable {
    public let divisor: Int64
    public let quotient: Int64
    public let remainder: Int64
    public let high: Int64
    public let low: UInt64
}

/// Which of the two domains to draw from.
public enum Domain: Sendable, CaseIterable {
    /// The corpus's generator, unchanged: stratify by top byte, fill the low
    /// 56 bits at random.
    case original
    /// The conversion: the same stratification with **per-slot edge rotation**
    /// layered on top.
    case edgeRotating
}

public enum DivisionDomain {

    /// Divisor edges. Zero is deliberately absent — `dividingFullWidth` traps
    /// on a zero divisor and this suite is the *inbounds* one, so a domain
    /// containing it would be testing a different contract.
    public static let divisorEdges: [Int64] = [1, -1, 2, -2, .max, .min, .max - 1, .min + 1]

    /// Quotient edges. Zero **is** included: a dividend smaller in magnitude
    /// than its divisor is a perfectly inbounds case that the original domain
    /// never once reaches.
    public static let quotientEdges: [Int64] = [0, 1, -1, 2, -2, .max, .min]

    /// Remainder edges have to be expressed as a policy rather than as values,
    /// because the legal range is `0 ..< |divisor|` and so depends on the
    /// divisor drawn. Zero is exact division; `|divisor| - 1` is the largest
    /// legal remainder and the one a missing final correction step gets wrong.
    public enum RemainderEdge: Sendable, CaseIterable {
        case zero
        case one
        case maximumLegal
        case halfway
    }

    /// Both arms run 256 × 256 = 65,536 trials, the same count as the original.
    public static let trialCount = 65_536

    /// Generates the domain and hands each trial to `body`.
    ///
    /// Why **rotation** rather than a fixed bias: a static "always edge slot 1"
    /// scheme spends the whole edge budget on the divisor and never pairs an
    /// edge divisor with an edge remainder. Rotating the slot keeps the
    /// three-way interactions alive while leaving three quarters of the trials
    /// on the original stratified draw, which is what protects interior
    /// coverage (see `M8` in the refutation gate).
    public static func generate(_ domain: Domain, _ body: (Trial) -> Void) {
        let step: Int64 = 0x100_0000_0000_0000
        var generator = WyRand(state: 0)
        let edged = domain == .edgeRotating

        for (divisorIndex, divisorHighByte) in ((-128 as Int64) ... 127).enumerated() {
            // The stratified draw is taken unconditionally in both arms, so the
            // two domains consume the PRNG identically and the comparison is
            // not confounded by stream drift.
            let stratifiedDivisor = divisorHighByte << 56
                | Int64.random(in: 0 ..< step, using: &generator)
            let divisor = (edged && divisorIndex % 32 == 0)
                ? divisorEdges[(divisorIndex / 32) % divisorEdges.count]
                : stratifiedDivisor

            for (quotientIndex, quotientHighByte) in ((-128 as Int64) ... 127).enumerated() {
                let stratifiedQuotient = quotientHighByte << 56
                    | Int64.random(in: 0 ..< step, using: &generator)
                let quotient = (edged && quotientIndex % 4 == 0)
                    ? quotientEdges[(quotientIndex / 4) % quotientEdges.count]
                    : stratifiedQuotient

                let stratifiedMagnitude = UInt64.random(in: 0 ..< divisor.magnitude, using: &generator)
                var remainderMagnitude = stratifiedMagnitude
                if edged && quotientIndex % 4 == 2 {
                    // Offset from the quotient slot so the two never coincide.
                    switch RemainderEdge.allCases[(quotientIndex / 4) % RemainderEdge.allCases.count] {
                    case .zero:
                        remainderMagnitude = 0
                    case .one:
                        remainderMagnitude = divisor.magnitude > 1 ? 1 : 0
                    case .maximumLegal:
                        remainderMagnitude = divisor.magnitude - 1
                    case .halfway:
                        remainderMagnitude = divisor.magnitude / 2
                    }
                }

                // --- verbatim from the corpus arm, in both domains ---
                let product = divisor.multipliedFullWidth(by: quotient)
                let remainder = product.high < 0
                    ? -Int64(remainderMagnitude)
                    : Int64(remainderMagnitude)
                let (low, carried) = product.low
                    .addingReportingOverflow(UInt64(truncatingIfNeeded: remainder))
                let high = product.high &+ (remainder >> 63) &+ (carried ? 1 : 0)
                // --- end verbatim ---

                body(Trial(
                    divisor: divisor,
                    quotient: quotient,
                    remainder: remainder,
                    high: high,
                    low: low
                ))
            }
        }
    }
}
