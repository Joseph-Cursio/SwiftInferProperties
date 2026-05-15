# v1.77 Calibration Cycle 74 — Findings (V2.0.M3: in-process verify path skeleton)

Captured: 2026-05-15. swift-infer at v1.77. SwiftPropertyLaws at v2.2.0 (local, still unpushed).

## Headline

**The verify-interaction surface is online**, end-to-end through
stub emission. v1.76 shipped M2's kit-side `ActionSequenceFactory`;
v1.77 ships M3 — the swift-infer side that consumes it. Four
sub-cycles deliver:

- **M3.A** — `ReducerPurityAnalyzer`: a SwiftSyntax walker that
  classifies a reducer body into `.pure` / `.effectBearing` /
  `.hiddenMutability`. The routing signal between M3's in-process
  path and M8's subprocess path (PRD §7.4 / §4.1).
- **M3.B** — `ActionSequenceStubEmitter`: text-emits the verifier
  `main.swift` source that imports the user's module + PropertyLawKit,
  drives `ActionSequenceFactory.actionSequence(forCaseIterable:)`, and
  runs N action sequences through the reducer. Trap-as-exit-code
  outcome model — clean exit + marker line = no traps; non-zero
  exit or missing marker = something failed.
- **M3.C** — `VerifyInteractionPipeline.runPipeline`: orchestration
  threading M1's `ReducerDiscoverer` + M1.C's `ReducerPin` + M3.B's
  stub emitter. Renders a "stub emitted, harness pending" outcome
  with the stub source verbatim so users can inspect / hand-build.
- **M3.D** — `swift-infer verify-interaction --target X` subcommand
  registered in `SwiftInferCommand.subcommands` alongside
  `discover-reducers` / `verify` / `accept-check`.

Cycle-66's **52/103 = 50.5% measured-execution** carries forward
unchanged — v1.77 still doesn't touch v1 emitter/resolver/carrier
paths.

## What M3.0 ships (and explicitly doesn't ship)

**Ships:**
- Pure code-walking purity classifier with stable rawValues.
- Stub emitter for the two non-effect signature shapes
  (`.stateActionReturnsState`, `.inoutStateActionReturnsVoid`) on
  `.elmStyle` / `.generic` carriers.
- Pipeline orchestration with pin resolution + clear error paths
  (zero match / ambiguous / requires pin / unsupported shape).
- CLI subcommand with `--target` / `--reducer` / `--user-module` /
  `--sequence-count` flags.

**Explicitly out of M3.0** (with rationale in this section):
- The actual **build-and-run loop**. v1.42's `VerifierWorkdir` bakes
  in SwiftPropertyLaws v2.1.0 + PropertyLawComplex deps that
  interaction verify doesn't need. Adapting it to a v2.2.0 + PropertyLawKit
  workdir is straightforward but better landed alongside a real
  kit pin — pinning to v2.2.0 ahead of publication breaks the
  build (see cycle-73 findings). Deferred to **M3.E** (post-kit-
  publication).
- **Invariant checking**. PRD §7.2 step 2 says "checking the
  candidate invariant at each step" but candidate invariants are
  produced by M4–M7 template families. M3 ships fuzz-testing-the-
  reducer ("did it trap?"); M4 will attach the first lifted
  Conservation invariant to the same harness.
- **Trace shrinking + persistence** (PRD §7.5). Land alongside the
  first M4–M7 family that produces real failing traces.
- **Effect-bearing reducers** — `.effectBearing` and
  `.hiddenMutability` purity classes don't route through the
  in-process path at all. M8 ships the subprocess path; the
  `-∞` veto on hidden mutability is a discovery-time signal that
  may eventually feed a `.skipped` decision through the §17
  metrics arc.
- **`.tca` carrier support**. TCA `Reduce { state, action in ... }`
  closures aren't callable via the simple `<Type>.<funcName>(...)`
  shape M3.B emits — they need closure-relative state init that
  requires plumbing the closure source into the synthesized
  verifier. Deferred to M3.E or later.

## Architectural choices baked into M3

**Three open questions settled at scope time:**

1. **What "in-process" means.** Literally running user code inside
   swift-infer's host process would require dlopen / JIT
   infrastructure that's a much larger undertaking. M3 ships
   **compile-once-run-many** instead: synthesize a verifier
   executable, build it once, run it once, let it execute 1k
   sequences inside its own process. PRD §15's 100ms budget is
   achievable because the build cost amortizes over all sequences.
2. **Where the candidate invariant comes from.** The chicken-and-egg
   between M3 (verifies invariants) and M4–M7 (produce invariants)
   resolves by shipping M3.0 *without* invariant checking — outcome
   is "ran cleanly / trapped." Real signal: catches force-unwrap
   traps, array-out-of-bounds, etc. M4 attaches the first real
   invariant predicate to the same harness.
3. **Reuse v1.42 workdir or build new.** v1.42's `VerifierWorkdir`
   is a fit *with a small adapter* — its dep block bakes in
   v2.1.0 + PropertyLawComplex which interaction-verify doesn't
   need. Rather than refactor that today (which adds churn before
   the kit pin lands), M3 ships stub-emission only and lets M3.E
   pair the workdir adapter with the v2.2.0 pin bump.

**One drive-by finding:** SwiftParser leaves `Self.counter += 1`
unfolded as a `SequenceExprSyntax` of `[Self.counter, +=, 1]`
rather than an `InfixOperatorExprSyntax`. SwiftSyntax doesn't run
operator-precedence folding, so the hidden-mutability detector
overrides both `InfixOperatorExprSyntax` (for plain `=`) and
`SequenceExprSyntax` (for compound assignments). Worth knowing
for any future SwiftSyntax-based mutation analysis.

## Test count

**2633 → 2675 (+42):**

- M3.A `ReducerPurityAnalyzerTests` (+13).
- M3.B `ActionSequenceStubEmitterTests` (+14).
- M3.C `VerifyInteractionPipelineTests` (+11).
- M3.D `VerifyInteractionCommandTests` (+4).

§13 budgets unchanged. M3's per-cycle perf-target test
(§15: 1k sequences in <100ms) defers to M3.E when there's a real
build-and-run loop to time against.

## What's next — M3.E and beyond

The natural next-cycle is **M3.E** — pair the kit-tag publication
with workdir/build/run integration. Three deliverables:

1. **Push the v2.2.0 kit tag** (user-action from cycle 73's
   findings).
2. **Bump the repo `Package.swift` pin** to `from: "2.2.0"`.
3. **Add interaction-verify workdir support** — either parametrize
   `VerifierWorkdir.renderPackageSwift` to accept a kit-version /
   product-list, or ship a sibling `InteractionVerifierWorkdir`
   for the new shape. Replace M3.C's "pending harness" rendering
   with the v1.42-shape five-category outcome.

Beyond M3.E:
- **M4** — lift v1's Conservation + Idempotence families to
  reducer carriers. First real invariant checks plumbed into M3's
  harness; first calibration cycle for v2.0 metrics.
- **M5–M7** — the three new families (Cardinality, Referential
  integrity, Biconditional). Each ships at default-`Possible`
  visibility through three calibration cycles per PRD §3.5.

## Artifacts

- v1.77 sources:
  - `Sources/SwiftInferCore/ReducerPurityAnalyzer.swift` (M3.A)
  - `Sources/SwiftInferCLI/ActionSequenceStubEmitter.swift` (M3.B)
  - `Sources/SwiftInferCLI/VerifyInteractionPipeline.swift` (M3.C)
  - `Sources/SwiftInferCLI/VerifyInteractionCommand.swift` (M3.D)
- Prior cycle: `docs/calibration-cycle-73-findings.md` (M2 — kit-side
  ActionSequenceFactory).
- v2.0 PRD: `docs/SwiftInferProperties PRD v2.0.md`.
