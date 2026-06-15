# Calibration cycle 139 — refint Identifiable stub-emit gate

**Captured 2026-06-15. v1.130.0** (binary change). The cycle-138 optional
follow-up: make the referential-integrity verify path verify *un-curated*
corpora gracefully. Refint's predicate references `$0.id`, so a
non-Identifiable collection element makes the synthesized stub fail to
`swift build` — pre-139 that surfaced as `architectural-coverage-pending`
only *after* a wasted ~minute-long build. This cycle detects it **before**
building and returns a clean, disclosed skip.

## What shipped

1. **`IdentifiableResolver`** (`Sources/SwiftInferCore/IdentifiableResolver.swift`)
   — a three-valued textual classifier mirroring `EquatableResolver`, built
   from the corpus's `TypeDecl`s. A type is `.identifiable` when a corpus
   decl (primary or extension, merged by name) declares `Identifiable`
   **or** has a stored `id` member; `.notIdentifiable` only when the decl is
   *seen* with neither; `.unknown` for unseen/external types. Conservative
   by construction: the consumer skips only on `.notIdentifiable`, so an
   external Identifiable dependency type (`.unknown`) is never wrongly
   skipped.

2. **The gate** (`Sources/SwiftInferCLI/VerifyInteractionPipeline+RefintGate.swift`)
   — `runWithInvariant` now calls `applyRefintIdentifiabilityGate` after
   `resolveAndEmit` and before `executeAndParse`. For a refint invariant it
   recovers the collection element type (re-running
   `ReferentialIntegrityWitnessDetector` over the candidate's State and
   matching the witness whose `selected`/`collection` property names appear
   in the predicate — the template's `makePredicate` is module-internal),
   classifies it via `IdentifiableResolver` over
   `FunctionScanner.scanCorpus` typeDecls, and — when provably
   non-Identifiable — returns a pre-build `architectural-coverage-pending`
   `Result` with a clear disclosure (`element type \`Note\` is not
   Identifiable (no \`id\` member) — the \`$0.id\` reference … cannot
   compile`). The skip is recorded like any other outcome; the fold treats
   architectural-coverage-pending as score-neutral, so the refint suggestion
   stays `.possible`.

## Why a gate and not a discovery change

Discovery still surfaces the refint witness regardless of identifiability —
"a selection should point to a valid item" is a meaningful *suggestion*
even when it can't be auto-verified. The gate is verify-only: it changes
*how the verify attempt resolves* (clean disclosed skip vs. doomed build),
never *what discovery emits*.

## Proof corpus

`Tests/Fixtures/refint-verify-corpus/` gains **NoteFeature** (element type
`Note` is deliberately NOT Identifiable and has no `id` member), joining the
cycle-138 LibraryFeature (verifies → `.verified`) and CatalogFeature (false
positive → suppressed). The measured survey now splits three ways:

- LibraryFeature → `measured-bothPass` → `.verified`
- CatalogFeature → `measured-defaultFails` → suppressed
- NoteFeature → `architectural-coverage-pending` (gate skip, **no build**) →
  stays `.possible`, disclosure in the survey output

## Verification

- **Fast (Core):** `IdentifiableResolverTests` — 6 tests over the
  three-valued classifier (conformance lift, stored-`id` lift,
  extension-merge lift, seen-but-non-identifiable, external→unknown, trim).
- **Fast (CLI):** `RefIntVerifyCorpusTests` — discovery surfaces all three
  refint identities at `.possible` (discovery doesn't check Identifiable).
- **Measured (`.subprocess`):** `RefIntVerifyCorpusMeasuredTests` (~63s) —
  the three-way split end-to-end; evidence 3 records (1 bothPass / 1
  defaultFails / 1 architectural-coverage-pending); the `Note` disclosure
  rides into the survey summary; discover keeps NoteFeature at `(Possible)`.
- `swiftlint` clean (the gate-handling was extracted to the +RefintGate file
  to keep the pipeline file under `file_length`).

## What's next

The family-coverage arc and its robustness follow-up are both complete: all
five families have a measured-verify path, and refint now handles
un-curated (non-Identifiable-element) corpora gracefully. Remaining items
are all off the critical path and unchanged from cycle 138: corpus widening
(volume, not coverage), and the long-shelved value-generator (c119) /
`.tca` C1 reducer-slice-extractor (c126) items. The frozen 50.5%
measured-execution rate stays a discovery-corpus metric.
