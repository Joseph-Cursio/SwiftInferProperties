# Interaction-surface SemanticIndex (V1.141)

Extends the shipped SemanticIndex (PRD §20.1, `swift-infer index` / `query`,
`.swiftinfer/index.json`) — previously **algebraic-only** — to also index the
**interaction surface**: the reducer / MVVM invariant families discovered by
`discover-interaction` (idempotence, referential-integrity, biconditional,
conservation, cardinality, plus the `.redux`-paradigm families). Before this,
none of the v2 interaction work was queryable through the index.

## The two-surface model

The index holds two disjoint row types in one `IndexStore.Index`:

| Surface | Row type | Discovered by | Key columns |
|---|---|---|---|
| Algebraic | `SemanticIndexEntry` (`entries`) | `Discover.collectVisibleSuggestions` | `templateName`, `typeName`, verify shape flags |
| Interaction | `InteractionIndexEntry` (`interactionEntries`) | `DiscoverInteraction.collectSuggestions` | `family`, `reducerQualifiedName`, `stateTypeName`, `actionTypeName`, `predicate`, `moduleName` |

Kept as parallel arrays (not merged) because the column sets are disjoint. The
store bumped to **schema v5** — the new `interactionEntries` key is
`decodeIfPresent` with `[]` default, so v1–v4 index files decode cleanly.

Both share `identityHash` (the `0x` display form; decisions join on the
normalized no-`0x` form), `score`, `tier`, `decision`/`decisionAt`,
`firstSeenAt`/`lastSeenAt`, with the same upsert semantics (preserve
`firstSeenAt`, refresh the rest, keep historical rows).

## CLI

- `swift-infer index --target <T>` — now also runs interaction discovery on
  `Sources/<T>`, joins `interaction-decisions.json`, and writes
  `interactionEntries`. Guarded to the single-target path via
  `IndexInputs.targetName`/`workingDirectory`; `verify`'s whole-`Sources`
  reindex passes neither, so it is unaffected. Interaction-discovery failure is
  caught + warned, never sinking the algebraic index. Summary reports
  `+ N interaction invariant(s)`.
- `swift-infer query`:
  - `--surface algebraic|interaction|all` (default `all`; lenient — unknown
    value warns and falls back to `all`).
  - `--family <name>` — interaction-only filter (excludes algebraic rows).
  - `--tier` / `--decision` / `--min-score` apply to both surfaces;
    `--template` / `--type` are algebraic-only (exclude the interaction surface).
  - Output gains an `Interaction invariants:` section
    (`family | module.reducer | predicate`); `--limit` caps combined output.

## Known limitation — identity is not rename-stable

Interaction identity is `SHA256(family::reducerQualifiedName::predicate)` (the
PRD §7.5 "AST-shape" component is unimplemented on both surfaces). Renaming the
reducer or a State field named in the predicate re-keys the row and **resets
`firstSeenAt`**. This matches the algebraic surface's current behavior; the
accept-reset-on-rename posture is deliberate, not a bug — rename-stable identity
would be its own epic.

## Files / tests

- Core: `InteractionIndexEntry.swift`.
- Store: `IndexStore.swift` (`interactionEntries`, `upsertInteraction`, schema v5).
- CLI: `IndexCommand+Projection.swift` (`buildInteractionEntry`,
  `interactionEntries`), `IndexCommand.swift` (wiring),
  `QueryCommand+Interaction.swift` (`QuerySurface`, `applyInteractionFilters`,
  interaction render), `QueryCommand.swift` (`renderCombined`, surface gating).
- Tests: `InteractionIndexEntryTests`, `IndexStoreInteractionTests`,
  `IndexCommandInteractionEntryTests`, `QueryCommandInteractionTests`,
  `IndexQueryInteractionIntegrationTests` (end-to-end: index → query on a real
  in-process reducer package).
