import Foundation
import Testing

@testable import SwiftInferCore

/// **Naming the caller a `private`-subject law should be lifted to.**
///
/// The design is `roadtest-self-dogfood-2026-08-08.md` §2's: lift rather than widen,
/// because a lifted law survives the helper being renamed or inlined and — measured there
/// — catches a call-site mutant the helper-level law is structurally blind to.
///
/// **The negative cases are the load-bearing ones.** A caveat that names the wrong caller,
/// or names a caller the reader also cannot reach, is worse than no caveat: it spends the
/// reader's trust and sends them to a dead end. Each is asserted separately below.
@Suite("LiftTargets — name a visible caller, or say nothing")
struct LiftTargetsTests {

    static func summary(
        _ name: String,
        file: String = "F.swift",
        line: Int,
        calls: [String] = []
    ) -> FunctionSummary {
        FunctionSummary(
            name: name,
            parameters: [],
            returnTypeText: "Int",
            isThrows: false,
            isAsync: false,
            isMutating: false,
            isStatic: true,
            location: SourceLocation(file: file, line: line, column: 1),
            containingTypeName: "Carrier",
            bodySignals: .empty,
            calledFreeFunctionNames: calls
        )
    }

    static func restricted(_ summary: FunctionSummary) -> RestrictedFunction {
        RestrictedFunction(summary: summary, restriction: .notVisibleToTests)
    }

    // MARK: - Positive

    @Test("a visible same-file caller is named")
    func visibleCallerIsNamed() {
        let helper = Self.summary("normalize", line: 10)
        let caller = Self.summary("lookupSuggestion", line: 40, calls: ["normalize"])
        let targets = LiftTargets.make(
            summaries: [helper, caller], restrictedFunctions: [Self.restricted(helper)]
        )

        #expect(targets.callers(for: helper.location) == ["lookupSuggestion"])
        let caveat = targets.caveat(for: helper.location)
        #expect(caveat?.contains("lookupSuggestion") == true)
        #expect(caveat?.contains("LIFT IT INSTEAD OF WIDENING") == true)
    }

    @Test("several visible callers are all offered")
    func severalCallersAreOffered() {
        let helper = Self.summary("normalize", line: 10)
        let one = Self.summary("lookup", line: 40, calls: ["normalize"])
        let two = Self.summary("resolve", line: 60, calls: ["normalize"])
        let targets = LiftTargets.make(
            summaries: [helper, one, two], restrictedFunctions: [Self.restricted(helper)]
        )

        #expect(targets.callers(for: helper.location) == ["lookup", "resolve"])
        #expect(targets.caveat(for: helper.location)?.contains("or `resolve`") == true)
    }

    // MARK: - Negative

    /// **A private caller is no more reachable than the subject.** Naming one moves the
    /// reader's problem instead of solving it — they would lift the law onto something
    /// they still cannot call.
    @Test("a caller that is itself restricted is NOT named")
    func restrictedCallerIsNotNamed() {
        let helper = Self.summary("normalize", line: 10)
        let caller = Self.summary("innerHelper", line: 40, calls: ["normalize"])
        let targets = LiftTargets.make(
            summaries: [helper, caller],
            restrictedFunctions: [Self.restricted(helper), Self.restricted(caller)]
        )

        #expect(targets.callers(for: helper.location).isEmpty)
        #expect(targets.caveat(for: helper.location) == nil, """
        A private caller was offered as a lift target. The reader cannot reach it either, \
        so the caveat sends them to a dead end — worse than saying nothing.
        """)
    }

    /// **`private` is file-scoped, so a caller in another file cannot be this subject's.**
    /// Same-file is what makes a reverse *name* index sound rather than a guess, and this
    /// is the assertion that keeps it honest: same name, different file, not a caller.
    @Test("a same-named caller in ANOTHER file is not a caller")
    func otherFileCallerIsNotNamed() {
        let helper = Self.summary("normalize", file: "A.swift", line: 10)
        let stranger = Self.summary("elsewhere", file: "B.swift", line: 40, calls: ["normalize"])
        let targets = LiftTargets.make(
            summaries: [helper, stranger], restrictedFunctions: [Self.restricted(helper)]
        )

        #expect(targets.caveat(for: helper.location) == nil, """
        A caller in another file was named for a `private` subject. Swift makes that \
        impossible, so the match is a name collision — exactly what the same-file rule exists \
        to exclude.
        """)
    }

    @Test("a subject nothing calls yields no caveat")
    func uncalledSubjectYieldsNothing() {
        let helper = Self.summary("normalize", line: 10)
        let targets = LiftTargets.make(
            summaries: [helper], restrictedFunctions: [Self.restricted(helper)]
        )
        #expect(targets.caveat(for: helper.location) == nil)
    }

    /// `@testable` reaches `internal`, so those rows verify today; offering a lift target
    /// for one would advise a refactor that is not needed.
    @Test("an internal-or-SPI subject is out of scope")
    func internalSubjectIsOutOfScope() {
        let helper = Self.summary("normalize", line: 10)
        let caller = Self.summary("lookup", line: 40, calls: ["normalize"])
        let targets = LiftTargets.make(
            summaries: [helper, caller],
            restrictedFunctions: [RestrictedFunction(summary: helper, restriction: .internalOrSPI)]
        )
        #expect(targets.caveat(for: helper.location) == nil)
    }
}

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
