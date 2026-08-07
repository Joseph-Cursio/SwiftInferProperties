# Project overview (`swift-infer report`, V1.149)

A read-only, one-glance overview of what the tool knows about a project —
folding the SemanticIndex (algebraic + interaction), the measured-verify
evidence, and the cross-type insights into a single status view. Reads only;
never writes.

```
swift-infer report [--directory <root>] [--index-path <p>]
```

## What it shows

- **Algebraic surface** — total properties, tier breakdown
  (Verified/Strong/Likely/Possible), and a by-template count.
- **Interaction surface** — total invariants, tier breakdown, and a by-family
  count (idempotence / referential-integrity / cardinality / …).
- **Measured verify** — from `verify-evidence.json`, the four-bucket tally
  (Proven / Disproven / Unverifiable / Inconclusive); prompts to run
  `verify --all-from-index` when there's no evidence yet.
- **Cross-type structure** — the `insights` groups (types sharing an algebraic
  shape) at Strong/Likely.

Each section degrades gracefully to a "none" line, and a footer points at the
detail commands (`query` / `insights` / `prove-then-show`).

## Example

```
SwiftInfer report  (index updated 2026-07-08T18:40:57Z)

Algebraic surface — 4 properties
  Likely 4
  by template: associativity 2, commutativity 2

Interaction surface — 9 invariant(s)
  Likely 3 · Possible 6
  by family: determinism 3, idempotence 3, unknown-action-is-no-op 3

Measured verify — no evidence yet (run `swift-infer verify --all-from-index`)

Cross-type structure — none (need ≥2 types sharing a Strong/Likely shape)

Detail: `swift-infer query` · `insights` · `prove-then-show`
```

## Dogfood — attaswift/BigInt (2026-07-08, clean)

Validated on a real, independent package. `report` composed correctly with no
fix warranted (like the swift-system / SwiftEffectInference clean-precision
dogfoods): **Algebraic surface — 51 properties** (`Strong 1 · Likely 3 ·
Possible 47`, by-template breakdown), **Interaction surface — 6** (all
Possible), **Cross-type structure — none** (BigInt's structure sits at
Possible, below the Strong/Likely insights gate). The standout is that the
**Measured verify** section is *honest about the constructibility wall*: after
a verify run it read `51 record(s) — Proven 0 · Disproven 0 · Unverifiable 51`,
faithfully surfacing that the engine found 51 properties but could test none
(`BigUInt`/`BigInt` aren't constructible carriers) — never a misleading "0
problems".

Known limitation (not a bug): the Measured-verify section counts the flat
`verify-evidence.json` log, which on BigInt is all algebraic; the 6 interaction
invariants would need `verify-interaction --all` for evidence, so 51 ≠ the full
57 picks. The section doesn't split evidence by surface — fine for a one-glance
overview.

## Files / tests

- `ReportRenderer.swift` (pure: composes the sections from an `IndexStore.Index`
  + `VerifyEvidenceLog` + `[InsightsGroup]`), `ReportCommand.swift` (loads the
  stores + computes insights). Tests: `ReportRendererTests` (2).
