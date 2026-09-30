# Evaluating `#if` before scanning: built, 279 rows withdrawn, 1 surfaced

> **Status:** `measured` · **As of:** 2026-09-30

Before this change, `FunctionScanner` walked every `#if` branch, so a declaration in a branch the build
does not compile was scanned as live (`open-threads.md` row 74). `inactive-if-config-census.md` sized
this at 138 whole-file rows. It declined to build a gate, because the only instrument available read a
condition's *name*. `precondition-helper-hop.md` then added a second cost: two false generator declines.
The plan and predictions are in `docs/plans/inactive-if-config-scope.md`, committed before any code.

## 1. The change

Each file is now evaluated with swift-syntax's `SwiftIfConfig` against a macOS arm64 debug build.
Custom conditions come from the nearest `Package.swift`, read by `ManifestConditions`:

- a top-level `.define`, or a `-D` in `unsafeFlags`, sets its condition, subject to any
  `.when(platforms:configuration:traits:)` filter;
- a trait in `.default(enabledTraits:)` is set, closed over each enabled trait's own `enabledTraits`;
- a define under a manifest-level `if` is unknown;
- a condition the manifest never names is not set.

Some questions have no answer here: `canImport`, `hasFeature`, `hasAttribute`, `compiler(…)` and
`swift(…)`, and any custom condition in a corpus with no manifest. `configuredRegions` would treat
those as false and drop the code. So each file is evaluated twice, once with every unknown answered
`true` and once `false`, and **a clause is skipped only when it is inactive in both**
(`InactiveClauses`). Only declaration scanning changes. The visitor never walks function bodies, so
body analysis, including the precondition hop's, is untouched.

**One departure from the scope:** `compiler(…)` and `swift(…)` were first answered with the host
compiler, 6.3. They were moved to unknown (0 and 99) before any measurement was read, because a pinned
version silently misjudges every `compiler(>=…)` block the day the toolchain moves. This keeps 53
functions (1,928 → 1,875 skipped) that are behind `compiler(>=6.4)` alone. It is recorded in the scope's
table, and the predictions were not edited.

## 2. What it skips

**The declaration probe** (`fixtures/inactive-if-config/skipped-declarations-probe.swift.txt`, output
beside it): **1,765 functions** are skipped across the 20 manifest corpora. The probe prints 1,875
because GRDB appears twice in its directory list. By condition:

| condition | functions | corpus |
|---|---:|---|
| `FOUNDATION_FRAMEWORK` (and conjunctions) | 684 | swift-foundation |
| `UnstableContainersPreview`, `UnstableSortedCollections`, `UnstableHashedContainers` (traits off by default) | 806 | swift-collections |
| GRDB: `GRDBCUSTOMSQLITE \|\| SQLITE_HAS_CODEC` 92, `SQLITE_HAS_CODEC` 10, `os(iOS)` 6, other 2 | 110 | grdb |
| `os(Windows)`, `os(Linux)` and similar | 56 | foundation, nio, SwiftPM |
| `#if false` 22, `COLLECTIONS_INTERNAL_CHECKS` 14, `COLLECTIONS_SINGLE_MODULE` 8 | 44 | swift-collections |
| `!_runtime(_ObjC)`, `arch`, `_ptrauth` | 45 | swiftlang-swift |
| `!DATA_LEGACY_ABI` 14, `else of DEBUG` 4, other 2 | 20 | foundation, syntax, nio |
| **total** | **1,765** | |

## 3. Result — discovery rows, same code with the change off and on

A row-level dump of `TemplateRegistry.discover` over the 20 manifest corpora
(`row-dump-probe.swift.txt`). The change was turned off by blanking the visitor's clause set, and
restored afterwards:

| | rows |
|---|---:|
| before | 6,262 |
| after | **5,994** |
| removed | 279: swift-collections 130, swift-foundation 119, swiftlang-swift 17, grdb 8, nio 3, SwiftPM 1, swift-syntax 1 |
| added | 11: **10 relocated, 1 new** |

**The 10 relocations are the same suggestion with a different location.** Each pairs with a removed row
of the same template and subject whose evidence pointed at an inactive twin: for example
`processorCount` at `ProcessInfo+ObjC.swift:81`, behind `FOUNDATION_FRAMEWORK`. Now the row points at the
live declaration. Which of two same-named declarations a row cites is inferred to follow scan order,
not traced.

**The 1 new row** is `_Representation.stabilizeAddresses()` `idempotence`, in
`Data+LegacyRepresentation.swift`, behind the active `DATA_LEGACY_ABI`. Its twin with the same qualified
name, in `Data+Representation.swift` behind `!DATA_LEGACY_ABI`, is now skipped. The pair had been
suppressing both. That is the live declaration surfacing, not a new law about dead code.

`CatalogHealthCensusMeasuredTests`' own count moves **6,251 → 5,995**. The census and the dump count rows
differently, which is the run-to-run instability `monotonicity-verify-reach.md` recorded. Quote the dump.

**The census's whole-file table** (`InactiveIfConfigCensusMeasuredTests`): **148 → 30.** Every condition
it had confirmed inactive now reads **0**:

- `UnstableSortedCollections` 49, `FOUNDATION_FRAMEWORK` 60, `UnstableContainersPreview` 5,
  `COLLECTIONS_SINGLE_MODULE` 2, `#if false` 2 and `UnstableHashedContainers` 1: 119 rows at today's
  corpus size, where the census had 109 at its own.
- The 30 left are the ones it measured active (`SQLITE_ENABLE_FTS5` 6, `DATA_LEGACY_ABI` 7, including the
  new row) and the 17 unresolved `SWIFT_*` rows in swiftlang-swift, which has no manifest.

**The helper-hop probe, re-run:** types that lose initializer derivation go **5 → 3**. `Heap` and
`BitSet.Counted` recover; `SuffixRowAdapter`, `CircularBuffer.Index` and `BigString.Index` stay
declined. Initializers marked by the hop go 300 → 281.

**The 19 funnel repositories:** every per-repository line is identical to census 21, on every bar (1,176
stubs, 940 compiled, 773 passed). No stub any of them emits sits in a skipped clause.

**The test suites:** perf and all eight batches are green, run one by one at the final code, and the
fast suite is green at 6,241. Every batch assertion over the corpora is
a floor (`> 1_000` rows), so they could not have caught movement; the dump above is the A/B.

## 4. The predictions, scored

| # | prediction | result | |
|---|---|---|---|
| 1 | the census's confirmed rows go, its 12 measured-active rows stay | **all confirmed conditions → 0** (119 rows); the active ones stay at 6 + 7 | ✅ |
| 2 | the 17 unresolved swiftlang-swift rows stay | **17** | ✅ |
| 3 | removals between 109 and 600 | **279** | ✅ |
| 4 | 0 rows added | **1** new, plus 10 relocated | ❌, by one row, in the right direction |
| 5 | `Heap` and `BitSet.Counted` regain derivation, the other 3 stay | as predicted | ✅ |
| 6 | the 19 funnel repositories: ≤ 10 stubs change, no pass lost | **0** change | ✅ |

## 5. What this does not answer

- The manifest reader follows literal structure, not execution. A define reached through a helper
  function is unknown, and a package whose targets define different conditions is treated as one
  condition set. Both keep code.
- An Xcode-project corpus has no `Package.swift`, so its custom conditions stay unknown.
  `SWIFT_ACTIVE_COMPILATION_CONDITIONS` is not read.
- `DEBUG` is set, because stubs build in debug. A declaration that exists only in release builds is
  therefore skipped, which is correct for a law the tests must run, and says nothing about release
  behaviour.
- `MemberBlockInspector` reads initializers and stored members by iterating a member list, and never
  looks inside an `#if` there. That is an existing blind spot in both directions, and unchanged.
