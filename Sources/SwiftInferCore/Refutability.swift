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

        // Nothing refutable survived. Was there anything refutable to begin with? If not, this is
        // an honest empty — the code under analysis offered no law, and saying so is correct.
        let keptIdentities = Set(filtered.map(\.identity))
        let dropped = candidates.filter { candidate in
            isRefutable(candidate) && !keptIdentities.contains(candidate.identity)
        }
        guard !dropped.isEmpty else {
            return Outcome(kept: filtered, rescued: [])
        }

        // The filter found laws that could fail and was about to show the reader none of them.
        return Outcome(kept: filtered + dropped, rescued: dropped)
    }
}
