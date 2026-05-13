# SwiftInferProperties — v1.59 Performance Baseline (Phase 2; ninth gap-closing cycle; second TypeShape scaffold step)

PRD v1.0 §13 mandates that "a 25% regression in any number fails the build."

**Captured:** 2026-05-13 against the V1.59.A + V1.59.B commit. v1.59
ships the strategist-side OrderedSet<Int> recipe + double-qualifier
fix + reclassification pattern extensions + cycle-56 measurement +
standard closeout.

**Discover-pipeline impact: none.** v1.59 introduces zero discover-
side changes.

**Test-suite measurement (non-subprocess fast path):** **2412 tests**
passing across **335 suites** in **~4 seconds**.

**Test count +6 vs v1.58** (2406 → 2412):
- V1.59.B added 4 reclassification-pattern tests (`matchesNoExactMatchesInstance`,
  `matchesCompilerCrash`, `matchesConformanceRequirement`,
  `renderStripsQualifierPrefix`).
- Plus 2 supporting tests (precedence + alternative-stream coverage).

**Per-survey-run cost (V1.59 cycle-56 measurement):** **~10-12 minutes**
wall-clock for the full 103-pick survey — substantially longer than
cycle-55's ~5 min. **The increase reflects 26 OS picks now actually
running `swift build`** instead of failing fast at resolution. Each
compile-then-fail cycle adds ~10-15s; 26 × ~12s ≈ 5 min extra.

Projected v1.60+ cost: similar ~10-12 min baseline. Once mutating-
method emission lands and OS picks reach the property check, expect
+5-10 min as the property-check loops run (100 trials per pick on
21 newly-running picks).

**Per-verify-call cost (single suggestion):** **~13-15s cold**
(unchanged at the resolver layer). For OS picks now compiling,
add ~10-15s for the swift build step.

**§13 budget compliance:** all v1.41-v1.58 measurements hold. v1.59
added zero subprocess integration tests; V1.59.B's tests are pure-
Swift Substring matches.

**Survey wall-clock model (v1.59):**
- `--max-parallel 4` (default): ~10-12 min for the 103-pick cycle-27
  fixture. 26 OS picks now compile + fail at instance-method shape;
  77 picks fail at resolution → fast.
- Cycle-57 trajectory (v1.60 lands mutating-method emission): expect
  21 instance-method-shape-not-supported picks to actually run the
  property check; +5-10 min for the property-check loops; total
  ~15-22 min wall-clock.

**Phase 2 cycle-56 measurement summary**: **20 / 103 = 19.4%
measured-execution** (unchanged from cycle-55). v1.59 ships the
second TypeShape scaffold step; aggregate counts identical to
cycle-55, but the **detail-string distribution shifts substantially**:
26 OS picks moved from `unsupported-carrier:OrderedSet<Int>` (resolver
layer) to `instance-method-shape-not-supported` (21), `internal-api-
not-accessible` (3), `carrier-missing-required-conformance` (2). 3 OS
picks remain at the resolver layer (likely dual-style-consistency
taking a different code path).

**Critical: `.measured-error = 0` baseline preserved across the
scaffold transition.** V1.59.A's reclassification pattern matcher
absorbs the new error categories cleanly.

**Bug discovered + fixed during cycle**: indexer-produced
`primaryFunctionName` carries a type-qualifier prefix for some picks
(`OrderedSet.sort()`) but not others (`exp(_:)`). The resolver was
producing `OrderedSet.OrderedSet.sort` (double-qualified). Fix in
`CallExpressionShape.render` strips the `<typeQualifier>.` prefix if
present. Regression-pinned by V1.59.B.

**32-pick sample-subset agreement with cycle-46**: unchanged from
cycles 52-55:
- Strict 4-category match: 5/13 = 38%
- Semantic "property holds" match: 13/13 = **100%**

v1.59 baseline is the Phase 2 second-scaffold-step reference point.
