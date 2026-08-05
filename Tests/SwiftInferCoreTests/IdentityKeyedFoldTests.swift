import Foundation
import Testing

@testable import SwiftInferCore

/// `IdentityKeyedFold` — the shared merge the four aggregate logs adopted.
///
/// **Both laws are asserted, and that is the point.** The old per-type folds were
/// *take-first-max*: not commutative, but genuinely associative. A tie-break that
/// restored commutativity while breaking associativity would fix the measured bug
/// and introduce an unmeasured one, so every arm here checks the pair.
///
/// The domain is deliberately collision-dense — few identities, few timestamps,
/// differing payloads — because a law that fails only when two generated values
/// collide is invisible to a generator drawing from a realistic domain. That is
/// the standing note in CLAUDE.md, and it is why the whole-corpus survey caught
/// these merges at all: the derived generator happened to draw a two-letter
/// alphabet and two distinct dates.
@Suite("IdentityKeyedFold")
struct IdentityKeyedFoldTests {

    /// Minimal stand-in with the shape all four real records share: an identity,
    /// a date, and a payload that does not participate in either.
    private struct Row: Encodable, Equatable {
        let identityHash: String
        let payload: String
        let stamp: Date
    }

    private static func fold(_ lhs: [Row], _ rhs: [Row]) -> [Row] {
        IdentityKeyedFold.merged(
            primary: lhs,
            secondary: rhs,
            identity: \.identityHash,
            timestamp: \.stamp
        )
    }

    /// Every single-record log over 2 identities x 2 payloads x 2 stamps.
    private static var universe: [[Row]] {
        var rows: [[Row]] = []
        for identity in ["A", "B"] {
            for payload in ["p", "q"] {
                for offset in [0.0, 1.0] {
                    let row = Row(
                        identityHash: identity,
                        payload: payload,
                        stamp: Date(timeIntervalSince1970: offset)
                    )
                    rows.append([row])
                }
            }
        }
        return rows
    }

    @Test("commutative over a collision-dense domain")
    func commutativeExhaustively() {
        var failures = 0
        for lhs in Self.universe {
            for rhs in Self.universe where Self.fold(lhs, rhs) != Self.fold(rhs, lhs) {
                failures += 1
            }
        }
        #expect(failures == 0)
    }

    /// The property the OLD fold already had. Measured 0/512 before this change
    /// and asserted here so the tie-break cannot silently trade one law for the other.
    @Test("associative over a collision-dense domain")
    func associativeExhaustively() {
        var failures = 0
        for lhs in Self.universe {
            for mid in Self.universe {
                for rhs in Self.universe
                where Self.fold(Self.fold(lhs, mid), rhs) != Self.fold(lhs, Self.fold(mid, rhs)) {
                    failures += 1
                }
            }
        }
        #expect(failures == 0)
    }

    /// The exact counterexample the whole-corpus survey found on
    /// `PostAcceptanceOutcomeLog.merge` — one identity, one timestamp, two
    /// different payloads. Under the old `>=` tie-break this returned the
    /// left-hand payload in one direction and the right-hand payload in the other.
    @Test("equal timestamps do not let argument order decide the winner")
    func equalTimestampsAreOrderIndependent() {
        let when = Date(timeIntervalSince1970: 0)
        let lhs = [Row(identityHash: "A", payload: "from corpus A", stamp: when)]
        let rhs = [Row(identityHash: "A", payload: "from corpus B", stamp: when)]
        #expect(Self.fold(lhs, rhs) == Self.fold(rhs, lhs))
        #expect(Self.fold(lhs, rhs).count == 1)
    }

    /// Recency still decides when the dates differ — the fix must not flatten the
    /// "latest run in effect" posture into "whichever encodes larger".
    @Test("a later timestamp still wins regardless of argument order")
    func laterTimestampWins() {
        let early = Row(
            identityHash: "A", payload: "early", stamp: Date(timeIntervalSince1970: 0)
        )
        // Payload chosen so the canonical encoding of the EARLIER row sorts
        // higher; if the tie-break leaked into the non-tie path, this fails.
        let late = Row(
            identityHash: "A", payload: "aaa", stamp: Date(timeIntervalSince1970: 10)
        )
        #expect(Self.fold([early], [late]) == [late])
        #expect(Self.fold([late], [early]) == [late])
    }

    /// Distinct identities are never collapsed, and the row ORDER is stable —
    /// the guarantee the old fold's doc comment actually delivered.
    @Test("distinct identities all survive, sorted by (timestamp, identity)")
    func distinctIdentitiesSurvive() {
        let first = Row(
            identityHash: "B", payload: "x", stamp: Date(timeIntervalSince1970: 0)
        )
        let second = Row(
            identityHash: "A", payload: "y", stamp: Date(timeIntervalSince1970: 5)
        )
        let merged = Self.fold([first], [second])
        #expect(merged == [first, second])
        #expect(Self.fold([second], [first]) == [first, second])
    }
}
