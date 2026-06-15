# Calibration cycle 132 — composed-body scoping (Scope / CombineReducers / multi-Reduce)

> **STATUS: SCOPING (no binary change — investigation + decision record).**
> Scopes verifying a composed TCA reducer body (multiple `Reduce { }`
> closures, or `Reduce` + `Scope`/`CombineReducers`). **Finding: a real
> correctness gap** — composed bodies emit multiple same-`qualifiedName`
> candidates; the *discover* path dedups them but the *verify* pin path
> doesn't, so a composed reducer currently surveys as `measured-error`
> (`ambiguousPin`), not verified. The fix is small (mirror the existing
> discover-side dedup in the verify path). This is the one remaining `.tca`
> item needing a *code* change rather than corpus curation. Captured
> 2026-06-15.

## What's genuinely new

Per PRD §6.3 the discoverer emits **one `ReducerCandidate` per `Reduce`
closure**, so a composed body —

```swift
var body: some Reducer<State, Action> {
    Reduce { state, action in … }                 // candidate 1
    Scope(state: \.child, action: \.child) { Child() }
    Reduce { state, action in … }                 // candidate 2
}
```

— yields **multiple candidates with the same `qualifiedName`** (`Feature.body`),
same `State`/`Action`. Discovery of this is already tested
(`ReducerDiscovererTCATests`: "multiple Reduce closures in one body all
surface" → count 2; "Reduce nested inside Scope" → count 2).

## The break: dedup mismatch between discover and verify

| Path | Dedup? | Composed-body result |
|---|---|---|
| **discover** (`collectSuggestions`) | **Yes** — `dedupedByStateAndAction` (`DiscoverInteractionCommand.swift:312`), first-seen wins, by `(stateQualifiedName, actionQualifiedName)` | one suggestion per (state, action) — fine |
| **verify** (`resolveCandidate`, `VerifyInteractionPipeline.swift:194`) | **No** — re-discovers, no dedup | exact-match count = 2 (≠1) → lenient match = 2 → **`ambiguousPin` thrown** |

So the survey flow for a composed reducer:

1. `collectSuggestions` (deduped) finds the witness — good.
2. `surveyOne` → `runWithInvariant("Feature.body")` → `resolveAndEmit` →
   `resolveCandidate` re-discovers **without** dedup → two `Feature.body`
   candidates → `ambiguousPin`.
3. The cycle-120 error-tolerant survey catches it → records **`measured-error`**.

**Net: a composed-body reducer is currently unverifiable — it surveys as an
error, not a verdict.** This isn't hypothetical: the isowords `Settings.body`
(10 inline `Reduce` closures) is exactly the shape the discover-side dedup
test (`DiscoverInteractionDedupeTests`) was written for.

## The fix (small, mirrors existing code)

Apply the same `(state, action)` dedup in the **verify** path — in
`resolveAndEmit`, right after `ReducerDiscoverer.discover` and before
`resolveCandidate` — reusing `DiscoverInteraction.dedupedByStateAndAction`
(same module). After dedup, `Feature.body` resolves to one candidate and the
verifier runs `Feature().reduce(into:&s, action:)`, which executes the
**whole composed body** (every closure + `Scope` + child).

That is the correct idempotence semantic: the property is verified against
the user's actual composed reducer, not an individual closure. Picking
first-seen is safe because all the duplicate candidates carry the same
enclosing type / State / Action — the verify invocation only needs those,
not the per-closure source location.

~5 lines + the reuse. Low risk: the discover path has run this exact dedup
since the isowords 10-closure case.

## Scope / child: already handled by Phase B

For `Scope(state: \.child, action: \.child) { Child() }`:

- Parent `Action` gains `case child(Child.Action)` → **Phase B already
  classifies it non-derivable → excluded** (with the partial-exploration
  disclosure). No new code.
- Parent `State` needs `var child: Child.State = .init()` — zero-arg
  `Equatable` — a *fixture* requirement, not a code change.
- `Child` must be co-compiled (it lives in the corpus dir) and the survey
  will additionally discover `Child`'s own witnesses (extra coverage, fine).

## Decision / build plan

Worth doing — it's the only remaining `.tca` item that needs a code change,
and it closes a real correctness gap (composed reducers un-verifiable).
Tested increments:

1. **Dedup fix** in `resolveAndEmit` + a fast unit test: `resolveCandidate`
   / `resolveAndEmit` no longer throws `ambiguousPin` on duplicate
   `Feature.body`; the deduped candidate resolves.
2. **Fixtures**: `MultiReduceFeature` (two `Reduce` closures — the minimal
   repro) and a `ParentFeature` + `ChildFeature` `Scope` composition (the
   realistic case, also exercising child-action exclusion in a composed
   context).
3. **Measured test**: survey them → witnesses verify `bothPass` (the parent
   discloses `excluded: child`).

## What's next

After this, the `.tca` epic covers composed bodies too. Remaining
genuinely-optional: C1's literal discovery-corpus extractor (only if that
number is ever required). Default idempotence stays `.likely`; the other
four interaction families stay `.possible` behind `--include-possible`.
