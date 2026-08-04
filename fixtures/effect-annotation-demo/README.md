# effect-annotation-demo

The toolchain's worked example of SwiftIdempotency's **effect vocabulary** reaching
`swift-infer` — the `@NonIdempotent` half, which the product source cannot
demonstrate because it does not contain one.

## Why a fixture rather than the repo's own source

Searched on 2026-08-04: **SwiftInferProperties has no truthful `@NonIdempotent`
function.** The owner defines the tier as *"unconditionally non-idempotent —
re-invocation produces additional observable effects (sending email, inserting
rows, publishing events)"*, and every persistence path in this repo is an upsert
or a dedup-add — `VerifyEvidenceLog.upserting` replaces by `identityHash`,
`VerifyCorpus.adding` guards on `dedupKey`, `IndexStore.upsert` keys by hash. The
tool is *designed* to be re-runnable, so nothing here sends, inserts, or
publishes.

That is a finding, not a search failure, and annotating `quoted(_:)` or
`defaultPath(for:)` to fill the gap would have been **false**: both are pure, so
they satisfy the retry-safety definition they would be denying. This fixture
contains the three effects the owner's definition literally names, so the
annotations are true by construction rather than by argument.

Dependency-free on purpose: every annotation uses the `/// @lint.effect`
doc-comment spelling, which needs no dependency on SwiftIdempotency at all.

## What it shows

Two files. `Effects.swift` declares the retry-hostile layer; `Callers.swift`
declares `T -> T` functions that call it. **Nothing in `Callers.swift` is
annotated** — the evidence has to arrive from the callee, one file over, or the
fixture proves nothing.

```
cd fixtures/effect-annotation-demo
swift-infer discover --target EffectDemo --include-possible
swift-infer discover --target EffectDemo --include-possible --resolve-effects
```

| function | no flag | `--resolve-effects` | |
|---|---:|---:|---|
| `normalise` | 35 | **suppressed** | shape-only guess, silenced |
| `canonicalise` | 35 | **suppressed** | second effect, same outcome |
| `normalize` | 75 | **30** | curated verb — demoted, still visible |
| `shorten` | 35 | **35** | CONTROL — calls nothing, untouched |

The four rows are the argument for `-45` rather than a veto weight: a shape-only
guess is silenced, a corroborated law is **demoted and left for a human**, and
the control proves the pass is not simply demoting everything.

## Two traps this fixture fell into first

Recorded because both would have made it measure itself rather than the tool.

1. **The control was a curated verb.** It was called `trim`, which is in
   `IdempotenceTemplate.curatedVerbs`, so it scored 75 while its subjects scored
   35. A control that scores differently from what it controls is not one. Now
   `shorten`.
2. **A doc comment moved a score.** The word "idempotence" appeared in prose on
   `normalize`, and `DocstringPropertyCorroborator` credited it +15 — the row read
   90 instead of 75. The doc comments are deliberately bland now.

Both are the same shape as the defect that produced this whole line of work: the
annotation `/// @lint.effect idempotent` was itself being read as prose and paid
for twice. **Anything written in a doc comment is an input.**

## What it does NOT show

`--resolve-effects` reads only *declared* effects upward — the heuristic
classifier that guesses tiers from callee names is deliberately disabled, so a
callee nobody annotated propagates nothing. And only the retry-hostile direction
travels: an inferred `pure`/`idempotent` is the least upper bound of what a body
calls and says nothing about the caller, so it is discarded rather than turned
into corroboration.
