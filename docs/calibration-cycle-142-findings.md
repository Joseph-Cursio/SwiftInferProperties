# Calibration cycle 142 — biconditional verify corpus widened (3 → 5 reducers)

**Captured 2026-06-15.** No binary change — fixtures + test updates. Third
corpus-widening follow-up (after conservation c140, cardinality c141). The
original biconditional trio annotated its Bool flags explicitly (`var
isActive: Bool = false`) with `Int?` optionals and drifted only one way.
This widens to cover the **V1.97 literal-inferred Bool**, a **`String?`**
optional, the **Refreshing** pattern, and the **inverse drift direction**.

## What shipped

`Tests/Fixtures/biconditional-verify-corpus/` gains two real `@Reducer`s,
each one Bool-flag × one Optional (biconditional only):

- **FeedFeature** — uses `var isRefreshing = false` (no `: Bool`
  annotation — the literal-inference path the detector recovers from the
  `false` initializer) paired with `feed: String?`. The reducer keeps
  `isRefreshing == (feed != nil)` in sync, all Action cases payload-free →
  FULL-coverage `measured-bothPass` → the Finding-G pin is OVERRULED →
  `.verified`. Confirms the overrule holds when the Bool was type-inferred,
  not annotated, and over a `String?` optional.
- **PendingFeature** — a false positive with the INVERSE drift direction:
  StaleFeature sets the flag ahead of the optional (`isLoading = true`
  while `data` nil); PendingFeature's `.receive` sets the optional WITHOUT
  the flag (`nextPage = 5` while `isFetchingMore` false), and `.beginFetch`
  sets the flag without the optional. Either direction violates the iff →
  `measured-defaultFails` → suppressed.

## Measured baseline

`verify-interaction --all --family biconditional` now: **5 identities → 3
`measured-bothPass` + 2 `measured-defaultFails`**:

- SessionFeature (annotated Bool, full) → `.verified` (overrule)
- ConnectionFeature (partial — `received(Data)` excluded) → `.possible`
- FeedFeature (literal-inferred Bool, full) → `.verified` (overrule)
- StaleFeature (flag-ahead drift) → suppressed
- PendingFeature (optional-ahead / inverse drift) → suppressed

So the overrule now holds for both annotated and literal-inferred Bool
flags, and the false-positive suppression catches both drift directions —
coverage breadth, not just count.

## Calibration note

`settle` (an early action name on PendingFeature) matched the `set*`
idempotence prefix and surfaced a stray idempotence witness, tripping the
"biconditional only" guard. Renamed to `finish`. A reminder that verify-
corpus action names must dodge the idempotence witness vocabulary
(exact + `set*`/`select*`/`show*`/`present*` prefixes) to keep a
single-family fixture single-family.

## Verification

- **Fast:** `BiconditionalVerifyCorpusTests` (~0.4s) — discovery surfaces
  exactly the five biconditional identities at `.possible`, no other family.
- **Measured (`.subprocess`):** `BiconditionalVerifyCorpusMeasuredTests`
  (~74s) — 5 → 3 bothPass + 2 defaultFails; discover promotes Session +
  Feed to `(Verified)` with the overrule disclosure, keeps Connection at
  `(Possible)`, suppresses Stale + Pending.
- `swiftlint` clean.

## What's next

Unchanged — all off the critical path: further corpus widening (refint and
idempotence-tca remain candidates), the shelved value-generator (c119) /
`.tca` C1 (c126) items. The frozen 50.5% measured-execution rate stays a
discovery-corpus metric.
