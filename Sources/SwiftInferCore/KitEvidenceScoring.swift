import Foundation

/// **Kit-as-signal post-pass** — folds PropertyLawKit's executed verdicts into suggestion
/// scores, so the toolchain's only *measured* evidence participates in inference instead of
/// stopping at the end of the pipeline.
///
/// Deliberately shaped like `VerifyEvidenceScoring`: a pure function over suggestions plus
/// a loaded evidence log, appending a signal via `appendingScoreSignal`. The difference is
/// what it keys on — verify evidence is keyed by *suggestion identity* (this exact law was
/// executed), kit evidence is keyed by *carrier* (this type's `==` was executed), and its
/// consequence is therefore cross-cutting: one refuted equality undermines every
/// `==`-shaped law proposed about that type.
/// ## The licensing assumption, and why only one direction moves the score
///
/// `==` correctness is the **Equatable laws' job**. A mistake there is caught by
/// `checkEquatablePropertyLaws`, not by anything here — so inference is entitled to *assume*
/// the carrier's `==` is sound and build on it. That assumption is what makes every
/// `==`-shaped law statable in the first place.
///
/// Which fixes the asymmetry this type would otherwise get wrong:
///
/// - **No kit evidence → unchanged.** The assumption stands. This is the status quo and the
///   overwhelmingly common case.
/// - **Kit passed → score-NEUTRAL provenance.** A passing Equatable suite does not make
///   `f(f(x)) == f(x)` more likely to be true; it makes *testing* it meaningful. The
///   assumption was already granted, so confirming it earns a line, not points — the same
///   posture `StdlibAnchor` takes, and for the same reason.
/// - **Kit refuted → demote.** The exception. The assumption inference was relying on has
///   been measured false, and every `==`-shaped law about that carrier inherits the problem.
///
/// Only the third case changes a grade, because only the third case changes what was
/// assumed.
public enum KitEvidenceScoring {

    /// Heavy enough to drop a `Strong` suggestion below the default cut, deliberately short
    /// of `Signal.vetoWeight`.
    ///
    /// A veto would erase the suggestion, and erasing is the wrong response to *"your
    /// equality is broken"* — the reader needs the diagnosis and the prerequisite, not an
    /// empty run. At `-45` an 85-point `Strong` idempotence claim lands at 40, still
    /// reachable, carrying the explanation. `--include-possible` shows the rest.
    public static let refutedOracleWeight = -45

    /// Suggestions re-graded against what the kit actually measured.
    ///
    /// Pass-through (identical value, so callers may rely on `==`) when there is no
    /// evidence for the carrier, when the carrier's equality was not refuted, or when the
    /// suggestion is `.advisory` — mirroring `VerifyEvidenceScoring`'s exemption, since an
    /// advisory row is not making a checkable claim to begin with.
    public static func applied(
        to suggestions: [Suggestion],
        evidence: KitEvidenceLog
    ) -> [Suggestion] {
        guard !evidence.outcomes.isEmpty else { return suggestions }
        return suggestions.map { suggestion in
            guard suggestion.score.tier != .advisory,
                  let carrier = carrierName(of: suggestion) else {
                return suggestion
            }
            if let refuted = evidence.refutedEqualityOracle(for: carrier) {
                return suggestion.appendingScoreSignal(
                    Signal(
                        kind: .kitEqualityOracleRefuted,
                        weight: refutedOracleWeight,
                        detail: detail(for: refuted, carrier: carrier)
                    ),
                    explainabilityArm: .whyMightBeWrong
                )
            }
            // Confirmed sound: provenance only. See the licensing note on the type — the
            // assumption was already granted, so confirming it earns a line, not points.
            guard evidence.confirmedEqualityOracle(for: carrier) else { return suggestion }
            return suggestion.withExplainability(
                ExplainabilityBlock(
                    whySuggested: suggestion.explainability.whySuggested + [
                        "PropertyLawKit executed `\(carrier)`'s equality laws and they held, so "
                            + "the `==` this law is stated with is a verified oracle rather than "
                            + "an assumed one. Score is unchanged — a sound `==` does not make "
                            + "this law truer, it makes testing it meaningful."
                    ],
                    whyMightBeWrong: suggestion.explainability.whyMightBeWrong
                )
            )
        }
    }

    /// One line per carrier whose equality the kit refuted, for the caller to emit as a
    /// run-level diagnostic.
    ///
    /// **Necessary because the demotion can hide its own explanation.** A `-45` on a 70-point
    /// pick lands at 25 — `Possible`, which the default cut hides — so a reader who did not
    /// pass `--include-possible` would see `0 suggestions.` and no reason. That is the
    /// silent-confident-zero failure `TargetDirectory`'s doc names as the worst answer a tool
    /// can give, reintroduced by a feature meant to inform.
    ///
    /// So the demotion goes on the suggestion and the diagnosis goes on stderr, where the
    /// visibility cut cannot reach it.
    public static func diagnostics(
        for suggestions: [Suggestion],
        evidence: KitEvidenceLog
    ) -> [String] {
        guard !evidence.outcomes.isEmpty else { return [] }
        var affected: [String: (law: String, count: Int)] = [:]
        for suggestion in suggestions {
            guard let carrier = carrierName(of: suggestion),
                  let refuted = evidence.refutedEqualityOracle(for: carrier) else { continue }
            affected[carrier, default: (refuted.law, 0)].count += 1
        }
        return affected.sorted { $0.key < $1.key }.map { carrier, info in
            "PropertyLawKit refuted `\(carrier)`'s equality (`\(info.law)`, Strict). "
                + "\(info.count) suggestion(s) about it are demoted by "
                + "\(abs(refutedOracleWeight)) points — they are stated with `==`, so they "
                + "cannot be checked until that is fixed. Fix the equality first; these "
                + "become meaningful again afterwards."
        }
    }

    /// The carrier a suggestion is about, generics stripped so `Box<Int>` matches a kit run
    /// recorded against `Box`.
    static func carrierName(of suggestion: Suggestion) -> String? {
        let raw = suggestion.carrierTypeName ?? suggestion.carrier
        guard let raw, !raw.isEmpty else { return nil }
        guard let angle = raw.firstIndex(of: "<") else { return raw }
        return String(raw[raw.startIndex..<angle])
    }

    /// The explanation, written to name the prerequisite rather than to scold.
    static func detail(for refuted: KitLawOutcome, carrier: String) -> String {
        let witness = refuted.counterexample.map { " Counterexample: \($0)." } ?? ""
        return "PROPERTYLAWKIT REFUTED `\(carrier)`'s EQUALITY — `\(refuted.law)` failed at "
            + "Strict tier.\(witness) This law is stated with `==`, so it cannot be checked "
            + "until that is fixed: a green run would mean the comparison agreed with itself, "
            + "not that the property holds. The law may well be true — this is a "
            + "PREREQUISITE, not a refutation of the law. Note the Equatable laws can all "
            + "pass while this fails, because a projecting `==` is still a valid equivalence "
            + "relation; that is exactly the shape `\(refuted.law)` catches."
    }
}
