import Foundation
import Testing

@testable import SwiftInferCore

// MARK: - Transitive

extension LiftTargetsTests {

    /// **The 842 → 561 gap the direct pass leaves.** A private helper called only by
    /// another private helper still has a visible caller — one hop further up — and
    /// leaving it uncaveated says "nothing to lift to" when there is.
    @Test("a caller two hops up is found, and the caveat says the reach is indirect")
    func transitiveCallerIsFound() {
        let leaf = Self.summary("normalize", line: 10)
        let middle = Self.summary("prepare", line: 20, calls: ["normalize"])
        let top = Self.summary("lookupSuggestion", line: 30, calls: ["prepare"])
        let targets = LiftTargets.make(
            summaries: [leaf, middle, top],
            restrictedFunctions: [Self.restricted(leaf), Self.restricted(middle)]
        )

        #expect(targets.callers(for: leaf.location) == ["lookupSuggestion"])
        #expect(targets.target(for: leaf.location)?.depth == 2)

        let caveat = targets.caveat(for: leaf.location)
        #expect(caveat?.contains("reaches this through 1 more private helper") == true, """
        The caveat claims a direct call for a two-hop reach. A reader looking for the call \
        will not find it and will distrust the advice.
        """)
        #expect(caveat?.contains("helpers") == false, "singular expected at depth 2")
    }

    @Test("three hops pluralises the helper count")
    func threeHopsPluralise() {
        let leaf = Self.summary("a", line: 10)
        let mid1 = Self.summary("b", line: 20, calls: ["a"])
        let mid2 = Self.summary("c", line: 30, calls: ["b"])
        let top = Self.summary("visible", line: 40, calls: ["c"])
        let targets = LiftTargets.make(
            summaries: [leaf, mid1, mid2, top],
            restrictedFunctions: [leaf, mid1, mid2].map(Self.restricted)
        )

        #expect(targets.target(for: leaf.location)?.depth == 3)
        #expect(targets.caveat(for: leaf.location)?.contains("2 more private helpers") == true)
    }

    /// **The nearest visible caller wins.** A chain that passes a visible function should
    /// stop there rather than walking past it to a further one — the reader wants the
    /// closest place the law can be stated, not the outermost.
    @Test("the walk stops at the nearest visible caller")
    func walkStopsAtNearest() {
        let leaf = Self.summary("normalize", line: 10)
        let near = Self.summary("nearVisible", line: 20, calls: ["normalize"])
        let far = Self.summary("farVisible", line: 30, calls: ["nearVisible"])
        let targets = LiftTargets.make(
            summaries: [leaf, near, far], restrictedFunctions: [Self.restricted(leaf)]
        )

        #expect(targets.callers(for: leaf.location) == ["nearVisible"])
        #expect(targets.target(for: leaf.location)?.depth == 1)
    }

    /// **Mutual recursion must terminate, not hang.** Two private helpers calling each
    /// other with nothing visible above them is rare and not impossible, and a tool that
    /// hangs inside `discover` is worse than one that declines to answer.
    @Test("a cycle with no visible caller terminates and yields nothing")
    func cycleTerminates() {
        let one = Self.summary("ping", line: 10, calls: ["pong"])
        let two = Self.summary("pong", line: 20, calls: ["ping"])
        let targets = LiftTargets.make(
            summaries: [one, two], restrictedFunctions: [one, two].map(Self.restricted)
        )

        #expect(targets.caveat(for: one.location) == nil)
        #expect(targets.caveat(for: two.location) == nil)
    }
}
