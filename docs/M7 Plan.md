# M7 Execution Plan

Working doc for the M7 milestone defined in `SwiftInferProperties PRD v0.4.md` §5.8. Decomposes M7 into six sub-milestones so progress is checkable session-by-session. **Ephemeral** — archive to `docs/archive/M7 Plan.md` once M7 ships and the §5.8 acceptance bar is met (mirroring M1–M6).

> **M7 closes out the v1 TemplateEngine surface.** It adds the last two unary templates (monotonicity + invariant-preservation) and ships **Contribution 3 — RefactorBridge** (PRD §6) with the `[A/B/s/n/?]` interactive prompt promised since v0.2 §8. After M7 lands, the only remaining TemplateEngine v1 milestone is **M8** (algebraic-structure composition); M8 layers on top of M7 by accumulating per-template signals into stronger conformance suggestions.

## What M7 ships (PRD v0.4 §5.8)

> **M7 (was M6).** Monotonicity (`Possible` by default — escalation only via TestLifter corroboration or explicit annotation per §5.2 caveat); invariant-preservation (annotation-only); RefactorBridge upstream-loop conformance suggestions written to `Tests/Generated/SwiftInferRefactors/` (§6, §16 #1).

Three concrete deliverables:

1. **Monotonicity template** — type pattern `T → U` with an ordered codomain (commonly `T → Int` or `T → Double`); curated naming list (`length`, `count`, `size`, `priority`, `score`, `depth`, `height`, `weight`, `size(...)`, `len(...)`); accumulator/reduce-usage as a body signal; `Possible` tier by default per the §5.2 caveat. Escalation paths: TestLifter corroboration (still gated on TestLifter M1) or explicit `@CheckProperty(.monotonic(over:))` annotation (M5 macro extension).
2. **Invariant-preservation template** — annotation-only signal. Doesn't fire on naming or type pattern alone; requires `@CheckProperty(.preservesInvariant(_:))` on the user's function. The interactive accept gesture for an invariant-preservation suggestion writes a property test that runs the user-supplied invariant predicate before and after.
3. **RefactorBridge** — extends the M6.4 interactive prompt to `[A/B/s/n/?]`. `B` accepts a structural-conformance suggestion (e.g., "this type with curated `merge` over `T × T → T` is a `Semigroup` candidate") and writes an `extension MyType: Semigroup {}` conformance stub to `Tests/Generated/SwiftInferRefactors/<TypeName>/<ProtocolName>.swift`. SwiftProtocolLaws then verifies the conformance laws on every CI run via `swift package protolawcheck` (kit-side, not this repo).

### Important scope clarifications

- **M7's RefactorBridge fires on simple structural signals it discovers itself; M8 layers richer aggregation on top.** PRD §5.4 says "multiple per-template signals on the same type → structural claim → RefactorBridge suggestion." That accumulation pass is M8. M7's RefactorBridge ships the *writeout infrastructure* (the `Tests/Generated/SwiftInferRefactors/` path, the conformance-stub emitter, the `[A/B/s/n/?]` prompt extension, the decisions-schema bump for the `B` arm) and fires on per-template signals available today. M8 then makes the suggestions stronger and more frequent without changing the writeout machinery.
- **Invariant-preservation is annotation-only — it does NOT emit at discover time without an annotation present.** PRD §5.2 caveat: invariant-preservation is structurally too easy to misinfer; we require explicit user opt-in via `@CheckProperty(.preservesInvariant(_:))`. Discover surfaces it only when the annotation is detected during the SwiftSyntax walk (extending the M5.1 `@Discoverable` recognizer). The interactive accept path then emits a property test that runs the predicate before/after the call.
- **Monotonicity stays Possible by default per the §5.2 caveat.** "Possible by default — escalation only via TestLifter corroboration or explicit annotation." Without `--include-possible` on the CLI (M1 default), monotonicity suggestions are hidden from `discover` output. They do still flow through the pipeline (drift, decisions persistence, etc.).
- **TestLifter cross-validation `+20` still gated on TestLifter M1** (PRD §7.9). M3.5's `crossValidationFromTestLifter` parameter remains dormant under M7. Monotonicity's TestLifter-corroboration escalation path is wired but inert until TestLifter M1 ships in this repo.
- **`apply` subcommand stays v1.1+** (PRD §20.6). M7's `B` arm goes through `--interactive`'s prompt-driven path, same shape as M6.4's `A` arm.
- **Algebraic-structure composition (semigroup → monoid → group → semilattice → ring chain) is M8, not M7.** M7's RefactorBridge can suggest individual conformances based on single-template signals (e.g., commutativity + identity-element on the same type → `CommutativeMonoid` candidate), but the multi-template *aggregation pass* itself is M8. This is the cleanest split: M7 ships the bridge, M8 makes the bridge fire more often.

## Sub-milestone breakdown

| Sub | Scope | Why this order |
|---|---|---|
| **M7.1** | `MonotonicityTemplate`. New `Sources/SwiftInferTemplates/MonotonicityTemplate.swift`: type pattern `T → U` where `U` is `Comparable` (curated stdlib list: `Int`, `Double`, `Float`, `String`, `Date`, `Duration`); curated naming verbs (`length`, `count`, `size`, `priority`, `score`, `depth`, `height`, `weight` plus the `*Count` / `*Size` suffix patterns); body signal — function calls into a stdlib comparison or accumulator the SwiftSyntax walker already classifies. Score lands in the Possible tier (20–39) per the §5.2 caveat — the type pattern alone scores 30, naming match adds 10, accumulator usage adds 10. Project-vocabulary `monotonicityVerbs` extension to `Vocabulary` (§4.5). Tests cover: type-pattern only (Possible); type + name (Possible — still under 40); annotation-corroborated escalation hook (asserts `Possible` today, `Likely` once the M5 macro extension lands). | Pure template — no orchestration. Sits below M7.4 (RefactorBridge needs templates to consume). |
| **M7.2** | `InvariantPreservationTemplate`. New `Sources/SwiftInferTemplates/InvariantPreservationTemplate.swift`: scans for `@CheckProperty(.preservesInvariant(_:))`-annotated functions during the SwiftSyntax walk (extending M5.1's `@Discoverable` recognizer with a new attribute name match). Emits a Strong-tier suggestion only when the annotation is present — no naming or type-pattern fallback. The annotation's `_:` argument carries the invariant predicate name (e.g., `\.isValid`); the suggestion's `Evidence` carries it through to the LiftedTestEmitter (M7.3) for the `before == after invariant check` body. Tests cover: annotation present → suggestion emitted; annotation absent → no suggestion (even on functions whose name strongly suggests preservation, like `mutate`); malformed annotation argument → diagnostic + suggestion suppressed. | Annotation-only, so depends on the M5.1 attribute-recognizer hook but not on M7.1. Independent — can land alongside M7.1 if we want to. |
| **M7.3** | `LiftedTestEmitter` arms for monotonicity + invariant-preservation. Extends `Sources/SwiftInferTemplates/LiftedTestEmitter.swift` with `monotonic(funcName:typeName:returnType:seed:generator:)` (asserts `f(small) <= f(large)` over a sorted pair drawn from the generator) and `invariantPreserving(funcName:typeName:invariantName:seed:generator:)` (asserts `invariant(value)` implies `invariant(f(value))`). Byte-stable goldens for both shapes. Mirror of M6.3's idempotent + roundTrip arms. M6.4's `liftedTestStub(for:)` switch picks them up automatically. The unsupported-template diagnostic ("no stub writeout available for template X in v1") finally retires for these two arms — commutativity / associativity / identity-element get theirs in M8. | Bridges the M7.1 + M7.2 templates to the M6.4 accept path. Doing it before M7.5 means M7.5 just needs to extend the prompt UI without inlining stub-template logic. |
| **M7.4** | `LiftedConformanceEmitter` (parallel to `LiftedTestEmitter`) + RefactorBridge writeout infrastructure. New `Sources/SwiftInferTemplates/LiftedConformanceEmitter.swift`: pure-function emission of an `extension MyType: <Protocol> {}` source string from a `(typeName, protocolName, requirements)` tuple. `Tests/Generated/SwiftInferRefactors/<TypeName>/<ProtocolName>.swift` writeout convention per PRD §16 #1's allowlist extension. Initial conformance arms: `Semigroup` (commutativity-template signal alone) and `Monoid` (commutativity + identity-element on the same type) — these are the simplest M7-discoverable structural claims. The full algebraic-structure aggregation pass (group / semilattice / ring) lands in M8. Byte-stable goldens for both arms. | Independent of M7.1–M7.3 — pure function over a different input shape (type + protocol vs function + property). Can land in parallel. |
| **M7.5** | `RefactorBridgeOrchestrator` + extend interactive prompt to `[A/B/s/n/?]`. New `Sources/SwiftInferCLI/RefactorBridgeOrchestrator.swift`: scans `Suggestion` lists for structural-conformance candidates (commutativity-only → Semigroup proposal; commutativity + identity-element on same type → Monoid proposal). Extends `InteractiveTriage` (M6.4) to surface the `B` arm only when the suggestion has an associated `RefactorBridgeProposal`. Routes `B` accept through `LiftedConformanceEmitter` (M7.4) → file write to `Tests/Generated/SwiftInferRefactors/<TypeName>/<ProtocolName>.swift`. **Decisions schema bump** (M6.1's `Decision` enum gains `.acceptedAsConformance` per open decision #1 below): a fourth case so drift can distinguish "user took Option A" from "user took Option B" from "user took both". Schema version bumps from 1 → 2; loaders that see v2 files load cleanly on v1 readers (additive only). | First user-facing piece of RefactorBridge. M6.4 + M7.4 ready as inputs. The `[A/B/s/n/?]` prompt UI is the most architecturally invasive surface — splitting it from M7.6 keeps each PR reviewable. |
| **M7.6** | Validation suite: byte-stable goldens for both LiftedTestEmitter arms (M7.3) and both LiftedConformanceEmitter arms (M7.4); CRUD lifecycle tests for the v2 decisions.json schema (M7.5); integration tests for the `[A/B/s/n/?]` prompt loop via `RecordingPromptInput`; §13 perf re-check on `swift-collections` + the synthetic 50-file corpus *with M7's two new templates active* — synthetic corpus gains a `length(_:)`-shaped function so monotonicity fires; §16 #1 hard-guarantee extension confirming M7's RefactorBridge writeouts go ONLY to `Tests/Generated/SwiftInferRefactors/<TypeName>/<ProtocolName>.swift`; CLI golden test for the extended `[A/B/s/n/?]` prompt rendering (only when a `RefactorBridgeProposal` is associated; otherwise prompt stays `[A/s/n/?]` per M6.4). Mirror of M1.6 + M2.6 + M3.6 + M4.5 + M5.6 + M6.6. | Validation, not new code. Closes the M7 acceptance bar. |

## M7 acceptance bar

Mirroring PRD §5.8's prior acceptance bars, M7 is not done until:

a. **Monotonicity template surfaces in `--include-possible` runs** with the curated naming + type-pattern signals firing as expected. Hidden by default per the §5.2 caveat; explicit `--include-possible` exposes them. Project-vocabulary `monotonicityVerbs` flows through to a `Project-vocabulary monotonicity verb match` signal. Tier escalation hooks (annotation, TestLifter) are wired but the annotation arm fires only when M7.2's macro extension lands and the TestLifter arm stays dormant.

b. **Invariant-preservation template emits ONLY when `@CheckProperty(.preservesInvariant(_:))` is detected.** Functions whose name suggests preservation (e.g., `mutate`, `apply`) but lack the annotation produce no suggestion. Malformed annotation argument (no key path, wrong type) emits a stderr diagnostic and suppresses the suggestion.

c. **`LiftedTestEmitter.monotonic` and `.invariantPreserving` shapes are pinned via byte-stable goldens** matching the per-shape `f(small) <= f(large)` and `invariant(f(x)) when invariant(x)` test bodies. Goldens cover the generator expression, seed literal, and property closure body — same shape as M6.3's idempotent / roundTrip pin.

d. **`LiftedConformanceEmitter` emits compilable Swift extension source** for the `Semigroup` and `Monoid` arms. Byte-stable goldens pin the file content. The extension carries the §4.5 explainability "why suggested / why this might be wrong" header as a comment block so the developer reading the writeout sees the same justification as the CLI rendered.

e. **`swift-infer discover --interactive` extends to `[A/B/s/n/?]` only when a `RefactorBridgeProposal` is attached to the surfaced suggestion.** Suggestions without an associated proposal stay on M6.4's `[A/s/n/?]` prompt — no dead `B` affordances. Integration tests via `RecordingPromptInput` cover both paths plus the help-text re-prompt loop (which now mentions B in the `?` output when a proposal is attached).

f. **Decisions schema v2 round-trips byte-identically** through the new `.acceptedAsConformance` arm. v2 files are forward-compatible with v1 readers (the new case is additive); v1 readers see the new case via the JSON `rawValue` fallback per the existing `Decision: Codable` shape. Drift correctly suppresses warnings on `.acceptedAsConformance` records the same way it does for `.accepted`.

g. **§13 performance budget for `swift-infer discover` (< 2s wall on 50-file module) still holds** on `swift-collections` and the synthetic 50-file corpus *with the two new M7 templates active*. The synthetic corpus tests gain a `length(_:)`-shaped function per file so monotonicity fires; the perf re-check covers the additional template traversal cost.

h. **§16 #1 hard guarantee preserved** — discover never writes to source files. The M7 writeouts go ONLY to `Tests/Generated/SwiftInfer/` (LiftedTestEmitter; M6.4 path) and `Tests/Generated/SwiftInferRefactors/` (LiftedConformanceEmitter; M7.5 path). Verified by `HardGuaranteeTests` extension that runs `--interactive` with a scripted `B` accept and snapshots the source-file tree before/after.

## Out of scope for M7 (re-stated for clarity, milestone numbers per PRD v0.4)

- **Algebraic-structure composition (semigroup → monoid → group → semilattice → ring chain) is M8.** M7's RefactorBridge can fire `Semigroup` and `Monoid` proposals from individual template signals; M8 adds the multi-template signal-accumulation pass that suggests `Group` (commutativity + associativity + identity + inverse), `Semilattice` (commutativity + associativity + idempotence), `Ring` (two compatible structures), etc.
- **`inverse-pair` template** — M8 deliverable per PRD §5.8. M7's round-trip template (M1, shipped) stays the canonical inverse-detection path; M8's `inverse-pair` ships standalone for non-Equatable cases (suppressed per §16 #6 explainability).
- **`@CheckProperty(.monotonic(over:))` and `@CheckProperty(.preservesInvariant(_:))` macro arms.** Recognition (the scanner-side detection) is M7. Macro expansion of the annotation into a peer `@Test func` is a follow-on extension to the M5.2 `SwiftInferMacroImpl` target. M7 plan tracks recognition-only; macro expansion lands in **M7.2.a** as an addendum if the user wants to drive the templates through the annotation API as well as through discover.
- **`swift-infer apply --suggestion <hash>`** — v1.1+ per PRD §20.6. Shared `LiftedTestEmitter` + `LiftedConformanceEmitter` will back it.
- **TestLifter integration** — TestLifter M1 hasn't started; M3.5 cross-validation seam stays dormant.

## Open decisions to make in-flight

1. **Decision states: `accepted` vs `acceptedAsConformance` distinct?**
   - **(a) Add `.acceptedAsConformance` as a fourth case.** Schema bumps from v1 → v2. Drift treats both as suppression. Most explicit; future `swift-infer metrics` (v1.1+) can split per-arm adoption rates.
   - **(b) Keep three states, add a per-record `acceptedArm: "test" | "conformance"` metadata field.** Schema stays v1 with an optional new field; v1 readers ignore the field cleanly (Codable additive). Less explicit but doesn't require a schema bump.
   - **Default unless reason emerges:** **(a) add `.acceptedAsConformance`**. PRD §17.1 calls out per-arm calibration explicitly; the case-distinction is what `swift-infer metrics` (v1.1+) reads. Schema bump is cheap (additive), and the M6.1 schema-version field is exactly the affordance for this.

2. **Does the `[A/B/s/n/?]` prompt show `B` for every suggestion, or only when a `RefactorBridgeProposal` attaches?**
   - **(a) Only when attached.** Suggestions without a structural-conformance angle (e.g., a one-off idempotence on a `String` function) keep the M6.4 `[A/s/n/?]` prompt — no dead `B` affordance.
   - **(b) Always show, with "no conformance proposal available" if user picks B without a proposal.** Confusing UX — advertises a gesture that fails on most prompts.
   - **Default unless reason emerges:** **(a) only when attached**. Same posture as M6 plan open decision #1 (defer affordances we can't deliver). M6.4 already drops to `[A/s/n/?]` for templates without writeouts; M7 mirrors that for the conformance arm.

3. **Conformance file path convention.**
   - **(a) `Tests/Generated/SwiftInferRefactors/<TypeName>/<ProtocolName>.swift`** — sub-folder per type; one file per protocol conformance. Mirrors M6.4's `Tests/Generated/SwiftInfer/<TemplateName>/<FunctionName>.swift` shape.
   - **(b) `Tests/Generated/SwiftInferRefactors/<TypeName>+<ProtocolName>.swift`** — flat folder, plus-separator filenames matching the Swift community convention for extension files.
   - **(c) `Tests/Generated/SwiftInferRefactors/<TypeName>.swift`** — flat, multiple `extension` blocks per file when one type has multiple proposed conformances.
   - **Default unless reason emerges:** **(a) sub-folder per type**. Mirrors M6.4 path convention; sub-folder lets users `git diff Tests/Generated/SwiftInferRefactors/Money/` to see all conformance proposals on one type. The `+` convention (option b) is appealing but the flat layout collapses the conformance-grouping affordance.

4. **Monotonicity tier policy: `Possible` by default vs `Likely` with curated naming + type pattern.**
   - **(a) `Possible` by default per the PRD §5.2 caveat.** Hidden behind `--include-possible`. Escalation only via TestLifter corroboration (gated) or explicit annotation.
   - **(b) `Likely` when curated naming + ordered codomain both fire.** Visible by default; downgrades to Possible if only one of the two fires.
   - **Default unless reason emerges:** **(a) Possible by default**. PRD §5.2 explicitly calls out "Possible by default — escalation only via TestLifter corroboration or explicit annotation per §5.2 caveat." Conservative posture wins; users opt in via `--include-possible` if they want to see them.

5. **Invariant-preservation: parse the predicate from the annotation's keypath argument, or treat as opaque?**
   - **(a) Opaque keypath.** The annotation `@CheckProperty(.preservesInvariant(\.isValid))` is read as text; the LiftedTestEmitter generates `#expect(input.isValid implies output.isValid)` literally without resolving the keypath. Errors at user compile time, not at scan time.
   - **(b) Resolve the keypath through the SwiftSyntax type-shape data (M4.1's `TypeShape`)** — verify the keypath is valid against the function's parameter type before emitting the suggestion.
   - **Default unless reason emerges:** **(a) opaque keypath**. M4.1's `TypeShape` doesn't carry computed-property metadata; resolving keypaths would need a deeper SwiftSyntax pass. Opaque-text path is consistent with the M5.2 macro impl that doesn't validate the user's invariant predicate either. v1.1+ can layer keypath validation on top once the SemanticIndex (PRD §20.1) ships.

6. **Semigroup proposal: fire on commutativity-only signal, or require associativity too?**
   - **(a) Commutativity alone.** A type with a curated-named commutative `merge` op gets a Semigroup proposal. Generous; M8's accumulation pass tightens this into stricter proposals.
   - **(b) Commutativity + associativity.** A type needs both signals on the same op before Semigroup is suggested. Tighter; consistent with the formal definition (Semigroup = associativity only; CommutativeSemigroup = commutativity + associativity).
   - **(c) Associativity alone.** Strictly the formal definition.
   - **Default unless reason emerges:** **(c) associativity alone**. PRD §6 says the bridge "accumulates strong evidence for a monoid/ring/semilattice." Semigroup is associativity-by-definition; commutativity is a separate axis (CommutativeSemigroup is its own kit conformance). Firing on the right signal matches the kit's protocol shape and avoids surprising the user. The M7.4 LiftedConformanceEmitter ships both `Semigroup` (associativity-only) and `Monoid` (associativity + identity-element); commutativity layered on top is M8's `CommutativeMonoid` arm.

7. **`RefactorBridgeProposal`: per-suggestion or per-type?**
   - **(a) Per-type.** `RefactorBridgeOrchestrator` aggregates suggestions across the whole `discover` run, groups by type, emits one `RefactorBridgeProposal` per type carrying the matched-protocol list.
   - **(b) Per-suggestion.** Each individual `Suggestion` carries an optional `proposal: RefactorBridgeProposal?` field; the prompt for that suggestion shows `B` if non-nil.
   - **Default unless reason emerges:** **(a) per-type**. Aggregation fits the §5.4 algebraic-structure-composition shape (M8 will accumulate signals across templates on the same type into a single conformance claim). The interactive prompt then surfaces the per-type proposal once — user sees `[A/B/s/n/?]` on the first suggestion for a type that has a proposal, and the prompt collapses to `[A/s/n/?]` on subsequent suggestions for the same type once the user has decided. Cleaner UX than re-prompting for B on every signal.

## New dependencies introduced in M7

None at the SwiftPM level. M7 uses the existing `swift-syntax` for the `@CheckProperty(.preservesInvariant(_:))` recognizer extension, the existing `Foundation` for I/O, and the SwiftInferCore / SwiftInferTemplates / SwiftInferCLI internal layout. The kit-side `SwiftProtocolLaws` continues to be referenced via local-path dep through pre-1.0 (M7 doesn't need any new exports from the kit; M7 emits conformance stubs against existing `Semigroup` / `Monoid` protocols already defined in the kit's `ProtoLawCore`).

## Target layout impact

```
Sources/
  SwiftInferTemplates/    # + MonotonicityTemplate.swift                 (M7.1)
                          # + InvariantPreservationTemplate.swift        (M7.2)
                          # + LiftedConformanceEmitter.swift             (M7.4)
                          # LiftedTestEmitter gains .monotonic + .invariantPreserving arms (M7.3)
  SwiftInferCore/         # Vocabulary gains monotonicityVerbs key       (M7.1)
                          # Decision enum gains .acceptedAsConformance   (M7.5; schema v2)
  SwiftInferCLI/          # + RefactorBridgeOrchestrator.swift           (M7.5)
                          # InteractiveTriage extends to [A/B/s/n/?]     (M7.5)
                          # InteractiveTriage+Accept gains B-arm route   (M7.5)
Tests/
  SwiftInferTemplatesTests/    # + MonotonicityTemplateTests.swift
                               # + InvariantPreservationTemplateTests.swift
                               # + LiftedConformanceEmitterTests.swift
                               # LiftedTestEmitterTests gains monotonic + invariant goldens
  SwiftInferCoreTests/         # DecisionsTests v2-schema round-trip
                               # VocabularyTests monotonicityVerbs decode
  SwiftInferCLITests/          # + RefactorBridgeOrchestratorTests.swift
                               # InteractiveTriageTests gains B-arm tests
                               # DiscoverPipelineTests gains monotonicity smoke
  SwiftInferIntegrationTests/  # HardGuaranteeTests extension for SwiftInferRefactors/ allowlist
                               # PerformanceTests synthetic corpus gains length(_:) for monotonicity
```

`InteractiveTriage.swift` and `InteractiveTriage+Accept.swift` get the largest CLI surface change since M6.4 — the prompt-string shape, the `[A/B/s/n/?]` parsing, the per-type `RefactorBridgeProposal` lookup, and the `B`-arm dispatch into `LiftedConformanceEmitter`. The split-out helpers from M6.4 (`InteractiveTriage+Accept.swift`) keep the main enum body under SwiftLint's 250-line cap as the orchestration grows.

## Cross-cutting per-template requirement (PRD §5.8)

M7 adds two new templates (monotonicity + invariant-preservation). Both must ship the §4.5 explainability block ("why suggested" + "why this might be wrong") with their per-template caveats:

- **Monotonicity caveats.** "ordered codomain assumption breaks under custom `Comparable` conformances that don't satisfy strict order"; "TestLifter corroboration not yet wired (gated on TestLifter M1)"; "Possible-tier by default — explicit `@CheckProperty(.monotonic(over:))` annotation escalates to Strong".
- **Invariant-preservation caveats.** "predicate is opaque text; user-side compile error if the keypath doesn't resolve against the parameter type"; "doesn't fire without explicit annotation — the M5.2 `@CheckProperty` annotation API is the opt-in path"; "`if invariant(x) then invariant(f(x))` is a *one-way* implication; the test does not verify that `f` rejects invalid inputs".

These caveats render in every monotonicity / invariant-preservation suggestion's "why this might be wrong" block. Same shape as M6.3's lifted-test stub — the explainability data is template-known and template-emitted, not synthesized by the orchestrator.
