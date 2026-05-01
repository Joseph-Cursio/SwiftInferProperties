# M4 Execution Plan

Working doc for the M4 milestone defined in `SwiftInferProperties PRD v0.3.md` §5.8. Decomposes M4 into five sub-milestones so progress is checkable session-by-session. **Ephemeral** — archive to `docs/archive/M4 Plan.md` once M4 ships and the §5.8 acceptance bar is met (mirroring M1 + M2 + M3).

## What M4 ships (PRD §5.8)

> Scoring model surfaced fully in output (per-signal weights in the explainability block); sampling-before-suggesting (§4.3) using the seeded policy of §16 #6.

The PRD line conflates two architecturally distinct workstreams. M4's first job is to disentangle them and pick a defensible interpretation:

### Workstream A — Generator inference via `DerivationStrategist`

Now-unblocked: `ProtoLawCore` v1.6.0 (re-enabled in M3.1) exposes `DerivationStrategist.strategy(for:)` plus the supporting value types (`TypeShape`, `StoredMember`, `RawType`, `MemberSpec`, `DerivationStrategy`) publicly. M1's `Suggestion.generator` field has carried `.notYetComputed` placeholders since M1.3; M4 turns the SwiftInfer scanner output into the `TypeShape` records the strategist consumes and renders the resulting strategy in the explainability block.

Each Strong-tier suggestion gains a real `GeneratorMetadata.Source` value:

- `.derivedCaseIterable` — `enum T: CaseIterable`
- `.derivedRawRepresentable` — `enum T: <RawType>` for stdlib `RawType`
- `.derivedMemberwise` — struct with 1–10 stored properties whose types resolve to stdlib `RawType`s
- `.todo` — every other case (including arity 11+, classes, actors, structs with unrecognised members, enums missing both raw type and `CaseIterable`)

Confidence (`.high` / `.medium` / `.low`) is set from the chosen strategy: `.userGen` → `.high`; `.derivedCaseIterable` / `.derivedRawRepresentable` → `.high`; `.derivedMemberwise` with all stdlib raw types → `.medium`; anything fall-through to `.todo` → `nil` (no confidence reported because no generator was selected).

### Workstream B — "Sampling-before-suggesting" — interpretation pass

The PRD's "sampling-before-suggesting" phrase reads as if SwiftInfer should execute candidate properties at `discover` time, recording trial counts and counterexamples on the suggestion before emission. **Architecturally that's not viable in v1.** SwiftInfer is a static analysis tool — it scans the source corpus via SwiftSyntax but never loads the user's compiled module. To run a sampling trial of `normalize(normalize(x)) == normalize(x)`, the tool would need to:

- Generate a per-suggestion harness file referencing the user's module.
- Spin up a scratch SwiftPM context to compile and link that harness against `ProtocolLawKit` (which transitively pulls `Testing.framework` — explicitly excluded from `swift-infer`'s runtime per `Package.swift:35-38`).
- Spawn a child process, capture stdout, parse pass/fail.

That's a v1.1+ effort, not an M4 sub-milestone. M4's resolution: **adopt the §16 #6 reading** that the seed is computed at suggest-time and *rendered into the lifted test stub*, with sampling executed by the lifted test (M5+) when the developer runs `swift test`. The `+10` "sampling pass" signal from PRD §4.1 stays unused in v1; SwiftInfer never claims a property held dynamically on its own. The `samplingResult` field stays `.notRun` for every M4-emitted suggestion.

This interpretation is the conservative-precision reading consistent with PRD §3.5 — the tool refuses to claim a property holds without having actually tested it, and refuses to actually test it from a static-analysis context. The seed-emission half of §16 #6 is in scope; the sampling-execution half is post-v1.

### Workstream C — Per-signal weights in the explainability block

Largely already shipped. The current `SuggestionRenderer` already emits one bullet per `Signal` with `(+N)` / `(-N)` / `(veto)` formatting (see `IdempotenceTemplate.formatSignalLine` and identical helpers in the four other templates). M4's task here is a small consolidation: extract the formatter into one place (Core or Renderer), confirm byte-stable output across all five templates, and add explicit golden coverage for the `+20` cross-validation signal (M3.5) once that line surface is exercised by an M4-internal test.

## Sub-milestone breakdown

| Sub | Scope | Why this order |
|---|---|---|
| **M4.1** | `TypeShapeBuilder` — convert `ScannedCorpus.typeDecls` (M3.2) + the per-type stored-property records that M3.2 *doesn't* yet emit into `ProtoLawCore.TypeShape` records. M3.2 captures `name`, `kind`, `inheritedTypes`, `location`; `TypeShape` additionally needs `hasUserGen`, `storedMembers: [StoredMember]`, `hasUserInit: Bool`. The scanner must emit those three new fields on every `TypeDecl`. New file: `Sources/SwiftInferCore/TypeShapeBuilder.swift`; `TypeDecl` gains the three fields (additive, defaulted, no breaking changes to existing tests). | Generator selection can't run without a `TypeShape`. M3.2's `TypeDecl` was scoped narrowly for the resolver; M4.1 widens it to cover the strategist's input contract. Doing this as a dedicated sub-milestone keeps the scanner extension reviewable and its perf impact (one more pass over `MemberBlockSyntax` per type decl) measurable in isolation. |
| **M4.2** | `GeneratorSelection` — for every Strong-tier suggestion that has a "generator-relevant type" (round-trip's `T` and `U`; commutativity / associativity / identity-element's `T`; idempotence's `T`), look up the matching `TypeShape` from M4.1's records and call `DerivationStrategist.strategy(for:)`. Map the returned `DerivationStrategy` back to `GeneratorMetadata.Source` + `Confidence` and rebuild the suggestion. New file: `Sources/SwiftInferTemplates/GeneratorSelection.swift`; `TemplateRegistry.discover` runs it after the contradiction filter and before cross-validation (so cross-validated suggestions show the generator info too). | The selection layer is template-agnostic — it consumes the same per-suggestion type-text map the contradiction layer (M3.4) already builds. Layering it here keeps the registry's discover pipeline readable as "collect → drop → cross-validate → select generator → sort". |
| **M4.3** | `SamplingSeed` — compute the §16 #6 seed at suggest-time (`SHA256(suggestionIdentityHash.normalized + "\|sampling")` — low 64 bits) and surface it in `GeneratorMetadata`. Render in the explainability block as `Sampling seed: 0x...` so the lifted test stub (M5+) can pin its RNG seed and reproduce SwiftInfer-rendered results. The `samplingResult` field stays `.notRun`; the renderer line changes from "not run (M4 deferred)" to "not run; lifted property test will sample under seed 0xABCD..." so the dormant state is informative rather than apologetic. New file: `Sources/SwiftInferCore/SamplingSeed.swift`. | Seed computation is a one-line digest derivation but the rendered-output change is byte-affecting — every emitted suggestion gains a seed line. Splitting it from M4.2 isolates the renderer churn. |
| **M4.4** | Renderer cleanup — extract the per-template `formatSignalLine` helper (currently duplicated five times across `IdempotenceTemplate`, `RoundTripTemplate`, `CommutativityTemplate`, `AssociativityTemplate`, `IdentityElementTemplate`) into `SuggestionRenderer` as a static `formatSignal(_:)` method consumed at render time rather than at suggest time. The explainability block keeps the same byte-stable output but the responsibility moves from each template's "build whySuggested lines" pass to the renderer's "lay out the bullet list" pass. Existing per-template explainability strings stay intact for the non-signal lines (evidence rows, caveats). | Five copies of the same five-line function is a small smell that becomes a real one if M5's `@Discoverable` annotation adds a sixth template. Doing the consolidation under M4 keeps the surface clean before annotation work touches the same files. Strictly speaking optional for M4's PRD line, but the "scoring model surfaced fully" half of M4 is what this is about — moving signal-line responsibility to the renderer makes per-signal weights *the* canonical surface. |
| **M4.5** | Validation suite: golden-file tests for the rendered explainability block on each shipped template (idempotence, round-trip, commutativity, associativity, identity-element) under M4.2's generator + M4.3's seed lines; integration tests for `GeneratorSelection` over fixture corpora that exercise each `DerivationStrategy` arm; §13 perf re-check on `swift-collections` + the synthetic 50-file corpus with M4.2's selection pass active; updated CLI byte-stable goldens in `DiscoverPipelineTests` covering the new "Sampling seed:" line. Mirror of M1.6 + M2.6 + M3.6. | Validation, not new code. Closes the M4 acceptance bar. |

## M4 acceptance bar

Mirroring PRD §5.8's M1 / M2 / M3 acceptance bars, M4 is not done until:

a. Every emitted suggestion that targets a struct/enum the corpus declares carries a `GeneratorMetadata.Source` value other than `.notYetComputed`. Specifically: structs with 1–10 stdlib-`RawType` stored members render `.derivedMemberwise` with `.medium` confidence; `enum: CaseIterable` renders `.derivedCaseIterable` with `.high`; `enum: <RawType>` renders `.derivedRawRepresentable` with `.high`; everything else renders `.todo` with `nil` confidence. Each arm has a golden-file test covering the rendered explainability block byte-for-byte.
b. The §13 performance budget for `swift-infer discover` (< 2s wall on 50-file module) still holds on `swift-collections` and the synthetic 50-file corpus with M4.2's per-suggestion `DerivationStrategist` calls active. Incremental cost: one strategy lookup per Strong-tier suggestion per type — bounded by `O(suggestions × log(typeDecls))` with a precomputed name-keyed index built once per `discover`.
c. The §16 #6 seed is reachable from `GeneratorMetadata` and rendered in the explainability block of every emitted suggestion, regardless of generator strategy. Re-running `discover` on the same source produces byte-identical seed values (already covered by `HardGuaranteeTests`'s reproducibility row, but extended with seed-line equality assertions).
d. The renderer's `formatSignal(_:)` is the only spelling of the `(+N)` / `(-N)` / `(veto)` line shape in the codebase. Templates no longer carry their own `formatSignalLine` helper. Existing per-template explainability tests stay byte-stable — the consolidation is a refactor, not a behaviour change.

## Out of scope for M4 (re-stated for clarity)

- **Actually sampling property candidates at `discover` time.** Per the §3.5 conservative-precision posture and the architectural reality of SwiftInfer being a SwiftSyntax-only tool that never loads the user's compiled module, M4 emits the seed but doesn't run trials. The `+10` sampling-pass signal from PRD §4.1 stays unused in v1. Reaching for in-process sampling is a v1.1+ scratch-package-spawn effort — explicitly out of v1 scope.
- **Cross-validation +20 signal sourcing from a real TestLifter.** TestLifter M1 still hasn't shipped in SwiftProtocolLaws (no `TestLifter` target in the v1.6 product set). M3.5 wired the receiving end (`crossValidationFromTestLifter` parameter); the producing end is gated on TestLifter, not on M4.
- **Generator emission as actual Swift source.** `DerivationStrategist` returns advice (e.g. `"Gen<Int>.int()"` per `RawType.generatorExpression`); turning that into a complete generator function is the lifted-test stub's job, which lands at M5 along with the `Tests/Generated/SwiftInfer/` writeout. M4 only consumes the strategy enum to label the suggestion's `Source` + `Confidence`.
- **Annotation API** (`@CheckProperty`, `@Discoverable`, PRD §5.7) — M5.
- **Monotonicity / invariant-preservation templates** — M6.
- **Algebraic-structure composition** — M7.

## Open decisions to make in-flight

1. **`hasUserGen` detection scope.** `DerivationStrategist` honours `.userGen` as the highest-priority strategy when the type provides a `gen()` static method. The scanner needs to detect this. Two viable scopes:
   - **(a) Same-file only.** Scan for `static func gen()` declarations in the type's primary decl + extensions in the same source file.
   - **(b) Cross-file.** Walk every extension across the corpus.
   - **Default unless reason emerges:** **(a)**. Matches `DerivationStrategist`'s docstring contract ("an extension in the same file"); cross-file detection adds an extra index without a clear correctness gain. Re-evaluate if the calibration sample shows users routinely declaring `gen()` in `+Generators.swift` style files.

2. **Generator selection over generic / collection types.** The current `commutativityTypes(for:)` and `roundTripTypes(for:)` helpers in `TemplateRegistry` extract type-text strings verbatim. For `func merge(_:_:) -> [Int]`, the relevant type is `[Int]`, which has no `TypeShape` in the corpus. Two viable behaviours:
   - **(a) Skip selection for non-corpus types.** `Source` stays `.notYetComputed` for any type not in the corpus's `TypeShape` index. Conservative.
   - **(b) Stdlib generators for stdlib types.** Hard-code `.derivedRawRepresentable` (or a new `.derivedStdlib` arm) for `Int`, `String`, etc., bypassing `DerivationStrategist`.
   - **Default unless reason emerges:** **(a)**. Matches the M3.3 / M3.4 stance where stdlib-type handling lives in curated lists scoped to the resolver, not the selection layer. M5's annotation API is the natural place to let users opt stdlib-typed properties into a specific generator.

3. **Seed-line rendering for `.notRun` sampling.** Three viable formats:
   - **(a)** `Sampling:  not run (M4 deferred)` — current text. Hides the seed entirely.
   - **(b)** `Sampling:  not run; lifted test seed: 0xABCDEF1234567890` — one line, seed inline.
   - **(c)** Two lines: `Sampling:  not run` + `Seed:      0xABCDEF1234567890`.
   - **Default unless reason emerges:** **(b)**. One line keeps the renderer's vertical density; "lifted test seed" framing is honest about who actually consumes the seed (the M5+ stub, not SwiftInfer itself).

4. **`formatSignal` consolidation: Renderer or Core?** The helper is used by templates at *suggest* time (built into `whySuggested` strings) and by the renderer at *render* time. Two homes:
   - **(a) `SuggestionRenderer.formatSignal(_:)`** — render-time only. Templates stop pre-formatting; `whySuggested` carries `Signal` references rather than strings. Bigger API surface but cleaner separation.
   - **(b) `Signal.formattedLine` extension** — value-type method. Templates and renderer both call into it.
   - **Default unless reason emerges:** **(b)**. Smaller blast radius — `whySuggested: [String]` keeps its current shape, the helper just lives on `Signal` itself. Re-evaluate if M5's annotation API needs richer signal metadata in the rendered output (in which case `whySuggested: [SignalLine]` becomes the right call and (a) wins).

5. **Confidence calibration.** `DerivationStrategy` doesn't carry a confidence field; the mapping is SwiftInfer's responsibility. The simple table:

   | DerivationStrategy | GeneratorMetadata.Confidence |
   |---|---|
   | `.userGen` | `.high` |
   | `.caseIterable` | `.high` |
   | `.rawRepresentable(_)` | `.high` |
   | `.memberwiseArbitrary(members:)` | `.medium` |
   | `.todo(reason:)` | `nil` |

   Open: should `.memberwiseArbitrary` with arity > 5 (or some other threshold) drop to `.low`? PRD §4.3's three-state confidence implies `.low` is reachable; we currently have nothing that emits it. Default unless reason emerges: **leave `.low` unused in M4**, document that it's reserved for `inferredFromTests` paths landing post-M5.

## New dependencies introduced in M4

None. `ProtoLawCore` was wired in M3.1; M4 only consumes its existing public surface. No new SwiftPM packages, no new Swift-syntax requirements.

## Target layout impact

No new top-level targets. New source files land in existing targets:

```
Sources/
  SwiftInferCore/         # + TypeShapeBuilder.swift            (M4.1: TypeDecl → TypeShape)
                          # + SamplingSeed.swift                (M4.3: §16 #6 seed derivation)
                          # TypeDecl.swift extended with hasUserGen, storedMembers, hasUserInit
                          # FunctionScanner.swift extended for the new TypeDecl fields
                          # Signal.swift gains `formattedLine: String` (open decision #4 default)
                          # SuggestionRenderer.swift consumes the new GeneratorMetadata seed field
  SwiftInferTemplates/    # + GeneratorSelection.swift          (M4.2: per-suggestion strategy lookup)
                          # SwiftInferTemplates.swift (TemplateRegistry.discover) wires
                          # the selection pass between contradiction filter and cross-validation
                          # The five template files lose their formatSignalLine helper (M4.4)
Tests/
  SwiftInferCoreTests/         # + TypeShapeBuilderTests.swift
                               # + SamplingSeedTests.swift
                               # TypeDeclScannerTests.swift extended for new fields
  SwiftInferTemplatesTests/    # + GeneratorSelectionTests.swift
                               # SwiftInferTemplatesTests gets the discover-pipeline integration
  SwiftInferIntegrationTests/  # + GeneratorSelectionIntegrationTests.swift
                               # PerformanceTests perf re-check
  SwiftInferCLITests/          # DiscoverPipelineTests gains seed-line + generator-line goldens
```

`FunctionScanner.swift` will need its `swiftlint:disable file_length` directive extended (already disabled — M4.1 just adds member emission inside the existing `visit(StructDeclSyntax)` path).

## Cross-cutting per-template requirement (PRD §5.8)

M4 doesn't add new templates — generator selection is a *cross-cutting suggestion-construction layer* over existing template output. The §4.5 explainability-block requirement applies to suggestions; M4's contribution is filling in the placeholder fields (`Generator: not yet computed (M3 prerequisite)` → real strategy text; `Sampling:  not run (M4 deferred)` → `not run; lifted test seed: 0x...`) so the block's M1-emitted scaffolding finally carries content.
