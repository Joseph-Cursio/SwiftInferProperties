# SwiftInferProperties — v1.58 Performance Baseline (Phase 2; eighth gap-closing cycle; TypeShape scaffold opening)

PRD v1.0 §13 mandates that "a 25% regression in any number fails the build."

**Captured:** 2026-05-13 against the V1.58.A + V1.58.B commit. v1.58
ships the TypeShape scaffold opening (OrderedSet binding) +
methodology guard + cycle-55 measurement + standard closeout.

**Discover-pipeline impact: none.** v1.58 introduces zero discover-
side changes. The §13 discover budgets stay unchanged from v1.41-v1.57.

**Test-suite measurement (non-subprocess fast path):** **2406 tests**
passing across **335 suites** in **~4 seconds** when running
`swift test --skip VerifyPipelineIntegrationTests`.

**Test count +3 vs v1.57** (2403 → 2406). Breakdown:
- V1.58.A added 1 test (`orderedSetBindsToInt`).
- V1.58.B added 2 tests (`everyBindingMatchesAFixtureCarrier`,
  `intentionalEscapeHatchesAreActualBindings`).

**Per-survey-run cost (V1.58 cycle-55 measurement):** **~4-5 minutes**
wall-clock for the full 103-pick survey via `swift-infer verify
--all-from-index --max-parallel 4` (matched cycle-54). V1.58.A's
binding adds <1ms per pick at the resolver layer; negligible.

Projected v1.59+ cost: minimal change until the v1.59 strategist
recipe lets OC picks reach `swift build`. Once that happens, expect
+5-15 min wall-clock as 29+ new picks compile + run.

**Per-verify-call cost (single suggestion):** **~13-15s cold**
(unchanged from v1.57).

**§13 budget compliance:** all v1.41-v1.57 measurements hold. v1.58
added zero subprocess integration tests; V1.58.A's binding test and
V1.58.B's methodology-guard tests are pure-Swift JSON-parsing.

**Survey wall-clock model (v1.58):**
- `--max-parallel 4` (default): ~4-5 min for the 103-pick cycle-27
  fixture (20 picks reach property check; 0 build-failed; 83 fail
  at resolution → fast).
- Cycle-56 trajectory (v1.59 closes strategist recipe layer for
  OrderedSet<Int>): expect +29 OS picks reaching swift build →
  ~7-10 min wall-clock.

**Phase 2 cycle-55 measurement summary**: **20 / 103 = 19.4%
measured-execution** (unchanged from cycle-54). V1.58 is scaffolding;
no picks closed. Detail-string shift on 29 OS picks confirms the
binding-resolver layer accepts `OrderedSet<Int>`; next-layer gap is
strategist-side generator generation (v1.59 scope).

**V1.58.B methodology guard surfaced 4 latent V1.47.D bindings**:
`Self.Index`, `Self.Element`, `Base.Element`, `Iterator.Element`.
These were added preemptively in V1.47.D for protocol-extension
TypeShapes that don't appear in cycle-27. Documented in
`intentionallyUnmatchedKeys` escape-hatch set with rationale. Going
forward, any new binding key that doesn't match cycle-27 + isn't in
the escape hatch fails the guard pre-merge.

**Pre-existing test failures caught + fixed**: V1.51.D's `count == 109`
assertion was latent-failing after v1.57's 109 → 103 fixture
rebuild (test passed pre-rebuild; failed post-rebuild; v1.57.0 tag
shipped silently broken). V1.54.B's `OrderedSet == nil` assertion
was broken by V1.58.A's new binding. Both fixed cleanly; methodology
lesson noted in cycle-55 findings (run tests *after* fixture
rebuilds, not before).

**32-pick sample-subset agreement with cycle-46**: unchanged from
cycles 52-54:
- Strict 4-category match: 5/13 = 38%
- Semantic "property holds" match: 13/13 = **100%**

v1.58 baseline is the Phase 2 TypeShape-scaffold-opening reference
point.
