import Foundation

/// **No filter may take a run to zero refutable laws.**
///
/// A law is *refutable* when there exists an implementation of its subject — type-correct and
/// plausible — that the law rejects. `concat(chunks(payload, k)) == payload` admits many. The
/// generic determinism law, `f(x) == f(x)`, admits **none**: it is true of every implementation
/// that compiles, so no reader can ever learn anything from watching it pass. A run that surfaces
/// six determinism laws and nothing else has told the reader precisely nothing, in the confident
/// voice of a tool that found six things.
///
/// This type exists because `swift-infer` has **two filters in series** — the tier cut (hide
/// `Possible`) and the seed focus (keep only what the linter named) — and *each one independently*
/// has the power to discard the last law in the run that could fail. On the road-test fixture both
/// of them did. A fix applied to one filter is not a fix: the other one eats the law instead, and
/// the scoreboard reads the same. So the rule is stated once, here, and enforced at both.
///
/// **The rule does not gut either filter.** Narrowing still works exactly as before whenever the
/// filtered set retains *any* refutable law — an ordinary run discards irrelevant refutable laws
/// freely, and should. The rule engages only at the boundary where the filter is about to leave the
/// reader with nothing that could ever fail, which is not a narrowing at all but an erasure.
///
/// **A rescue is a bug report, not a feature.** Every time this fires, some upstream stage has a
/// blind spot: the scorer undervalued the only real law in the run, or the linter cannot see a
/// function it should have seeded. Callers must say so loudly and name the subject. A rescue that
/// happened quietly would let the upstream defect live forever behind a safety net — which is how
/// the seed focus came to eat the partition law for three releases without anyone noticing.
public enum Refutability {

    /// Templates whose law is a **tautology** — true of every implementation that type-checks.
    ///
    /// Exactly one, and it is not an accident that it is the *synthesized* one: `determinism` is
    /// what `Discover+GenericLaws` emits for a seeded pure function that **no template matched**.
    /// It is the catalogue's way of saying "I have nothing to offer here," dressed as a finding.
    ///
    /// Adding a template to this set is a deliberate, reviewable act: state the implementation the
    /// law cannot reject. If you cannot name one, the template is refutable and does not belong
    /// here. If you *can*, ask why the template exists at all.
    public static let tautologicalTemplates: Set<String> = [
        // f(x) == f(x). No implementation, however wrong, fails this.
        "determinism"
    ]

    /// Whether this suggestion's law could ever fail against a wrong implementation.
    public static func isRefutable(_ suggestion: Suggestion) -> Bool {
        !tautologicalTemplates.contains(suggestion.templateName)
    }

    /// Templates whose law a **correct implementation cannot fail** — it is *entailed by the role*,
    /// not conjectured from a name.
    ///
    /// This is a different axis from `tautologicalTemplates`, and confusing the two is a mistake I
    /// made and had to be shown. Refutable means *a wrong implementation can fail it*. Role-entailed
    /// means *a right implementation cannot*. A law wants both: it must be able to catch a bug, and
    /// it must not cry wolf on correct code.
    ///
    /// - A **comparator** owes a strict weak ordering, a **partition** owes a tiling, a **predicate**
    ///   owes totality — *by virtue of being one*. Any implementation that fails these is broken.
    /// - **`monotonicity`** and **`idempotence`** are **conjectures**, inferred from a name. They can
    ///   be false of perfectly correct code: `func get(_ key: String) -> Int { key.count }` is not
    ///   monotone in its argument — `"aa" < "b"` while `count("aa") > count("b")` — and no bug is
    ///   involved. Proposing that law to a reader spends their trust and returns nothing.
    ///
    /// The distinction earns its keep in exactly one place: deciding which laws may be shown *below
    /// the confidence cut*. A weak law that is owed beats a tautology. A weak law that is **guessed**
    /// does not — that is what the cut is for, and **a tool that proposes a false law is worse than
    /// one that proposes nothing.**
    public static let roleEntailedTemplates: Set<String> = [
        "predicate",     // totality: it must answer for every input its type admits
        "comparator",    // a strict weak ordering, or `sorted` may trap
        "partition",     // the parts tile the whole, exactly
        "state-machine"  // `up ∘ down == id` — gated so the forward move NAMES what it did
    ]

    /// Whether a correct implementation is *guaranteed* to satisfy this suggestion's law.
    public static func isRoleEntailed(_ suggestion: Suggestion) -> Bool {
        roleEntailedTemplates.contains(suggestion.templateName)
    }

    /// A law worth showing a reader **below the confidence cut**: it can catch a bug, and it cannot
    /// cry wolf on correct code.
    ///
    /// Both halves are load-bearing, and I shipped a version with only the first. `monotonicity` on
    /// `func get(_ key: String) -> Int { key.count }` is refutable — a wrong implementation could
    /// fail it — and it is **also false of the correct one** (`"aa" < "b"`, yet
    /// `count("aa") > count("b")`). Surfacing it because "at least it isn't a tautology" hands the
    /// reader a test that goes red for no reason. The tautology was useless; this is worse than
    /// useless.
    public static func isWorthSurfacingBelowCut(_ suggestion: Suggestion) -> Bool {
        isRefutable(suggestion) && isRoleEntailed(suggestion)
    }

    /// The outcome of applying a filter under the invariant.
    public struct Outcome: Sendable, Equatable {
        /// What the caller should actually surface: the filter's own result, plus any rescue.
        public let kept: [Suggestion]

        /// Refutable laws the filter would have discarded, and which the invariant kept alive.
        /// **Empty on every healthy run.** Non-empty means an upstream stage has a blind spot —
        /// the caller must warn, and name these.
        public let rescued: [Suggestion]

        public init(kept: [Suggestion], rescued: [Suggestion]) {
            self.kept = kept
            self.rescued = rescued
        }
    }

    /// Apply a filter's verdict without letting it erase the last refutable law.
    ///
    /// - Parameters:
    ///   - filtered: what the filter decided to keep.
    ///   - candidates: everything the filter was choosing *from*. Callers must exclude anything
    ///     that is dead for reasons unrelated to this filter — a verify-*disproven* suggestion
    ///     (`Tier.suppressed`) is not a law we failed to show, it is a law we **checked and
    ///     refuted**, and resurrecting it would be the opposite of honest.
    ///
    /// - Returns: `filtered` unchanged whenever it already holds a refutable law, or holds none
    ///   because there were none to hold. Otherwise `filtered` plus the refutable laws the filter
    ///   dropped.
    public static func preservingLastRefutable(
        filtered: [Suggestion],
        from candidates: [Suggestion]
    ) -> Outcome {
        // The filter kept something that can fail: it did its job, narrow away.
        guard !filtered.contains(where: isRefutable) else {
            return Outcome(kept: filtered, rescued: [])
        }

        // Nothing refutable survived. Was there anything **worth surfacing** to begin with?
        //
        // Note the asymmetry, which is deliberate: the *trigger* is `isRefutable` (would the reader
        // be handed nothing but tautologies?) but the *rescue* is `isWorthSurfacingBelowCut` (may
        // this particular law be shown below the cut?). A run whose only non-tautology is a
        // conjecture — `monotonicity` guessed from a name — triggers the check and rescues nothing,
        // and that is right. The reader keeps their tautologies and their trust; a law that a
        // *correct* implementation fails would cost them both.
        let keptIdentities = Set(filtered.map(\.identity))
        let dropped = candidates.filter { candidate in
            isWorthSurfacingBelowCut(candidate) && !keptIdentities.contains(candidate.identity)
        }
        guard !dropped.isEmpty else {
            return Outcome(kept: filtered, rescued: [])
        }

        // The filter found laws that could fail and was about to show the reader none of them.
        return Outcome(kept: filtered + dropped, rescued: dropped)
    }
}
