# Measured-verify architecture (v2 interaction families)

**Status: complete (cycles 110–145). Consolidation doc — captured 2026-06-16.**

This is the single-page reference for how SwiftInferProperties turns a
statically-discovered interaction-invariant suggestion into a
*machine-confirmed* one by **executing** a generated verifier. It
synthesizes the per-cycle findings (`docs/calibration-cycle-1NN-findings.md`)
into one place. For the change-by-change story, read `git log` + those docs.

---

## 1. The loop: discover → verify → fold → promote

```
discover-interaction   →  InteractionInvariantSuggestion (tier from static score)
        │
        ▼
verify-interaction      →  synthesize a SwiftPM workdir with a generated
  (--reducer / --all)       verifier `main.swift`, `swift build`, run it,
        │                   parse the outcome
        ▼
verify-evidence.json    →  one VerifyEvidence record per suggestion identity
        │
        ▼
discover-interaction    →  InteractionVerifyEvidenceScoring folds the evidence
  (re-run)                  into the grade; a confirmed pick renders (Verified),
                            a disproven one is suppressed
```

- **Producer**: `VerifyInteractionPipeline` (SwiftInferCLI) — `resolveAndEmit`
  (pure: discover candidates → pin-resolve → emit stub) + `executeAndParse`
  (`swift build` + run + `InteractionVerifyOutcomeParser`). Evidence is
  written by `VerifyInteractionPipeline+Evidence.swift`.
- **Consumer**: `InteractionVerifyEvidenceScoring.applied(to:evidenceByIdentity:)`
  (SwiftInferCore) — pure, order-preserving fold, run on the discover render
  path before the visibility cut.
- **The generated verifier**: `ActionSequenceStubEmitter` emits a `main.swift`
  that builds a deterministic action-sequence `Gen`, drives the reducer over
  N sequences from a fixed `Xoshiro` seed, and asserts the family predicate.
  Determinism is load-bearing (cycle 118): a byte-stable custom SipHasher
  seeds per `qualifiedName`, so a single confirmed run + a determinism
  guarantee replaces the PRD §3.5 three-cycle calibration (which exists to
  absorb variance the measured path doesn't have).

## 2. Predicate shapes — idempotence is the odd one out

| Family | Predicate (what the stub asserts) | Check shape |
|---|---|---|
| idempotence | `f(f(x)) == f(x)` for a witness action | **post-loop double-apply** (`makePostLoopCheck` → `makeIdempotenceCheck`) |
| conservation | `state.count == state.collection.count` | per-step `precondition` |
| cardinality | `Σ (presentation indicator) <= 1` | per-step `precondition` |
| biconditional | `state.bool == (state.optional != nil)` | per-step `precondition` |
| referential integrity | `state.sel == nil \|\| coll.contains { $0.id == state.sel }` | per-step `precondition` |

The four non-idempotence families all emit a **State-boolean predicate**
checked after each action (`makePerStepCheck`, `ActionSequenceStubEmitter+FamilyChecks.swift`);
idempotence verifies a *single action's* algebraic property via the
double-apply. Building the per-step check once served all four
(cycle 134's headline finding: the path was already family-generic).

## 3. Scoring, tiers, and the Finding-G gate

- **Tier bands** (`Tier(score:)`): `75+` → `.strong`, `40..<75` → `.likely`,
  `20..<40` → `.possible`, else `.suppressed`. `.verified` and `.strong` are
  never returned by score alone.
- **Static initial scores**: idempotence `40` (`.likely`, promoted cycle
  107); the other four `30` (`.possible`).
- **Measured bothPass**: `+50` (`VerifyEvidenceScoring.verifyBothPassWeight`,
  shared with the algebraic fold), tier recomputed, then
  `Tier.promoted(byVerifyOutcome: .measuredBothPass)` lifts `.strong →
  .verified`. So idempotence 40+50=90→verified; the others 30+50=80→verified
  (when un-gated / overruled).
- **measuredDefaultFails** → `.suppressed` (an executed counterexample is not
  a heuristic guess — same precision argument as the algebraic veto).
- **The Finding-G gate** (`InteractionInvariantFamily.tier(forScore:)`):
  cardinality + biconditional carry a `swiftProjectLintDeferral`
  (`mutually-exclusive-presentation-state` / `flag-optional-pair-state`) and
  are **clamped to `.possible` regardless of score**. They detect a
  *representable illegal state* (a SwiftProjectLint refactor smell) that
  holds only 33–50% as a runtime property — often enforced at a UI layer the
  reducer-level test doesn't model.

## 4. The cardinality/biconditional gate-overrule (cycles 135/136/137)

A measured `bothPass` overrules the Finding-G pin **only at full
action-space coverage** (`VerifyEvidence.excludedActionCount == 0`):

- **Why coverage-gated**: cardinality/biconditional failures live in exactly
  the action types Phase B's relaxed exploration *excludes* (`binding`,
  `PresentationAction`, nested `X.Action`). A *partial* bothPass is
  systematically biased toward false-pass. At *full* coverage the reducer
  provably maintains the invariant over its entire action space with no UI
  layer in the loop — sound per-candidate proof.
- **Where**: a measured-evidence-only carve-out in
  `InteractionVerifyEvidenceScoring.gradedForBothPass` — `overruled =
  family.swiftProjectLintDeferral != nil && excludedActionCount == 0` → use
  the *ungated* `Tier(score:)` and disclose the overrule in `whySuggested`.
  The gate (`tier(forScore:)`) is unchanged; **static score alone never
  overrules**.
- `excludedActionCount` (cycle 136) rides on `VerifyEvidence` (optional,
  backward-compatible Codable) and `InteractionVerifyOutcomeParser.Result`,
  stamped for every carrier in `foldPartialExplorationDisclosure`
  (`= ActionSequenceStubEmitter.excludedCaseNames(candidate).count`).

## 5. Phase A/B exploration and the `.tca` carrier (cycles 122–127)

- **Phase A**: payload-free Action enums — full exploration.
- **Phase B** (relaxed partial-exploration, cycle 124 sign-off): explore the
  *constructible* action subset (payload-free + single recognized-raw
  payload via `RawType`), skip non-derivable composition cases, and
  **disclose the excluded set** in the verdict (`explored M of N action
  types (excluded: …)`). A partial bothPass promotes idempotence
  `.likely → .verified` with the annotation; it does **not** overrule a
  gated family's pin (§4).
- **`.tca` carrier**: real `@Reducer` + `@ObservableState` reducers build via
  direct source inclusion + a `ComposableArchitecture` dependency
  (`VerifierWorkdir.interactionTCA`). Composed bodies (multiple `Reduce`
  closures, `Scope`, `CombineReducers`) emit one candidate per closure;
  `DiscoverInteraction.dedupedByStateAndAction` collapses them so the whole
  composed body verifies via `Feature().reduce` (cycles 132/133/144).

## 6. The refint Identifiable gate (cycle 139)

Refint's predicate references `$0.id`, so a non-`Identifiable` element makes
the stub fail to compile. `IdentifiableResolver` (SwiftInferCore, mirrors
`EquatableResolver`) classifies the element type from corpus `TypeDecl`s
(`.identifiable` if it declares `Identifiable` or has a stored `id` member;
`.notIdentifiable` only when *seen* with neither; `.unknown` for external
types). `VerifyInteractionPipeline.runWithInvariant` skips the build on
`.notIdentifiable` and records a disclosed `architectural-coverage-pending`
instead of wasting a doomed build. Conservative: `.unknown` still builds (no
regression).

## 7. Verify-ready corpora

Each family has a checked-in, packaged-at-test-time corpus
(`CorpusPackager.fromSourcesDirectory`) with a fast discovery test + a
`.subprocess` measured test. Every corpus includes a deliberate **false
positive** that only execution disproves.

| Corpus | Family | Carrier | Reducers | Notes |
|---|---|---|---|---|
| `idempotence-survey-corpus/` | idempotence | plain / Elm / TCA-convention | 5 | exact + prefix witnesses; `setBadge` FP |
| `tca-verify-corpus/` | idempotence | real `.tca` | 13 | all composition operators; Int/String/Double/Bool raws; setBadge + hide FPs |
| `conservation-survey-corpus/` | conservation | plain | 4 | lockstep + recompute; increment-/clear-without-reset FPs |
| `cardinality-verify-corpus/` | cardinality | real `.tca` | 5 | Bool + Optional indicators; ≥3-field witness; full/partial/FP split |
| `biconditional-verify-corpus/` | biconditional | real `.tca` | 5 | annotated + literal-inferred Bool; both drift directions |
| `refint-verify-corpus/` | refint | real `.tca` | 5 | `[T]` + `IdentifiedArrayOf`; non-Identifiable gate case |

**Corpus hygiene** (see `verify-corpus-action-name-gotcha` memory): a
single-family fixture's Action names must dodge the idempotence witness
vocabulary (exact + `set*`/`select*`/`show*`/`present*` prefixes); cardinality
needs ≥2 presentation fields; biconditional stays cardinality-only by using a
non-`Showing`/`Presenting` Bool or all-Optional state.

## 8. The frozen 50.5% measured-execution rate

`52/103 = 50.5%`, frozen since cycle 66 — this is the **algebraic** verify
pipeline (round-trip / idempotence / commutativity / associativity /
monotonicity / dual-style / lifted over the v1 corpus
`fixtures/cycle27-surface/`: swift-algorithms / swift-collections /
swift-numerics / SwiftPropertyLaws), a *different subsystem* from the v2
interaction work above.

**Correction (cycle 147):** earlier revisions of this doc and CLAUDE.md
attributed the freeze to "non-promotable nested-action composition +
non-compilable corpora." That is the blocker for the **TCA interaction
corpora** (`tca-10`/`tca-25`, cycles 119/126) — a *different* corpus. The v1
**algebraic** 52/103 is blocked by **carrier/shape coverage**, not Action
payloads. The 51 unmeasured picks (in
`fixtures/cycle27-surface/.swiftinfer/verify-evidence.json`,
`architectural-coverage-pending`) break down as:

(Counts are the cycle-147 regen-confirmed current-binary classification;
the rate 52/103 reproduces per-identity-identical.)

| Category | Count | Nature |
|---|---|---|
| `unsupported-carrier` | 22 | strategist can't resolve a generator/recipe — split between addressable public types and unconstructible internals/lazy-wrappers |
| `instance-method-shape-not-supported` | 20 | public method (all assoc/commutativity), static call emitted where an instance/mutating call is needed |
| `internal-api-not-accessible` | 9 | the selected symbol is `internal` in an external module — unverifiable by an external verifier |

Of the 22 unsupported-carrier: 9 are `_`-prefixed private stdlib internals
(`_HashTable`, `_HashTable.UnsafeHandle`, `_UnsafeHashTable`), 6 are
lazy-wrapper result types (`EvenlyChunkedCollection`, `ChunkedByCollection`,
`CombinationsSequence`), 6 are real public types missing a recipe
(`OrderedSet<Int>` round-trip ×3, `OrderedDictionary` ×3), and 1 is a local
false positive (`ViolationFormatter`).

**The metric is movable** (cycle 147 finding). The non-public picks (9
`_`-internals + 9 `internal-api`) are false positives by the project's own
high-precision standard — a direct extension of the cycle-54 filter that
already drops `private`/`fileprivate` at scan time. Filtering them shrinks
the denominator honestly (~52/85 ≈ 61%). The **20** instance-method-shape
picks are pure emitter work (the dominant lever → ~85%). Pair/recipe gaps
for the real public types add ~6 (~92%). The lazy-wrapper/local FPs are a
cheap filter (~100% of the legitimate denominator). See the cycle-147
decision record for the sized levers A–D.

## 9. Tooling

- **`Makefile`**: `make test` (fast suite + 4 sequential subprocess
  batches), `make test-fast`, `make batch1..4`, `make clean-temp`,
  `make help`. `.NOTPARALLEL` so batches never run concurrently.
- **Fast path**: `swift test --skip 'MeasuredTests|MeasuredExecutionTests|VerifyPipeline'`
  — one regex covering all 16 `.subprocess` suites (don't enumerate names; an
  incomplete list silently runs the heavy suites — cycle 145 forensics).
- **Temp-disk caution**: each `.tca` verify build resolves
  swift-composable-architecture (multi-GB); a subprocess suite killed
  mid-run skips its cleanup `defer` and leaks those workdirs to `$TMPDIR`.
  `make clean-temp` clears them. Run via batches, not a bare full
  `swift test`, to bound peak disk + dodge the §13 perf-budget contention.

## 10. What's complete / what's open

**Complete**: all five interaction families have a demonstrated
measured-verify path (idempotence c118, conservation c134, cardinality c136,
biconditional c137, refint c138); the gate-overrule (135/136), refint
Identifiable gate (139), and corpus widening (140–144) shipped; tooling +
code-health (145) done; full suite green (3200 fast + 33 subprocess).

**Active epic (cycle 147+)**: moving the frozen algebraic 50.5% (§8) via
levers A (non-public-carrier filter), B (instance/mutating-method emitter),
C (pair/recipe gaps) — projected ~78%. See
`docs/calibration-cycle-147-findings.md`.

**Open, off the critical path**: the shelved value-generator (c119) and
`.tca` C1 reducer-slice extractor (c126) — both belong to the *TCA
interaction* corpora, not the v1 algebraic metric.
