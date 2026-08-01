import Foundation
@testable import LeaderboardSort

/// The generators — **the experiment, not a detail**.
///
/// A tie is a COLLISION, and CLAUDE.md's standing rule is that any property whose failure
/// needs two generated values to collide is invisible to a generator drawing from a
/// realistic-width domain. This fixture is a rare *positive* control for that rule,
/// because the natural bowling domain is narrow enough for ties to appear on their own.
///
/// With 5 players drawn from `0...300`, the chance of at least one tie is roughly **6.5%**
/// per trial, so a 100-trial run is near-certain to find one. Draw the same scores from
/// the full `Int` range and it never happens — same law, same code, refuted or green
/// depending only on the generator.
///
/// Deterministic by construction: every generator takes an explicit seed, so a failure is
/// replayable and the README's trial numbers are checkable.
public struct Generators {

    private var state: UInt64

    public init(seed: UInt64) {
        // Avoid the zero state, which is a fixed point for xorshift.
        self.state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
    }

    public mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }

    public mutating func int(in range: ClosedRange<Int>) -> Int {
        let span = UInt64(range.upperBound - range.lowerBound + 1)
        return range.lowerBound + Int(next() % span)
    }

    /// **Narrow** — the real bowling domain. Ties arise naturally.
    public mutating func realisticBoard(playerCount: Int) -> [PlayerScore] {
        (0..<playerCount).map { index in
            PlayerScore(name: "P\(index)", score: int(in: ScoreBounds.range))
        }
    }

    /// **Wide** — scores drawn from a domain so large that two never collide.
    ///
    /// Nonsense as bowling and entirely plausible as a generator: it is what
    /// `Int.random(in:)` over an unconstrained type gives you, and a reviewer scanning for
    /// a suspicious literal walks straight past it.
    public mutating func wideBoard(playerCount: Int) -> [PlayerScore] {
        (0..<playerCount).map { index in
            PlayerScore(name: "P\(index)", score: int(in: 0...Int(Int32.max)))
        }
    }

    /// Ties guaranteed **and positioned to matter** — the control that proves the failure
    /// is reachable, so a green narrow-domain run means "no tie arose" rather than "no tie
    /// can".
    ///
    /// **A tie is not sufficient, and the first version of this generator was wrong.** It
    /// tied the even indices at a shared score and produced `[300, 144, 300, 29, 300]` —
    /// three ties, and selection sort agreed with the built-in exactly. The ties were the
    /// MAXIMUM, so no swap ever moved them.
    ///
    /// Selection sort destabilises when a swap jumps an element OVER an equal one, which
    /// needs the tied pair to be followed by something larger: `[200, 200, 300]` selects
    /// the 300, swaps it into slot 0, and sends the first 200 to the back — behind the
    /// second. So the shape below is two tied entries then a higher one.
    ///
    /// That refines the collision rule rather than restating it: it is not enough for two
    /// generated values to COLLIDE, the collision has to be POSITIONED where the code
    /// treats the two differently.
    public mutating func forcedTieBoard(playerCount: Int) -> [PlayerScore] {
        precondition(playerCount >= 3, "the instability shape needs a tied pair and a higher entry")
        let tied = int(in: 0...(ScoreBounds.perfectGame - 1))
        var board = [
            PlayerScore(name: "P0", score: tied),
            PlayerScore(name: "P1", score: tied),
            PlayerScore(name: "P2", score: ScoreBounds.perfectGame)
        ]
        for index in 3..<playerCount {
            board.append(PlayerScore(name: "P\(index)", score: int(in: 0...tied)))
        }
        return board
    }

    /// Names collide — the arm that can refute `namesAreUnique`.
    ///
    /// Same collision lesson as the scores, relocated: with unique names the invariant is
    /// unfalsifiable, so a generator drawing names from a wide alphabet reports green
    /// forever.
    public mutating func duplicateNameBoard(playerCount: Int) -> [PlayerScore] {
        (0..<playerCount).map { index in
            PlayerScore(name: "P\(index % 2)", score: int(in: ScoreBounds.range))
        }
    }
}
