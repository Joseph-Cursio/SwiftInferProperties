import Foundation

/// One player's single game. **Each player plays once**, so `name` is a key — which is
/// what makes arm B's comparator a total order (see `Comparators.swift`).
///
/// ## Two types, because the `==` body is the variable under test
///
/// `fixtures/equatable-signal` measured `Equatable` as a conformance-keyed signal and
/// concluded the opposite of what it set out to test: **conformance does not predict
/// refutability, the shape of the `==` body does**. When `==` is a *projection* of the
/// stored fields it remains an equivalence relation however wrong it is, so all four
/// Equatable laws pass on a type whose equality hides a real defect.
///
/// A Swift type has exactly one `Equatable` conformance, so demonstrating that needs two
/// types. `PlayerScore` is memberwise; `ProjectedPlayerScore` compares score alone. They
/// are otherwise identical, and the fixture sorts both.
public struct PlayerScore: Equatable, Hashable, Sendable {
    public let name: String
    public let score: Int

    public init(name: String, score: Int) {
        self.name = name
        self.score = score
    }
}

/// The same value with a **projecting** `==` — `EqualityBodyShape.storedFieldProjection`,
/// the shape three real swift-collections bugs live in (`OrderedSet` order, `BitArray`
/// padding, `Deque` head rotation), each of which passes 4 of 4 Equatable laws.
///
/// It is a legitimate equivalence relation: reflexive, symmetric, transitive. That is
/// exactly the problem — the laws cannot see what it forgot.
/// **Declared `Hashable` deliberately, with a hand-written `==` and a SYNTHESIZED
/// `hash(into:)`.** Swift synthesizes the hash from *all* stored properties whenever they
/// are `Hashable`, even when `==` is written by hand — so this type satisfies all four
/// Equatable laws and violates the one that matters:
///
///     a == b  ⟹  a.hashValue == b.hashValue
///
/// Two players with equal scores are `==` and hash differently, which breaks `Set` and
/// `Dictionary` outright. See `EquatableLawsTests`.
public struct ProjectedPlayerScore: Equatable, Hashable, Sendable {
    public let name: String
    public let score: Int

    public init(name: String, score: Int) {
        self.name = name
        self.score = score
    }

    /// Deliberately ignores `name`. Two players who both bowled 214 are `==`.
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.score == rhs.score
    }
}

/// A bowling score is **bounded**, not merely non-negative.
///
/// `measure-non-negativity` covers the lower half (`>= 0`) and the catalog has no
/// upper-bound template, so `score <= perfectGame` is a law the code owes that nothing
/// currently proposes. Recorded here as a candidate gap rather than asserted as one —
/// see README §5.
///
/// Note the range is *achievable-agnostic*: some values just below 300 are not reachable
/// in real play, and this fixture does not encode which. `0...300` is the type-level
/// bound, which is the one a generator needs.
public enum ScoreBounds {
    public static let minimum = 0
    public static let perfectGame = 300
    public static let range = minimum...perfectGame
}
