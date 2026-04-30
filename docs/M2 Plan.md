# M2 Execution Plan

Working doc for the M2 milestone defined in `SwiftInferProperties PRD v0.3.md` §5.8. Decomposes M2 into six sub-milestones so progress is checkable session-by-session. **Ephemeral** — archive to `docs/archive/M2 Plan.md` once M2 ships and the §5.8 acceptance bar is met (mirroring M1).

## What M2 ships (PRD §5.8)

> Commutativity, associativity, identity-element templates; project configuration (`.swiftinfer/config.toml`); pluggable naming vocabulary (§4.5) loaded from `.swiftinfer/vocabulary.json`.

Three new templates plus two new file-driven configuration surfaces. **Sampling is not part of M2** (deferred to M4 per PRD §5.8) — every M2 template renders with `samplingResult: .notRun`. Algebraic-structure composition (semigroup / monoid / group / semilattice / ring claims aggregated across templates per PRD §5.4) is **not** part of M2 either — that is M7. M2 templates fire individually; the §5.4 cluster logic lands later.

## Sub-milestone breakdown

| Sub | Scope | Why this order |
|---|---|---|
| **M2.1** | `.swiftinfer/vocabulary.json` loader → `Vocabulary` value type threaded through `TemplateRegistry.discover(...)` and template `suggest(...)` entry points. Existing round-trip + idempotence templates extended to consult `inversePairs` + `idempotenceVerbs` alongside their curated lists. | Vocabulary plumbing must land before the new templates so M2.3–M2.5 consume it from day one. M1 templates exercise the loader without introducing new template surface — flushes the data-flow before the new-template work piles on. The TODO comment at `Sources/SwiftInferTemplates/IdempotenceTemplate.swift:21` pointing at "M2" is the explicit hook. |
| **M2.2** | `.swiftinfer/config.toml` loader → `Config` value type for tier thresholds, `--include-possible` default, vocabulary file path. CLI flags continue to win against config (CLI > config > defaults). | Same rationale as M2.1: config plumbing in place before any new template depends on a configurable threshold. Decision deferred to this sub-milestone: hand-parse the minimal TOML subset we need vs. add a TOML dep — see "Open decisions" below. |
| **M2.3** | Commutativity template: binary-op type pattern `(T, T) → T` with `T: Equatable`; curated naming list (`add`, `combine`, `merge`, `union`, `intersect` per PRD §4 / §5.2); anti-commutativity counter-signal (-30 per PRD §4.1) from curated list (`subtract`, `difference`, `divide`, `apply`, `prepend`, `append`, `concat`-family) plus project-vocab `antiCommutativityVerbs`; explainability block per §4.5. | Simplest of the three — single-function template with no new type-flow signals required (anti-commutativity is naming-only). Establishes the binary-op detection pattern reused by M2.4 + M2.5. |
| **M2.4** | Associativity template: same `(T, T) → T` shape as M2.3; **new type-flow signal — reducer/builder usage** (+20 per PRD §5.3) detected at the call-site pattern `xs.reduce(seed, op)` / equivalents; explainability block. | Builds on M2.3's binary-op detection. Only new concept is the reducer-usage type-flow extension to `FunctionScanner` (currently scans for composition and non-deterministic calls; reducer-usage is a new detector). |
| **M2.5** | Identity-element template: binary op `(T, T) → T` paired with an identity-shaped constant on the same type `T` (signature-pattern + cross-function pairing extending M1.4's `FunctionPairing`); **new type-flow signal — accumulator-with-empty-seed** (+20 per PRD §5.3) detected at `xs.reduce(.identity-shaped-literal, op)`; explainability block. | Most complex of the three — extends `FunctionPairing` to pair op + constant on the same type, AND adds the empty-seed type-flow detector. Doing it last means M2.3 + M2.4 have already validated the binary-op machinery and reducer-usage detection. |
| **M2.6** | Validation suite: golden-file tests for the three new templates' explainability blocks (per PRD §18); golden-file additions for vocabulary-extended round-trip + idempotence outputs (proves M2.1 actually flows through to rendered text); §13 perf re-check on `swift-collections` + the synthetic 50-file corpus with all five templates active; vocabulary + config integration tests (project vocab adds for round-trip, config tier-threshold change visible in output). | Validation, not new code. Mirror of M1.6 + M1.7 with vocabulary/config wiring as the new integration surfaces. |

## M2 acceptance bar

Mirroring PRD §5.8 M1 acceptance, M2 is not done until:

a. Every emitted stub for commutativity, associativity, and identity-element has a golden-file test covering the explainability block byte-for-byte; and golden-file coverage for round-trip + idempotence is extended to include the vocabulary-extension path (project vocab match contributing the same +40 / +25 weights as the curated list, surfaced in the rendered "why suggested" trail).
b. The §13 performance budget for `swift-infer discover` (< 2s wall on 50-file module) still holds on `swift-collections` and the synthetic 50-file corpus with all five templates active.
c. `.swiftinfer/vocabulary.json` and `.swiftinfer/config.toml` have integration tests proving the values flow through to scoring + rendering (vocabulary entry adds to score; config-set tier threshold changes which suggestions render).

## Out of scope for M2 (re-stated for clarity)

- **Sampling** (PRD §4.3) — M4. M2 templates render `samplingResult: .notRun`.
- **Algebraic-structure composition** (PRD §5.4) — M7. M2 templates fire individually; no semigroup / monoid / group / semilattice / ring aggregation across templates yet.
- **Contradiction detection** (PRD §5.6) — M3. The contradiction table is not consulted in M2 even though commutativity + anti-commutativity are the canonical contradiction example; the counter-signal naming list at the *template* level is sufficient for M2 precision.
- **`@CheckProperty` / `@Discoverable` annotation API** (PRD §5.7) — M5. Configuration in M2 is file-driven only.
- **`DerivationStrategist` exposed publicly from SwiftProtocolLaws** — still an M3 prerequisite (PRD §21 OQ #4). M2 does not need it.
- **Inverse-pair standalone template for non-Equatable cases** — M7.

## Open decisions to make in-flight

1. **TOML parsing strategy (M2.2).** Two viable paths:
   - **(a) Hand-parse the minimal subset.** Config keys we know we need are small (`thresholds.*` ints, `discover.includePossible` bool, `discover.vocabularyPath` string). A 50-line parser handles them. No dep, no version-pin churn. Risk: every config-key addition is parser work; non-trivial TOML constructs (arrays of tables, inline tables, dotted keys) are forbidden by construction.
   - **(b) Add a TOML dep.** Probably `swift-toml` (LebJe) or similar. Full TOML 1.0 fidelity, future-proof for any config knob M3+ wants. Cost: a new transitive dep on a downstream-of-SwiftInfer-only library, version churn, license review.
   - **Default unless reason emerges:** (a) hand-parse. M2 + M3 + M4 config keys are still likely under 10. Revisit if config grows past that.
2. **Vocabulary-file path resolution.** PRD §4.5 says `.swiftinfer/vocabulary.json` lives at the project root; `discover` is invoked from anywhere. Walk-up-to-`Package.swift` lookup vs. require explicit `--config-root` / `--vocabulary` flag? Default to walk-up, mirroring how `swift build` finds `Package.swift`; CLI flag overrides.
3. **Vocabulary keys not listed in the PRD §4.5 example.** PRD §4.5 lists `inversePairs`, `idempotenceVerbs`, `commutativityVerbs`, `antiCommutativityVerbs`. Associativity + identity-element rely on type-flow signals (§5.3), not naming, so vocabulary.json does **not** need keys for them in M2. Don't over-spec the schema; leave room for M3+ to add keys without breaking the loader (loader treats unknown keys as warnings, not errors).
4. **Tier-threshold config keys.** PRD §4.2 fixes the boundaries (Strong ≥ 80, Likely 60–79, Possible 40–59, Suppressed < 40 / any veto). Should `config.toml` even be allowed to move them? Argument for: project-specific calibration. Argument against: PRD-level constants — moving them defeats cross-project comparability. **Default unless reason emerges:** read-only in M2, the only `[discover]` knob initially is `includePossible` (boolean default false). Revisit if a calibration use case lands.

## New dependencies introduced in M2

- **None mandated.** TOML parser dep (decision 1 above) is the only candidate; default plan is hand-parse, no dep.

## Target layout impact

No new top-level targets. New source files land in existing targets:

```
Sources/
  SwiftInferCore/         # + Vocabulary.swift, + Config.swift  (data model: pure value types)
  SwiftInferTemplates/    # + CommutativityTemplate.swift, + AssociativityTemplate.swift,
                          #   + IdentityElementTemplate.swift
                          # FunctionScanner.swift extended with reducer-usage + empty-seed detectors
                          # FunctionPairing.swift extended for op-and-identity-on-same-type pairing
  SwiftInferCLI/          # + ConfigLoader.swift, + VocabularyLoader.swift; SwiftInferCommand.swift
                          #   threads Vocabulary + Config into TemplateRegistry.discover(...)
Tests/
  SwiftInferCoreTests/         # + VocabularyTests.swift, + ConfigTests.swift
  SwiftInferTemplatesTests/    # + CommutativityTemplateTests.swift, + AssociativityTemplateTests.swift,
                               #   + IdentityElementTemplateTests.swift; existing pairing tests extended
  SwiftInferIntegrationTests/  # vocabulary + config integration tests (M2.6); perf suite re-runs
```

`FunctionScanner` and `FunctionPairing` extensions belong in their existing files — splitting them produces parallel-file pairs that have to be edited in lockstep.

## Cross-cutting per-template requirement (PRD §5.8)

Every template added in M2 ships its §4.5 explainability block populated from matched counter-signals plus the template's known caveats. There is no separate "explainability sub-milestone" inside M2 — each of M2.3 / M2.4 / M2.5 includes its block at template-introduction time, with golden-file coverage closed out in M2.6.
