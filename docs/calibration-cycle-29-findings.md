# v1.32 Calibration Cycle 29 — Findings (Design-Completion Phase)

Captured: 2026-05-11. swift-infer at v1.32 development tip (`66ef997`). The twenty-ninth execution of PRD §17.3's empirical-tuning loop and the **second design-completion cycle** (after v1.31's FP approximate-equality template arm).

## Headline

**Domain Template Packs (PRD §20.3) shipped.** Splits the monolithic 10-template registry into 5 named domain packs (`numeric`, `serialization`, `collections`, `algebraic`, `concurrency`). Cycles 1–28 were the prerequisite benchmark data the PRD required. **No acceptance-rate re-measurement** — v1.32 is a user-facing surface change that scopes which templates fire; per-template inference precision is unchanged.

| Metric | Cycle 28 (post-v1.31) | Cycle 29 (post-v1.32) | Δ |
|---|---:|---:|---|
| Surface (default mode) | 109 | 109 | 0 (monolithic-default preserved) |
| Acceptance rate (default mode) | 72.4% (cycle-27 measurement carries) | 72.4% (no re-measurement) | 0pp |
| Mechanism classes shipped | 16 | 16 (no new classes; packs are a surface, not a mechanism) | 0 |
| Test count | 1959 | **1994** | +35 |

## What v1.32 ships

Three independently-mergeable workstreams:

- **V1.32.A**: `TemplatePack` enum + pack-to-templates resolver in `SwiftInferCore`. 5 named packs; non-exclusive membership (e.g., `monotonicity` ∈ `{numeric, collections}`). Helpers: `resolve(_:Set<TemplatePack>) -> Set<String>`, `parse(_:String) -> Set<TemplatePack>`, `allTemplateNames`, `unknownPackNames(in:)`. 21 unit tests.

- **V1.32.B**: Optional `templateFilter: Set<String>?` parameter on the three `TemplateRegistry.discover` entry points. Nil filter preserves the monolithic behavior bit-for-bit; non-nil filters post-sort to the allowed templates. 7 unit tests verifying nil-equivalence + resolve(_:) integration + post-filter sort ordering.

- **V1.32.C**: `Discover` subcommand `--packs <comma,separated,list>` CLI flag + `[discover].packs` TOML config (comma-separated string form — MinimalTOMLParser doesn't support arrays in v1). Resolver precedence: CLI > config > nil. Diagnostic warnings for unknown pack names + effective-empty-set surfaces. 7 unit tests + end-to-end verification against swift-numerics ComplexModule.

## Pack groupings (rationale)

Templates were assigned to packs based on cycle-1–28 per-corpus rate evidence:

| Pack | Templates | Calibration anchor |
|---|---|---|
| `numeric` | commutativity, associativity, identity-element, monotonicity | swift-numerics ComplexModule (cycle-25/27 accept rates 100% on `_relaxedMul`/`_relaxedAdd` commutativity + associativity; canonical math monotonicity) |
| `serialization` | round-trip, inverse-pair | swift-numerics math forward/inverse pairs (cycle-25/27 8/8 ACCEPT on `exp/log`, `cos/acos`, etc.) |
| `collections` | idempotence, monotonicity, dual-style-consistency, composition, invariant-preservation | swift-collections OrderedCollections (cycle-17→27 100% rate-stability on sort lifts + form/non-form dual-style) |
| `algebraic` | commutativity, associativity, identity-element, idempotence, composition | algebra-modeling corpora (semigroup/monoid/group/semilattice/semiring laws) |
| `concurrency` | (empty) | aspirational per PRD §20.3 — no current templates target concurrency primitives |

Cross-pack membership (a template can be in multiple packs): `monotonicity` ∈ `{numeric, collections}`; `commutativity` ∈ `{numeric, algebraic}`; `idempotence` ∈ `{collections, algebraic}`; `composition` ∈ `{collections, algebraic}`. This is correct — pack membership describes "useful for codebases of type X," not "exclusively applies to X."

## End-to-end behavior verified

`swift-infer discover --target ComplexModule --include-possible --packs <X>`:

| Flag | Surface |
|---|---:|
| (none — default; all packs) | 20 |
| `--packs numeric` | 12 (6 commutativity + 6 associativity; no id-el survives V1.29.B; no monotonicity surfaces) |
| `--packs serialization` | 8 (8 round-trip canonical inverses; no inverse-pair survives V1.27.B + V1.29.A) |
| `--packs algebraic` | 12 (overlaps with numeric on this corpus) |
| `--packs collections` | 0 (no collection-shaped templates surface on ComplexModule) |
| `--packs concurrency` | 0 (empty pack) |
| `--packs bogus` | 0 + 2 diagnostic warnings (unknown name + effective-empty-set) |

The pack filter is post-discover (templates run as usual; suggestions outside the pack are dropped from final output). This is the simplest semantics with no per-template perf change.

## Scope boundaries observed

- **In scope**: opt-in filter mechanism. Backward-compatible: optional parameter / optional CLI flag defaults preserve the monolithic-registry behavior bit-for-bit.
- **Out of scope**: per-pack signal-weight overrides. Future cycle if empirical evidence shows a template needs different weights per pack.
- **Out of scope**: pack-author API for third-party templates. Adding new templates is still a Sources/ change; v1.32 packs only group existing templates.
- **Out of scope**: pack-aware perf optimization (skipping template invocations). Current implementation runs all templates and filters post-collection. Future cycle if the filter check becomes a measurable cost.
- **Out of scope**: TOML array form. `[discover].packs = ["numeric", "serialization"]` is the natural form but the MinimalTOMLParser doesn't support arrays. Comma-separated string `[discover].packs = "numeric,serialization"` is the pragmatic v1.32 form. TOML array support is a non-breaking upgrade (additive).

## Cycle-30 priorities

Per the three-cycle design-completion sequence agreed upon: v1.32 Domain Template Packs → **v1.33 SemanticIndex (PRD §20.1)** → v1.34 Constraint Engine upgrade (PRD §20.2).

1. **v1.33 SemanticIndex (PRD §20.1)**. Persistent SQLite-backed index of inferred properties across runs. Foundation for cross-run queries ("monoids in MyApp") and integration with §20.2 Constraint Engine.
2. **v1.34 Constraint Engine upgrade (PRD §20.2)**. Replace "templates as patterns over signatures" with "constraints over a function graph + types + usage." The v1 architecture is constraint-engine-ready; the matcher refactor is large but doesn't touch downstream contracts.
3. **Test-execution evidence** (architectural shift) — remains the higher-leverage long-term move; deferred pending design discussion.

## Conclusion

v1.32 closes PRD §20.3 Domain Template Packs and completes the second of three planned design-completion cycles. The 5-pack split is empirically grounded in cycles 1–28 calibration data per the PRD's prerequisite. Backward-compatibility is preserved by default (nil filter = monolithic behavior bit-for-bit).

Three mechanism classes (inverse-pair, identity-element, composition-lifted) remain empty on the cycle-1..14 corpora as of v1.29; the pack split doesn't change that. v1.33 SemanticIndex begins next.
