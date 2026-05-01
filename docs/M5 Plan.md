# M5 Execution Plan

Working doc for the M5 milestone defined in `SwiftInferProperties PRD v0.4.md` §5.8. Decomposes M5 into six sub-milestones so progress is checkable session-by-session. **Ephemeral** — archive to `docs/archive/M5 Plan.md` once M5 ships and the §5.8 acceptance bar is met (mirroring M1–M4).

> **PRD v0.4 update (post-audit).** Several capabilities this plan originally classified as "GAP — no v1 milestone owner" (the `Tests/Generated/SwiftInfer/` writeout from `discover`, `--interactive` triage, `swift-infer drift`, `.swiftinfer/decisions.json` infrastructure) gained an explicit owner in v0.4: a new **TemplateEngine M6 "workflow operationalization"** row in §5.8. Existing v0.3 M6 (RefactorBridge + monotonicity) renumbered to M7; existing M7 (algebraic-structure composition) renumbered to M8. M5 itself is unchanged in scope. References below to "M6 / M7 / M8" use the v0.4 numbering throughout.

## What M5 ships (PRD §5.8 + §5.7)

> `@CheckProperty` and `@Discoverable` annotation API (§5.7); `--dry-run` / `--stats-only` modes.

PRD v0.4 §5.7 (verbatim):

> Reuses the **`@Discoverable(group:)` attribute syntax** from `ProtoLawMacro`. SwiftInferProperties' scanner recognizes the attribute by name match during the SwiftSyntax walk — *no runtime dependency* on `ProtoLawMacro` is required at scan time, so users opting into `@Discoverable` solely for SwiftInfer scoping don't pay a forced second `import` ... Introduces only `@CheckProperty(.idempotent)` / `@CheckProperty(.roundTrip, pairedWith:)` for direct stub generation. Implemented as a SwiftSyntax peer macro (lands in M5 per §5.8) that expands the tagged function decl into an `@Test func` peer in the user's source — not into `Tests/Generated/SwiftInfer/`. The latter is the M6 `--interactive` writeout path (§3.6 step 3 + §5.8 M6); `@CheckProperty` is the per-declaration opt-in path. Both paths consume the M4.3 sampling seed (§16 #6) and the M4.2 `GeneratorSelection` strategy.

So M5 has three concrete deliverables:

1. **Detect `@Discoverable(group:)`** — re-uses the kit's attribute *syntax* without runtime dep on `ProtoLawMacro`. SwiftInfer recognizes the attribute on function decls during scanning and uses the group as a cross-function pairing signal-booster (open decision #1 default; PRD §5.5 calls it a "scope filter" but the §3.5 conservative-precision posture argues for boost-not-filter).
2. **Ship `@CheckProperty(.idempotent)` / `.roundTrip(pairedWith:)`** — a NEW SwiftInfer-side peer macro that expands a tagged function decl into a peer `@Test` stub running the property under `SwiftPropertyBasedBackend` with the M4.3 sampling seed (widened to 256 bits per PRD v0.4 §16 #6).
3. **Add `--dry-run` and `--stats-only` CLI modes** to `swift-infer discover`.

### Important scope clarifications

- **No `Tests/Generated/SwiftInfer/` writeout in M5.** The §3.6 step 3 writeout from `discover` is owned by **M6 (workflow operationalization)** per PRD v0.4 §5.8 — not M5. M5's stub *generation* happens entirely inside the `@CheckProperty` macro's peer-macro expansion, which produces a peer `@Test` declaration in the user's own source file (the file where they wrote the attribute), *not* under `Tests/Generated/SwiftInfer/`. The directory is reserved for M6's `--interactive`-accept writeout and the (eventually-shipping) TestLifter's lifted-from-existing-tests writeout. PRD §5.9 cross-ref table (NEW in v0.4) lists every owner.
- **`--dry-run` is currently a no-op** in M5, since `discover` already does no source-file writes (PRD §16 #1 hard guarantee). The flag ships at the API surface as a forward-looking placeholder for **M6's `--interactive` writeout** — when there's a real write to suppress, `--dry-run` already exists with stable semantics. M5 plumbs the flag through ArgumentParser, asserts behaviour is identical to the no-flag path, emits a placeholder-status stderr diagnostic, and moves on.
- **Cross-validation +20 from real TestLifter is still gated** on TestLifter M1 in this repo (PRD §7.9). M3.5's `crossValidationFromTestLifter` parameter remains dormant under M5.

## Sub-milestone breakdown

| Sub | Scope | Why this order |
|---|---|---|
| **M5.1** | `DiscoverableGroupScanner` — extend `FunctionScannerVisitor` to detect `@Discoverable(group:)` attributes on function decls and store the group name on `FunctionSummary` as a new `discoverableGroup: String?` field (defaults `nil`, additive). `FunctionPairing.candidates(in:)` gains a same-group preference: pairs sharing a non-nil group score a `+35` `Signal(kind: .discoverableAnnotation)` (PRD §4.1's row) at the registry layer. Pairs with mismatched groups still pair (PRD §5.5 calls it a *scope filter*, but the conservative-precision posture from §3.5 says: don't drop candidates just because they're not in the same group; signal-boost the matched ones instead). | Detection sits at the scanner layer, where M3.2's `TypeDecl` and M2.5's `IdentityCandidate` emission already proved out the additive-field pattern. Doing this first makes the rest of M5 self-contained — the annotation API works against any FunctionSummary regardless of source. |
| **M5.2** | `SwiftInferMacro` + `SwiftInferMacroImpl` targets — new SwiftPM macro pair mirroring `ProtoLawMacro` / `ProtoLawMacroImpl` from SwiftProtocolLaws. `SwiftInferMacroImpl` ships the `CheckPropertyMacro` `PeerMacro` impl (SwiftSyntaxMacros). Initial scope: the `.idempotent` case. Expands `@CheckProperty(.idempotent) func normalize(_ value: String) -> String { ... }` into a peer `@Test func normalize_isIdempotent() async` that:<br/>• Imports `ProtocolLawKit` + `PropertyBased`.<br/>• Constructs `SwiftPropertyBasedBackend()`.<br/>• Computes the §16 #6 sampling seed from a stable identity hash derived from `(template, function name, signature)` — same shape `SuggestionIdentity` uses today.<br/>• Calls `backend.check(...)` with a generator emitted via `GeneratorExpressionEmitter.expression(...)` (K-prep-M1 dep) and a property closure asserting `f(f(x)) == f(x)`.<br/>• Reports counterexamples via Swift Testing's `Issue.record` if `.failed`. | Two-target macro shape is the proven Swift-macro pattern (kit's `ProtoLawMacro` does it). Starting with `.idempotent` keeps the scope tight — one strategy arm, no cross-function pairing yet. The kit's `MacroExpansionTests` byte-stable goldens via `SwiftSyntaxMacrosTestSupport.assertMacroExpansion` give us a template for verification. |
| **M5.3** | Add `.roundTrip(pairedWith:)` arm to `CheckPropertyMacro`. Peer macro on the *forward* function expands to an `@Test func encode_decode_roundTrip()` that imports both directions (the `pairedWith:` argument carries the inverse function's name as a string), runs `decode(encode(value)) == value`. The macro syntactically validates that `pairedWith:` references a function in the same scope (best-effort — peer macros can see only the decoratee; the invariant is enforced by the compiler's symbol resolution at expansion time). | The `.roundTrip` arm needs a different stub shape (paired function reference, two type signatures). Splitting from M5.2 isolates the design call about how `pairedWith:` resolves. |
| **M5.4** | `--stats-only` mode for `swift-infer discover`. Argument flag plumbed through `Discover` command. When set, the renderer emits a summary block instead of per-suggestion explainability:<br/>```<br/>37 suggestions across 5 templates.<br/>  idempotence:        12 (8 Strong, 3 Likely, 1 Possible)<br/>  round-trip:          7 (5 Strong, 2 Likely)<br/>  commutativity:       9 (3 Strong, 4 Likely, 2 Possible)<br/>  associativity:       6 (2 Strong, 3 Likely, 1 Possible)<br/>  identity-element:    3 (2 Strong, 1 Likely)<br/>```<br/>New `SuggestionRenderer.renderStats(_:)` static method. Byte-stable golden tests for the summary shape. | Stats mode is genuinely useful today for CI dashboards ("did the count of Strong-tier suggestions regress this commit?"). Implementing it before `--dry-run` keeps M5.5 a pure plumbing change with no rendering implications. |
| **M5.5** | `--dry-run` mode for `swift-infer discover`. ArgumentParser flag plumbed; `Discover.run` records that it was set; behaviour identical to no-flag path because there's no write capability to suppress yet (PRD §16 #1 already guarantees `discover` is read-only). Test confirms the flag is recognized and an explanatory diagnostic lands on stderr (`"--dry-run is a forward-looking placeholder for M6's --interactive writeout; no writes are issued by v1 discover"`) when the user passes it explicitly. | Surface area pinned now so **M6's `--interactive` writeout** can flip the flag to actually do something without an API break. The diagnostic prevents silent confusion from users who pass the flag expecting current behaviour to change. |
| **M5.6** | Validation suite: byte-stable `assertMacroExpansion` goldens for both `.idempotent` and `.roundTrip(pairedWith:)` cases of `@CheckProperty`; integration test for `@Discoverable(group:)` recognition over a fixture corpus; golden tests for `--stats-only` output; CLI test for `--dry-run` flag recognition + diagnostic; §13 perf re-check on `swift-collections` + the synthetic 50-file corpus with the new scanner extensions active. Mirror of M1.6 + M2.6 + M3.6 + M4.5. | Validation, not new code. Closes the M5 acceptance bar. |

## M5 acceptance bar

Mirroring PRD §5.8's prior acceptance bars, M5 is not done until:

a. `@Discoverable(group:)` annotations on function decls are detected by the scanner and surface in `FunctionSummary.discoverableGroup`. Cross-function pairs sharing a non-nil group emit a `+35` `Signal(kind: .discoverableAnnotation)`. Integration tests against fixture corpora prove the detection + scoring works end-to-end.
b. `@CheckProperty(.idempotent)` peer-macro expansion is byte-stable against an `assertMacroExpansion` golden. The expanded code compiles and exercises `SwiftPropertyBasedBackend` against an idempotent function.
c. `@CheckProperty(.roundTrip, pairedWith: "decode")` peer-macro expansion is byte-stable against an `assertMacroExpansion` golden. The expanded code references both halves of the pair.
d. `swift-infer discover --stats-only` renders a byte-stable summary block. Golden test pins the per-template / per-tier counts.
e. `swift-infer discover --dry-run` is recognized by ArgumentParser, behaves identically to the no-flag path, and emits the placeholder-status stderr diagnostic. CLI test confirms.
f. The §13 performance budget for `swift-infer discover` (< 2s wall on 50-file module) still holds on `swift-collections` and the synthetic 50-file corpus with M5.1's `@Discoverable` scanner extension active.

## Out of scope for M5 (re-stated for clarity, milestone numbers per PRD v0.4)

- **Writeout from `discover` to `Tests/Generated/SwiftInfer/`.** PRD v0.4 §5.8 M6 (workflow operationalization) owns this — `discover --interactive` accepts a suggestion and writes the lifted property-test stub. M5's `@CheckProperty` macro is a *parallel* opt-in path that produces a peer in user source instead.
- **`--interactive` triage mode itself.** Also M6 per PRD v0.4 §5.8.
- **`swift-infer drift` + `.swiftinfer/decisions.json` infra.** Also M6.
- **`apply` subcommand.** v1.1+ ergonomics per PRD §20.6.
- **TestLifter cross-validation +20 wakeup.** Still gated on TestLifter M1 in this repo (the dormant `crossValidationFromTestLifter` parameter from M3.5).
- **RefactorBridge conformance suggestions to `Tests/Generated/SwiftInferRefactors/`.** M7 deliverable (was M6 pre-v0.4 renumber).
- **Monotonicity / invariant-preservation templates.** Also M7.
- **Algebraic-structure composition** — M8 (was M7 pre-v0.4 renumber).
- **`--show-suppressed` / `--seed-override` flags.** v1.1+ per PRD v0.4 §16 #6.

## Open decisions to make in-flight

1. **`@Discoverable(group:)` as filter vs. signal-boost.** PRD §5.5 calls it a "scope filter" but the §3.5 conservative-precision posture says don't drop candidates that *might* be valid:
   - **(a) Pure filter.** Cross-function pairs only consider functions sharing a `@Discoverable(group:)` annotation OR neither annotated.
   - **(b) Signal-boost only.** Pairs always considered; same-group adds `+15`, mismatched-group is a no-op (not a counter-signal).
   - **(c) Scope-filter + signal-boost hybrid.** Same-group fires `+15`; mismatched-group drops the pair entirely (filter); both-unannotated is the M1 default.
   - **Default unless reason emerges:** **(b) signal-boost only**. Matches M1/M2's caveat-don't-drop posture and lets the user opt INTO scoping by tagging — not opt-out by leaving things untagged. Re-evaluate if calibration shows untagged cross-pairs flood the output.

2. ~~**`@CheckProperty` macro target — re-export the kit's `@Discoverable` or recognize-only?**~~ **Resolved by PRD v0.4 §5.7.** SwiftInferProperties recognizes `@Discoverable(group:)` by name match during the scanner's SwiftSyntax walk; no runtime dependency on `ProtoLawMacro` at scan time. Users wanting compile-time validation of the attribute import `ProtoLawMacro` themselves. M5.1 implements the recognize-only path; `SwiftInferMacro` ships only `@CheckProperty`.

3. ~~**`SwiftInferMacro`'s `Seed` derivation — splat or widen?**~~ **Resolved by PRD v0.4 §16 #6.** The seed is now spec'd as "all 256 bits of `SHA256(identity || "sampling")` packed as four big-endian UInt64s for the Xoshiro256\*\* state." `SamplingSeed.derive` widens from `UInt64` to a 4-`UInt64` value type (or `Seed` directly — open implementation choice); the renderer's `Sampling: ... lifted test seed: 0x{hex}` line widens to 64 hex chars; the M4.3 + M4.5 byte-stable goldens shift in lockstep. M5.2 picks up the widening since the macro is the first consumer that actually feeds the seed into a Xoshiro state. (The M4.3 `UInt64` form was a v0.3 PRD-conformant choice; v0.4 audited the upstream API and corrected the spec.)

4. **Peer macro can't see sibling functions.** `@CheckProperty(.roundTrip, pairedWith: "decode")` references a sibling function by name string. The macro expansion produces a stub that calls `decode(encode(value))` — but the macro itself doesn't validate that `decode` exists or has the right type. The compiler catches type mismatches at expansion-output compile time. Acknowledge this in the macro's docstring; the stub's compile error is the validation surface.

5. **`--stats-only` rendering format**. Two viable shapes for the per-template line:
   - **(a) Aligned columns** as drafted in M5.4 (`idempotence:        12 (8 Strong, 3 Likely, 1 Possible)`).
   - **(b) Markdown table** (machine-parseable for CI dashboards).
   - **Default unless reason emerges:** **(a) aligned columns**. Matches the existing renderer's text-table shape. Markdown adds a whole rendering mode (would need a `--stats-format=markdown` switch); deferred until a real CI consumer asks.

## New dependencies introduced in M5

- **`SwiftSyntaxMacros` + `SwiftCompilerPlugin` + `SwiftSyntaxMacrosTestSupport`** — pulled via the existing `swift-syntax` package dep; just adding the products to the new `SwiftInferMacroImpl` target. Same pattern the kit's `ProtoLawMacroImpl` uses.

No new top-level package dependencies. `ProtoLawCore` (M3.1) already provides `GeneratorExpressionEmitter` (K-prep-M1).

## Target layout impact

New SwiftPM macro target pair, mirroring the kit's macro layout:

```
Sources/
  SwiftInferCore/         # FunctionSummary.swift gains `discoverableGroup: String?`
                          # FunctionScanner.swift extended for @Discoverable detection
                          # SamplingSeed.swift widened to 256 bits (PRD v0.4 §16 #6)
                          # SuggestionRenderer.swift adds renderStats(_:)
                          # Signal.Kind gains .discoverableAnnotation if not already present
  SwiftInferTemplates/    # FunctionPairing.swift adds the +15 same-group signal
  SwiftInferMacro/        # NEW. Declarations only. Re-exports nothing.
                          # CheckProperty.swift defines the @CheckProperty attached macro.
  SwiftInferMacroImpl/    # NEW. SwiftCompilerPlugin entry point + CheckPropertyMacro
                          # implementation using SwiftSyntaxMacros.
  SwiftInferCLI/          # SwiftInferCommand.swift gains --stats-only and --dry-run flags
                          # plus the placeholder-status diagnostic for --dry-run
Tests/
  SwiftInferCoreTests/         # + SamplingSeedTests.swift extended for 256-bit form
                               # + SuggestionRendererStatsTests.swift
  SwiftInferTemplatesTests/    # + FunctionPairing tests for @Discoverable boost
  SwiftInferMacroTests/        # NEW. assertMacroExpansion goldens for both arms.
  SwiftInferIntegrationTests/  # + DiscoverableGroupIntegrationTests.swift
                               # + StatsOnlyGoldenTests.swift
  SwiftInferCLITests/          # DiscoverPipelineTests gains --stats-only + --dry-run
                               # smoke tests
```

Notable: the M5 macro target is a **runtime macro** — users add `import SwiftInferMacro` and write `@CheckProperty(.idempotent)`. The macro expands at *their* compile time, not SwiftInfer's. SwiftInfer ships the macro definition; users link against it.

## Cross-cutting per-template requirement (PRD §5.8)

M5 doesn't add new templates. The §4.5 explainability-block requirement applies to suggestions; M5's scoring contribution is the `+35` `Signal(kind: .discoverableAnnotation)` row in PRD §4.1 (canonical weight per the v0.4 PRD) — which renders through the existing `Signal.formattedLine` (M4.4) without per-template work. The `@CheckProperty` macro expansion produces test stubs, not suggestions, so the explainability requirement doesn't directly apply there — but the macro's docstring + the byte-stable expansion goldens together serve the same "documented + verifiable" contract.
