# How often is a module-state mutation judged pure?

> **Status:** `measured` · **As of:** 2026-08-17

Re-derivable at any time — `ModuleStateCensusMeasuredTests` *is* the harness, and
`make batch2` runs it.

**Measured: the base rate is ZERO, and it is zero because this corpus declares no
file-scope `var` at all.** The asymmetry is real; it has no victims here. That makes
it a **latent unsoundness**, which is item 40's result and must be reported as item
40's was — not as a defect, and not as a clean bill of health either.

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
