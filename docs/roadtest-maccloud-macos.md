# Road-test — MacCloud_client_MacOS (2026-07-18)

Toolchain-facing record of pointing the PBT toolchain at a second MacCloud fixture
(the macOS client, after the iOS one). Goal: assess PBT adoption, find toolchain
gaps, and find real bugs in the fixture. One toolchain fix landed in this repo
(`Data` in `EquatableResolver`); two fixture bugs were found, pinned with property
tests, and fixed in the fixture repo.

## Setup (honesty)

- **No hand-written answer-key branch**, so this is an **adoption walkthrough + bug
  hunt**, not a scored benchmark (a real answer key must be written before/without
  the tools — Appendix C).
- The fixture is **already partially PBT-adopted**: `ChunkPlan` ships parameterized
  `@Test` properties (tiling, ceil, empty-payload, monotonic progress). So the real
  question was **"what do the existing property tests miss?"** — and the answer is
  the road-test's whole lesson.
- Xcode project (not SwiftPM), scanned via `discover --sources MacCloudClient/`.
  App tally: 1 Likely / 31 Possible / 0 Strong — normal for a SwiftUI/networking
  app; the value is in the kernels.

## Two fixture bugs — both masked by a green hand-written test

### Bug A (HIGH, reachable) — incremental sync is dead code
`MacCloudSyncManager+Sync.identifyChanges` keyed local files by **bare filename**
(`scanLocalFiles` uses `lastPathComponent` → `"photo.jpg"`) but the remote map by
**leading-slash path** (`"/photo.jpg"`). The key spaces never intersect, so an
already-synced file was **re-uploaded AND re-downloaded every cycle**, and the
conflict-detection branch (the only path that produces a `SyncConflict`) was
**unreachable**. Runs on every timer/manual/wake sync.
- **Masking test:** `identifyChangesConflict` hand-built `localFiles` keyed
  `"/c.txt"` (remote convention), not `scanLocalFiles`'s real bare-name output — so
  it was green.
- **Catching property:** the sync no-op law — *"syncing an already-in-sync
  directory produces zero uploads and zero downloads"* — fails for **every** input.
- **Fix:** key the remote map by `.name` (with `uniquingKeysWith` for crash-safety)
  to match the local scan's flat convention; fixed the masking test's key too.
  **Assumption flagged:** this bakes in a *flat* namespace (what `scanLocalFiles`
  already assumes). Subdirectory support would instead need `scanLocalFiles` to emit
  relative paths on both sides.

### Bug B (latent contract violation) — `ChunkPlan.progress(afterCompleting:)` traps at `Int.max`
`min(max(index + 1, 0), totalChunks)` computes `index + 1` *first* → overflow trap
at `Int.max`. The type's docstring claims Int-range totality and `byteRange` is
overflow-hardened — `progress` was missed.
- **Masking test:** `progressReachesOne` iterates `for index in 0 ..< totalChunks`
  — bounded, never hits the boundary. Note `byteRange`'s totality test *does*
  quantify over out-of-range indices: the **test coverage has the same gap as the
  code** (byteRange hardened, progress not).
- **Catching property:** `∀ index: progress ∈ [0, 1]` — which `discover` surfaced
  verbatim.
- **Fix:** `index.addingReportingOverflow(1)`, clamping to "complete" on overflow —
  the same overflow-reporting style `byteRange` already uses.
- **Scope:** not happy-path-reachable (the call loops over bounded `remainingIndices`)
  — a contract/test gap, not a live crash. Like Appendix C's BigUInt De Morgan find.

**Through-line:** both bugs are pinned by a passing test that asserts the buggy
shape — the exact failure mode Appendix C is built around, found twice.

## Toolchain findings

| # | Finding | Status |
|---|---|---|
| 1 | **`Data` missing from `EquatableResolver.curatedEquatableStdlib`** → the `(Data) throws -> Data` encrypt/decrypt round-trip demoted from RoundTripTemplate to the weaker inverse-pair tier. | **Fixed** in this repo (commit on `main`). Encrypt/decrypt now fires round-trip + surfaces the base64 stdlib anchor. |
| 2 | **Reference-type-carrier `-10`** holds the encrypt/decrypt round-trip at Possible because the functions live on a `class`. | **Observation, not fixed** — *defensible*: a crypto manager may carry key/IV state that breaks the round-trip. The caveat lets the human decide. |
| 3 | **Comparators-as-closures are invisible to `discover`** — `comparator` template fired 0×; `sortByName`'s folders-first SWO is an inline `.sorted {}` closure. | Known two-tool workflow — needs the SwiftProjectLint `--format pbt-seeds` closure-extraction step. |

**Toolchain positives:** `partition` on `byteRange` at Likely (chunk-tiling
`concat(chunks) == payload`); `monotonicity` + bounds on `progress` with the exact
*"an over-sending server drives it above 1.0"* caveat and the *"name the empty
case"* nudge — the suggestions **led straight to Bug B**. Precision held: the app is
mostly non-algebraic and the tool stayed appropriately quiet (0 Strong).

## Bug-hunt coverage (kernels checked clean)

encrypt/decrypt (genuine AES-GCM round-trip, fresh nonce per call — no IV reuse);
all four sort comparators (valid strict weak orderings; `sortByDate`/`sortBySize`'s
bare `>` is unstable-but-not-broken over a stable sort); file-type detection
(case-folded, no cross-category collisions); `MacCloudFile+Navigation`
(`hasPrefix(parent.path + "/")` correctly handles grandchildren and the
`/a` vs `/ab` false-prefix); preferences validation; Codable persistence round-trips.

## PBT-adoption loop demonstrated

Both bugs were run through the full loop: property written → shown red (verbatim
repros: Bug B SIGTRAP at `Int.max`; Bug A 1 upload + 1 download for an in-sync
file) → production fixed → shown green (all adversarial indices valid; in-sync →
0/0). Property tests added to the fixture: `progressIsTotalOverIntDomain`
(`ChunkPlanTests`) and `identifyChangesInSyncIsNoOp` (`SyncOperationsTests`).

**Fixture test-suite confirmation (xcodebuild):** `xcodebuild test` on the real
Xcode project (`platform=macOS`) — **TEST SUCCEEDED** for both new properties
(`progressIsTotalOverIntDomain` incl. `Int.max`; `identifyChangesInSyncIsNoOp`) and
the re-keyed `identifyChangesConflict`. The full red→green loop is validated in the
actual fixture, not just the repros.

## Two-tool seed step (comparators) — gap #3 is the workflow, not a defect

Ran `swiftprojectlint <fixture> --format pbt-seeds` → **20 seeds**, **6 in
`MacCloudFile+Sorting.swift`** (`sortByName`/`sortByType`/`sortByDate`/`sortBySize`).
Then `swift-infer discover --seeds <manifest> --sources MacCloudClient/`.

The seeded run surfaces an actionable **advisory** pointing at the exact comparator
closure:

> `MacCloudFile+Sorting.swift:12: inside 'sortByName' — extract it into a named
> value type, then re-run the linter to seed it properly.`

— and the same for `sortByType:45` (and `evaluateTrust:36`). So the folders-first
comparator that `discover` alone can't see (it's a `.sorted {}` closure) **is**
surfaced by the two-tool workflow: the linter's `pbt-seeds` + seeded `discover`
prescribe the extraction to a named `precedes(_:_:)`, exactly the path the iOS
road-test walked, at which point its strict-weak-ordering property becomes seedable
and verifiable. Gap #3 is therefore the *designed two-step*, not a defect — the
lesson is that comparator SWO properties require the seed step, not `discover` alone.

## Net

- **Toolchain fix landed** (this repo): `Data` ∈ `curatedEquatableStdlib`.
- **Two real fixture bugs** found, pinned with properties, fixed, green in-project.
- **Two-tool workflow validated** end-to-end on a second, independent fixture.
- **Precision held**: no default-tier false positives; the app's non-algebraic bulk
  stayed quiet; the one reference-type-carrier demotion is defensible.
