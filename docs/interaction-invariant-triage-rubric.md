# Interaction-Invariant Triage Rubric (v2.0)

Methodology document for the v2.0 calibration loop. Defines accept / acceptAsConformance / reject / skip criteria per InteractionInvariant family, what counts as evidence under single-runner triage, and how the rubric handles edge cases.

**Scope:** v1.100 / cycle 98 onward — the v2.0 analog of `cycle-6-triage-rubric.md`. Reusable across the three-cycle calibration loop (cycles 98 → 99 → 100) that gates tier promotion from default-`.possible` to `.likely`.

## What we're measuring

Each `InteractionInvariantSuggestion` is a *claim* swift-infer makes — "this reducer + State shape looks like it satisfies a `<family>` invariant." The triage decision answers: **does the invariant actually hold under every reachable action sequence?**

The four decisions persisted to `.swiftinfer/interaction-decisions.json` (v1.88 surface):

- **`accepted`** — yes, the invariant holds. The user would write a property test stub from this suggestion and ship it. Counts as +1 in the family's acceptance numerator.
- **`acceptedAsConformance`** — same as `accepted` *plus* the user is willing to commit to it as a `*Invariant` protocol conformance (v2.3.0 family), unlocking the v2.4.0 runtime harness + v2.5.0 macro-emitted CI tests. Counts as +1 in the family's acceptance numerator + signals strong adoption (used for M9 Bridge gating).
- **`rejected`** — no, the invariant doesn't hold. The reducer is correctly shaped to *look* like the family, but counterexample reachable sequences violate the predicate. A property test stub would fail. Counts as 0 in numerator, 1 in denominator.
- **`skipped`** — the rater can't determine the answer from public-API + commit-history evidence alone. UI-only — never persisted; suggestion re-surfaces in the next run. Excluded from both numerator and denominator (same role as `unknown` in v1).

**Per-family acceptance rate** = `(accepted + acceptedAsConformance) / (accepted + acceptedAsConformance + rejected)`.

The PRD §3.5 tier-promotion gate: a family with **≥ 70% acceptance rate across three consecutive calibration cycles** promotes from default-`.possible` to `.likely`. Three more cycles at ≥ 70% promotes to `.strong`, which unlocks M9 Bridge proposals + M10 drift warnings in production.

## Single-runner triage caveat

This rubric documents what *one* rater can determine from each reducer's source code + git log + (for TCA exemplars) the official Examples readme. It deliberately excludes:

- **Running the macro-emitted property check.** Once v1.100's `@InteractionInvariantTests` is wired against an accepted invariant, the runtime harness becomes the source of truth (and a `nowFails` outcome from `accept-check-interaction` retroactively flips an `accepted` → `accepted` + execution-disproven). This rubric covers the *first-pass* decision before that execution evidence exists.
- **TCA Effect side-effects on State.** swift-infer's verify path (M8) discards `Effect<Action>` per PRD §16 #1 — the rubric likewise focuses on the synchronous reducer's State→State function. If a real-world bug requires an Effect to fire then race against a follow-up action to violate the invariant, that's out of scope for first-pass triage.
- **Multi-rater consensus.** Single rater per cycle. A second rater might call differently on the ambiguous edges; cycle 100's findings doc should note any rater-disagreement spots.

When the evidence is genuinely ambiguous, the rubric mandates `skipped` — *not* a forced binary call.

## Per-family criteria

### Cardinality — `(flagA ? 1 : 0) + (flagB ? 1 : 0) + ... <= 1`

The "mutual exclusion of presentation slots" invariant. Detected when State has ≥ 2 Bool fields containing `Showing`/`Presenting` (case-sensitive), or Optional fields whose lowercased name matches `sheet`/`alert`/`fullscreencover`/`popover`, or `@Presents` / `@PresentationState`-annotated Optionals (post-v1.94).

**Accept** when:
- All paired fields are genuine UI presentation slots (not "is loading" or "has data" flags).
- The reducer has exactly one "show X" entry point per slot that nils-out / falsifies the others (the modal-mutual-exclusion idiom).
- The State has no overlapping-by-design state (e.g., a sheet that's allowed to be shown *over* an active full-screen cover).
- The user would commit to the modal-mutex contract going forward.

**AcceptAsConformance** when accept criteria hold *and*:
- The reducer is in a stable file (not actively being refactored).
- The State type is the root reducer's `State` (not a nested child where promotion of the invariant would force every parent to also know about cardinality).
- The team is willing to fail CI on future regression.

**Reject** when:
- The paired fields *are* allowed to be simultaneously true by design (e.g., `isShowingToast` + `isShowingSheet` — a toast over a sheet is legal).
- One field is a "in-flight" flag (e.g., `isPresentingSheet` + `isDismissingSheet`) where transitional both-true is valid.
- The reducer has a code path that sets multiple flags true intentionally (e.g., a "shown debug overlay" that stacks on top of any active modal).

**Skipped** when:
- The presentation-slot pairing is plausible but the file is too large to verify every code path sets-then-clears correctly.
- TCA's `@Presents var destination: Destination.State?` style with multiple optionals — the macro-generated bindings make the action-mutex contract non-trivial to audit from the State declaration alone.

### Referential Integrity — `state.<sel> == nil || state.<coll>.contains { $0.id == state.<sel> }`

The "selected ID is always either nil or present in the collection" invariant. Detected when State has both an Optional whose name starts with `selected*` (case-insensitive) and a collection (`[T]` literal or `IdentifiedArrayOf<T>` post-v1.95).

**Accept** when:
- The Optional name unambiguously refers to a row in the collection (`selectedMessageID`, `selectedItem`).
- The reducer has a clear "delete from collection" handler that nils-out the selection if it pointed at the deleted row.
- Element type is `Identifiable` (or has an `id` property convention).
- No code path leaves a stale selection pointing at a deleted row.

**AcceptAsConformance** when accept criteria hold *and*:
- The collection is the canonical source of truth (not a derived/cached view of another collection).
- The selection contract holds for all paired collections (if the State has both `messages: [Message]` and `drafts: [Draft]` paired with `selectedMessageID`, the contract must hold for both).
- The team is willing to fail CI on future regression.

**Reject** when:
- The selection legitimately *can* point at an item not currently in the collection (e.g., pagination: selected may be off-screen but still tracked).
- The "delete" handler intentionally leaves the selection stale for UX continuity.
- The Optional and collection are unrelated despite the naming coincidence (rare; skip is usually safer).

**Skipped** when:
- The collection is shared across multiple State branches via cross-cutting carriers and the delete-and-nil contract spans several files.
- The selection is updated only by Effects (deferred async — first-pass triage skips this per the caveat above).

### Biconditional — `state.<bool> == (state.<optional> != nil)`

The "loading flag iff result is present" invariant. Detected when State has both a Bool field containing `Loading`/`Showing`/`Presenting`/`Active`/`Fetching`/`Refreshing` (case-sensitive) and any Optional field. Post-v1.97 the Bool side also matches inferred-Bool initializers (`var isLoading = false`).

**Accept** when:
- The Bool/Optional pair represents a single in-flight request (Bool = "request active", Optional = "request result").
- The reducer sets both in lockstep: `.start → bool=true, opt=nil`; `.received → bool=false, opt=value`; `.fail → bool=false, opt=nil`.
- No code path leaves the Bool true while the Optional is non-nil (or vice versa) for a meaningful duration.

**AcceptAsConformance** when accept criteria hold *and*:
- The pair has a single canonical source of truth (not multiple actions racing to set it).
- The reducer has explicit `.cancel` handling that resets both halves cleanly.
- The team is willing to fail CI on future regression.

**Reject** when:
- The Bool tracks a *different* aspect than the Optional (e.g., `isShowingSearch` and `lastQueryResult: String?` — the search UI can be shown without a prior result).
- The Bool intentionally stays true while caching the previous result (`isRefreshing` + `cachedItems: [Item]?` — both true during refresh-with-stale-cache).
- The Optional is populated synchronously while the Bool tracks an async fetch.

**Skipped** when:
- The pair is plausibly biconditional but the reducer has many code paths and the rater can't verify every one maintains lockstep.
- The Bool/Optional are in different sub-states that the reducer composes (cross-reducer biconditional invariant — out of scope for v2.0).

### Conservation — `state.<aggregate> == state.<collection>.count`

The "aggregate stays in sync with collection size" invariant. Detected when State has a stored Int-named-aggregate field plus an array collection in the same State, with the predicate cleanly fitting the `aggregate == collection.count` shape.

**Accept** when:
- The aggregate is unambiguously a count of the collection (`itemCount` + `items: [Item]`).
- The reducer updates both in every mutation (`.add → itemCount += 1, items.append`; `.remove → itemCount -= 1, items.remove`).
- No external producer mutates the collection without touching the aggregate.

**AcceptAsConformance** when accept criteria hold *and*:
- The aggregate is materialized (stored) rather than computed for performance reasons that constrain the team's refactor freedom.
- The team is willing to fail CI on future regression.

**Reject** when:
- The aggregate is a derived quantity that *should* differ from `count` (e.g., `totalCount` = server-reported total, while `items: [Item]` is the loaded page — total > count by design).
- The aggregate is a different kind of count (e.g., `unreadCount` vs `messages: [Message]` — unread is a filter of count, not the count itself).
- The aggregate is incremented for events not associated with collection-add (e.g., `messageEventCount` increments on every server event, while `messages` only appends new-message events).

**Skipped** when:
- The aggregate-collection naming is suggestive but the reducer's update logic is too spread out to verify.

### Action Idempotence — for `a ∈ idempotentActions`: `reducer(reducer(s, a), a) == reducer(s, a)`

The "applying this action twice is the same as applying once" invariant. Detected by Action-case-name pattern matching: exact-set (`refresh`, `clear`, `dismiss`, `reset`, `task`, `delegate`, `binding` post-v1.96) and prefix-set (`setX*`, `showX*`, `hideX*`).

**Accept** when:
- The action is a "setter to a fixed value" (`.dismiss → showsModal = false`).
- The action is a TCA-convention action with idempotent semantics (`.task` subscribes idempotently; `.delegate` is a no-op for State; `.binding` is a key-path setter for the same payload).
- The reducer's handler is a pure assignment with no `+=` / `-=` / `.append` / `.toggle`.

**AcceptAsConformance** when accept criteria hold *and*:
- The action's idempotent semantics are part of the public contract (e.g., the documented TCA pattern for `.task`).
- The team is willing to add the action to `idempotentActions: Set<Action>` and fail CI on future regression.

**Reject** when:
- The action's name matches the pattern but the semantics are *not* idempotent (e.g., `.refreshCounter → counter += 1` — toggle / increment / accumulate semantics).
- The action conditionally branches on State and produces different results on second application (e.g., `.dismissTopmost` — first dismiss removes modal A, second removes modal B).
- The action triggers an Effect whose return action mutates State (the State-side is idempotent but the observable behavior isn't — out of scope for first-pass triage; lean accept).

**Skipped** when:
- The action handler is implemented as a switch over a sub-state with many cases, and the rater can't verify all branches are idempotent.
- The action's name is `.task` or `.binding` but the reducer has explicitly overridden the conventional behavior.

## Cross-family — when a reducer fires multiple suggestions

A single reducer can fire suggestions across multiple families (e.g., HandRolled `Hand03_Cardinality.swift` has both Cardinality and Biconditional witnesses). Each suggestion is triaged independently — there's no "package deal" because a user might accept the Cardinality conformance and reject the Biconditional one.

**Bridge gating** — when ≥ 3 Strong-tier suggestions land on the same reducer, the M9 `InteractionInvariantBridge` proposes a peer stub bundling all of them. The bridge-level decision is its own surface (PRD §9.4); per-suggestion triage decisions land first.

## What "skipped" means for the calibration loop

`skipped` decisions don't help promote a family — they leave the suggestion in the queue for re-evaluation. Across three cycles, persistently skipped suggestions surface a rubric gap: either the family's predicate shape is too narrow (forcing skip on borderline real-world cases) or the rubric criteria are under-specified.

**Action threshold:** if a family's `skipped / total` ratio exceeds 30% across a cycle, the next cycle's findings doc should propose a rubric refinement (additional accept / reject bullet) targeted at the skipped class.

## Process

For each cycle:

1. `swift package clean && swift build --product swift-infer`
2. Re-measure all 3 corpora with `discover-interaction --include-possible`, persist raw outputs to `docs/calibration-cycle-N-data/`.
3. For HandRolled, run `--interactive` from the project root and triage each of the 18 suggestions against this rubric.
4. For TCA 1.25.5 + TCA 1.0.0, replicate the corpus layout under `$HOME/xcode_projects/calibration-corpora/tca-{25,10}-discovery` (NOT `/tmp` — it gets auto-purged) per the setup commands in `calibration-corpus-v2.0.md`, then run `--interactive` from those workdirs.
5. Aggregate decisions from `.swiftinfer/interaction-decisions.json` (each corpus has its own) into per-family acceptance rates.
6. Write `docs/calibration-cycle-N-findings.md` reporting:
   - Per-corpus reducer / interaction counts (baseline vs. cycle-N delta).
   - Per-family acceptance rate (numerator / denominator / skipped count).
   - Promotion candidates (families at ≥ 70% in N consecutive cycles).
   - Any rubric refinement proposals for families with high skip rates.

Three cycles of stable per-family ≥ 70% → propose tier promotion in the cycle-N+1 findings doc.
