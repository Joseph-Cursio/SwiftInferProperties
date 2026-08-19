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
