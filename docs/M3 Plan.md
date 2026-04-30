# M3 Execution Plan

Working doc for the M3 milestone defined in `SwiftInferProperties PRD v0.3.md` §5.8. Decomposes M3 into six sub-milestones so progress is checkable session-by-session. **Ephemeral** — archive to `docs/archive/M3 Plan.md` once M3 ships and the §5.8 acceptance bar is met (mirroring M1 + M2).

## What M3 ships (PRD §5.8)

> Contradiction detection (§5.6); cross-validation with TestLifter (+20 signal per §4.1) once TestLifter M1 lands. Prerequisite: `DerivationStrategist` exposed publicly from SwiftProtocolLaws (see §11, §21 OQ #4).

**Prerequisite resolved in this session:** SwiftProtocolLaws v1.6.0 (commit `03c843e`, tag `v1.6.0`) ships `ProtoLawCore` as a public library product with `DerivationStrategist` + its supporting value types (`TypeShape`, `StoredMember`, `RawType`, `MemberSpec`, `DerivationStrategy`) graduated from `package` to `public`. SwiftInferProperties's `Package.swift:31-38` already documents the reactivation path.

**Cross-validation with TestLifter is structurally deferred.** TestLifter M1 has not landed in SwiftProtocolLaws (no TestLifter target exists in the v1.6 product set). Per PRD §5.8, the +20 signal cannot fire without it. M3 ships contradiction detection only; the cross-validation hookup gets a follow-on micro-milestone whose timing is gated on TestLifter, not on this plan.

### Contradiction-detection scope per PRD §5.6 (frozen v0.2 table)

| # | Combination | Action | M3 status |
|---|---|---|---|
| 1 | Idempotent + Involutive | Warn; demote both to Possible | **Structurally inert in M3** — no involutive template ships in v1 (PRD §5.2 lists 8 templates, none of which is "involutive"). Detection lives at M7's algebraic-structure cluster or whenever an involutive template lands. |
| 2 | Commutative + non-Equatable output | Drop commutativity suggestion | **In scope for M3.** |
| 3 | Round-trip without T:Equatable | Drop round-trip suggestion | **In scope for M3.** |
| 4 | Idempotent on binary op + Identity | Note: consider conformance (§5.9) | **Structurally inert in M3** — current idempotence template is unary only. Detection lives at M7 ("expanded identity-element detection... + reduce-usage signals" per §5.8). |

So 2 of 4 contradictions are wirable now; 2 are deferred to M7 alongside the templates that would emit the conflicting suggestions in the first place. M3 leaves seams for the M7-deferred contradictions but doesn't pretend to ship them.

## Sub-milestone breakdown

| Sub | Scope | Why this order |
|---|---|---|
| **M3.1** | Re-enable the `../SwiftProtocolLaws` dep in `Package.swift`. Add `.product(name: "ProtoLawCore", package: "SwiftProtocolLaws")` as a target dep on `SwiftInferCore` (the only target that converts between SwiftInfer's textual type representations and `ProtoLawCore.TypeShape`). Smoke test: a single-line test that `DerivationStrategist.strategy(for:)` is callable and returns the expected `.userGen` for a `hasUserGen: true` shape. | The dep wiring is mechanical and pre-1.0-fragile (cross-package transitive resolution, swift-syntax version alignment between the two packages, swift-tools-version compatibility). Doing it as a dedicated sub-milestone makes the diff small enough to bisect against and surfaces any version-pin churn before substantive code lands. |
| **M3.2** | `TypeDeclScanner` — extends `FunctionScanner.scanCorpus` to harvest one `TypeDecl` record per type declaration (struct / class / enum / actor / extension): `{ name, kind, inheritedTypes, location }`. Mirrors how M2.5 added `IdentityCandidate` to the same single-pass scan; reuses the existing `typeStack` machinery in `FunctionScannerVisitor`. New output channel on `ScannedCorpus`: `typeDecls: [TypeDecl]`. | Contradictions #2 and #3 need to answer "is `T` Equatable?" against a per-corpus picture. The scanner extension is the single source of truth — adding it before the resolver work lets M3.3 build against a stable input shape. The §13 perf budget governs: `scanCorpus` already does one AST walk per file, and adding a `visit(StructDeclSyntax)` / `visit(EnumDeclSyntax)` etc. emission step is an incremental cost on the same walk, not a second pass. |
| **M3.3** | `EquatableResolver` — best-effort textual Equatable detection. Curated stdlib list (`Int`, `String`, `Bool`, `Double`, `Float`, fixed-width integer family, `UUID`, `Date`, `URL`); corpus-derived list (every `TypeDecl` with `"Equatable"` in `inheritedTypes`, plus its supertype-introduced inheritance via the curated `KnownEquatableConformance` set); curated **non-Equatable** list (function types matched by `(...) ->`, `Any`, `AnyObject`, opaque types prefixed `some `, existential types prefixed `any `, closures). Three-valued result: `.equatable`, `.notEquatable`, `.unknown`. Public API: `EquatableResolver.classify(typeText:) -> EquatableEvidence`. | Contradictions #2 and #3 *drop* on `.notEquatable` evidence and *keep* otherwise. Three-valued is the right shape because §5.6's "drop" action only fires when we have clear signal — `.unknown` types stay caveated, matching the M1/M2 stance. Decision deferred to M3.3: `.unknown` → drop or keep? See "Open decisions" below. |
| **M3.4** | `ContradictionDetector` — pure-function pass over `[Suggestion]` that emits a filtered list plus per-suggestion contradiction notes. For each `Suggestion`:<br/>• Commutativity: drop if any parameter or return type classifies `.notEquatable`.<br/>• Round-trip: drop if either pair half's domain or codomain classifies `.notEquatable`.<br/>Render the dropped contradiction as a stderr diagnostic when running through the CLI (mirrors the existing config / vocab warning channel) so a developer can see *which* contradiction collapsed *which* candidate. Wire into `TemplateRegistry.discover` after suggestion collection but before the final `(file, line)` sort. | Detection is a separate concern from emission. Building the detector as a pure function over `[Suggestion]` keeps it test-isolated from the scanner / template layers and makes the "what got dropped" diagnostic stream a thin extension — single seam, single test surface. |
| **M3.5** | Cross-validation hook **planned but not implemented.** Adds a `crossValidationFromTestLifter: Set<SuggestionIdentity>` parameter (default `[]`) to `TemplateRegistry.discover`; when populated, emits a `+20` `Signal(kind: .crossValidation)` for matching suggestions. M3 ships with the parameter present at the API level but no caller — when TestLifter M1 lands, that milestone wires the input. | Adds the seam without faking the work. Per the PRD §3.5 conservative-precision posture, an unsourced cross-validation signal is worse than no signal; better to ship a callable surface that's dormant than a stub that pretends to fire. |
| **M3.6** | Validation suite: golden-file tests for the dropped-contradiction CLI diagnostics; golden tests for the post-drop `[Suggestion]` rendering (proves contradictions #2 / #3 actually elide the offending suggestion); §13 perf re-check on `swift-collections` + the synthetic 50-file corpus with all five M2 templates active *plus* the new contradiction pass; integration tests for `EquatableResolver` against the curated lists. Mirror of M1.6 + M2.6. | Validation, not new code. Closes the M3 acceptance bar. |

## M3 acceptance bar

Mirroring PRD §5.8 M1 / M2 acceptance, M3 is not done until:

a. Every emitted commutativity suggestion is dropped when a parameter or return type classifies `.notEquatable`; every emitted round-trip suggestion is dropped when either side's domain or codomain classifies `.notEquatable`. Each drop has a golden-file test covering the stderr diagnostic byte-for-byte.
b. The §13 performance budget for `swift-infer discover` (< 2s wall on 50-file module) still holds on `swift-collections` and the synthetic 50-file corpus with all five templates plus the new contradiction pass active.
c. `EquatableResolver` has integration tests proving it correctly classifies the curated stdlib types as `.equatable`, the curated non-Equatable shapes as `.notEquatable`, and corpus-declared `: Equatable` types as `.equatable`. Three-state semantics are exercised against fixture corpora.
d. The `crossValidationFromTestLifter` parameter is reachable from `TemplateRegistry.discover`'s public API, with a unit test confirming that populating it produces a +20 `.crossValidation` signal on the matched suggestion. The integration with TestLifter remains a follow-on milestone — its acceptance bar is out of M3's scope.

## Out of scope for M3 (re-stated for clarity)

- **Cross-validation +20 signal sourcing from a real TestLifter.** TestLifter M1 hasn't shipped in SwiftProtocolLaws. M3 ships the receiving end (the `Set<SuggestionIdentity>` parameter); the producing end is a separate downstream milestone.
- **Contradictions #1 (idempotent + involutive) and #4 (idempotent binary op + identity).** Both require new SwiftInfer detection capabilities (an involutive template; binary-op idempotence) that the PRD §5.2 v1 template list doesn't ship until M7's algebraic-structure-composition milestone. M3 leaves seams in `ContradictionDetector` for these but doesn't activate them.
- **Sampling** (PRD §4.3) — M4. Contradiction detection is a *static* signal layer; sampling-based refutation is a different (and stronger) drop mechanism that lives in M4.
- **Annotation API** (`@CheckProperty`, `@Discoverable`, PRD §5.7) — M5.
- **Generator inference using `DerivationStrategist`.** M3 wires the dep but doesn't *call* `DerivationStrategist.strategy(for:)` for generator emission — that's an M4 concern (sampling needs generators). M3 only uses `ProtoLawCore` types as a future-proofing exercise; if the milestone ends up not calling into `DerivationStrategist` at all, the dep stays for M4 to consume.
- **Semantic resolution** of generic `Equatable` propagation (`Array<T>: Equatable where T: Equatable`). The M3 resolver does textual best-effort; full conditional-conformance reasoning is a v1.1 constraint-engine concern (PRD §20.2).

## Open decisions to make in-flight

1. **`.unknown` Equatable evidence — drop or keep?** Two viable defaults:
   - **(a) Keep.** Match M1/M2's caveat-don't-drop stance. Drops only on `.notEquatable` evidence. Accepts that complex generic types (`Result<Success, Failure>`, custom containers) won't have their commutativity / round-trip suggestions dropped even when *T* is non-Equatable, as long as we can't prove it textually.
   - **(b) Drop.** Match the §3.5 "fewer suggestions when in doubt" posture, accepting that complex generics that *are* Equatable (e.g., `Result<Int, MyError>` where `MyError: Equatable`) will lose their suggestions silently.
   - **Default unless reason emerges:** **(a) Keep.** The M1/M2 explainability blocks already render the Equatable caveat for every emitted suggestion; demoting to drop on `.unknown` produces silent loss without informing the user. The §3.5 "fewer suggestions" posture is satisfied here by the curated non-Equatable list, which is large enough to catch the obvious cases (closures, `Any`, function types). Revisit if calibration shows the curated list misses a meaningful fraction of real false-positive sources.

2. **TypeDecl emission on `extension`s.** Extensions don't *introduce* a type but can *add* protocol conformance. `extension Foo: Equatable { ... }` should bump `Foo` into the resolver's `.equatable` set. Two options:
   - **(a) Emit a `TypeDecl` per extension** with `inheritedTypes` carrying just the extension's added conformances. The resolver merges multiple `TypeDecl`s per type name.
   - **(b) Emit a `ConformanceAddition` record** distinct from `TypeDecl` — more accurate but adds a parallel emission channel.
   - **Default unless reason emerges:** **(a)**. Mergeable `TypeDecl`s keep the data model flat. `ScannedCorpus.typeDecls` becomes a multimap-shaped list rather than a 1:1-with-source-decl list, but resolver consumption is the same shape either way.

3. **`isProvablyNonEquatable` shape — text matching vs. structural.** A function type like `(Int) -> String` and a closure expressed inline are syntactically distinct. The resolver textually matches `(...) ->` patterns. False negative: a typealias `typealias Handler = (Int) -> Void` then `param: Handler` doesn't match, because the textual type is `Handler`. M3 conservative scope accepts this — typealiases that obscure non-Equatable shapes won't be caught until v1.1 semantic resolution.

4. **Diagnostic stream for dropped contradictions.** Three options for how the user learns a suggestion was dropped:
   - **(a) Silent drop** — the suggestion just doesn't appear. Cleanest output.
   - **(b) Stderr diagnostic** with one line per drop, matching the existing config / vocab warning channel pattern.
   - **(c) "Dropped suggestions" footer** in the regular output, surfaced under `--show-rejected` (which the v0.2 PRD §5.5 already mentions for sampling refutations).
   - **Default unless reason emerges:** **(b)** for M3, **(c)** when M4 sampling lands. Stderr drops are visible to a developer running interactively and are quiet enough not to clutter the byte-stable suggestion stream. The `--show-rejected` flag is a natural M4 add when sampling-refuted candidates need the same surface.

## New dependencies introduced in M3

- **`../SwiftProtocolLaws` (`ProtoLawCore` v1.6.0+)** — re-enabled per the existing `Package.swift:31-38` plan. Local-path until SwiftInfer crosses the 1.0 boundary; swap to a versioned URL dep before tagging.

## Target layout impact

No new top-level targets. New source files land in existing targets:

```
Sources/
  SwiftInferCore/         # + TypeDecl.swift              (data model: pure value type)
                          # + EquatableResolver.swift     (curated lists + corpus lookup)
                          # FunctionScanner.swift extended for type-decl emission
                          # IdentityCandidate.swift's ScannedCorpus extended with typeDecls
  SwiftInferTemplates/    # + ContradictionDetector.swift (pure-function filter pass)
                          # SwiftInferTemplates.swift (TemplateRegistry.discover) wires
                          # the detector after suggestion collection; gains the
                          # crossValidationFromTestLifter parameter
Tests/
  SwiftInferCoreTests/         # + TypeDeclScannerTests.swift
                               # + EquatableResolverTests.swift
  SwiftInferTemplatesTests/    # + ContradictionDetectorTests.swift
  SwiftInferIntegrationTests/  # contradiction-pass golden-file tests; perf re-runs (M3.6)
```

`FunctionScanner.swift` will likely need its file-length disable extended for M3.2's type-decl emission. `EquatableResolver` is small enough (~150–200 lines) to live as one file.

## Cross-cutting per-template requirement (PRD §5.8)

M3 doesn't add new templates — contradiction detection is a *cross-cutting filter layer* over existing template output. The §4.5 explainability-block requirement applies to suggestions, not to filter passes. The closest analog in M3 is the dropped-contradiction diagnostic stream (open decision #4), which gets golden-file coverage in M3.6.
