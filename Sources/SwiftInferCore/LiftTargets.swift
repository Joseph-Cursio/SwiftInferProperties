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

    /// Visible callers, by the restricted subject's location. Sorted, so the rendered
    /// caveat is stable across runs — PRD §16 #6 reaches this.
    private let callersBySubject: [SourceLocation: [String]]

    public init(callersBySubject: [SourceLocation: [String]] = [:]) {
        self.callersBySubject = callersBySubject
    }

    /// Visible callers for a subject, or `[]` when it has none.
    public func callers(for subject: SourceLocation) -> [String] {
        callersBySubject[subject] ?? []
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

        var index: [SourceLocation: [String]] = [:]
        for subject in subjects {
            let visible = (byFile[subject.location.file] ?? []).filter { caller in
                caller.location != subject.location
                    && caller.calledFreeFunctionNames.contains(subject.name)
                    && !restrictedLocations.contains(caller.location)
            }
            guard !visible.isEmpty else { continue }
            index[subject.location] = Set(visible.map(\.name)).sorted()
        }
        return Self(callersBySubject: index)
    }

    /// The caveat line, or `nil` when no visible caller was found.
    ///
    /// **Additive.** §2 is explicit that the row itself is right — *"not a gate, not a
    /// demotion, not a veto"* — so this adds a line and changes no score.
    public func caveat(for subject: SourceLocation) -> String? {
        let names = callers(for: subject)
        guard let first = names.first else { return nil }
        let target = names.count == 1
            ? "`\(first)`"
            : "`\(first)` (or \(names.dropFirst().map { "`\($0)`" }.joined(separator: ", ")))"
        return "LIFT IT INSTEAD OF WIDENING: \(target) calls this and is visible to tests. "
            + "State the law there — a lifted law survives the helper being renamed, inlined "
            + "or replaced, and it tests how the helper is USED, which is where this class of "
            + "bug lives."
    }
}
