# Does the tool propose laws that cannot be written?

> **Status:** `measured` · **As of:** 2026-08-22

**Measured YES, and fixed — 24 of 4,161 evidence-rows (0.58%) named a declaration that
cannot be called.** Small, concentrated, and worth doing anyway: it costs **no laws**, which
is the whole argument. Nobody should quote this as a large win.

---

## 1. The witness

`swift-system`'s `FilePath.dirname` produced a suggestion, a score, and a verify verdict of:

```
error: 'dirname' has been renamed to 'removingLastComponent()'
```

```swift
// MARK - Renamed
@available(System 0.0.2, *)
extension FilePath {
  @available(*, unavailable, renamed: "removingLastComponent()")
  public var dirname: FilePath { removingLastComponent() }
}
```

**Discovery consulted availability nowhere.** It read visibility and stopped.

Found only because `criterion-a-swift-system.md` §3's emitter fix made the stub compile far
enough to reach a *different* error. Before that fix the row failed with
`cannot call value of non-function type` and the availability problem was invisible behind
it — the same *a refuter that fires first hides every refuter behind it* shape this project
records elsewhere, at pipeline scale.

---

## 2. Why this is a refusal, not a caveat

`FunctionScanner` deliberately does **not** withhold `private` declarations, and the reason
is recorded at the call site: property-based tests are refactoring-safe, so a `private`
function's law is worth surfacing with the one refactor that reaches it, and dropping it
silently was *the confident zero that left the tool blind on application code*.

**None of that transfers.** There is no refactor for `@available(*, unavailable)`: the
declaration cannot be called by anyone, including its own module. A law on it cannot be
written, cannot compile, and cannot be acted on. It is not a conservative suggestion — it is
a wrong one.

---

## 3. The population, measured before building

`swift-infer discover --include-possible` over every resolving corpus, joined back to the
source line and up through the declaration's attribute block:

| corpus | evidence-rows | naming an uncallable subject |
|---|---:|---:|
| swiftlang-swift | 1,723 | **19** |
| swift-system | 47 | **5** |
| *the other 16* | 2,391 | **0** |
| | **4,161** | **24** |

**0.58% of output, and 79% of that in one corpus.** By this project's own standards that
concentration is an argument *against* building — it is what killed the postcondition
body-guard route (*9 of 13 in one file*).

**What carries it instead is that the gate costs no laws.** All 24 carry `renamed:`, and
**20 of the 24 are strict duplicates**:

- swiftlang-swift's 19 point at `extracting(first:)` / `extracting(droppingFirst:)` /
  `extracting(droppingLast:)`, which carry **48** live evidence-rows of their own.
- swift-system's `dirname` points at `removingLastComponent()`, which has its own row — the
  one that passes at 100 trials and fails at 2,000 (`criterion-a-swift-system.md` §8.2).

The remaining four — `dup` / `dup2` / `dup3` → `duplicate`, and `pwrite` → `write` — have no
replacement row and still lose nothing actionable: they are uncallable either way, and three
of them have bodies that are literally `fatalError("Not implemented")`.

⚠ **The 24 has NOT been re-taken, and cannot be cheaply.** The gate now suppresses exactly the
rows the join counted, so re-running it returns ~0 — a measurement of the fix, not of the
population. The bound available instead is the declaration count above: the three
newly-included corpora carry **6** blocking declarations between them, all in GRDB, so the true
row figure is a little above 24 and not materially so. Re-taking it properly would mean
building with the gate disabled, which is not worth it for a number already labelled a lower
bound.

⚠ **Two instrument caveats on the 24.** The join inspected only a declaration's own attribute
block, on a **single line**, so an enclosing unavailable `extension` and any multi-line
`@available(…)` were invisible — §5 shows both mattered. And three corpora returned zero
evidence-rows entirely (`swift-syntax`, `swiftlint-rule-studio`, `cycle27-surface`), which is
a scoping artifact, not a measurement: **their contribution is unmeasured, not zero.**

---

## 4. The rule is two keywords, and that is the measured part

The tempting version — *skip anything carrying `@available`* — would be a catastrophe. Over
the same corpora, on `public` / `package` declarations:

| form | sites | callable? |
|---|---:|---|
| `@available(*, deprecated, …)` | **1,181** | **yes**, with a warning |
| version floors — `@available(macOS 13, iOS 16, *)` | hundreds | **yes** |
| `@available(*, noasync)` | 34 | **yes** — the emitted stub is synchronous |
| `@available(*, unavailable, …)` | 98 | no |
| `@available(swift, …, obsoleted: 5.0, …)` | **106** | no — already removed |

> **Re-taken 2026-08-23 after the corpus-manifest fix, and the manifest was the SMALLER of two
> errors.** Decomposed rather than swapped in:
>
> | | previously-measured 17 corpora | 3 newly-included | corrected |
> |---|---:|---:|---:|
> | `unavailable` | **92** — reproduces the old figure exactly | 6 | **98** |
> | `obsoleted:` | **106** | 0 | **106** |
> | `deprecated` | **1,163** — reproduces exactly | 18 | **1,181** |
>
> **Both original figures reproduce to the digit on their original population**, which
> cross-validates the two instruments. The manifest fix moved them by **6 and 18** — the three
> corpora that had been resolving to zero `.swift` files
> (`open-threads.md` → *Six wrong instruments in one cycle*) carry little `@available` surface.
>
> **The larger error was `obsoleted: 49+`, which is really 106.** That figure came from a
> form-census truncated to its top 18 shapes, so it undercounted by more than half — nothing to
> do with the manifest. It is now a full count.
>
> **None of this changes the gate's design.** `deprecated` at 1,181 still dwarfs blocking at
> 204, so gating on `@available` generally would still sweep an order of magnitude more than it
> saved. If anything the case is stronger.

So: block on `unavailable` and `obsoleted:`, admit everything else. **`deprecated` is the one
that would hurt** — a deprecated API is a perfectly good law subject, and gating on it would
throw away an order of magnitude more than it saved.

**`@available(swift, deprecated: 3.0, obsoleted: 5.0, renamed: …)` says BOTH words**, so a
rule keyed on the wrong one reads a Swift-5-removed declaration as callable. Most of
`UncallableDeclarationTests`' arms are negative cases for exactly this reason: the risk is
not that two keywords fail to fire, it is that they fire on a third.

**`obsoleted:` does not compare versions.** Deliberate, with a measured basis: every instance
found is a Swift-version obsoletion already passed, against a Swift 6 toolchain. A wrong
decline costs one suggestion; a wrong admission costs a guaranteed build failure. If a subject
ever declares `obsoleted:` at a version not yet reached, this over-declines — and the fix is
to compare, not to loosen.

---

## 5. Measured after building — the estimate was a floor, and that was checked

| corpus | suggestions | evidence-rows |
|---|---|---|
| swiftlang-swift | 1,332 → **1,313** (−19) | −35 |
| swift-system | 40 → **35** (−5) | 47 → 42 |
| home corpus | unchanged | **0 blocked** |

**−35 rows against a predicted 24 is the direction that would mean over-firing**, so it was
checked rather than accepted. It is not: `count`, `byteCount` and `underestimatedCount` all
still produce suggestions afterwards. Two causes, both of which make the pre-build estimate a
floor:

1. **The estimating regex read one line.** A multi-line `@available(*, unavailable,` /
   `renamed: …)` was invisible to it and is not invisible to the parser.
2. **A gated declaration takes its PARTNER's evidence row with it.** A `round-trip` pairing
   `byteCount()` with a withdrawn `dropFirst(_:)` is *one* suggestion; removing it removes
   both rows, and only one of them is withdrawn.

**The home corpus cannot control this change.** Adding `UncallableDeclaration.swift` to
`Sources/SwiftInferCore` adds four discovery rows of its own — the count went *up* by 4 while
the gate blocked 0. A control that shares a source tree with the change is not a control.

---

## 6. What this does not claim

**Not a reach fix.** Zero rows move *into* execution. The gate removes output; §3's argument
is that the removed output could never have been acted on.

**Not generalisable from 24.** Two corpora carry the whole population, and one of them is the
Swift standard library, which is not a representative subject. A third corpus with a large
rename surface would move this number and nothing here predicts by how much.

**Says nothing about `deprecated`.** 1,163 public declarations are deprecated and still get
laws, which is correct and deliberate. Whether a *caveat* on those is worth surfacing is
unmeasured and not proposed.
