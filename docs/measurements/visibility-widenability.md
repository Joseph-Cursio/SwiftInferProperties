# What would widening access actually buy?

> **Status:** `measured` · **As of:** 2026-08-21

Harness `CatalogHealthCensusMeasuredTests.visibilityCensus`, `make batch8`. A third
reading of that suite's single scan over the 17 corpora `CorpusManifest` resolves.

**Measured: 883 rows — 16% of all discovery output — would be freed by widening one
access modifier. It is the largest lever measured this cycle. And 87% of the gain lands
in the two templates a hand-check found produce false laws.**

> **Re-taken 2026-08-21.** The first pass read **897 of 6,508** and predates the emitter
> fixes in `criterion-a-unmet-subject.md` §6, which removed 994 spurious rows — 992 of
> them `idempotence`. **Both the lever and the 87% survived; the denominator did not.**

---

## 1. The population

| | rows | share |
|---|---:|---:|
| all discovery rows | 5,514 | |
| **restricted subject** | **2,407** | 44% |
| — `internalOrSPI` | 1,392 | **not blocked** |
| — **`notVisibleToTests`** | **883** | **widenable** |
| — `enclosingTypeNotVisibleToTests` | 127 | not widenable |
| — `nestedLocal` | 5 | not widenable |

**`internalOrSPI` is 59% of the restricted set and blocks nothing.** A test target using
`@testable import` already reaches `internal`. Counting it as blocked would inflate the
lever by 2.7×, and this is the single easiest way to misread the table.

**Only `.notVisibleToTests` is widenable.** Widening a member of a `private` *type* frees
nothing — the enclosing type still cannot be named — which is `SpeculativeWidening`'s
named trap, and it was live in the code until 2026-08-06 while a doc claimed otherwise.
`nestedLocal` has no caller to widen to.

So **883, not 2,407**, is what a willingness to widen is worth.

---

## 2. It refutes the home-corpus hypothesis it was built to test

The home survey showed five templates with every row behind the visibility wall and
**zero** running — `value-round-trip`, `comparator`, `round-trip`, `input-totality`,
`monotonicity` — against a running set that was 87% `predicate` + `idempotence`. The
reading offered was structural: *small pure total functions live in `private` helpers,
so the most specific templates are the least testable.*

**Measured across seventeen corpora, that does not hold.**

| template | home: ran | 17 corpora: reachable | widenable |
|---|---:|---:|---:|
| round-trip | 0 | **405** | 1 |
| monotonicity | 0 | **146** | 36 |
| input-totality | 0 | 36 | 27 |
| value-round-trip | 0 | 9 | 29 |
| comparator | 0 | 3 | 1 |

`round-trip` looked *entirely* trapped and runs **405** times across seventeen corpora.
The hypothesis was a fact about one syntax-analysis tool whose helpers are nearly all
`private`, and it was flagged as home-corpus-only when stated — **the flag is the only
reason it was measured rather than believed.**

---

## 3. Where the 897 actually lands

| template | blocked | **widenable** | reachable today |
|---|---:|---:|---:|
| predicate | 818 | **403** | 1,022 |
| idempotence | 763 | **367** | 500 |
| monotonicity | 159 | 36 | 146 |
| **value-round-trip** | 40 | **29** | **9** |
| input-totality | 89 | 27 | 36 |
| measure-non-negativity | 192 | 9 | 209 |
| inverse-pair | 84 | 5 | 121 |
| normal-form | 4 | 3 | 13 |
| everything else | — | ≤2 each | — |

**770 of the 883 — 87% — are `predicate` and `idempotence`.** That is the generic head,
already 66% of all output, and `docs/measurements/refutation-hand-check.md` measured its
refutations at **15 of 15 false laws, zero real bugs**. Widening broadly would
manufacture more of the output already measured as uninformative.

**One row is different. `value-round-trip` goes 9 → 38, a 4× increase**, and it is a
specific refutable template rather than a generic one. It is the only place in this table
where widening changes the character of the output rather than its volume.

---

## 4. This predicts the yield the shipped command already measured

`SpeculativeRefactorRunner` — `swift-infer suggest-refactors` — widens on a **copy**,
derives the newly-visible laws, verifies, and surfaces the refactor **only if a law ran**.
Its header records *"Measured 2026-08-04: 14 of 20 widenings gained nothing at all."*

This census explains that 6-of-20: most widenable subjects carry generic laws, and the
runner's own gate is what keeps the failures off the report.

**Widening is also the safest refactor the tool can propose**, and the reason is worth
keeping: the **compiler** guarantees it preserves behaviour. Same symbol, same body, one
keyword — so a verdict on the copy is a verdict on the reader's code. No later refactor
tier can claim that without differential testing.

---

## 5. The recommendation

**Do not widen broadly.** 897 rows is real and 87% of it is noise by an already-measured
standard.

**Use `suggest-refactors`**, which enforces the discipline structurally — it reports a
widening only when a law actually ran.

**Target `value-round-trip` deliberately.** 29 widenings take a specific template from 9
to 38, and it is the one ratio in the table that is worth acting on for its own sake.

---

## 6. What would reopen it

- **A precision measurement on the widened laws.** This counts rows freed, not laws worth
  having. `value-round-trip`'s 29 could be 29 false laws; nothing here says otherwise, and
  the hand-check's 15-of-15 is a warning against assuming.
- **The 175 `enclosingTypeNotVisibleToTests` rows.** Widening the *type* rather than the
  member would reach them. That is a larger edit than one keyword and is unmeasured.
- **A corpus with a wide public surface.** Every corpus here is a library, and app code —
  where `private` is more common and public API thinner — is unrepresented.
