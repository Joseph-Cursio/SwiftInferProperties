/// Consults the purity verdict this analyzer already computed for a callee.
///
/// `SoundPurity.verdict(for:)` decides each declaration from its own syntax plus the
/// project's construction table (`PackagePurity`) — it never consults another FUNCTION's
/// verdict, so `DrainedProcess.standardOutputViaEnv` — whose one-line body calls a
/// `standardOutput` that spawns a subprocess and drains two pipes on a global queue — reads
/// as `.pure`. The callee's verdict is computed and then never consulted. This consults it.
///
/// **The table and this join compose, and that is how the motivating case is refuted.**
/// SwiftLintRuleStudio's `generateRecommendations` constructs nothing itself; it calls four
/// `inout` helpers that each construct a `HealthRecommendation` minting a `UUID`. The table
/// refutes the helpers, and this join carries that one hop to the caller — neither alone does.
///
/// **Measured before it was built**: `docs/measurements/purity-refuting-fixpoint-census.md`
/// — 18 rows retracted at one hop over 2,396 `.pure` subjects, 29 at fixpoint over six
/// hops. One hop is 62% of the effect and is what this ships; the loop's multiplier
/// (1.6×) is weaker than the promoting direction's, so it is a later phase. Open item 43.
///
/// ## Refuting, not promoting — the direction is the whole design
///
/// The mirror question was measured and **declined twice**
/// (`docs/measurements/purity-blocking-callee-census.md`): a promotion's freed rows land
/// on `.pureButPartial`, which nothing reads. A retraction lands on `.pure`, and
/// `isInferredPure` is `purityVerdict == .pure` — the field the one live consumer reads.
///
/// It is also the only **sound** direction. An inferred `.pure` would be a claim about
/// every callee a body reaches, including the ones this toolchain cannot resolve; an
/// inferred refutation is a claim about *one* callee it did resolve.
///
/// ## Only evidence propagates, established from the summary alone
///
/// `PurityVerdict` carries no witness, and a `FunctionSummary` carries only the verdict. SEI's
/// first witness IS public now (`PurityInferrer.refutation(for:)`, surfaced here as
/// `SoundPurity.inferrerRefutation(for:)`), but it is not on the summary this join reads — so
/// the witness is still established indirectly, and soundly: `propagatedTry` requires a
/// `throws` clause by definition, and `noBody` is structurally unreachable here because the
/// scanner skips protocol requirements. **A `.refuted` declaration that does not throw
/// therefore cannot be an ignorance-only refutation.**
///
/// **The `!isThrows` proxy is kept deliberately, and it is now visibly narrow.** Construction
/// facts give a THROWING function a witness the proxy cannot see: on this repo two rows
/// (`dispatchSideOrchestrator`, `runInteractiveBranch`) changed their first witness from
/// `propagatedTry` to a construction, and neither seeds this join. Carrying SEI's witness on
/// the summary would let them seed — which retracts more rows, a verdict-moving change of its
/// own, so it is its own A/B and not part of the wiring that exposed it
/// (`docs/measurements/construction-facts-wiring.md`).
///
/// Spreading ignorance would retract advice on the grounds that something *might* be
/// impure, which is the opposite of this repo's conservative posture. The cost is
/// one-sided: a throwing callee that also carries a marker is a witness this rule cannot
/// see, so the join under-retracts. That is the safe direction to be wrong in.
///
/// **No marker set is replicated here.** A second copy of SEI's refuters is exactly the
/// drift relocating `PurityInferrer` into SEI ended.
public enum PackagePurityJoin {

    /// Names whose every declaration is settled impure **with a witness**.
    ///
    /// *Every* declaration, because a name is all this join can resolve: if one
    /// `classify` is refuted and another is pure, a call to `classify` might reach
    /// either. Requiring unanimity is what makes the name safe to act on, and omitting
    /// that check was one cause of the 61% false-positive rate the fixpoint census
    /// measured on its first run.
    ///
    /// **`public` because the veto consumes it** (`TemplateRegistry.applyImpureSubjectVeto`,
    /// in another module). Sharing the predicate rather than restating it is what makes the
    /// veto's scope and this join's scope the *same* rule — a second copy would drift, and
    /// drift between two statements of one rule is what relocating `PurityInferrer` into SEI
    /// ended.
    public static func refutingNames(in summaries: [FunctionSummary]) -> Set<String> {
        var byName: [String: [FunctionSummary]] = [:]
        for summary in summaries {
            byName[summary.name, default: []].append(summary)
        }
        return Set(
            byName
                .filter { _, declarations in
                    declarations.allSatisfy { $0.purityVerdict == .refuted && !$0.isThrows }
                }
                .keys
        )
    }

    /// Retract every `.pure` verdict whose body calls a settled-impure package function.
    ///
    /// The `.pure` rows are the only population a retraction can cost, since
    /// `isInferredPure` is `purityVerdict == .pure`; every other row is already withheld.
    public static func applied(to summaries: [FunctionSummary]) -> [FunctionSummary] {
        let refuting = refutingNames(in: summaries)
        guard !refuting.isEmpty else { return summaries }

        return summaries.map { summary in
            guard summary.purityVerdict == .pure,
                  summary.calledFreeFunctionNames.contains(where: refuting.contains) else {
                return summary
            }
            return summary.withPurityRetracted()
        }
    }
}
