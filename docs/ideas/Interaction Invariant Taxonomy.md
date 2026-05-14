# Interaction Invariant Taxonomy

**Status:** Direction note — captures a v2.x extension surface; not committed to any milestone.
**Target:** SwiftInferProperties engine (this repo); orthogonal to the SwiftPropertyLaws kit roadmap.
**Date:** 2026-05-13
**Companion to:** `docs/ideas/Stateful Testing Kit Proposal.md` (kit-side, command-sequence harness); this note proposes engine-side discovery of UI-style invariants over reducer / SwiftUI-state carriers.

## 1. Summary

A shape-based taxonomy of UI-relevant invariants — eight families grouped by what the law looks like and how you'd check it. Two families (idempotence, conservation-as-round-trip) are what this project already mines for pure-function carriers. Five are new shape families that would require new templates + resolvers. One (accessibility) isn't PBT at all and belongs in a linter.

Recorded as a v2.x direction in case the project eventually extends beyond pure-function carriers into reducer / SwiftUI state-machine carriers.

## 2. Origin

Drafted from a 2026-05-13 conversation about two ChatGPT notes on SwiftUI + property-based testing. The notes group invariants by *domain* (cart, nav, auth) which obscures the design space. Re-grouping by *shape* (what the law mathematically is) makes the cost/tool picture clear and shows which families this project's existing machinery already covers.

## 3. The eight shape families

For each family: definition, check strategy, example, and whether the current pipeline can already discover/verify it.

### 3.1 Cardinality
"At most/exactly N of X."
- Example: only one modal sheet presented. Exactly one auth state visible. No duplicate IDs in a list.
- Check: count predicate over state. Local; cheap.
- Current pipeline: **no** — no template emits count predicates.

### 3.2 Referential integrity
"Every reference points at extant data."
- Example: selected message ID exists in current message list. Route ID maps to a real entity. Tab index in range.
- Check: existence predicate spanning two state fields. Local; cheap. Mathematically a foreign-key constraint.
- Current pipeline: **no** — no template emits cross-field membership checks.

### 3.3 Biconditional (iff)
"X visible iff Y true."
- Example: checkout button visible iff cart non-empty. Spinner visible iff request in flight. Save enabled iff form valid.
- Check: derived-predicate equivalence between two state subsets that usually live in different layers (view-state vs model-state). Drift between the two is exactly where SwiftUI async-race bugs show up.
- Current pipeline: **no** — closest analog is the v1.42 round-trip pair list but the shape differs.

### 3.4 Conservation
"Derived quantity equals recomputation from components."
- Example: cart total = sum of line items. Filter-then-count = count-then-filter (when commutative). Undo restores prior state byte-for-byte.
- Check: equality between two computations.
- Current pipeline: **yes** — what round-trip (v1.42) and commutativity (v1.45) capture for pure carriers. The shape extends naturally to reducer carriers given an indexing path.

### 3.5 Idempotence / stability
"f(f(s)) == f(s)."
- Example: pull-to-refresh idempotent. Save idempotent. Submit-once enforcement.
- Check: apply twice; compare.
- Current pipeline: **yes** — idempotence non-lifted (v1.44) and idempotence-lifted (v1.48) cover this for pure carriers. Lifting to reducer carriers is mostly an indexing problem.

### 3.6 Reachability
"From state P, no transition sequence reaches state Q." Or its dual: "Q is always reachable from P."
- Example: authenticated content unreachable while unauth. Deleted-and-logged-out user can't surface in a list. Home screen always reachable.
- Check: bounded model checking or random sequence exploration. Where stateful PBT lives (Hypothesis bundles, `quickcheck-state-machine`, Erlang QuickCheck).
- Current pipeline: **no** — would need a sequence generator and a transition-relation template family. Overlaps heavily with the kit-side Stateful Testing proposal.

### 3.7 Temporal
"Eventually X" or "never X within T."
- Example: spinner disappears within timeout. Stale async write from a cancelled task never reaches the UI. Debounced submit fires exactly once per quiet period.
- Check: async-aware harness with a virtual clock. Classical PBT shrinking breaks here.
- Current pipeline: **no** — and likely out of scope. Needs virtual-clock support in swift-testing that doesn't exist yet, plus a different shrinking model.

### 3.8 Accessibility
"All buttons have labels. Focus always visible. Dynamic type never truncates critical content. Reduced motion respected."
- Check: mostly static AST or static-state predicates. **Not PBT at all.**
- Current pipeline: out of scope; belongs in a linter (SwiftLint custom rules, or the PRD §20 Semantic Linting bridge if that ever lands).

## 4. Mapping to project work

Triaged by extension cost:

| Family | Cost | What's needed |
|---|---|---|
| 3.4 Conservation (reducer) | low | Indexer extension: discover reducer functions `(State, Action) -> State`, route through existing round-trip template |
| 3.5 Idempotence (reducer) | low | Same indexer extension, route through existing idempotence template |
| 3.1 Cardinality | medium | New template + new emitter (count predicate over `State`) |
| 3.2 Referential integrity | medium | New template + new emitter (membership across two `State` fields) |
| 3.3 Biconditional | medium-high | New template; tricky because the law spans view-derived and model state |
| 3.6 Reachability | high | New harness (sequence generator, state-machine bundle, action-precondition system) — overlaps with kit-side Stateful Testing |
| 3.7 Temporal | very high | Virtual clock + async-aware shrinking — research-level |
| 3.8 Accessibility | n/a | Belongs in a linter, not here |

The cheap path (3.4 + 3.5 on reducer carriers) is the natural v2.x first step: same templates as today, new carrier discovery. The medium-cost templates (3.1–3.3) are the meaningful new surface. The high-cost families should wait for the kit-side Stateful Testing kit to land first — without it, family 3.6 would force this project to duplicate that infrastructure.

## 5. Formal backing

The academic version of this taxonomy is **Linear Temporal Logic (LTL)** and **Computation Tree Logic (CTL)** from the formal-methods literature (Pnueli 1977; Clarke / Emerson 1981). Core operators: **G** (globally), **F** (finally), **X** (next), **U** (until). CTL adds path quantifiers **A** (all paths) / **E** (exists path).

The pragmatic-vs-formal mapping:

- Families 3.1, 3.2, 3.3, 3.4, 3.5 are **safety properties** — "bad never happens" — written `G(ϕ)` in LTL. Finite counterexamples; cheap to check.
- Family 3.6 reachability is mixed: "Q unreachable" is safety; "Q always reachable" is `AG EF Q` in CTL.
- Family 3.7 temporal is **liveness** — "good eventually happens" — written `F(ϕ)` or `G(req → F(resp))`. Counterexamples are infinite traces; expensive.

Industrial tools that use this vocabulary: **TLA+** (Lamport; most accessible entry point), **SPIN**, **NuSMV**, **UPPAAL** (timed). The point of citing them isn't to use them — it's to point at the existing formal language for invariants when we eventually need precise specifications.

## 6. Open questions

1. **Reducer discovery surface.** What does the indexer scan to find reducers? Plain functions with a `(State, Action) -> State` shape? TCA `Reducer` conformances? `@Reducer` macro outputs? `@Observable` types with mutating methods? Each has a different precision/recall profile. Worth one cycle of empirical surface measurement before committing to a discovery strategy.

2. **Action enum generation.** For families 3.1–3.5 a generator over the `Action` enum is enough. For 3.6 reachability the generator must produce *valid* action sequences (no select-after-delete-of-selected), which is the stateful-testing problem and shouldn't be solved twice.

3. **Where the new templates live.** The current 10-template registry (numeric / serialization / collections / algebraic / concurrency packs per v1.32) has no "ui-state" or "interaction-invariant" pack. v2.x would add a sixth pack.

4. **Verification feasibility on reducer carriers.** A v1.42-style verify run on a reducer needs to instantiate the reducer + an initial state + apply a generated action. The v1.49.A stub-preamble channel can probably synthesize this, but the workdir setup is more involved than the current pure-function workdir — likely a new `VerifierWorkdir` variant rather than an extension.

5. **Relationship to TCA.** TCA is the only mainstream SwiftUI architecture where reducer-as-state-machine maps cleanly onto our existing templates. `TestStore` already scripts action sequences. Open: do we target TCA specifically (high precision, low recall) or stay architecture-agnostic on the `(State, Action) -> State` shape (lower precision, higher recall)? Same tension as the early calibration cycles' carrier-binding work.

## 7. Status

Captured for reference; no implementation work proposed. Likely v2.x — after Phase 2 measurement work (currently 42/103 = 40.8% measured at v1.63) reaches a stable plateau and the kit-side Stateful Testing proposal either lands or is firmly deferred.
