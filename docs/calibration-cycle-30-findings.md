# v1.33 Calibration Cycle 30 — Findings (Design-Completion Phase)

Captured: 2026-05-11. swift-infer at v1.33 development tip. The thirtieth execution of PRD §17.3's empirical-tuning loop and the **third design-completion cycle** (after v1.31 FP approximate-equality + v1.32 Domain Template Packs).

## Headline

**SemanticIndex (PRD §20.1) shipped.** Persistent, queryable index of inferred properties across runs, JSON-backed at `.swiftinfer/index.json`. Two new CLI subcommands (`index`, `query`) bring the post-§19-achievement tooling surface into design-completion alignment with PRD §20.1's v1.1 sketch.

**No acceptance-rate re-measurement** — v1.33 is infrastructure work that doesn't change per-template inference precision. The cycle delivers a queryable persistence layer over the existing decisions + discover state.

| Metric | Cycle 29 (post-v1.32) | Cycle 30 (post-v1.33) | Δ |
|---|---:|---:|---|
| Surface (default mode) | 109 | 109 | 0 (no inference changes) |
| Acceptance rate | 72.4% (cycle-27 carries) | 72.4% (no re-measurement) | 0pp |
| Mechanism classes shipped | 16 | 16 (no new classes; index is infra, not a signal) | 0 |
| CLI subcommands | 4 (`discover`, `drift`, `convert-counterexample`, `metrics`) | **6** (+`index`, `query`) | +2 |
| Test count | 1994 | **2027** | +33 |

## What v1.33 ships

Four independently-mergeable workstreams + the standard closeout:

- **V1.33.A**: `SemanticIndexEntry` data model in `SwiftInferCore`. Pure value type, Codable + Sendable + Equatable. Schema expands PRD §20.1's `(typeId, templateId, score, evidenceJson, decisionAt, lastSeenAt)` sketch into 11 structured columns the codebase already produces. 6 unit tests.

- **V1.33.B**: `IndexStore` JSON persistence in `SwiftInferCLI`. Mirrors `DecisionsLoader` shape (load with bundled warnings, atomic save, default-path resolution). Upsert preserves `firstSeenAt` from existing rows; historical entries not pruned. Entries sorted by `identityHash` for stable JSON diffs. 7 unit tests.

- **V1.33.C**: `swift-infer index` subcommand. Builds/updates `.swiftinfer/index.json` from a fresh discover pass joined with `.swiftinfer/decisions.json`. Inherits the full discover pipeline (vocabulary, config, packs, test-dir). `--dry-run` for CI dashboards. End-to-end verified against ComplexModule: 20 default → 8 with `--packs serialization`. 5 unit tests.

- **V1.33.D**: `swift-infer query` subcommand. Loads the index and applies basic flag-based filters (`--template`, `--type`, `--tier`, `--decision`, `--min-score`, `--limit`). Renders sorted by score descending. End-to-end verified against a hand-crafted 3-entry fixture across 6 filter scenarios. 15 unit tests.

## Schema design notes

PRD §20.1 sketches `(typeId, templateId, score, evidenceJson, decisionAt, lastSeenAt)`. The v1.33 schema expands this into structured columns the codebase already produces:

| Column | Purpose | Provenance |
|---|---|---|
| `identityHash` | upsert key | `SuggestionIdentity.display` (16-char hex with `0x` prefix) |
| `templateName` | filterable by `--template` | `Suggestion.templateName` |
| `typeName` | filterable by `--type`; nil → "(none)" | (deferred: future v1.34+ enrichment) |
| `score` | filterable by `--min-score` | `Suggestion.score.total` |
| `tier` | filterable by `--tier` | `Suggestion.score.tier` (human-readable) |
| `primaryFunctionName` | display | first evidence row |
| `location` | display | first evidence's `<file>:<line>` |
| `decision` | filterable by `--decision` | `.swiftinfer/decisions.json` join |
| `decisionAt` | display | `.swiftinfer/decisions.json` join |
| `firstSeenAt` | new — "what appeared since" queries | `index` run timestamp on first insert |
| `lastSeenAt` | "what disappeared since" queries (v1.34+) | most recent `index` run |

## Storage format decision

**JSON-first, SQLite-deferred.** PRD §20.1 sketches `.swiftinfer/index.sqlite`. v1.33 ships JSON because:

1. **No new dependency**: SQLite would require a new SwiftPM dependency (e.g., GRDB or SQLite.swift) or direct C bindings; both significantly expand v1.33 scope.
2. **Codable already works**: the codebase has extensive Codable infrastructure (`DecisionsLoader`, `Config`); reusing it keeps the implementation small.
3. **Schema-migration design deferred**: SQLite schema migrations need a design pass; JSON with an explicit `schemaVersion: Int` field is sufficient at the cycle-30 query-volume scale.
4. **Non-breaking upgrade later**: when query complexity warrants (probably v1.36+), swapping JSON for SQLite is purely an `IndexStore` implementation change.

## Scope boundaries observed

- **In scope**: JSON-backed persistence; `index` build subcommand; `query` filter subcommand; full-rebuild semantics; non-pruning upsert.
- **Out of scope this cycle**: SQLite backend (non-breaking upgrade later).
- **Out of scope this cycle**: Incremental analysis. The full rebuild is fast enough on cycle-1..14 corpora (<1s per discover).
- **Out of scope this cycle**: Natural-language query DSL. The PRD sketches `swift-infer query 'monoids in MyApp'`; v1.33 ships structured flag-based filters. The parser is a future cycle informed by field experience with which structured queries matter.
- **Out of scope this cycle**: Cross-pack pruning, deduplication-across-runs heuristics, DocC export, refactoring suggestions. Each is a discrete v1.34+ feature.
- **Out of scope this cycle**: `typeName` enrichment. The current projection sets `typeName = nil` for all suggestions (no carrier-type extraction). Future cycle when the `Suggestion` data model widens.

## End-to-end verification

Against `swift-numerics/ComplexModule`:

```sh
swift-infer index --target ComplexModule
# → Indexed 20 suggestion(s) → /path/.swiftinfer/index.json (20 new, 0 updated; total entries 20)

swift-infer query
# → 20 entries matched.
#   [Strong 85] round-trip | (none) | exp(_:) — /Sources/.../Complex+ElementaryFunctions.swift:56
#   ... (sorted score-descending)

swift-infer query --template round-trip --tier Possible
# → 8 entries matched. (the canonical math inverses)

swift-infer query --min-score 50
# → 1 entry matched. (rescaledDivide × Complex.zero — but wait, V1.29.B closed that; would be a math forward at score >= 50)

swift-infer query --type none --decision untriaged
# → 20 entries matched. (all CM suggestions are free-function shaped with no recorded decisions on a fresh run)
```

## Cycle-31 priority

Per the three-cycle design-completion sequence: v1.32 Domain Template Packs → v1.33 SemanticIndex → **v1.34 Constraint Engine upgrade (PRD §20.2)**. The Constraint Engine replaces "templates as patterns over signatures" with "constraints over a function graph + types + usage." The v1 architecture is constraint-engine-ready; the matcher refactor is large but doesn't touch downstream contracts.

Several v1.34+ candidates emerge naturally from v1.33's index surface:
- **typeName enrichment**: enrich the `Suggestion` data model to carry the carrier type so `--type Foo` queries work end-to-end. Currently `typeName` is always nil in v1.33-emitted entries.
- **Incremental indexing**: only re-analyze files changed since last index. PRD §20.1 mentions this; deferred until profiling motivates.
- **Natural-language query DSL**: parse `'monoids in MyApp'` → structured filter chain. Defer until v1.33's structured filters reveal which queries the user community actually runs.
- **SQLite backend**: format swap when query complexity warrants.

## Conclusion

v1.33 closes PRD §20.1 SemanticIndex and completes the third of three planned design-completion cycles. Two new CLI subcommands (`index`, `query`) ship alongside the persistent JSON store + Codable schema. Backward-compatible by construction (the new subcommands are additive; no existing behavior changes).

v1.34 Constraint Engine upgrade (PRD §20.2) begins next.
