# Mutation sweep, slice 1 — measured

> **Status:** `measured` · **As of:** 2026-08-08

Runs `docs/plans/mutation-sweep-slice1-scope.md`. The scope's question was **not** "is the
suite good" but "what fraction of survivors are actionable" — the number that decides
whether the mutation layer is worth building.

**Headline: the question is unanswered, and the reason is the finding.** One survivor is
not a rate. The sweep did produce a real, actionable defect and it has been fixed, but
n=1 cannot say whether triage would be affordable at scale.

## 1. Result

`SwiftInferCore`, 107 eligible sites, 30 sampled at seed `20260808`, one mutant at a time:
apply → `swift build --build-tests` → scoped suite → classify → `git checkout --`.
~44s each, ~22 minutes total.

| outcome | n |
|---|---:|
| killed | **26** |
| **survived** | **1** |
| error (did not compile) | 3 |
| apply-failed | 0 |

| operator | killed | survived | error |
|---|---:|---:|---:|
| relational (`<`→`<=`, `>`→`>=`) | 12 | **1** | 0 |
| negation (`if x`→`if !x`) | 8 | 0 | 0 |
| arithmetic (`+`→`-`) | 3 | 0 | **3** |
| boundary (`N`→`N+1`) | 3 | 0 | 0 |

**Mutation score 26/27 = 96%** of compiling mutants.

## 2. Against the frozen prediction

The scope froze four predictions before any mutant existed. Scored honestly:

| # | prediction | outcome |
|---|---|---|
| 1 | **>50% of survivors are equivalent** | **REFUTED** — 0 of 1. But n=1, so this is not evidence either way. |
| 2 | `gen-unreachable` is the second-largest bucket | **not observed** — 0 of 1 |
| 3 | **≥1 real gap in 30** | **CONFIRMED** — exactly 1 |
| 4 | **>60% killed** | **CONFIRMED, and then some** — 87% of all, 96% of compiling |

Two of four confirmed, and the two that failed failed for the same reason: **there was no
survivor population to describe.** Getting prediction 4 emphatically right is what made
predictions 1 and 2 unmeasurable — a suite that kills almost everything leaves nothing to
triage.

## 3. §9 fired, and it is the verdict

The scope named this outcome in advance:

> a **high kill rate with zero survivors** — that reads as "the suite is excellent" and is
> more likely to mean the operator set is too timid or the sampled sites are trivial. If
> that happens, the honest report is that slice 1 measured nothing, not that the suite is
> perfect.

One survivor rather than zero, but the conclusion stands: **the noise rate is unmeasured.**
The go/no-go in §6 is arithmetically satisfiable — actionable survivors are 1 of 1, which
clears the ≥25% bar — and reporting that as **GO** would be a number dressed as evidence.
It is one sample.

## 4. What the operators cost, which is measurable

**3 of 30 mutants (10%) did not compile, all `arithmetic`, all the same cause:** `+` is
overloaded in Swift and a grammar-level swap has no type information.

| site | expression |
|---|---|
| `Refutability.swift:182` | `filtered + dropped` — array concatenation |
| `VariantMarkers.swift:112` | `reference + marker` — string concatenation |
| `SuggestionRenderer.swift:45` | string concatenation |

The site scanner skipped any line containing a quote, which removes string *literals* but
not string or array *variables*. So the arithmetic operator wasted a build on **half its
own sample** (3 of 6). Any real layer needs types, not a regex — which raises the cost of
the "boring operators are cheap" assumption the scope leaned on.

That filter also **biases the sample**: skipping quoted lines skips string-handling code
wholesale, and the surviving sites skew toward comparison and branch logic, which is
exactly what unit tests cover best. The 96% is a score over that biased population, not
over `SwiftInferCore`.

## 5. The one survivor — a real gap, fixed

`InteractionMetricsRenderer.swift:242`, in `anyFamilyExceedsSkipThreshold`:

```swift
if let skipRate = report.bucket(for: family).skipRate, skipRate > threshold {
```

Mutated `>` → `>=`. Adjudicated **real gap**, not equivalent, under §5's rule — an input
distinguishes the two, so `equivalent` is foreclosed:

- the threshold defaults to `0.30`;
- the only test that exercised it used **4 skipped of 5 = 80%**, its own comment reading
  *"well above 30% threshold"*;
- **3 skipped of 10 is an exact witness**: `Double(3)/Double(10) == 0.30` is `true` and
  `> 0.30` is `false`, verified directly rather than assumed.

No randomized generator is involved, so the remedy is a killer test rather than a
distribution fix — the `gen-unreachable` branch does not apply.

**Graduated.** `skipRateExactlyAtThresholdIsNotFlagged` now pins the threshold as
exclusive: it passes on `HEAD` and **fails with the mutant applied**, which is the
negative control that turns the adjudication from a claim into a demonstration.

The defect is small but real: without it, nothing distinguished "exceeds the refinement
threshold" from "reaches it", and the renderer would have flagged a family that merely
reached 30%.

## 6. The killer test was wrong first, and that is worth recording

Its first version asserted `!rendered.contains("30%*")` — no flag asterisk on the row. It
**failed against correct code**, because the overall row renders `**30%**` in markdown and
`"30%*"` matches the bold delimiter.

Two things follow. The assertion had to move to the **footnote**, which is what
`anyFamilyExceedsSkipThreshold` actually drives — the row's asterisk comes from a
*different* comparison (`SuggestionRenderer`-style `rate > $0` at `:205`), so a test
asserting on the row could never have killed this mutant however it was written. And a
mutation-testing workflow will generate assertions against unfamiliar output formats
constantly; substring matching on rendered markdown is a trap the layer would hit
repeatedly.

## 7. Recommendation

**Do not build the layer on this evidence, and do not call this a GO.** Slice 1 was
designed to measure a rate and returned a sample of one.

What a second slice must change, in order of importance:

1. **Type-aware operators.** 10% wasted builds and a 50% waste rate on `arithmetic` alone
   is the clearest measured defect, and it is a `SwiftSyntax` problem this repo is already
   equipped for — the scanner has type information the regex does not.
2. **Sites the suite is less likely to cover.** The quote filter biased toward
   branch logic. Sampling should be stratified over *file* or *coverage*, not uniform over
   grammar hits, or the sweep re-measures the best-covered code every time.
3. **A bigger N, or a subject with known-weaker tests.** 30 mutants over a heavily-tested
   module was always likely to yield few survivors; the scope predicted 87%-equivalent kill
   rates would starve the measurement and it did.

**What slice 1 did establish**, and it is not nothing: the mechanics work end to end
(reversible apply/build/run/revert, 0 apply-failures, clean tree after 30 cycles), the cost
is **~44s per mutant**, and the graduate path — survivor → adjudication → killer test →
permanent guard — has been walked once, in full, with a negative control.

## Reproducing

```
python3 <scratch>/sites.py        # 107 sites, seed 20260808, samples 30
<scratch>/sweep.sh                # apply / build / test / classify / revert
```

The generator and runner were scratch scripts, deliberately not committed: the scope's §7
says slice 1 builds no tool, and committing a regex-based site scanner would invite reuse
of the exact thing §7.1 says to replace. The sample is reproducible from the seed and the
operator table above.
