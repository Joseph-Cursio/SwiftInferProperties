# Stop scanning declarations in `#if` branches the build does not compile

> **Status:** `proposed` · **As of:** 2026-09-30

`open-threads.md` row 74: `FunctionScanner` walks every `#if` branch `.sourceAccurate`, so a declaration
in an inactive branch is scanned as live. `inactive-if-config-census.md` sized it at **138 rows of
5,858** in whole-file guards alone (109 confirmed inactive, 12 measured active, 17 unresolved). It
declined a gate because the only instrument it had read a condition's *name* and guessed.
`precondition-helper-hop.md` then measured a second cost: `Heap` and `BitSet.Counted` lose their
generator, because the trapping `_checkInvariants()` sits in an inactive `#if
COLLECTIONS_INTERNAL_CHECKS` branch.

swift-syntax 602, which this package already pins, ships `SwiftIfConfig`. It evaluates a condition
against a `BuildConfiguration`, so the tool can evaluate conditions instead of guessing from names.

## 1. The change

**A declaration is skipped only if its clause is inactive whatever the unknowns turn out to be.**
`configuredRegions(in:)` treats a condition the configuration cannot answer as false, which is the wrong
default here: an unknown condition must keep its code. So each file is evaluated twice. In one
configuration every unknown answer is `true`; in the other every unknown answer is `false`. The visitor
skips a clause only when it is inactive in **both**. `#if canImport(X) … #else …` therefore keeps both
branches, and `#if os(Linux)` on this host drops its body.

What the configuration knows:

| question | answer | why |
|---|---|---|
| custom condition, a `.define("X")` in the nearest `Package.swift` at top level | **set** | SwiftPM defines it. Counted package-wide, so every imprecision keeps code |
| `.define` with `.when(platforms:)` | set iff the list includes `.macOS` (or `configuration: .debug`) | the tool builds and verifies on the macOS host, in debug |
| `.define` inside an `if` / `#if` / `guard` in the manifest, or a variable the reader cannot follow | **unknown** | GRDB appends `SQLITE_ENABLE_PREUPDATE_HOOK` under an `if` |
| a trait named in `.default(enabledTraits:)` | **set** | SwiftPM exposes enabled traits as conditions |
| a trait declared but not enabled by default, or a condition the manifest never names | **not set** | swift-collections' `UnstableSortedCollections`; swift-foundation's `FOUNDATION_FRAMEWORK` |
| `DEBUG` | **set** | stubs build in debug |
| any custom condition when no manifest is found, or the manifest does not parse | **unknown** | swiftlang-swift, the Xcode-project corpora |
| `os`, `arch`, `targetEnvironment`, `_runtime`, `_ptrauth`, endianness, pointer width | the host (macOS, arm64) | a law about Linux-only code cannot be run on the host that verifies it |
| `canImport`, `hasFeature`, `hasAttribute` | **unknown** | depends on dependencies and compiler flags |
| `compiler(…)`, `swift(…)` | **unknown** (0 and 99) | pinning the host version would go stale when the toolchain moves |

Commented-out `.define`s are trivia, so the syntax tree never sees them. That is correct: the census's
`SQLITE_HAS_CODEC` is commented out.

**Scope:** declaration scanning in `FunctionScanner` only (`scanCorpus`, so discover, index and the census
surveys). Function *bodies* are not re-read: the kit's precondition detector, and the hop, still count a
`#if DEBUG fatalError` inside a body.

## 2. Measurement

- **The 20 manifest corpora**: discovery rows before and after (`make batch8`'s census), with removals
  attributed by condition.
- **The 19 funnel repositories**: the funnel census against census 21.
- **The helper-hop population probe**, re-run.
- **A full `make test`**: every `*MeasuredTests` baseline that surveys a corpus is expected to move, and
  each moved figure is re-taken and attributed, not just updated.

## 3. Predictions

| # | prediction |
|---|---|
| 1 | the census's **109 confirmed** whole-file rows are removed, and its **12 measured-active** rows (`SQLITE_ENABLE_FTS5`, `DATA_LEGACY_ABI`) survive |
| 2 | the **17 unresolved** swiftlang-swift rows survive (no manifest, so unknown) |
| 3 | total removals over the 20 corpora are **≥ 109 and ≤ 600**: whole-file guards are a floor, and inner blocks plus `os(…)` add to it |
| 4 | **0** rows are added |
| 5 | the helper-hop probe: `Heap` and `BitSet.Counted` regain initializer derivation, and the other 3 of its 5 stay declined |
| 6 | the 19 funnel repositories: **≤ 10** stubs change, and no pass becomes a failure |

## 4. What this does not answer

The reader follows a manifest's literal structure, not its execution. A define reached through a helper
function or a computed array is unknown, so those branches are kept. A package whose targets define
different conditions is treated as one condition set, which also keeps code rather than dropping it.
