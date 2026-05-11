# v1.39 Calibration Cycle 36 — Findings (Constraint Engine Batch Migration #2)

Captured: 2026-05-11. swift-infer at v1.39 development tip. The thirty-sixth calibration cycle. **Second batch-migration cycle** for the Constraint Engine refactor (PRD §20.2).

## Headline

**3 suggest entry points migrated** (RoundTripTemplate + IdempotenceTemplate non-lifted + IdempotenceTemplate lifted) — counts as **2 template-name migrations** (round-trip + idempotence) plus the first `Constraint<LiftedTransformation>` migration. Constraint API extended with one new field (`additionalWhySuggested`) to support templates that insert per-suggestion narrative between evidence and signal lines.

**Templates migrated: 7 / 10** (at template-name granularity). Lifted variants share the parent template name and the SemanticIndex emits them under a single `templateName`. Counted at code-path granularity (separate `suggest(...)` entry points), v1.39 brings the total to **8 / 13** migrated entry points.

| Metric | Cycle 35 (post-v1.38) | Cycle 36 (post-v1.39) | Δ |
|---|---:|---:|---|
| Surface (default mode) | 109 | 109 | 0 (no inference changes) |
| Acceptance rate | 72.4% | 72.4% (no re-measurement) | 0pp |
| Templates migrated (by name) | 5/10 | **7/10** | +2 |
| Suggest entry points migrated | 5/13 | **8/13** | +3 |
| Test count | 2088 | **2093** | +5 |

## What v1.39 ships

Four workstreams + Constraint API extension:

- **Constraint API extension**: new optional `additionalWhySuggested: @Sendable (Subject) -> [String]` field with default `{ _ in [] }`. ConstraintRunner inserts these lines between the evidence-display lines and the signal-formatted lines in the emitted `whySuggested`. Backward-compatible — the 5 templates migrated in v1.36–v1.38 fall through to the default with no behavioral change. New field is the **first non-defaultable functional change** to the v1.36.A abstraction; necessary to preserve bit-for-bit equivalence on `IdempotenceTemplate+Lifted` whose pre-migration emit inserts `lifted.rationale` at this position.

- **V1.39.A — RoundTripTemplate** (Subject: FunctionPair). 3 runtime inputs. Constant-true gate (pre-migration unconditionally seeded the typeSymmetry signal; the gate reflects that). 2-constant caveats.

- **V1.39.B — IdempotenceTemplate (non-lifted)** (Subject: FunctionSummary). 3 runtime inputs. Gate: `typeSymmetrySignal(for:) != nil`. 2-constant caveats.

- **V1.39.C — IdempotenceTemplate (lifted)** (Subject: LiftedTransformation). **First `Constraint<LiftedTransformation>` migration** — introduces the **third Subject shape** (after FunctionSummary and DualStylePair). Uses the new `additionalWhySuggested` field to insert `lifted.rationale` between evidence and signals.

- **V1.39.D — equivalence tests**. 7 tests across 3 nested suites + a dedicated test verifying that the new `additionalWhySuggested` field correctly inserts `lifted.rationale` between evidence and signal lines in the emitted explainability block.

## Migration pattern stability (4th validation)

After 4 cycles (V1.36 + V1.37 + V1.38 + V1.39) and 8 suggest entry points, the pattern held across:

- **4 runtime-input cardinalities**: 0, 1, 2, 3.
- **3 Subject shapes**: FunctionSummary, DualStylePair, FunctionPair, LiftedTransformation (4 distinct types).
- **4 caveat patterns**: constant, keypath-conditional (InvariantPreservation), FP-conditional (Commutativity, Associativity), carrier-embedded (IdempotenceTemplate+Lifted).
- **One Constraint API extension**: `additionalWhySuggested` field added without disturbing existing migrations.

The extension was discovered late (V1.39.C) rather than designed up-front in V1.36. This is the expected cost of incremental migration — each new template variant surfaces small explainability quirks. Future per-template surprises should be similarly manageable.

## Remaining templates (5 suggest entry points; 3 template names)

| Template | Subject | Runtime inputs | Quirks expected |
|---|---|---|---|
| InversePairTemplate non-lifted | FunctionPair | vocabulary, EquatableResolver, inheritedTypes | New: EquatableResolver runtime input |
| InversePairTemplate lifted | LiftedInversePair | vocabulary, inheritedTypes, EquatableResolver | New Subject shape: LiftedInversePair |
| IdentityElementTemplate non-lifted | IdentityElementPair | opsWithIdentitySeed, inheritedTypes, carrierKindResolver | New Subject shape: IdentityElementPair |
| IdentityElementTemplate lifted | LiftedIdentityElementPair | similar | New Subject shape: LiftedIdentityElementPair |
| CompositionTemplate | LiftedTransformation | vocabulary, carrierKindResolver | Same Subject as Idempotence-lifted |

v1.40 batch-migrates all 5 to complete the 10-template / 13-entry-point refactor. After v1.40 every `suggest(...)` is a 4-line `ConstraintRunner.suggest` wrapper, and v1.41+ unlocks higher-order property composition (PRD §20.2 lookahead) or pivots to the deferred backlog items (dominant-pattern cluster classification, cross-type abstraction discovery, incremental indexing, SQLite backend, etc.).

## Cycle-37 priority

**v1.40 batch-migrate the last 5 suggest entry points** to complete the Constraint Engine refactor.
