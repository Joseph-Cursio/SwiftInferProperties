# What did three days of fixes buy? The funnel, re-run

> **Status:** `measured` · **As of:** 2026-09-19

**Third run of the corpus pipeline walk**, repeating
[2026-09-16](corpus-funnel-census-2026-09-16.md)'s pipeline on the same 19 repositories.
Harness: `scripts/corpus_funnel.py` + `scripts/corpus_funnel_stage5.py` — **committed this time**,
unlike the two before it. Census binary: SwiftInferProperties `24270a1f`, one binary for all 19.

> **Answer: passing laws more than doubled, 67 → 150, and compiles rose 183 → 219 while stubs
> FELL 980 → 924.** Fewer stubs, more of them compiling, far more reaching a pass — which is the
> shape the shipped work predicts: gates withdrawing rows, emitter fixes making the survivors
> build, and SwiftPropertyLaws 4.7.0 clearing every stateless struct.

## The funnel

| stage | 14 Sep | 16 Sep | **19 Sep** | vs 16 Sep |
|---|---:|---:|---:|---:|
| named seeds | 2,716 | 2,723 | **2,730** | +7 |
| any law proposed | 2,079 | 2,080 | **1,915** | −165 |
| refutable law proposed | 1,010 | 1,019 | **937** | −82 |
| stub file written | 309 | 980 | **924** | −56 |
| **stub compiles** | 92 | 183 | **219** | **+36** |
| **law passes** | 71 | 67 | **150** | **+83** |

**All six stages are measured from one run.** The first version of this census captured only four
and said so; the middle two are now read from `seed-index.json`, one entry per suggestion with its
`templateName` and a `path:line` location, joined on `(file, line)` like every other stage.

**The whole funnel moves in one direction and it is the predicted one**: fewer laws proposed, as
the gates withdraw rows — generic functions (#497), subset names (#476), involution, availability
— fewer stubs, and yet *more of them compiling* and *more than twice as many passing*. The drops
upstream are the deliberate ones.

**`refutable` reproduces the 16 September census exactly on every repository that could be
checked**: SwiftMarkdownWiki 26, SwiftCloneDetector 15, MacCloud_server 6, SwiftIdempotency 6 —
subjects the parser was not tuned against.

⚠ **837 of 924 stubs were measured.** 68 are blocked by subject-side dependency conflicts and 19
returned no verdict (below). Neither is counted as a failure.

## Where the movement is

| repo | stubs | compiles | passes | 16 Sep (stub/comp/pass) |
|---|---:|---:|---:|---|
| SwiftProjectLint | 434 | 31 | **30** | 434 / 31 / 19 |
| pbt-book | 134 | 74 | **43** | 108 / 68 / 4 |
| SwiftAssist | 77 | 34 | **26** | 78 / 27 / 18 |
| SwiftPropertyLaws | 45 | 22 | **20** | 52 / 20 / 7 |
| SwiftLintRuleStudio | 41 | 15 | **12** | 56 / 3 / 2 |
| SwiftMarkdownWiki | 35 | 11 | 9 | 34 / 10 / 7 |
| SwiftEffectInference | 33 | 5 | 3 | 32 / 5 / 0 |

**The load-bearing row is SwiftProjectLint: 434 stubs and 31 compiles, both IDENTICAL to
16 September, and passes 19 → 30.** Same subject, same counts at every stage that should not have
moved, more laws passing at the one that should. That is what separates a real improvement from a
different harness measuring differently — and it is why the seeds/named columns are quoted
alongside: they reproduce the previous census across every repository.

## What is not measured, and why

| repo | stubs | reason |
|---|---:|---|
| SwiftUMLStudio | 43 | kit 2.x vs a library-code pin of swift-property-based 1.x |
| pbt-workbook-corpus | 20 | same |
| pbt-workbook-sampler | 4 | same |
| pbt-workbook | 1 | same |
| **SwiftFormatRuleStudio** | **19** | **no verdict — the test process hangs before any test reports** |

The four dependency conflicts are the limit the 16 September census recorded and deliberately
left standing; they were worth 2 compiles there, so the comparison is close to like-for-like.

### ⚠ Two wrong instruments on the way to the middle stages

The first attempt parsed `discover --interactive` output, and it could not have worked:
interactive triage never shows a determinism-only seed, so *any law proposed* came back EQUAL to
*refutable law proposed* on every repository. Its location regex also matched paths in
surrounding prose, so a transcript with four `Template:` blocks yielded fifteen locations —
**which happened to equal the published figure for that repository.** Agreeing with a known answer
for the wrong reason is worse than disagreeing with it, because nothing prompts a second look.

The "validation" run that followed read STALE result files, because `zsh` aborts a command on an
unmatched glob and the `rm` never ran. Caught only by checking whether the index files existed.

### ⚠ A product gap this census had to work around

**`index --target` resolves `Sources/<target>` and nothing else.** A manifest may place a target
anywhere via `path:` — SwiftMarkdownWiki uses `path: "SwiftMarkdownWiki"` — and the command then
fails with *no `Sources/` directory*, so that repository contributed **0** to both middle stages
while writing 35 stubs, which cannot both be true. `discover` has `--sources` for exactly this
case; `index` has no equivalent. The harness links the expected directory for the duration and
removes it afterwards, which is a workaround recorded as one.

⚠ **`no verdict` is a claim about the RUN, not about the laws.** SwiftFormatRuleStudio's 19 stubs
compile — 15 of them — and the process then hangs before printing a first test. Recording that as
*0 passed* would assert that 15 laws fail, which is not what was observed. They are excluded from
the pass column rather than counted as zero.

## A pass still means what it meant

**No planted violator was run against any passing law**, in this census or either of its
predecessors. A pass is *no counterexample in the generated domain*, which CLAUDE.md is explicit
is not *the property holds*. The 150 is a yield figure.

## The harness, and why the number cost what it did

Both earlier censuses said their driver was never committed, so each measurement has rebuilt the
thing that measures it. The 16 September rebuild found **eight defects in itself, seven caught by
a number that could not be true**. This rebuild found **around thirty**, and **seven are
byte-for-byte the ones that census recorded**:

- recorded decisions carrying between scan groups, so later groups are offered nothing
- a duplicate dependency declaration
- an unbalanced-paren manifest rewrite
- the toolchain not first on PATH, so stubs carry no `@testable import`
- two repositories measured on a different binary from the rest
- `passed` exceeding `compiled` because the two counted different things
- a run that hangs indefinitely — here diagnosed as SwiftPM's `swiftpm-testing-helper` outliving
  its parent and holding the inherited pipe open, so `capture_output` waits for an EOF that never
  comes

The rest were this rebuild's own, and the instructive ones are the **two documented adjustments
that prose could not convey precisely enough**: *"an existing SwiftPropertyLaws dependency was
replaced by HEAD"* does not say what to do when the dependency is already there at an older pin
(skip was wrong — it must be upgraded), and *"a swift-property-based 1.x pin used only by test
targets was dropped with those targets"* does not say that a general *prune what nothing
references* rule regresses three manifests that parsed a moment earlier.

**That is the argument for committing the harness rather than the argument against.**

## Reproducing

```
python3 scripts/corpus_funnel.py <out-dir> <swift-infer> <SwiftProjectLint CLI> <repo>...
```

Resumable: each repository writes `result-<repo>.json` and is skipped when that file exists.
Per-repository toolchain — Xcode's for the SwiftUI-shaped subjects, swift.org's for the rest —
because `swift-infer` resolves a subject's module by shelling out to bare `swift`, and the wrong
one silently drops every import.
