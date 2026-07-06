# Interaction Invariant Taxonomy

**Status:** **Substantially delivered.** Drafted 2026-05-13 as a v2.x direction note; families 3.1–3.5 (idempotence, conservation, cardinality, referential integrity, biconditional) have since shipped end-to-end — discovered, surfaced, AND measured-verified — over reducer (TCA / Elm / ReSwift / Mobius / Workflow) and `@Observable` MVVM carriers. See `docs/measured-verify-architecture.md` (consolidation) + the per-cycle findings docs. **The live content is now §3.6 (reachability), §3.7 (temporal), and §5 (the LTL/CTL framing);** the rest is retained as the design record it turned out to predict accurately.
**Target:** SwiftInferProperties engine (this repo); orthogonal to the SwiftPropertyLaws kit roadmap.
**Date:** 2026-05-13 (status refreshed 2026-07-06)
**Companion to:** `docs/ideas/Stateful Testing Kit Proposal.md` (kit-side, command-sequence harness); this note proposes engine-side discovery of UI-style invariants over reducer / SwiftUI-state carriers.

## 1. Summary

A shape-based taxonomy of UI-relevant invariants — eight families grouped by what the law looks like and how you'd check it. Two families (idempotence, conservation-as-round-trip) are what this project already mined for pure-function carriers when this was drafted. Five were then-new shape families needing new templates + resolvers. One (accessibility) isn't PBT at all and belongs in a linter.

**What happened since:** the five state-invariant families (3.1–3.5) were built out across the v2.x interaction-invariant work, exactly along the cheap-path-first sequencing this note recommended. The mapping in §3 records both the original v1.63 verdict and where each family stands today.

## 2. Origin

Drafted from a 2026-05-13 conversation about two ChatGPT notes on SwiftUI + property-based testing. The notes group invariants by *domain* (cart, nav, auth) which obscures the design space. Re-grouping by *shape* (what the law mathematically is) makes the cost/tool picture clear and shows which families this project's existing machinery already covers.

## 3. The eight shape families

For each family: definition, check strategy, example, the original v1.63 verdict, and where it stands today.

### 3.1 Cardinality
"At most/exactly N of X."
- Example: only one modal sheet presented. Exactly one auth state visible. No duplicate IDs in a list.
- Check: count predicate over state. Local; cheap.
- v1.63 verdict: **no** — no template emitted count predicates.
- **Today: SHIPPED + verified.** Cardinality template + resolver (`[<route> != nil, …].filter { $0 }.count <= 1`), pinned `.possible` by the Finding-G gate but promotable to `.verified` by a *full-coverage* measured bothPass (cycle 135/136).

### 3.2 Referential integrity
"Every reference points at extant data."
- Example: selected message ID exists in current message list. Route ID maps to a real entity. Tab index in range.
- Check: existence predicate spanning two state fields. Local; cheap. Mathematically a foreign-key constraint.
- v1.63 verdict: **no** — no template emitted cross-field membership checks.
- **Today: SHIPPED + verified.** Value-membership (`selected ⊆ items`) and the keyed `Identifiable` form (`selected == nil || coll.contains { $0.id == selected! }`), with a pre-build Identifiable gate that honestly skips non-Identifiable elements (cycle 138/139).

### 3.3 Biconditional (iff)
"X visible iff Y true."
- Example: checkout button visible iff cart non-empty. Spinner visible iff request in flight. Save enabled iff form valid.
- Check: derived-predicate equivalence between two state subsets that usually live in different layers (view-state vs model-state). Drift between the two is exactly where SwiftUI async-race bugs show up.
- v1.63 verdict: **no** — closest analog was the v1.42 round-trip pair list but the shape differs.
- **Today: SHIPPED + verified.** `flag == (optional != nil)` over a Bool/Optional pair sharing a name stem; rides the same full-coverage gate-overrule as cardinality (cycle 137).

### 3.4 Conservation
"Derived quantity equals recomputation from components."
- Example: cart total = sum of line items. Filter-then-count = count-then-filter (when commutative). Undo restores prior state byte-for-byte.
- Check: equality between two computations.
- v1.63 verdict: **yes** — for pure carriers (round-trip v1.42, commutativity v1.45).
- **Today: SHIPPED + verified on reducers.** `count == collection.count`; un-gated, so a measured bothPass promotes straight to `.verified` (cycle 134/140).

### 3.5 Idempotence / stability
"f(f(s)) == f(s)."
- Example: pull-to-refresh idempotent. Save idempotent. Submit-once enforcement.
- Check: apply twice; compare.
- v1.63 verdict: **yes** — for pure carriers (idempotence non-lifted v1.44, lifted v1.48).
- **Today: SHIPPED + verified on reducers AND MVVM.** The first interaction family promoted past default-`.possible` to `.likely`; a measured bothPass promotes it to `.verified` (cycle 115–118). Covers witness-vocabulary methods + x-curried single-arg actions.

### 3.6 Reachability
"From state P, no transition sequence reaches state Q." Or its dual: "Q is always reachable from P."
- Example: authenticated content unreachable while unauth. Deleted-and-logged-out user can't surface in a list. Home screen always reachable.
- Check: bounded model checking or random sequence exploration. Where stateful PBT lives (Hypothesis bundles, `quickcheck-state-machine`, Erlang QuickCheck).
- v1.63 verdict: **no** — would need a sequence generator and a transition-relation template family. Overlaps heavily with the kit-side Stateful Testing proposal.
- **Today: still the live frontier — PARTIAL at best.** The verifier drives the discovered action alphabet and re-checks a *state predicate* after each step (the safety half, `G(ϕ)`), but only as a **single deterministic pass** — NOT multi-step random sequences + shrinking, NOT precondition-guarded *valid*-sequence generation (the "no select-after-delete-of-selected" problem, §6 Q2), and NOT reachability queries proper (`AG EF Q`). True reachability remains unbuilt and should still wait on the kit-side Stateful Testing kit rather than duplicate a state-machine harness here.

### 3.7 Temporal
"Eventually X" or "never X within T."
- Example: spinner disappears within timeout. Stale async write from a cancelled task never reaches the UI. Debounced submit fires exactly once per quiet period.
- Check: async-aware harness with a virtual clock. Classical PBT shrinking breaks here.
- v1.63 verdict: **no** — and likely out of scope. Needs virtual-clock support in swift-testing that doesn't exist yet, plus a different shrinking model.
- **Today: still unbuilt, still out of scope** for the same reasons. This is the liveness frontier (§5).

### 3.8 Accessibility
"All buttons have labels. Focus always visible. Dynamic type never truncates critical content. Reduced motion respected."
- Check: mostly static AST or static-state predicates. **Not PBT at all.**
- v1.63 verdict: out of scope; belongs in a linter (SwiftLint custom rules, or the PRD §20 Semantic Linting bridge if that ever lands).
- **Today: unchanged** — correctly still out of scope for a PBT engine.

## 4. Mapping to project work

Triaged by extension cost. The "delivered" column records what actually landed — the sequencing this note predicted (cheap path first, then medium templates) is exactly the order the work shipped.

| Family | Cost | What was needed | Delivered |
|---|---|---|---|
| 3.4 Conservation (reducer) | low | Indexer extension → existing round-trip/equality template | ✅ cycle 134/140 |
| 3.5 Idempotence (reducer) | low | Same indexer extension → existing idempotence template | ✅ cycle 115–118 (+MVVM) |
| 3.1 Cardinality | medium | New template + emitter (count predicate over `State`) | ✅ cycle 136 |
| 3.2 Referential integrity | medium | New template + emitter (membership across two `State` fields) | ✅ cycle 138/139 |
| 3.3 Biconditional | medium-high | New template spanning view-derived and model state | ✅ cycle 137 |
| 3.6 Reachability | high | New harness (sequence generator, state-machine bundle, action-precondition system) — overlaps with kit-side Stateful Testing | ⚠️ partial (single-pass invariant check only) |
| 3.7 Temporal | very high | Virtual clock + async-aware shrinking — research-level | ❌ not built |
| 3.8 Accessibility | n/a | Belongs in a linter, not here | ❌ out of scope |

The cheap path (3.4 + 3.5 on reducer carriers) was the v2.x first step, and the medium-cost templates (3.1–3.3) followed as the meaningful new surface — all now shipped. The high-cost families should still wait for the kit-side Stateful Testing kit to land first — without it, family 3.6 would force this project to duplicate that infrastructure.

## 5. Formal backing

The academic version of this taxonomy is **Linear Temporal Logic (LTL)** and **Computation Tree Logic (CTL)** from the formal-methods literature (Pnueli 1977; Clarke / Emerson 1981). Core operators: **G** (globally), **F** (finally), **X** (next), **U** (until). CTL adds path quantifiers **A** (all paths) / **E** (exists path).

The pragmatic-vs-formal mapping — and the reason it still holds after the build-out: **everything shipped is a safety property; the unbuilt frontier is liveness.**

- Families 3.1, 3.2, 3.3, 3.4, 3.5 are **safety properties** — "bad never happens" — written `G(ϕ)` in LTL. Finite counterexamples; cheap to check. *(All now shipped — this is exactly the class the engine's per-step invariant checker verifies.)*
- Family 3.6 reachability is mixed: "Q unreachable" is safety; "Q always reachable" is `AG EF Q` in CTL. *(Only the safety half is even partially reachable today.)*
- Family 3.7 temporal is **liveness** — "good eventually happens" — written `F(ϕ)` or `G(req → F(resp))`. Counterexamples are infinite traces; expensive. *(Unbuilt.)*

Industrial tools that use this vocabulary: **TLA+** (Lamport; most accessible entry point), **SPIN**, **NuSMV**, **UPPAAL** (timed). The point of citing them isn't to use them — it's to point at the existing formal language for invariants when we eventually need precise specifications for the reachability/temporal frontier.

## 6. Open questions — RESOLVED by the shipped work

The five questions this note raised were all answered by the v2.x interaction-invariant build. Recorded here as the design record.

1. **Reducer discovery surface.** ✅ Answered empirically: `ReducerDiscoverer` recognizes five framework signatures (TCA `(State, Action)` closures + `@Reducer`, Elm free functions, ReSwift, Mobius, Workflow), and `ViewModelDiscoverer` handles `@Observable` / `ObservableObject` MVVM. Precision/recall was measured over the calibration cycles.
2. **Action enum generation.** ✅ For 3.1–3.5 a generator over the constructible-action subset (payload-free + raw cases) suffices — the relaxed partial-exploration decision (cycle 124). For 3.6 the "valid action sequence" requirement is exactly the stateful-testing problem this note said shouldn't be solved twice; still deferred.
3. **Where the new templates live.** ✅ `InteractionInvariantFamily` (the five families) is the interaction-invariant pack, separate from the algebraic templates.
4. **Verification feasibility on reducer carriers.** ✅ As predicted, this became new `VerifierWorkdir` variants (`.interaction` / `.interactionTCA` / `.interactionMobius`) rather than an extension of the pure-function workdir.
5. **Relationship to TCA.** ✅ Both — architecture-agnostic on the `(State, Action) -> State` shape AND a TCA-specific `.tca` carrier (Phase A/B, cycles 122/125). The precision/recall tension resolved by shipping the agnostic discovery with the TCA carrier as the high-precision verify path.

## 7. Status

**Families 3.1–3.5 delivered** across the v2.x interaction-invariant work (see `docs/measured-verify-architecture.md`). The v1.63-era measurement figure that gated this note (42/103 = 40.8%) is superseded — the v1 algebraic corpus is now 53/53 = 100% (cycle 151), and the interaction families have their own measured-verify path. **Remaining live surface: §3.6 reachability (proper valid-sequence generation + reachability queries) and §3.7 temporal** — both still gated on the kit-side Stateful Testing proposal landing or being firmly deferred.
