# Prove-then-show (`swift-infer prove-then-show`, V1.144)

> **Status:** `reference` · **As of:** 2026-07-08


The one-shot **inversion of the conservative default**. Normally `discover`
*hides* `Possible`-tier picks to avoid overwhelming you with false positives.
`prove-then-show` instead **tests** every pick (including `Possible`) and shows
what survives — because execution, not a static score, is the arbiter of truth.

## What it does

Three steps in one command:

1. **Index** the target *with* `Possible`-tier picks included (the whole point
   is to test the low-confidence ones the default view hides).
2. **Prove** — run the measured verify survey over every pick (`verify
   --all-from-index` internally, quietly).
3. **Show** — classify the live results into five honest buckets.

```
swift-infer prove-then-show --target <T> --corpus-module <T>
            [--surface algebraic|interaction] [--max-parallel N]
            [--budget small|medium|large] [--template <name>] [--family <name>]
```

`--corpus-module` is required: the verifier builds against the target's
compiled module to construct carrier values.

**Two surfaces (V1.148).** `--surface algebraic` (default) rides
`verify --all-from-index` over the algebraic picks. `--surface interaction`
rides `verify-interaction --all` over the reducer / MVVM invariant families
(`--family` restricts to one), classifying the same buckets — so a
`.possible` interaction invariant that *passed* execution surfaces, one that
*failed* is dropped, and a reducer that couldn't be constructed lands in
Unverifiable. A shared row-based renderer serves both; the algebraic and
interaction surveys already speak the same 5-outcome vocabulary.

## The five buckets

| Bucket | Meaning | Action |
|---|---|---|
| **Proven** | `measured-bothPass` — held under an executed property test | **surface these** |
| **Expected to hold** | `measured-defaultFails` on a `.likely`-or-better pick, with a counterexample and no partial coverage | **read these first** — and read both readings |
| **Disproven** | `measured-defaultFails` on a lower-confidence pick | a guess that did not survive |
| **Unverifiable** | `architectural-coverage-pending` — no generator for the carrier | **NOT tested, NOT a pass** — explicitly separated |
| **Inconclusive** | edge-case advisory / tooling error | needs a look |

**Expected to hold is a VISIBILITY class, not a verdict about your code**, and the
distinction is measured rather than cautious. `docs/plans/suspected-defect-verdict-scope.md`
§11 scored every signal that might separate *"the guess was wrong"* from *"the code is
wrong"*: the conjecture caveat fires on **14 of 14** refutations on record, defects and
false laws alike, and a body-shape reader would suppress the real defects while keeping the
false law. The distinguishing question is whether the property was ever *intended* to hold,
which is not in the code.

So the section renders **both readings and picks neither**. `fixtures/planted-defect-arm`
holds the measured pair that forces this: at the same tier, in one run, `BlendSummary`'s
`associativity` refutation is a real defect and `PathSegment`'s `commutativity` refutation
is a false law about correct code. Any wording that fits one misdescribes the other.

Tiers come from the index built in step 1, so they are **pre-verify**. When no tier is
available every refutation stays in Disproven — a missing tier must never promote a row
into a section headed *read these first*.

The **Unverifiable** bucket is the honest core of the design: an
un-constructible carrier (see the "non-constructible carrier" notes) can't be
tested, and that must never be mistaken for a clean pass. This distinction only
exists in the *live* survey records — when persisted to `verify-evidence.json`,
`architectural-coverage-pending` collapses to `measured-error` — so the command
runs over the survey results, not the saved evidence.

## Example (the loop working)

A `CaseIterable` enum `Level` with a genuinely-commutative `join` (max) and a
falsely-"commutative" left-biased `combine`:

```
$ swift-infer prove-then-show --target LoopDemo --corpus-module LoopDemo --template commutativity

Prove-then-show — 2 pick(s) tested

  Proven 1 · Expected-to-hold 0 · Disproven 1 · Unverifiable 0 · Inconclusive 0

PROVEN — surface these (verified by an executed property test)
  ✓ Level  commutativity  join(_:_:)

DISPROVEN — a low-confidence guess that execution refuted
  ✗ Level  commutativity  combine(_:_:)   [counterexample: (medium, low)]
```

`join` was hidden at `Possible` by the static default; execution promoted it.
`combine` was shown at `Likely` (the verb "combine" scored +40); execution
disproved it. The command corrects both.

## Bounded by constructibility

On a package whose types aren't in the strategist's generator recipe set (e.g.
`attaswift/BigInt` — `BigUInt`/`BigInt` are neither `CaseIterable` nor
synthesizable memberwise structs), **every** pick lands in Unverifiable
(`unsupported-carrier`), and the command says so plainly rather than implying a
pass. Widening carrier coverage is what moves picks out of that bucket.

## Files / tests

- `ProveThenShowRenderer.swift` (pure classifier/renderer),
  `ProveThenShowCommand.swift` (the subcommand). The survey entry
  (`Verify.runAllFromIndex`) gained a `quiet` flag + a `[SurveyRecord]` return
  so the command can render its own summary; `persistSurveyBatch` split to
  `VerifyCommand+AllFromIndex+Persist.swift` for the file-length cap.
- Tests: `ProveThenShowRendererTests` (5). Verified end-to-end on the `Level`
  corpus (Proven + Disproven live) and on BigInt (all Unverifiable).
