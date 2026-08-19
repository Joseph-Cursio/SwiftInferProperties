/// The visible caller a `private`-subject law should be **lifted** to.
///
/// `docs/measurements/roadtest-self-dogfood-2026-08-08.md` §2 settled the design and named
/// the two remedies:
///
/// - **Widen** — change `private` to `internal` so a test can reach the helper. The helper
///   joins the surface and can no longer be renamed, inlined or deleted freely, and every
///   refactor that touches it breaks the test *as a test failure*, which reads like a bug.
/// - **Lift** — leave the helper private and state the law about its nearest reachable
///   **caller**. Production code is untouched and the test survives the helper being
///   renamed, inlined, split or replaced, because it never names it.
///
/// Properties are the kind of test that should survive refactoring, so lifting is the
/// right move — and §2 measured that the lifted law is *strictly stronger*, catching a
/// call-site mutant the helper-level law is structurally blind to.
///
/// **This type names the caller. It does not write the law**, and that boundary is
/// deliberate: §2's own example turned `idempotence(normalize)` into metamorphic
/// spelling-insensitivity of `lookupSuggestion`, which is a *different* law arrived at by
/// judgement. Inventing law statements is a larger claim than this catalog makes anywhere.
///
/// ## Why same-file is sound rather than heuristic
///
/// `private` and `fileprivate` are **file-scoped in Swift**, so a caller of one of these
/// subjects must be in the same file. Restricting the search there is a consequence of the
/// language, not a guess — and it is what makes a reverse **name** index safe here, since
/// a `normalize` in another type cannot be a caller of this `normalize`.
///
/// Measured 2026-08-19 (`docs/measurements/lift-caller-reach.md`): **260 of 373**
/// visibility-declined suggestions can name a visible caller, and **534 of 561** subjects
/// have exactly one.
public struct LiftTargets: Sendable, Equatable {

    /// A visible caller, and how many hops away it is.
    public struct Target: Sendable, Equatable {
        public let names: [String]
        /// 1 when the subject is called directly; 2+ when the chain passed through
        /// further `private` helpers before reaching something a test can name.
        public let depth: Int

        public init(names: [String], depth: Int) {
            self.names = names
            self.depth = depth
        }
    }

    /// Visible callers, by the restricted subject's location. Names sorted, so the
    /// rendered caveat is stable across runs — PRD §16 #6 reaches this.
    private let targetsBySubject: [SourceLocation: Target]

    public init(targetsBySubject: [SourceLocation: Target] = [:]) {
        self.targetsBySubject = targetsBySubject
    }

    /// Visible callers for a subject, or `[]` when it has none.
    public func callers(for subject: SourceLocation) -> [String] {
        targetsBySubject[subject]?.names ?? []
    }

    /// The full target, including how far up the chain it was found.
    public func target(for subject: SourceLocation) -> Target? {
        targetsBySubject[subject]
    }

    /// Build the index.
    ///
    /// **Only `.notVisibleToTests` subjects**, per `AccessRestriction`'s own doc:
    /// `@testable` genuinely reaches `.internalOrSPI`, and `.nestedLocal` is a different
    /// problem left out until measured.
    ///
    /// A caller qualifies when it is in the same file, is not the subject itself, names
    /// the subject among its **free-shape** callees, and is **itself visible to tests** —
    /// a private caller is no more reachable than the subject, and naming one would move
    /// the reader's problem rather than solve it.
    public static func make(
        summaries: [FunctionSummary],
        restrictedFunctions: [RestrictedFunction]
    ) -> Self {
        let subjects = restrictedFunctions
            .filter { $0.restriction == .notVisibleToTests }
            .map(\.summary)
        guard !subjects.isEmpty else { return Self() }

        let restrictedLocations = Set(restrictedFunctions.map(\.summary.location))
        var byFile: [String: [FunctionSummary]] = [:]
        for summary in summaries where !summary.calledFreeFunctionNames.isEmpty {
            byFile[summary.location.file, default: []].append(summary)
        }

        var index: [SourceLocation: Target] = [:]
        for subject in subjects {
            if let target = walk(
                from: subject,
                peers: byFile[subject.location.file] ?? [],
                restrictedLocations: restrictedLocations
            ) {
                index[subject.location] = target
            }
        }
        return Self(targetsBySubject: index)
    }

    /// Walk *up* the caller chain until a visible function is reached.
    ///
    /// **The whole chain stays in one file, and that is a consequence rather than a
    /// restriction.** Each link is a call to a `private` declaration and `private` is
    /// file-scoped, so if A is private and B calls it, B is in A's file; if B is private
    /// too, so is its caller. The search cannot leave the file until it reaches something
    /// visible — which is exactly where it stops.
    ///
    /// Measured 2026-08-19: the direct pass reaches 561 of 934 subjects and the walk adds
    /// **267 more**, at depths 2:198, 3:62, 4:7. Shallow, which is why a bounded walk is
    /// enough and a full graph is not needed.
    ///
    /// **Cycles terminate on `visited`.** Mutual recursion between two private helpers is
    /// rare and not impossible, and an unguarded walk would hang rather than mis-answer —
    /// the worse of the two failures for a tool that runs inside `discover`.
    private static func walk(
        from subject: FunctionSummary,
        peers: [FunctionSummary],
        restrictedLocations: Set<SourceLocation>
    ) -> Target? {
        var frontier = [subject.name]
        var visited: Set<SourceLocation> = [subject.location]
        var depth = 0

        while !frontier.isEmpty, depth < maximumChainDepth {
            depth += 1
            var deeper: [String] = []
            var visible: [String] = []
            for caller in peers where !visited.contains(caller.location) {
                guard caller.calledFreeFunctionNames.contains(where: frontier.contains)
                else { continue }
                visited.insert(caller.location)
                if restrictedLocations.contains(caller.location) {
                    deeper.append(caller.name)
                } else {
                    visible.append(caller.name)
                }
            }
            if !visible.isEmpty {
                return Target(names: Set(visible).sorted(), depth: depth)
            }
            frontier = deeper
        }
        return nil
    }

    /// Bounded because the measured chains are short — the deepest on this corpus is 4 —
    /// and because `discover` runs under the §13 budget. A subject needing more than this
    /// yields no caveat rather than a slow one.
    static let maximumChainDepth = 8

    /// The caveat line, or `nil` when no visible caller was found.
    ///
    /// **Additive.** §2 is explicit that the row itself is right — *"not a gate, not a
    /// demotion, not a veto"* — so this adds a line and changes no score.
    public func caveat(for subject: SourceLocation) -> String? {
        guard let target = targetsBySubject[subject], let first = target.names.first else {
            return nil
        }
        let named = target.names.count == 1
            ? "`\(first)`"
            : "`\(first)` (or \(target.names.dropFirst().map { "`\($0)`" }.joined(separator: ", ")))"
        // **The hop count is stated when it is not 1.** A reader told to state the law on
        // something that does not call the subject directly will look for the call, not
        // find it, and distrust the advice — so the caveat says the reach is indirect
        // rather than leaving them to discover it.
        let reach = target.depth == 1
            ? "calls this"
            : "reaches this through \(target.depth - 1) more private helper"
                + (target.depth == 2 ? "" : "s")
        return "LIFT IT INSTEAD OF WIDENING: \(named) \(reach) and is visible to tests. "
            + "State the law there — a lifted law survives the helper being renamed, inlined "
            + "or replaced, and it tests how the helper is USED, which is where this class of "
            + "bug lives."
    }
}
