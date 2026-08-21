import Foundation

public struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    public init(seed: UInt64) { state = seed }
    public mutating func next() -> UInt64 {
        state ^= state << 13; state ^= state >> 7; state ^= state << 17
        return state
    }
}

/// The character classes a generator can draw from.
///
/// `letterOrNumber` is **what ships**: the emitted stub for a `String`-ish carrier uses
/// `Gen<Character>.letterOrNumber.string(of: 0...8)`. It is alphanumeric, so it cannot
/// produce a space, a tab or a control character — which is exactly the input class every
/// validation and legalisation function branches on.
public enum Domain: String, CaseIterable, Sendable {
    /// Alphanumeric. The shipped default.
    case letterOrNumber
    /// Alphanumeric plus space and tab.
    case withWhitespace
    /// A four-symbol alphabet — one letter, space, tab, and a control character — so
    /// structure repeats within and across draws. The `collidingString` idea applied to
    /// the *validity* axis rather than the substring axis.
    case narrowWithControls

    public var alphabet: [Character] {
        switch self {
        case .letterOrNumber: Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        case .withWhitespace: Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 \t")
        case .narrowWithControls: ["a", " ", "\t", "\u{0B}"]
        }
    }

    public func sample(_ rng: inout SeededGenerator) -> String {
        let count = Int.random(in: 0 ... 8, using: &rng)
        let letters = alphabet
        return String((0 ..< count).map { _ in letters[Int.random(in: 0 ..< letters.count, using: &rng)] })
    }
}

/// Is this a legal HTTP field value? Modelled on `HTTPField._isValidValue`: no leading or
/// trailing space/tab, and every byte in `0x09 | 0x20 | 0x21...0x7E | 0x80...0xFF`.
public func isValidValue(_ value: String) -> Bool {
    let bytes = Array(value.utf8)
    guard let first = bytes.first else { return true }
    if first == 0x09 || first == 0x20 { return false }
    if let last = bytes.last, last == 0x09 || last == 0x20 { return false }
    return bytes.allSatisfy { $0 == 0x09 || $0 == 0x20 || (0x21 ... 0x7E).contains($0) || $0 >= 0x80 }
}

/// The subject family. **The guard is the point**: the transform lives in the `else`
/// branch, so a generator that only produces valid values never runs it.
public enum Legalize {

    static func map(_ value: String, illegalTo replacement: UInt8) -> [UInt8] {
        Array(value.utf8).map { byte in
            switch byte {
            case 0x09, 0x20: byte
            case 0x21 ... 0x7E, 0x80...: byte
            default: replacement
            }
        }
    }

    static func trimmed(_ bytes: [UInt8], leading: Bool, trailing: Bool) -> [UInt8] {
        var result = bytes[...]
        if trailing { while let last = result.last, last == 0x09 || last == 0x20 { result = result.dropLast() } }
        if leading { while let first = result.first, first == 0x09 || first == 0x20 { result = result.dropFirst() } }
        return Array(result)
    }

    /// Correct: map illegal bytes to space, then trim BOTH ends. Idempotent.
    public static func correct(_ value: String) -> String {
        guard !isValidValue(value) else { return value }
        return String(decoding: trimmed(map(value, illegalTo: 0x20), leading: true, trailing: true), as: UTF8.self)
    }

    /// **A REAL BUG that is still IDEMPOTENT** — the defect planted on `swift-http-types`,
    /// and the reason that measurement's first reading was wrong.
    ///
    /// Trimming only the trailing end leaves leading whitespace, which is a genuine
    /// correctness defect: the package's own tests catch it. But the *result* is a
    /// fixpoint — `f(" x") == " x"` and `f(f(" x")) == " x"` — so **no idempotence law can
    /// refute it, at any generator domain.** Mapping illegal bytes is a fixpoint and
    /// trimming converges; normalisers are structurally hard to break idempotently.
    public static func trailingTrimOnly(_ value: String) -> String {
        guard !isValidValue(value) else { return value }
        return String(decoding: trimmed(map(value, illegalTo: 0x20), leading: false, trailing: true), as: UTF8.self)
    }

    /// **Mutant 2 — leading trim only.** The mirror.
    public static func leadingTrimOnly(_ value: String) -> String {
        guard !isValidValue(value) else { return value }
        return String(decoding: trimmed(map(value, illegalTo: 0x20), leading: true, trailing: false), as: UTF8.self)
    }

    /// **Also a real bug, also idempotent.** Mapping to a still-illegal byte looks like it
    /// would re-enter the transform, but the second pass maps that byte to itself, so the
    /// output is a fixpoint again.
    public static func mapsToIllegal(_ value: String) -> String {
        guard !isValidValue(value) else { return value }
        return String(decoding: trimmed(map(value, illegalTo: 0x0B), leading: true, trailing: true), as: UTF8.self)
    }

    /// **The genuinely NON-idempotent mutant** — trims at most one whitespace character
    /// per call, so a value with two leading spaces needs three passes to converge. This
    /// is what an idempotence law is actually able to refute, and it is the only mutant
    /// here that one can.
    public static func trimsOneWhitespace(_ value: String) -> String {
        guard !isValidValue(value) else { return value }
        var bytes = map(value, illegalTo: 0x20)[...]
        if let last = bytes.last, last == 0x09 || last == 0x20 { bytes = bytes.dropLast() }
        if let first = bytes.first, first == 0x09 || first == 0x20 { bytes = bytes.dropFirst() }
        return String(decoding: Array(bytes), as: UTF8.self)
    }

    /// **Control — a correct variant that trims in the other order.** Still idempotent; no
    /// domain may kill it, or the scorer is measuring its own aggression.
    public static func trimThenMap(_ value: String) -> String {
        guard !isValidValue(value) else { return value }
        let trimmedFirst = trimmed(Array(value.utf8), leading: true, trailing: true)
        let mapped = map(String(decoding: trimmedFirst, as: UTF8.self), illegalTo: 0x20)
        return String(decoding: trimmed(mapped, leading: true, trailing: true), as: UTF8.self)
    }
}

public struct LawOutcome: Sendable {
    public let passed: Bool
    public let counterexample: String?
    /// Trials in which the guard was FALSE — i.e. the transform actually ran.
    public let branchReached: Int
    public init(counterexample: String?, branchReached: Int) {
        self.counterexample = counterexample
        self.branchReached = branchReached
        passed = counterexample == nil
    }
}

/// Checks `f(f(x)) == f(x)` and **reports how often the else branch was reached**.
public func checkIdempotence(
    _ subject: @Sendable (String) -> String,
    domain: Domain,
    trials: Int = 100,
    seed: UInt64 = 0x5EED_1234
) -> LawOutcome {
    var generator = SeededGenerator(seed: seed)
    var reached = 0
    var counterexample: String?
    for _ in 0 ..< trials {
        let value = domain.sample(&generator)
        if !isValidValue(value) { reached += 1 }
        let once = subject(value)
        if subject(once) != once, counterexample == nil {
            counterexample = "\(value.debugDescription) -> \(once.debugDescription)"
        }
    }
    return LawOutcome(counterexample: counterexample, branchReached: reached)
}
