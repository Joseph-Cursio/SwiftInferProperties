# Laws proposed for code that is not in the build — `#if`, sized

> **Status:** `measured` · **As of:** 2026-08-30

**`open-threads.md` row 74, sized.** `SwiftSyntax` parses every `#if` branch into the tree and
`FunctionScanner` walks it `.sourceAccurate`, so a declaration inside an **inactive** branch is
scanned as if it were live. Nothing in `Sources/` reads `IfConfigDeclSyntax`, `configuredRegions`
or an active-clause rewriter.

## 1. The figure, and the correction that has to travel with it

| reading | rows |
|---|---:|
| in a file wholly behind a presumed-inactive `#if` | **138** of 5,858 (2.4%) |
| …of which **confirmed inactive** by reading the manifest | **109** (1.9%) |
| …**measured FALSE** — the package defines the flag | **12** |
| …**unresolved** — no SwiftPM manifest to read | **17** |

Denominators: **2,498** Swift files scanned (`EXCLUDED_DIRS` applied), **880** containing any
`#if`, **97** wholly guarded.

| condition | files | rows | status, hand-checked |
|---|---:|---:|---|
| `UnstableSortedCollections` | 54 | 50 | **inactive** — commented out of `.default(enabledTraits:)` |
| `FOUNDATION_FRAMEWORK` | 23 | 58 | **inactive** — never `.define`d in the package build |
| `UnstableHashedContainers` | 1 | 1 | **inactive** — commented out; the original exhibit |
| `SQLITE_ENABLE_FTS5` | 7 | 6 | ⚠ **ACTIVE** — GRDB `.define`s it unconditionally |
| `DATA_LEGACY_ABI` | 4 | 6 | ⚠ **ACTIVE** — `.define(…, .when(platforms: [.macOS, …]))` |
| four `SWIFT_*` stdlib flags | 6 | 17 | **unresolved** — CMake, no manifest |
| `SQLITE_HAS_CODEC` | 1 | 0 | inactive — `.define` is commented out |

⚠ **The name heuristic has a MEASURED false-positive rate: 2 of 11 conditions, 12 of 138 rows.**
Found by doing what the suite's own doc comment says to do — check a manifest before trusting a
name. **The two flags are deliberately NOT added to the exclusion list**: two corpora's build
settings are not a property of the rule, and hard-coding them would make the heuristic look more
accurate than it is.

## 2. Row 74's sharpest unchecked question, answered: YES

> *`SortedSet` / `SortedDictionary` are behind `UnstableSortedCollections` and are already in
> this tool's carrier vocabulary, so the census may find it has been classifying carriers that
> are not in any default build.*

**Confirmed. `SortedSet` is the single largest carrier in the affected set — 24 rows.**
`CatalogHealthCensusMeasuredTests.CarrierShape.of` lists `SortedSet<` and `SortedDictionary<`
among its collection heads, and every one of those 54 files is wholly behind a trait commented
out of the manifest's defaults.

By corpus: `swift-foundation` **64** · `swift-collections` **51** · `swiftlang-swift` **17** ·
`grdb` **6**. By template, the head is the catalogue's head: `predicate` 53, `idempotence` 23,
`measure-non-negativity` 17, `codable-round-trip` 7, `input-totality` 7.

## 3. Every figure is a FLOOR — whole-file guards only

This counts only a file whose **entire top level** sits inside one `#if`, because that is
decidable from the file itself and needs no judgement about where a declaration sits among nested
clauses. It was also the measured shape: all 54 `UnstableSortedCollections` files are of that
form.

**A declaration inside an inner block is invisible to it.** `swift-collections` alone holds 16
`COLLECTIONS_INTERNAL_CHECKS` blocks and **23 `#if false`** blocks that are not whole-file.
Naming the under-count is the point — row 74 says a grep is the wrong instrument, and an
over-claiming parser would be worse.

**And `#if compiler(…)` is deliberately not counted**, along with `swift(…)`, `os(…)`,
`canImport(…)`, `arch(…)`, `targetEnvironment(…)` and `DEBUG`. Those are usually active, and
sweeping them would be this row's version of *gating on `@available` would sweep 1,163
`deprecated`*. `swift-collections` alone has **303** `#if compiler` blocks.

## 4. An eighth instrument error, caught by an independent reading

**The first run applied none of `scripts/measurement.py`'s `EXCLUDED_DIRS`** — `(".build",
".git", "checkouts", "Tests", ".swiftinfer")` — and reported `#if UnstableSortedCollections` in
**188** files where the package holds **54**. The surplus was `swift-collections` vendored inside
other corpora's `.build/checkouts`.

**It was caught only because a direct `grep` of that package had been run minutes earlier and
disagreed.** A count with no independent reading beside it would have shipped.

✅ **And the finding did not move: 138 rows both before and after.** The excluded files inflated
the **denominator** 2.4× (7,504 files → 2,498) and contributed **no rows**, because
`FunctionScanner.scanCorpus` already excludes those paths. **The error was real, and it was in
the half of the instrument that reports scale rather than the half that reports the finding** —
which is why the file column and the row column are now printed side by side.

## 5. What this does and does not license

**Comparable to the availability gate, which is the precedent**: that withdrew **24 rows of
4,161 (0.58%)** and was built because it cost no laws. This is **109 confirmed of 5,858 (1.9%)**
— about three times the share — and should likewise cost no laws, since code excluded from the
build cannot be the subject of a law anyone can run.

⚠ **No gate is proposed here.** Row 74 asked for the size and this is the size. A gate needs a
decision about the 17 unresolved rows and about whether *presumed* inactive is a sound basis for
withdrawing a law, given a measured 2-of-11 false-positive rate on conditions. **The availability
gate reads an attribute out of the syntax tree; this would read a name and guess at a build
configuration**, which is the weaker basis the `monotonicity` gate already had to argue for.

## 6. What would refute this

- **A manifest showing `FOUNDATION_FRAMEWORK` is defined in the package build** — that is 58 of
  the 109 confirmed rows, and the largest single claim here.
- **Resolving the four `SWIFT_*` stdlib flags** against the compiler's CMake configuration, which
  would move 17 rows into or out of the count.
- **An inner-block reading finding the whole-file shape is a minority of the population**, which
  would make the floor here misleadingly low rather than usefully conservative.
