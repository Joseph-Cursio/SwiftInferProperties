# Calibration cycle 108 — A1 verify-evidence spike: two blockers on the measured-execution path for interaction invariants

> **STATUS: INVESTIGATION (no code shipped).** Cycle 108 opened the
> `.likely → .strong` campaign for idempotence via **option A1 — empirical
> verify evidence** (run the generated idempotence tests, harvest
> `.measuredBothPass`, the highest-quality signal for a production-gating
> promotion). The spike found the interaction measured-execution path is
> **not runnable end-to-end today** — two distinct blockers, one a small
> emitter bug, one architectural. Captured 2026-06-14.

## Why A1 (not A0 re-triage)

A `.likely → .strong` promotion unlocks M9 Bridge proposals + M10 drift
warnings in production. Re-triaging the byte-identical 51-identity corpus
three more times (the literal protocol) adds no independent evidence — it
reproduces the same 39 human-accept decisions. A1 instead *executes* the
generated idempotence double-apply tests: `.measuredBothPass` is empirical
proof the property holds under execution, exactly the rung `Tier` reserves
(`.strong` + `.measuredBothPass → .verified`).

## What the spike established

The kit-publication blocker the code comments worried about is **resolved**:
`Package.resolved` pins SwiftPropertyLaws at **2.5.0** (past the `v2.2.0`
the `VerifyInteractionPipeline` comment feared), and the synthesized
verify workdir resolves the full dependency graph cleanly
(swift-property-based 1.2.0, swift-numerics 1.1.1, swift-syntax 600.0.1,
SwiftPropertyLaws 2.5.0). So discovery → pin → stub-emit → `swift build`
*dependency resolution* all work. Two blockers remain past that point.

### Blocker A — stub emitter doesn't qualify nested `State` / `Action` (small bug)

`ActionSequenceStubEmitter` qualifies the reducer *call* by enclosing type
(`makeReducerCall` → `Demo.reduce`) but emits the State/Action *type*
references bare:

- line 64: `stateInit = "\(stateTypeName)()"` → `State()`
- line 126: `\(actionTypeName).self` → `Action.self`

For the universal real-world shape — `State`/`Action` nested in the
reducer type (every TCA `@Reducer`, every HandRolled fixture) — the
generated verifier imports the user module but not the reducer type, so
`State()` / `Action.self` fail with `cannot find 'State' in scope`. This
sat latent because the build+run leg was kit-blocked and never run
end-to-end; first real execution surfaces it immediately.

**Fix sketch + its subtlety.** Qualify by `enclosingTypeName` the way the
reducer call already is — BUT a name-only heuristic ("qualify if the name
contains no dot") mis-handles a reducer *method* that references a
*top-level* state type by bare name (e.g. `Inbox.reduce(_ s: AppState,…)`
→ wrongly `Inbox.AppState`). The existing emitter test fixture
(`enclosingTypeName: "Inbox"`, `stateTypeName: "AppState"`) is exactly this
shape. A correct general fix needs the **discoverer to record whether
State/Action are nested** (or to capture their qualified name), not a
string heuristic in the emitter. Corpus-only scope (all-nested) would work
with the heuristic, but it shouldn't land as a general fix without the
discoverer signal. *Spike fix was prototyped and reverted — not shipped.*

### Blocker B — verifier executable links `Testing.framework`, can't load it at runtime (architectural)

With Blocker A patched locally, the stub **compiles and the binary runs** —
but the outcome comes back `measured-defaultFails` ("trap in reducer body")
on a *total identity reducer that cannot trap*. Root cause: the synthesized
verifier is a plain `@main` executable that transitively links
`@rpath/Testing.framework` (confirmed via `otool -L`) through its
`PropertyBased` / `PropertyLawKit` (kit 2.5.0) dependencies. swift-testing
only loads inside a test-bundle host, so the executable fails at launch
with `dyld: Library not loaded: @rpath/Testing.framework`. The subprocess's
`DYLD_LIBRARY_PATH` injection (V1.53.A) targets `.dylib`s, not a
`.framework` loaded via `@rpath`, so it doesn't help. **The non-zero launch
exit is then misclassified by `InteractionVerifyOutcomeParser` as a Swift
trap → `.measuredDefaultFails`** — a false failure that would silently
poison any measured-evidence run.

This is the real content behind the long-standing
`.architecturalCoveragePending` status — not merely "kit tag unpublished,"
but "the plain-executable verifier architecture is incompatible with the
kit's swift-testing linkage." Resolving it needs one of: (a) a kit-side
product that doesn't drag in swift-testing for the verifier surface; (b)
building the verifier as a test target / bundle instead of an executable;
(c) `DYLD_FRAMEWORK_PATH` + rpath plumbing, if even tractable for a
framework that expects a test host.

## Net + recommendation

A1 is real multi-step work, not a command. Two follow-ups, independently
landable:

1. **Blocker A** — add a discoverer signal for nested vs top-level
   State/Action, then qualify in the emitter. Small, well-scoped, and
   correct-by-construction once the signal exists. A regression test
   should assert `Demo.State()` / `Demo.Action.self` for a nested
   candidate and bare names for a top-level one.
2. **Blocker B** — decide the verifier-architecture fix (likely kit-side).
   Until then, **no measured interaction evidence is obtainable**, and the
   parser's trap-vs-load-failure misclassification should be hardened so a
   dyld launch failure never reports as `.measuredDefaultFails`.

Until Blocker B is resolved, the `.likely → .strong` campaign cannot run on
empirical evidence. Options for the user: pursue the two fixes above as
their own cycles; or fall back to A0 (re-triage, weak evidence) / option B
(corpus expansion) for the `.strong` track. **Idempotence remains `.likely`
(v1.115.0); this spike changed no shipped behavior.**

## What's next

| Item | Where |
|---|---|
| Blocker A fix (discoverer nested-type signal + emitter qualification + test) | new cycle |
| Blocker B decision (verifier architecture vs swift-testing linkage) | needs design call, likely kit-side |
| Parser hardening (dyld launch failure ≠ reducer trap) | bundle with Blocker B |
