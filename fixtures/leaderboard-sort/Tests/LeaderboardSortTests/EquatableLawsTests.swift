import Testing
@testable import LeaderboardSort

/// **`Equatable` does imply laws — and they are the weak ones.**
///
/// `discover` proposes none of them, deliberately: `ProtocolCoverageMap` maps `Equatable` to
/// `{equatableReflexive, equatableSymmetric, equatableTransitive}` and `Hashable` to those
/// plus `hashableConsistency`, and vetoes any template that would restate a law
/// PropertyLawKit already runs. That is the division of labour working, not a miss — a
/// third category beside found and missed: **covered elsewhere**.
///
/// The point of this suite is what happens *after* they are covered. `fixtures/equatable-signal`
/// measured that conformance does not predict refutability — when `==` is a projection of the
/// stored fields it stays an equivalence relation however wrong it is, and three real
/// swift-collections bugs pass 4 of 4 Equatable laws. `ProjectedPlayerScore` is that shape,
/// and this suite shows the four laws passing on a type that is broken.
///
/// **The law that catches it is hash consistency**, which is why `Hashable` is declared here.
@Suite("Equatable — the four laws pass on a type that is broken")
struct EquatableLawsTests {

    private static let ann = ProjectedPlayerScore(name: "Ann", score: 200)
    private static let bob = ProjectedPlayerScore(name: "Bob", score: 200)
    private static let cal = ProjectedPlayerScore(name: "Cal", score: 200)

    // MARK: - All four Equatable laws hold

    @Test("reflexive")
    func reflexive() {
        for value in [Self.ann, Self.bob, Self.cal] { #expect(value == value) }
    }

    @Test("symmetric")
    func symmetric() {
        #expect((Self.ann == Self.bob) == (Self.bob == Self.ann))
    }

    @Test("transitive")
    func transitive() {
        #expect(Self.ann == Self.bob)
        #expect(Self.bob == Self.cal)
        #expect(Self.ann == Self.cal)
    }

    /// A projection is a perfectly good equivalence relation. That is the trap: the laws are
    /// satisfied *because* it is one, and they cannot see what it forgot.
    @Test("the four laws are satisfied by a projection, which is exactly the problem")
    func projectionIsAValidEquivalenceRelation() {
        #expect(Self.ann == Self.bob)
        #expect(Self.ann.name != Self.bob.name, "…while being observably different players")
    }

    // MARK: - The law that DOES catch it

    /// `a == b ⟹ a.hashValue == b.hashValue`. Swift synthesizes `hash(into:)` from all stored
    /// properties even when `==` is hand-written, so a projecting `==` breaks this the moment
    /// the ignored field differs.
    @Test("hash consistency is REFUTED where all four Equatable laws passed")
    func hashConsistencyIsRefuted() {
        #expect(Self.ann == Self.bob)
        #expect(
            Self.ann.hashValue != Self.bob.hashValue,
            "synthesized hash reads `name`; the hand-written `==` does not"
        )
    }

    /// **The container consequence is real and NONDETERMINISTIC — and I wrote the flaky
    /// version of this test first.**
    ///
    /// The obvious assertion is `Set([ann, bob]).count == 2` — a `Set` holding two elements
    /// that are `==`. Measured over six runs it gave 2, 2, 2, 2, **1**, 2.
    ///
    /// `Set` picks a bucket from `hashValue` and only calls `==` within a bucket. Different
    /// buckets ⇒ both inserted (count 2, the corruption is visible). Same bucket ⇒ `==` says
    /// equal ⇒ the second is dropped (count 1, the corruption is hidden). **Swift seeds
    /// hashing per launch**, so which happens varies per process.
    ///
    /// That is the catalog's own trap — *"Set iteration order is not a property … Swift seeds
    /// hashing per launch. A round-trip through an ordered carrier is a false law that passes
    /// locally and fails in CI"* — met from a new direction: a test asserting the CONSEQUENCE
    /// of a hash-inconsistency bug is itself hash-seed dependent.
    ///
    /// So the assertion below is the deterministic half. The container damage is described
    /// rather than asserted, because asserting it is the bug it is about.
    @Test("the container consequence is real, and asserting it directly would be flaky")
    func containerConsequenceIsNondeterministic() {
        #expect(Self.ann == Self.bob)
        #expect(Self.ann.hashValue != Self.bob.hashValue)

        // Deterministic statement of the damage: the two are `==`, so a Set is entitled to
        // hold either one or two of them, and which it does is not a property of the code.
        let count = Set([Self.ann, Self.bob]).count
        #expect(count == 1 || count == 2, "both outcomes are reachable across launches")
    }

    /// The correct type satisfies both, which is the control that makes the above meaningful.
    @Test("the memberwise type satisfies hash consistency")
    func memberwiseTypeIsConsistent() {
        let lhs = PlayerScore(name: "Ann", score: 200)
        let rhs = PlayerScore(name: "Ann", score: 200)
        #expect(lhs == rhs)
        #expect(lhs.hashValue == rhs.hashValue)
        #expect(Set([lhs, rhs]).count == 1)
    }
}
