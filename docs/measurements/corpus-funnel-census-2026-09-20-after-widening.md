# What did 42 widenings buy? The funnel, re-run — and one row moved

> **Status:** `measured` · **As of:** 2026-09-20
>
> The **second** run of 20 September: [`corpus-funnel-census-2026-09-20.md`](corpus-funnel-census-2026-09-20.md) is the first, and this repeats it after the widenings it made possible.

**Fifth run of the corpus pipeline walk**, repeating
[2026-09-20](corpus-funnel-census-2026-09-20.md)'s pipeline over the same 19 repositories with
the same harness. Census binary: SwiftInferProperties `bf389d65`, **one binary for all 19**,
51 minutes, no errors.

> **Answer: compiles 553 → 597 and passes 471 → 515, on stubs that fell 915 → 905 — and
> EXACTLY ONE REPOSITORY MOVED.**

## The funnel

| stage | 19 Sep | 20 Sep | **after widening** | vs 20 Sep |
|---|---:|---:|---:|---:|
| named seeds | 2,730 | 2,738 | **2,738** | ±0 |
| any law proposed | 1,915 | 1,921 | **1,921** | ±0 |
| refutable law proposed | 937 | 939 | **939** | ±0 |
| stub file written | 924 | 915 | **905** | −10 |
| **stub compiles** | 219 | 553 | **597** | **+44** |
| **law passes** | 150 | 471 | **515** | **+44** |

✅ **The three upstream stages are identical TO THE DIGIT.** Previous runs moved them by single
digits and called that the instrument check; this one does not move them at all. Widening 42
helpers in one package changes what a *test* can call, not what discovery can see, and the funnel
says so.

## Exactly one row moved

| | stubs | compiles | passes |
|---|---:|---:|---:|
| SwiftProjectLint | 434 → **424** | 251 → **295** | 248 → **292** |
| **every other repository, summed** | 481 → **481** | 302 → **302** | 223 → **223** |

**Eighteen repositories are identical on all three bars, every one to the digit.** All +44 is one
subject, and so is the entire −10 in stubs.

⚠ **That is the concentration warning, arriving as evidence rather than as a caveat.** Every fix
this cycle was built for SwiftProjectLint's shape — SwiftSyntax nodes, visitor classes, and the
helpers those visitors hide behind `private`. The other eighteen are the control, and they did not
move. **597 is what the toolchain reaches on this corpus, not a rate.**

⚠ **Two subjects moved on their own** (SwiftAssist `4fb3451` → `b85be61`, pbt-book `6f77d55` →
`9d0e27b`) and both report identical figures, so nothing here rests on that.

## What went into it

| change | measured |
|---|---|
| a test-local followed to the expression it is bound to | +2 compiles; **54 stubs re-reported their real blocker** ([`receiver-construction-local-inlining.md`](receiver-construction-local-inlining.md)) |
| a verbatim construction ranked above a recovered one | recovers 1 stub the inlining had cost |
| a stub withdrawn where the subject takes an opaque parameter | −10 stubs, 0 compiles lost ([`set-aside-stub-decomposition.md`](set-aside-stub-decomposition.md)) |
| **42 `private` helpers widened in SwiftProjectLint** | **+42 compiles, +42 passes** ([#243](https://github.com/Joseph-Cursio/SwiftProjectLint/pull/243)) |

## ⚠ The last stage did not reconcile, on this run or the one before

`compiled − (passed + failed)` reads **29** on both runs, and nothing printed it. A reader
subtracting found 29 stubs missing and no column to put them in.

| | stubs |
|---|---:|
| passed | 515 |
| failed | 53 |
| **trapped** | **23** |
| **unaccounted** | **6** |
| compiled | 597 |

✅ **23 are CRASHES, and a trap is a third outcome** — the law neither held nor was refuted, the
process died. `run_serially` has returned a `crashed` list all along; the repository-level summary
never summed it. It does now, alongside `hung`.

⚠ **The other 6 are a real loss, counted rather than explained away.** Two causes found:

- **A `consumer-producer` stub is documentation only** and declares no test at all —
  `display_resolve.swift` is nine lines of comment ending *"this is documentation only"*. It
  compiles, because a file of comments always does, and can never report an outcome.
- **Two pbt-book stubs share one `Suite.test` key** (`decode_input_totalityTests.decode_isTotal`),
  so the runner's results dictionary collapses them. That is the collision the runner's own
  docstring says the key exists to prevent — *"keying on the bare name silently collapsed them"* —
  arriving one level up, at the **suite** name.

**Four remain undiagnosed**, all in pbt-book, and are reported as a number rather than given a
cause.

✅ **Recorded per repository, not asserted.** A legitimate third outcome must not end a 50-minute
run. `result["unaccounted"]` is retro-checked against this run's stored records and reports 6,
which is what the hand analysis found.

## A pass still means what it meant

⚠ **Yield rose 9% and bug-finding did not move at all.** The 53 failures are the same count, in
the same repositories, in the same shapes, on both runs. And **all 42 new passes are `predicate`
totality over syntax nodes**, the arm `template-refutation-rates.md` measures at **0 refutations of
102**. What they establish is that these helpers do not crash on realistic Swift.

No planted violator was run against any passing law, in this census or its four predecessors.

## Adjustments, stated

The seed binary is **the one the previous run used**, deliberately: rebuilding it from the widened
subject would change two variables at once. `SwiftPropertyLaws/Package.swift` carries the same
uncommitted test-target removal as the previous run. Stale `.swiftinfer/` caches and one leftover
`Tests/PropertyLawMacroTests/Generated/` — the directory that forced SwiftPropertyLaws to be
re-run last time — were cleared from five trees beforehand; it built first time and reported
45 / 38 / 33 again.

## Reproducing

```
python3 scripts/corpus_funnel.py <out-dir> <swift-infer> <SwiftProjectLint CLI> <repo>...
```
