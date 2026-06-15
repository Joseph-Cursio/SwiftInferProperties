# Calibration cycle 137 — biconditional joins the gate-overrule (corpus only)

**Captured 2026-06-15.** No binary change — fixtures + two tests. The
cycle-136 "what's next": demonstrate that the full-coverage pin-overrule is
**family-generic**. Biconditional (the second `swiftProjectLintDeferral`
family) now promotes to `.verified` by the *same* rule cardinality did, with
**no new mechanism** — only a verify-ready corpus.

## Why no mechanism change was needed

The cycle-136 carve-out keys on `family.swiftProjectLintDeferral != nil`,
not on cardinality specifically (`InteractionVerifyEvidenceScoring.
gradedForBothPass`). Biconditional carries `flag-optional-pair-state`, so it
was already eligible the moment cardinality shipped — it lacked only a
corpus to exercise it. This cycle supplies that corpus, confirming the
generic path end-to-end on a second family.

## Proof corpus

`Tests/Fixtures/biconditional-verify-corpus/` — three real `@Reducer`s, each
pairing a biconditional Bool flag with an Optional (one BiconditionalWitness
apiece, `state.<bool> == (state.<optional> != nil)`):

- **SessionFeature** — keeps `isActive == (token != nil)` in sync; all
  Action cases payload-free → **full-coverage `bothPass`** → pin OVERRULED
  → `.verified`.
- **ConnectionFeature** — keeps `isFetching == (payload != nil)` in sync too
  (also `bothPass`), but its Action carries a non-constructible
  `received(Data)` case → **partial coverage** (`excludedActionCount == 1`)
  → pin NOT overruled → stays `.possible`. The coverage gate, not the
  bothPass, decides.
- **StaleFeature** — drifts the flag ahead of the result (`load` sets
  `isLoading = true` while `data` is still nil — the classic
  "flag-set-before-result-arrives" shape biconditional is pinned for) →
  `measured-defaultFails` → suppressed.

**Cross-family hygiene.** Bool names use `Active` / `Fetching` / `Loading`
(biconditional patterns that do NOT match cardinality's `Showing` /
`Presenting`), the Optionals use names that match no cardinality Optional
pattern, and one Bool × one Optional per reducer never reaches cardinality's
≥2-presentation-fields threshold. Action names avoid the idempotence witness
vocabulary. So each reducer surfaces exactly one biconditional identity and
nothing else.

## Verification

- **Fast (CLI):** `BiconditionalVerifyCorpusTests` (~0.2s) — discovery
  surfaces exactly the three biconditional identities at `.possible`, no
  other family.
- **Measured (`.subprocess`):** `BiconditionalVerifyCorpusMeasuredTests`
  (~66s) — the three-way split end-to-end: survey → 2 bothPass + 1
  defaultFails; evidence carries `excludedActionCount` 0 (Session) and 1
  (Connection); discover promotes Session to `(Verified)` with the overrule
  disclosure, keeps Connection at `(Possible)`, suppresses Stale.
- `swiftlint` clean. (The cycle-136 fold unit tests already cover the
  biconditional overrule arm directly — `bothPassFullCoverageOverrulesBiconditionalPin`.)

## What's next

Both gated families (cardinality + biconditional) now promote on a
full-coverage measured bothPass; both un-gated families that share the
State-boolean predicate shape are demonstrated (idempotence, conservation).
Remaining family work is **referential integrity** — the last un-gated
family — cheap once an `Identifiable` gate guards its
`contains { $0.id == … }` predicate at stub-emit time (completeness, low
recall: 2 corpus candidates). After that, all five interaction families have
a measured-verify path. The frozen 50.5% measured-execution rate remains a
*discovery-corpus* metric, unaffected by this family-coverage work.
