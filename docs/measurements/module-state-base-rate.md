# How often is a module-state mutation judged pure?

> **Status:** `measured` · **As of:** 2026-08-17

Re-derivable at any time — `ModuleStateCensusMeasuredTests` *is* the harness, and
`make batch2` runs it.

**Measured: the base rate is ZERO, and it is zero because this corpus declares no
file-scope `var` at all.** The asymmetry is real; it has no victims here. That makes
it a **latent unsoundness**, which is item 40's result and must be reported as item
40's was — not as a defect, and not as a clean bill of health either.

> **Do not stop reading here.** This is the *home* arm — one package. Its closing
> instruction, *"do not carry this zero to another corpus,"* was discharged on
> 2026-08-19: see **[The cross-corpus arm](#the-cross-corpus-arm--the-standing-instruction-discharged)**
> at the foot of this file. Across 17 corpora and 20,526 functions the base rate is
> **5, not 0** — and the home arm's prediction about which codebases would exhibit
> the shape is measured **wrong**.

---

## The question, and why it needed asking separately

`docs/measurements/ownership-premise-declined.md` turned this up while probing
something else:

| shape | verdict | refuted by |
|---|---|---|
| `S.total += value` — static member | `.refuted` | `ReducerPurityAnalyzer`'s static / `Self` clause |
| `counter += value` — **file-scope `var`** | **`.pure`** | **nothing** |
| `{ counter += 1 }` — closure capture | refuted | `refuteIfCaptured` |

The same write is refuted inside a closure and admitted inside a function. That
census deliberately did **not** measure how often it happens, because it is a
different query and folding it in would have implied coverage it did not have.

**What the number decides.** If zero, the missing refuter costs this corpus nothing
and the finding is theoretical. If not zero, every row is a **false `.pure`** — the
direction SEI's own doc calls the most dangerous place to land wrongly, because a
generated property test runs the function in-process over random inputs.

---

## Provenance

| | |
|---|---|
| corpus | this repo's `Sources/`, the item 29 census's own `corpus` / `verdicts` statics — shared, not recomputed |
| SEI pin | `3ea25f2` (`Package.swift:122`) |
| harness | `Tests/SwiftInferCoreTests/ModuleStateCensusMeasuredTests.swift` |
| population | the **2,396 `.pure`** subjects of 2,740 — the only rows a false verdict can cost |
| scope | file-scope `var` only, grouped by target |

**Scope is narrower than "global state", deliberately.** `static` and `Self` writes
are already refuted by `ReducerPurityAnalyzer` — the `reducerEffect` cause's 26 rows
— so admitting them would double-count a covered case. A `let` cannot be mutated.
Globals are grouped by `Sources/<Target>/` because a file-scope `var` is `internal`
and therefore visible across its own module and no further; matching every target's
globals at once would over-count.

---

## The measurement

| | count |
|---|---|
| file-scope `var` declarations in `Sources/` | **0** |
| `.pure` functions writing one | **0** |
| `.pure` functions calling a member on one (unresolved surface) | **0** |

**The zero is structural, not incidental.** There is no mutable module state in this
package to mutate, so no function can be wrongly judged pure for mutating it. The
`0` in row two is entailed by the `0` in row one rather than measured independently.

### Corroborated four ways, because a zero needs it

`grep` over `Sources/`, independent of the harness:

```
^var                      0
^public var               0
^internal var             0
^nonisolated(unsafe)      0
```

---

## The instrument was blind on its first run, and that is the part worth reading

**This census initially reported the same base rate of 0 with a detector that could
not see a single assignment.** `Parser.parse` leaves an operator sequence as a flat
`SequenceExprSyntax` until an `OperatorTable` folds it, so `counter += value` never
becomes an `InfixOperatorExprSyntax` — and the checker only overrode the folded form.
Every write in every body was invisible.

**`PurityInferrer` carries a comment warning about precisely this, one file away:**

> *The **unfolded** form, which is what `Parser.parse` actually produces: an operator
> sequence is a flat `SequenceExprSyntax` until an `OperatorTable` folds it, so a
> visitor that only knows `InfixOperatorExprSyntax` sees no assignments at all.*

It was re-entered rather than read. What caught it was not the number — the number was
identical before and after the fix — but `detectorFires`, a synthetic witness asserting
the detector fires on a mutation it must see and stays quiet on a shadowed local.

**Two rules this earns.**

1. **A zero measured with a blind instrument is not a zero**, and this repo has now
   produced that shape three times: item 33's closure base rate, item 40's, and this
   one. The difference is only that this instrument was fixed before its number was
   published.
2. **The control has to be able to fail for the reason you are worried about.** An
   assertion that the corpus contains no globals cannot distinguish an empty corpus
   from a broken collector; the synthetic witness can, and the `grep` corroboration
   covers the case where both are wrong together.

---

## The verdict

**The module-state asymmetry is REAL and has ZERO victims in this corpus.** Report it
as a latent unsoundness, exactly as item 40 was:

- **It is not a defect to fix now.** Nothing in `Sources/` exhibits the shape, so a
  refuter would move zero rows and its cost would buy nothing measurable here.
- **It is not sound, either.** The oracle would judge such a function `.pure` if one
  appeared, and the closure path proves the analysis is capable of the opposite answer.
  This is an *absence of exhibits*, not an absence of the hole.
- **It is a fact about this repository, not about Swift.** A codebase with a global
  cache, a shared counter, or a `nonisolated(unsafe)` singleton would exhibit it
  immediately, and every instance would be a false `.pure`. **Do not carry this zero
  to a road test on someone else's corpus** — that is the error §10.5 of the swift.org
  findings names, a census's zero being read without its corpus list.

`corpusHasNoModuleState` pins the population at zero and **fails the day a
module-level `var` lands**, which is the notification a comment would not give: at
that moment the asymmetry stops being theoretical and this census must be re-taken.

### What would reopen it

- **A file-scope `var` appearing in `Sources/`.** The guard fires; re-take the base
  rate before assuming it is still zero.
- **A road test on a corpus that has global mutable state.** The exposure is
  unmeasured *there* and this document cannot speak to it.
- **The closure path regressing.** If `refuteIfCaptured` stopped refuting, the
  asymmetry would close from the wrong side — the two paths would agree by both being
  unsound. `OwnershipPremiseCensusMeasuredTests.closureOracleRefutesCapturedMutation`
  is the guard for that direction.

---

# The cross-corpus arm — the standing instruction, discharged

> **Status:** `measured` · **As of:** 2026-08-19 · harness
> `ModuleStateCorpusCensusMeasuredTests` (`…+Corpora.swift`), `make batch2`

The home arm above closed with an instruction: ***"Do not carry this zero to a road
test on someone else's corpus."*** Nobody carried it anywhere, which is the same
thing — the zero simply sat as the only measured answer for two days. This arm runs
the identical detector over the **17 corpora `CorpusManifest` resolves**, so the
question moves from *does this package exhibit the shape* to *does the shape exist in
Swift as written*.

## The answer

**The base rate is 5 of 20,526 functions — 0.024% — and all five are in
`swiftlang-swift`.** Sixteen of seventeen corpora measure zero.

| | |
|---|---|
| corpora scanned | 17 (4 absent from this machine, 1 resolved-but-empty, both listed in the run) |
| functions | 20,526 |
| **stored** file-scope `var`s | **17** — 15 of them in `swiftlang-swift` |
| computed file-scope `var`s | 118 — **not module state**, see below |
| false `.pure` (writes a global) | **5** |
| touching a global but already refuted | 4 |
| member-call-only surface | 0 |

## The denominator was 87% wrong, and only a hand-check found it

The first run of this arm reported **135 file-scope `var`s**. 86 were
swift-foundation's, and every one is a *computed* platform shim:

```swift
internal var CLOCK_REALTIME: clockid_t { ... }
internal var _hexCharsUpper: ClosedRange<UInt8> { UInt8(ascii: "A") ... UInt8(ascii: "F") }
```

A constant wearing `var` because Swift has no other spelling for a computed global.
The finding count was unaffected — you cannot assign to a getter-only `var` — but a
reader computing *"5 of 135 globals are mishandled"* off that table would have quoted
a ratio whose denominator was overwhelmingly constants. The real figure is **5 findings
against 17 stored globals**, and the two numbers describe different worlds.

`FileScopeVarCollector` now reports `storedNames` and `computedNames` separately. The
union is still what writes are matched against, deliberately: **a computed `var` with
a setter is a real write target**, and one of the five findings arrives by exactly
that route. The obvious implementation — `accessorBlock == nil` — is wrong in the
flattering direction, because `var counter = 0 { didSet { … } }` is stored mutable
state carrying an accessor block; `storedAndComputedAreSeparated` asserts that case
rather than assuming it.

## All five hand-checked — 5/5 true positives, two for a weaker reason than the detector gave

Every census in this repo that skipped the hand-check got its first answer wrong (the
fixpoint census: 61% false). These were read in full:

| finding | write | verdict |
|---|---|---|
| `BridgeObjectiveC.swift:_connectOrphanedFoundationSubclassesIfNeeded` | `_orphanedFoundationSubclassesReparented = true` | **true** — direct assignment to a stored global |
| `EmbeddedRuntime.swift:_ensureErrorMetadataInitialized` | `_errorMetadataInitialized = true`, +2 more | **true** — textbook lazy-init of module state |
| `EmbeddedRuntime.swift:swift_allocEmptyBox` | `Builtin.addressof(&_emptyBoxStorage)`, then `swift_retain` | **true**, weaker reason — the detector fires on the `&`; the mutation is the refcount bump *through* the pointer |
| `EmbeddedRuntime.swift:swift_allocError` | `&_errorMetadataStorage` | **true**, weaker reason — the `&` is arguably just an address-of; the function mutates because it *calls* `_ensureErrorMetadataInitialized()` |
| `Exclusivity.swift:swift_endAccess` | `Access.remove(head: &accessHead)` | **true** — `accessHead` is a *computed* global whose setter writes exclusivity TLS |

So: **precision 5/5 on the category**, but only three of the five are caught for the
reason the instrument states. Two are true because of what happens one hop away —
which is the `&x` rule being conservative and landing right, not the rule being
precise. Do not read this as a validated 100% detector.

## What this does to the home arm's verdict

It **strengthens it, and refutes one of its predictions.**

The home arm said the shape *"is a fact about this repository, not about Swift"* and
that a codebase with *"a global cache, a shared counter, or a `nonisolated(unsafe)`
singleton would exhibit it immediately."* The first half is now measured **too weak**
and the second half is measured **wrong**:

- Mutable file-scope state is not a swift-infer quirk. It is **near-absent from Swift
  libraries generally** — 2 stored globals across the 16 non-stdlib corpora,
  including swift-collections, swift-syntax, NIO, swift-format, SwiftPM and
  ArgumentParser, none of which produced a single false `.pure`.
- The predicted exhibits did not appear. Not one corpus outside the standard library
  runtime has the shape at all.

Where it *does* appear is `stdlib/public/core` — `@c`, `@_silgen_name`, embedded
runtime, exclusivity TLS. Code implementing memory management, which is the one place
mutable process-global state is the whole point.

**The verdict is unchanged and now better founded: a latent unsoundness with real
exhibits, at a rate too low to justify a refuter.** What changed is that "no exhibits"
became "five exhibits, all in the one corpus where they are unavoidable" — which is a
stronger statement than the zero was, not a weaker one.

## What this arm does NOT claim

**Base rate is not reach.** A hit here is a false `.pure` in the oracle, and that is
checkable. It is *not* evidence that swift-infer would ever ask about these functions
— the tool only runs the oracle over subjects it has picked, and nothing here
establishes that a stdlib runtime entry point would be picked. Those are separate
questions and this measures the second one only, exactly as the soundness-arm reach
census had to say of itself.

**Scope is unchanged from the home arm**, and it is narrower than "global state":
`static`/`Self` writes are refuted elsewhere and would double-count; closures are
skipped as already refuted by `refuteIfCaptured`; only `func` bodies are examined, so
initializers and computed-property accessors are outside the population.

## What would reopen it

- **A corpus with a genuine global cache or singleton.** Sixteen libraries did not
  supply one; an application target might, and this document cannot speak for it.
  `populationIsNonEmpty` guards the direction where the arm goes blind rather than
  the corpora going empty.
- **A stored file-scope `var` landing in `Sources/`** — the home arm's
  `corpusHasNoModuleState` still fires.
- **`universeIsTheManifest` failing**, which means a re-take has quietly narrowed
  back to a handful of corpora and its number means nothing.
