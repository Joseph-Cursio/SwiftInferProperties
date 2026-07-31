import Foundation

/// **Every function here is deliberately wrong.** See `Package.swift` for why that makes the
/// experiment readable without judgement calls: any `measured-bothPass` is a verifier blind
/// spot, not a debatable result.
///
/// Each stub is labelled with the *kind* of violation it carries, because the hypothesis under
/// test is about kinds rather than templates:
///
/// - **BROAD** — violated on most inputs. A generator drawing anything at all should find it.
/// - **COLLISION** — violated only when two generated values **coincide**. CLAUDE.md records
///   this as the known blind spot: *"a derived generator is tuned for coverage of the TYPE and
///   is silently mistuned for coverage of the LAW … invisible to a generator drawing keys from
///   a realistic domain."* Measured once already — `Decisions.merge` commutativity is false and
///   verify reported `bothPass` at 100 trials.
/// - **EDGE** — violated only at a boundary value (empty, zero, `Int.max`). The verifier runs a
///   dedicated edge pass, so these test whether that pass earns its keep.
///
/// Predictions are frozen in `predictions.json` **before** the run.

// MARK: - BROAD — violated on most inputs

/// BROAD / idempotence. Appends on every call, so `f(f(x)) != f(x)` for *every* input.
public func normalizeTag(_ tag: String) -> String {
    tag + "!"
}

/// BROAD / commutativity. Subtraction is not commutative; fails for every `a != b`.
public func combineOffsets(_ first: Int, _ second: Int) -> Int {
    first - second
}

/// BROAD / round-trip (forward half). Pairs with `decodeTicket`.
public func encodeTicket(_ ticket: String) -> String {
    "T:" + ticket
}

/// BROAD / round-trip (reverse half). Drops the final character as well as the prefix, so the
/// round-trip fails for every non-empty ticket.
public func decodeTicket(_ encoded: String) -> String {
    let body = encoded.hasPrefix("T:") ? String(encoded.dropFirst(2)) : encoded
    return String(body.dropLast())
}

/// BROAD / monotonicity. A measure that *decreases* as its input grows.
public func weightOfPayload(_ payload: [Int]) -> Int {
    -payload.count
}

// MARK: - COLLISION — violated only when two generated values coincide

/// COLLISION / commutativity. Picks the later timestamp and breaks ties toward the FIRST
/// argument, so `merge(a, b) != merge(b, a)` **only when the two timestamps are equal**.
///
/// This is the exact shape the self-dogfood road test measured on `Decisions.merge`: false,
/// and reported `bothPass` at 100 trials until the timestamp alphabet was narrowed.
public func mergeSnapshots(_ first: Snapshot, _ second: Snapshot) -> Snapshot {
    second.timestamp > first.timestamp ? second : first
}

/// A two-field record whose `timestamp` is the collision-bearing slot.
public struct Snapshot: Equatable, Sendable {
    public let identifier: Int
    public let timestamp: Int
    public init(identifier: Int, timestamp: Int) {
        self.identifier = identifier
        self.timestamp = timestamp
    }
}

/// COLLISION / idempotence. Deduplicates by a **bucket** (`value % 8`) rather than by value, so
/// a second application is a no-op *unless* two distinct values share a bucket. Requires a
/// collision in the generated array to violate.
public func deduplicateByBucket(_ values: [Int]) -> [Int] {
    var seen: Set<Int> = []
    var result: [Int] = []
    for value in values where seen.insert(value % 8).inserted {
        result.append(value)
    }
    return result
}

/// COLLISION / model-law. An interval set whose `union` **drops** any interval from the other
/// side that begins exactly where one of ours ends, instead of merging the seam. Membership
/// then answers wrongly at that boundary — but only when two generated intervals happen to
/// abut, which is the collision this class is named for.
///
/// The first draft of this stub was not wrong at all: an *unmerged* concatenation still answers
/// `contains` correctly, so the membership law held and the stub tested nothing. Corrected
/// before the run, and recorded because it is the same trap the experiment is about — a law can
/// be unfalsifiable by construction, not merely by generator.
public struct IntervalSet: Equatable, Sendable {

    public let intervals: [Interval]

    public init(intervals: [Interval]) {
        self.intervals = intervals
    }

    public func contains(_ value: Int) -> Bool {
        intervals.contains { $0.lower <= value && value < $0.upper }
    }

    public func union(_ other: IntervalSet) -> IntervalSet {
        let kept = other.intervals.filter { candidate in
            !intervals.contains { $0.upper == candidate.lower }
        }
        return IntervalSet(intervals: intervals + kept)
    }
}

/// A half-open interval.
public struct Interval: Equatable, Sendable {
    public let lower: Int
    public let upper: Int
    public init(lower: Int, upper: Int) {
        self.lower = lower
        self.upper = upper
    }
}

// MARK: - EDGE — violated only at a boundary value

/// EDGE / round-trip (forward half). Pairs with `unpackLabel`.
public func packLabel(_ label: String) -> String {
    label.isEmpty ? "<none>" : label
}

/// EDGE / round-trip (reverse half). Correct for every non-empty label; the sentinel written by
/// `packLabel` does not decode back to the empty string, so the round-trip fails **only** on the
/// empty input.
public func unpackLabel(_ packed: String) -> String {
    packed
}

/// EDGE / idempotence. Correct for every non-empty string; returns a sentinel for the empty
/// one, so `f(f("")) != f("")`.
public func trimWhitespace(_ text: String) -> String {
    let trimmed = text.trimmingCharacters(in: .whitespaces)
    return trimmed.isEmpty ? "-" : trimmed
}

/// EDGE / monotonicity. Order-preserving everywhere except at zero, which maps above one.
public func scoreOf(_ value: Int) -> Int {
    value == 0 ? 2 : value
}

// MARK: - Int-carrier METHODS — the only shape the verifier can actually measure
//
// Two failed rounds taught the shape, and both failures were mine:
//
// 1. Free functions have **no carrier**. The emitter still renders a receiver, producing
//    `let applyOnce: (Int) -> Int = (none).normalizeScore` — uncompilable, reported as
//    `measured-error: build-failed` rather than `unsupported-carrier`. (That mismatch is a
//    real verifier defect: a shape it cannot support should be declined, not mis-emitted.)
// 2. Every stub emitter declares `supportedCarriers = ["Complex<Double>", "Double", "Int"]`,
//    so a law on `String`, an array, or a user's own struct is never measured at all.
//
// Hence: methods in an `extension Int`. This is the ONLY shape in which the experiment's real
// question — which violation kinds does the generator catch? — can even be asked.

public extension Int {

    /// BROAD / idempotence. Increments every call, so `f(f(x)) != f(x)` for every input.
    func normalizedScore() -> Int { self + 1 }

    /// BROAD / commutativity. Subtraction; fails for every `a != b`.
    func combinedTally(_ other: Int) -> Int { self - other }

    /// COLLISION / commutativity. Correct unless the operands agree modulo 100, where it
    /// returns the receiver — so the law breaks only when `a % 100 == b % 100` and `a != b`.
    /// Roughly a 1-in-100 coincidence over a wide domain: the regime CLAUDE.md says a derived
    /// generator misses.
    func combinedBucket(_ other: Int) -> Int {
        (self % 100 == other % 100) ? self : self &+ other
    }

    /// COLLISION / idempotence. Correct unless the value is a multiple of 997, where a second
    /// application moves it again.
    func canonicalizedOffset() -> Int {
        self % 997 == 0 ? self &+ 1 : self
    }

    /// EDGE / commutativity. Correct except when exactly one operand is `Int.min`, where it
    /// returns the receiver instead of the sum.
    func mergedBound(_ other: Int) -> Int {
        (self == Int.min || other == Int.min) ? self : self &+ other
    }
}
