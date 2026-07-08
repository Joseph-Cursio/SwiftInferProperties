# Prove-then-show (`swift-infer prove-then-show`, V1.144)

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
3. **Show** — classify the live results into four honest buckets.

```
swift-infer prove-then-show --target <T> --corpus-module <T>
            [--max-parallel N] [--budget small|medium|large] [--template <name>]
```

`--corpus-module` is required: the verifier builds against the target's
compiled module to construct carrier values.

## The four buckets

| Bucket | Meaning | Action |
|---|---|---|
| **Proven** | `measured-bothPass` — held under an executed property test | **surface these** |
| **Disproven** | `measured-defaultFails` — execution found a counterexample | drop these (shown with the counterexample) |
| **Unverifiable** | `architectural-coverage-pending` — no generator for the carrier | **NOT tested, NOT a pass** — explicitly separated |
| **Inconclusive** | edge-case advisory / tooling error | needs a look |

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

  Proven 1 · Disproven 1 · Unverifiable 0 · Inconclusive 0

PROVEN — surface these (verified by an executed property test)
  ✓ Level  commutativity  join(_:_:)

DISPROVEN — drop these (execution found a counterexample)
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
