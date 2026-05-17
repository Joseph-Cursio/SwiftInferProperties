# v1.101 Calibration Cycle 98 — Findings (calibration loop kickoff)

Captured: 2026-05-17. swift-infer at v1.101 / SwiftPropertyLaws at v2.5.0.

## Headline

**First measurement-only cycle of the three-cycle calibration loop proper.** After v1.97 closed the last detector-fix finding and v1.98–v1.100 shipped UI + cross-repo plumbing (interactive triage / kit harness / kit macro), cycle 98 confirms the cycle-7 detection baseline holds unchanged at v1.100 across all three corpora, then ships the methodology artifact that gates the next two cycles' triage work: `docs/interaction-invariant-triage-rubric.md`.

**No detection delta** — cycle-7 baseline (92 reducers, 76 interactions) reproduces exactly at v1.100 across all 11 targets. Cross-repo plumbing cycles v1.98–v1.100 are confirmed detection-neutral.

**The cycle-99 first-acceptance-rate measurement is gated on human triage** of the 76 suggestions via the v1.98 `discover-interaction --interactive` surface — swift-infer cannot fabricate accept / reject decisions. The cycle-98 deliverable is the methodology + the unchanged baseline; cycle 99 is the first cycle with actual acceptance-rate numbers.

## Re-measurement vs cycle-7 baseline

All 11 targets re-measured with `discover-interaction --include-possible` at v1.100. Raw outputs persisted to `docs/calibration-cycle-98-data/`.

### Reducer counts (unchanged from cycle-7)

| Corpus | Cycle-7 | Cycle-98 | Δ |
|---|---|---|---|
| HandRolled (7 fixtures) | 7 | 7 | 0 |
| TCA 1.25.5 (7 examples) | 50 | 50 | 0 |
| TCA 1.0.0 (3 examples) | 35 | 35 | 0 |
| **Total** | **92** | **92** | **0** |

### Interaction counts (unchanged from cycle-7)

| Corpus | Cycle-7 | Cycle-98 | Δ |
|---|---|---|---|
| HandRolled | 18 | 18 | 0 |
| TCA 1.25.5 | 34 | 34 | 0 |
| TCA 1.0.0 | 24 | 24 | 0 |
| **Total** | **76** | **76** | **0** |

### Per-family distribution (unchanged from cycle-7)

| Family | Cycle-7 | Cycle-98 | Share |
|---|---|---|---|
| Idempotence | 55 | 55 | 72.4% |
| Biconditional | 10 | 10 | 13.2% |
| Cardinality | 8 | 8 | 10.5% |
| Referential Integrity | 2 | 2 | 2.6% |
| Conservation | 1 | 1 | 1.3% |

### Per-target detail

```
HandRolled               reducers=7   interactions=18  (9 idem  + 2 card + 4 bicon + 2 refint + 1 cons)
TCA 1.25.5 CaseStudies        =36           =23       (17 idem + 4 card + 2 bicon + 0      + 0)
TCA 1.25.5 UIKitCaseStudies   =3            =5        (4 idem  + 0      + 1 bicon + 0      + 0)
TCA 1.25.5 Search             =1            =0
TCA 1.25.5 SpeechRecognition  =1            =0
TCA 1.25.5 SyncUps            =5            =2        (2 idem)
TCA 1.25.5 Todos              =1            =1        (1 idem)
TCA 1.25.5 VoiceMemos         =3            =3        (2 idem  + 1 card)
TCA 1.0.0  CaseStudies        =31           =19       (16 idem + 1 card + 2 bicon)
TCA 1.0.0  UIKitCaseStudies   =3            =5        (4 idem  + 0      + 1 bicon)
TCA 1.0.0  tvOSCaseStudies    =1            =0
```

The HandRolled per-family counts match the per-fixture design exactly (9 + 2 + 4 + 2 + 1 = 18), confirming the cross-contamination fix (v1.91) still holds.

## New artifact: `interaction-invariant-triage-rubric.md`

The v2.0 analog of `cycle-6-triage-rubric.md`. Per-family accept / acceptAsConformance / reject / skip criteria for all five families (Cardinality, Referential Integrity, Biconditional, Conservation, Action Idempotence). Covers:

- **What the four decisions mean** in terms of the v1.88 `InteractionDecision` enum + how they aggregate into the per-family acceptance rate that gates tier promotion.
- **Single-runner triage caveat** — what's in vs out of scope for a first-pass human decision (Effects, multi-rater consensus, runtime execution evidence).
- **Per-family criteria** — for each family, a paragraph of detection context, then accept / acceptAsConformance / reject / skip bullets grounded in concrete reducer-shape examples.
- **Cross-family handling** — when a single reducer fires across multiple families, each suggestion triages independently; M9 Bridge gating remains a separate downstream surface.
- **Skip-rate action threshold** — if a family's `skipped / total` exceeds 30% in a cycle, the next cycle's findings should propose a rubric refinement.
- **Process** — the exact six-step loop each calibration cycle follows.

This is the methodology document the next two cycles depend on. Without it, two human raters would land different accept rates on the same suggestions and the "stable ≥ 70% across three cycles" promotion gate becomes uninterpretable.

## Why no acceptance-rate measurement this cycle

The PRD §17.2 / §19 acceptance-rate metric requires per-suggestion human decisions persisted via `accept-interaction` (or the v1.98 interactive triage). swift-infer cannot legitimately fabricate these — doing so would mean the agent is rating its own output, which by design is what the calibration loop measures *against*. The cycle-98 measurement re-baselines the detector output; cycle 99 is the first cycle with rater decisions in hand.

The realistic cadence:

1. **Cycle 98 (this cycle)** — methodology + unchanged baseline.
2. **Cycle 99** — first triage pass on the 76 suggestions. Persists `.swiftinfer/interaction-decisions.json` for each corpus. Findings doc reports per-family acceptance rates as the cycle's 1st datapoint.
3. **Cycle 100** — second triage pass (or `accept-check-interaction` rerun against cycle-99 decisions, since the corpus is fixed). 2nd datapoint.
4. **Cycle 101** — third triage pass / rerun. 3rd datapoint. Families at ≥ 70% across all three cycles propose tier promotion in the cycle-101 findings doc.

Cycles 99–101 don't need code changes — they're measurement cycles. If any cycle surfaces a rubric gap (high skip rate on a family), the cycle following the rubric refinement resets the three-cycle counter for that family (per the cycle-6 pattern).

## What v1.101 changes

Code-side this cycle is small:

- CLI version bump 1.100.0 → 1.101.0 (continues the per-cycle bump cadence).
- `docs/interaction-invariant-triage-rubric.md` — new methodology doc.
- `docs/calibration-cycle-98-data/` — 22 raw output files (11 `discover-interaction.txt` + 11 `discover-reducers.txt`).
- `docs/calibration-cycle-98-findings.md` — this file.
- CLAUDE.md "Repository state" updates for cycle 98 / v1.101.

No source-code changes. The cross-repo pin stays at SwiftPropertyLaws v2.5.0.

## What's still in flight after v1.101

- **Calibration cycles 99 / 100 / 101** — the three triage cycles described above. Human-in-the-loop dependency.
- **Bridge-level N-arm peer triage** (PRD §9.4 full form, queued from cycle-95) — lower priority; calibration loop has precedence.
- **Real-world TCA dogfooding** on a non-corpus project — lowest velocity, highest signal-per-cycle for cross-cutting UX issues that synthetic corpora don't surface.

## Notes on the version-number cadence

v1.100 → v1.101 continues the SemVer minor-increment pattern from v1.99 → v1.100. Each calibration cycle gets its own version regardless of code delta size — the version-bump is itself the marker that a cycle's findings doc + raw data is the canonical reference for that point in time. SwiftPM handles `1.101.0 > 1.100.0` cleanly via numeric comparison.
