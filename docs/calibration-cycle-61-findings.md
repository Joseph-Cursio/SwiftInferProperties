# v1.64 Calibration Cycle 61 — Findings (Phase 2 accept-flow integration)

Captured: 2026-05-14. swift-infer at v1.64.

## Headline

**Architecture cycle, not a measurement cycle.** v1.64 ships **Phase 2
accept-flow integration** — the verify pipeline's outcomes now persist
and flow into the user-facing surface. No new full-surface survey was
run; cycle-60's **42/103 = 40.8% measured-execution** carries forward
unchanged (v1.64 touches no emitter, resolver, or carrier path).

The cycle was motivated by `docs/calibration-cycle-60-monotonicity-investigation.md`,
which verify-checked the two cycle-60 pick-closing priorities and found
both to be mirages (Comparable composer closes 0; "17 non-OC generics"
is ~3 genuinely closeable). With no high-yield pick target left, v1.64
pivoted to making the 42 already-measured outcomes *do something*.

## What shipped — five workstreams

| Workstream | Summary |
|---|---|
| **V1.64.A** | `VerifyEvidence` / `VerifyEvidenceLog` / `VerifyEvidenceOutcome` model in `SwiftInferCore` + `VerifyEvidenceStore` loader/writer in `SwiftInferCLI`. A parallel `.swiftinfer/verify-evidence.json` file, schema-versioned, `upserting` by `identityHash` — deliberately *not* a `DecisionRecord` field (orthogonal lifecycles; no schema-v3 migration of the v2 decisions format). |
| **V1.64.B** | The `verify` command persists outcomes. Single `--suggestion` upserts one record; `--all-from-index` survey upserts the batch. Best-effort — a write failure warns but never fails the verify gesture. Survey stdout JSON stream unchanged. |
| **V1.64.B fix** | `identityHash` normalized to the no-`0x` form. B initially keyed on `SemanticIndexEntry.identityHash` (the `0x`-prefixed display form), but `DecisionRecord` and `discover` suggestions use `SuggestionIdentity.normalized`. Caught during V1.64.C scoping, before any consumer was built on the mismatched key — the latent-key-format pattern the methodology guards exist to catch. |
| **V1.64.C** | `discover` annotates each explainability block with its persisted verify evidence — a `Verify:` line between `Sampling:` and `Identity:`, glyph + outcome label + optional detail. Absent evidence renders no line, so existing goldens are byte-identical. |
| **V1.64.D** | `metrics` cross-references evidence against decisions — `MetricsRenderer.evidenceRows` joins by `identityHash`, `render()` appends a `Decision × outcome` table. Feeds the PRD §17.2 question "does verify evidence predict the human decision?" Default walk-up mode only; explicit `--decisions` aggregation skips it (multi-corpus join out of scope). |
| **V1.64.E** | Version bump 1.63.0 → 1.64.0, this findings doc, CLAUDE.md "Repository state" update. |

## The evidence loop, end to end

```
swift-infer verify ──▶ .swiftinfer/verify-evidence.json ──▶ swift-infer discover  (Verify: annotation)
                                                       └──▶ swift-infer metrics   (§17.2 cross-reference)
```

Before v1.64 the verify pipeline's verdict was printed and discarded.
It now persists, keyed by suggestion identity, and surfaces in the two
places a user reads suggestion quality.

## Test count

**2415 → 2461 (+46)** across the cycle:

- V1.64.A: +20 (`VerifyEvidenceTests` 12, `VerifyEvidenceStoreTests` 8)
- V1.64.B: +11 (`VerifyEvidenceRecorderTests`)
- V1.64.B fix: +3 (`normalizedIdentityHash` cases)
- V1.64.C: +6 (`SuggestionRendererVerifyEvidenceTests`)
- V1.64.D: +6 (`MetricsRendererVerifyEvidenceTests`)

Full `swift test --skip VerifyPipelineIntegrationTests` fast path stays
at ~4–6s. No new subprocess integration tests; v1.64 adds no emitter or
verifier-workdir behaviour. §13 budgets unchanged. Perf baseline is a
v1.63 carry-forward.

## V1.64.E — validation on real data

A `verify --all-from-index` survey was run on the v1.64 binary against
the cycle-27 fixture to exercise the full loop end to end:

- **Producer** — produced `fixtures/cycle27-surface/.swiftinfer/verify-evidence.json`:
  103 records, schema v1, well-formed (no-`0x` `identityHash`,
  `swiftInferVersion: "1.64.0"`, ISO8601 `capturedAt`). Outcome
  distribution — 28 bothPass / 8 edgeCaseAdvisory / 6 defaultFails /
  61 architectural-coverage-pending — is **identical to cycle-60**, as
  expected: v1.64 touches no emitter/resolver/carrier path. The file is
  committed as the fixture's v1.64 evidence artifact (parallel to the
  committed `index.json`).
- **Consumer — `discover`** — on a temp package with one matching
  evidence record, the `Verify:` line renders between `Sampling:` and
  `Identity:` with the right glyph + label + detail, and only the
  evidence-bearing block of four is annotated.
- **Consumer — `metrics`** — loads the 103-record evidence file (takes
  the non-empty-log branch) and renders the cross-reference section.

The architecture is confirmed working on real data, not just unit
fixtures.

## Design decisions of record

1. **Parallel file, not a `DecisionRecord` field.** Verify evidence and
   user decisions have orthogonal lifecycles — a suggestion can be
   verified before it is triaged, or triaged without being verified.
   A parallel `verify-evidence.json` keeps them independent and needs
   no migration of the schema-v2 `Decisions` format.
2. **Best-effort persistence.** The verify verdict is the primary
   output; an evidence-write failure warns on stderr but never fails
   the command.
3. **`defaultFails` does not auto-reject.** PRD §3.5 conservative
   posture + "nothing auto-executes": `discover` renders a prominent
   `✗ defaultFails (verify-disproven)` annotation, but the user still
   decides. Auto-rejection would be the Daikon trap in reverse.
4. **No-`0x` normalized `identityHash`.** The canonical cross-file join
   key, consistent with `DecisionRecord` — see the V1.64.B fix above.
5. **Version-stamped evidence.** Each record carries
   `swiftInferVersion`; a future consumer reading evidence from an
   older binary can warn, mirroring the index-staleness pattern.

## What's next (post-v1.64)

The pick-closing game has hit diminishing returns (v1.62 closed 8,
v1.63 closed 1, v1.64 closed 0 by design). Candidate v1.65+ directions:

1. **Verification cache / "Verified" first-class tier** — the v1.51-era
   deferred item; `discover` could re-score or re-tier on verify
   evidence rather than only annotating. The committed fixture
   `verify-evidence.json` is a ready integration anchor.
2. **Monotonicity-emitter rework** — the only remaining real pick target
   (~4 direct + ~6 behind nested-OC scaffolds), but a weak trade per the
   cycle-60 investigation. Budget a cycle deliberately or leave it.
3. **`metrics` per-corpus evidence join** — extend V1.64.D's
   cross-reference to explicit `--decisions` aggregation mode.
4. **V1.42.C.5 deferred** — implicit reindex on demand (carried from v1.42).

## Artifacts

- v1.64 source: `Sources/SwiftInferCore/VerifyEvidence.swift`,
  `Sources/SwiftInferCLI/VerifyEvidenceStore.swift`,
  `Sources/SwiftInferCLI/VerifyEvidenceRecorder.swift`, plus edits to
  `VerifyCommand.swift`, `VerifyCommand+AllFromIndex.swift`,
  `SuggestionRenderer.swift`, `SwiftInferCommand.swift`,
  `MetricsCommand.swift`, `MetricsRenderer.swift`.
- Scoping evidence: `docs/calibration-cycle-60-monotonicity-investigation.md`.
- Cycle-60 measurement (carried forward):
  `docs/calibration-cycle-60-findings.md`,
  `docs/calibration-cycle-60-data/full-surface-summary.md`.
