# ValueSemantic — build plan (type-level copy-independence verification)

Status: **SHIPPED — slices 1–5 complete** (2026-07-06). Supersedes the
discovery/verify half of `docs/ideas/ValueSemantic Kit Proposal.md` (2026-05-04).
The feature discovers reference-backed struct candidates AND verifies the
copy-mutate-compare law end-to-end, catching all three pbt-book Ch. 9 bug shapes
(reference container / broken CoW / closure capture), a CI macro for adopters,
and a user-runnable **`verify-value-semantics` command** that reports confirmed
leaks with minimal repros on real `internal`-typed packages. Three kit releases
(v3.4.0 protocol + single-step, v3.5.0 multi-step interleaving, v3.6.0
`@ValueSemanticTests` macro). See **§10 What shipped** + **§11** (the command).
Remaining (optional): the slice-6 identity companion for reference types.

**Conceptual source: `~/xcode_projects/pbt-book` Chapter 9, "Value semantics,
COW and identity."** That chapter is effectively the spec for the property this
plan automates — it works out the copy-mutate-compare shape (§9.1.2), the
class/`NSMutableArray`/closure escape-hatch taxonomy (§9.1.3, = this plan's three
bug shapes), the CoW correctness claim + missing-`isKnownUniquelyReferenced`
bug and its shrink-to-minimal-repro (§9.2), the reference-type identity/`===`
law family (§9.3), the value-plus-edit-script generator pair (§9.4), and the
`COWBox<Element>` worked example (§9.5). This plan is "discover + auto-generate
the Chapter-9 property for candidate types," so it cites the chapter the way
the kit's `docs/FLOATING_POINT_ORACLE_RECONCILIATION.md` cites the book's
Chapter 8. Read Chapter 9 first for the *why*; this doc is the *how*.

## 1. Summary

Verify **value semantics** — "mutating one instance is unobservable through any
other instance" — as a first-class, discovered-and-verified property. For every
mutating operation `m` on a struct `T` that *claims* value semantics, copying
then mutating the copy must not be observable via the original:

```
∀ mutating m, ∀ instance a:  var b = a; b.m(args);  a == snapshot(a-before-b.m)
```

This is the book's **copy-mutate-compare** shape (Chapter 9 §9.1.2): a *value*
generator supplies the initial instance and a *mutation-script* generator
supplies the edits applied to the copy, so one property checks independence
across the whole space of starting values and edit scripts. It is a
**type-level** property (over a whole type's mutation surface), not a
**function-level** one (over a single signature) — so it is a *new* section in
the SwiftInferProperties PRD, not a `§5` template retrofit, exactly as the
original proposal argued. The engine discovers candidate types from a precise
structural signal, and the kit provides the protocol + runtime harness.

**Companion property for reference types (Chapter 9 §9.3).** For a `class` /
`actor` that vends a stable identifier, the dual law is **identity stability**:
identity (`===`, or a vended id) is *invariant under mutation* and *changes
under a defensive copy*. It is distinct from copy-independence (which is a
`struct` property) and rides the same discovery/verify plumbing with a different
predicate. Treated here as an **optional, later companion** (slice 6) so the
core struct property lands first — flagged now because the book pairs them.

## 2. Motivation

### 2.1 The bug class (invisible to review, real in bridging code)

Three shapes, all compile clean, type-check, and pass casual tests (verbatim
from `docs/ideas/ValueSemantic Kit Proposal.md` §2.2):

1. **Reference-container leak** — a struct wraps `NSMutableArray` (or any
   class-typed storage). `var b = a` copies the *reference*; `b.add(x)` mutates
   the array `a` still points at.
2. **Broken copy-on-write** — a struct intends CoW over a `final class Storage`
   but omits the `isKnownUniquelyReferenced(&storage)` uniqueness check, so
   copies share storage.
3. **Closure capturing mutable state** — a stored `() -> Int` closure captures a
   heap `var box`; every copy shares the box. **Hardest case:** the leak only
   surfaces on the original's *next* mutation, so it needs a *multi-step* test.

The bug is concentrated where Swift developers are most exposed: Foundation/ObjC
bridging (`NSMutable*`), hand-rolled CoW, and closure-captured state. Idiomatic
pure-value structs get value semantics for free from stdlib CoW — which is a
*feature* of the discovery signal below, not a limitation.

### 2.2 Why this fits SwiftInferProperties' posture

The engine is deliberately **high-precision, low-recall** ("when in doubt, fewer
suggestions"; "avoid the Daikon trap"). Value semantics has an unusually clean
discovery signal that plays directly to that posture: the candidate set is
*exactly* the structs that **can** violate it — those with a reference-typed,
closure-typed, or `NSMutable*` stored member. Pure-value structs (all stored
members are value types) satisfy the property trivially and must **never** be
surfaced. So the tool targets the small, high-yield subset by construction —
the ideal shape for this engine, and better-targeted than most candidate
extensions.

## 3. What already exists (the leverage)

This is mostly wiring, not new machinery. The pieces:

| Need | Already shipped | Where |
|---|---|---|
| Stored-member names + type spellings, folded across a corpus | `TypeDecl.storedMembers[].typeName`, `.kind`, `.inheritedTypes`; `FunctionScanner.scanCorpus` merges records per type name | `Sources/SwiftInferCore/TypeDecl.swift`, `FunctionScannerVisitor+TypeDecls.swift` |
| Three-valued corpus classifier (precedent) | `EquatableResolver`, `IdentifiableResolver` (`.identifiable / .notIdentifiable / .unknown` from folded `TypeDecl`s) | `Sources/SwiftInferCore/*Resolver.swift` |
| Instance construction from `init()` + a sequence of mutating ops | kit `ActionSequenceFactory` + `StatefulGuard` (v2.2.0); `checkInteractionInvariantPropertyLaws` step-driver (v2.4.0) | `SwiftPropertyLaws/Sources/PropertyLawKit/Public/` |
| Value generators for plain value types | kit `DerivationStrategist` (memberwise-Arbitrary; `.todo` for non-raw members) | `SwiftPropertyLaws` v1.6.0+ |
| Path-dependency verifier over a packaged corpus | `CorpusPackager`, `VerifierWorkdir`, `VerifierSubprocess`, `VerifyResultParser` | `Sources/SwiftInferCLI/` |
| Type-carrier discovery precedent (recognize a shape, emit a candidate) | `ViewModelDiscoverer`, `ReducerDiscoverer`, `RuleVisitorDiscoverer` | `Sources/SwiftInferCore/` |

Two consequences worth stating up front:

- **The kit's stateful machinery is the right substrate.** The very types that
  can violate value semantics (class/closure members) are the ones
  `DerivationStrategist` *cannot* auto-generate arbitraries for (non-raw members
  → `.todo`). So instances are built via `init()` + a generated **sequence of
  mutating ops**, not arbitrary generation — which is exactly what
  `ActionSequenceFactory` + the v2.4.0 step-driver already do. Example 3
  (closure capture) needs the multi-step form for the same reason.
- **The discovery signal is a textual/corpus fold**, identical in shape to
  `IdentifiableResolver` — no new AST pass.

## 4. The discovery signal (precision-first)

A struct `S` is a **ValueSemantic candidate** iff:

1. `S.kind == .struct` (classes/actors have reference semantics by definition —
   out of scope; enums with no stored class payload are trivially value types), AND
2. `S` declares ≥1 mutating method (the mutation surface to test), AND
3. ≥1 stored member of `S` is **reference-backed**, by `TypeDecl.storedMembers`
   textual classification folded across the corpus:
   - a closure type (`(…) -> …`, or `@escaping`/`@Sendable`-prefixed), OR
   - a known reference container (`NSMutable*`, `NSCache`, `NSHashTable`, …;
     curated list), OR
   - a member whose `typeName` resolves to a `.class`/`.actor` `TypeDecl` in the
     corpus (the `EquatableResolver`-style fold), OR
   - a `final class Storage`-style private nested class (the CoW shape).

**Pure-value structs (no reference-backed member) are excluded** — the property
is trivially true; surfacing it is the Daikon flood. A member whose type is
`.unknown` (external, unseen) is *not* enough on its own — conservative default
is exclude, mirroring the `IdentifiableResolver` gate. This keeps recall low and
precision high by design.

Naming is **not** a requirement here (unlike the idempotence vocabulary) — the
signal is purely structural, which is stronger. A declared `: ValueSemantic`
conformance (once the kit protocol exists) is an explicit opt-in that promotes a
candidate regardless of the structural heuristic.

## 5. Design

Split cleanly across the two repos, mirroring the existing kit/engine seam.

### 5.1 Kit side (SwiftPropertyLaws — next minor, e.g. v3.3.0)

- **`public protocol ValueSemantic`** — `associatedtype` is `Self`; the
  law-bearing scaffolding in the Semigroup/Monoid mold. Conformer contract:
  `Equatable` (to observe divergence) + a way to build a base instance
  (`static var probe: Self`, or reuse the `initialState` convention from the
  InteractionInvariant family).
- **`checkValueSemanticPropertyLaws(for:probe:mutations:…)`** — the runtime
  harness. Single-step form (Examples 1–2): `var b = a; b.apply(m); assert a == aSnapshot`.
  Multi-step form (Example 3): drive `b` and `a` through interleaved mutation
  sequences via the shipped `ActionSequenceFactory` step-driver, assert `a`
  matches an interference-free replay. One Strict-tier law:
  `copyMutationDoesNotLeak`. Reuses the internal `LawCheck` / `PerLawDriver`
  infrastructure the algebraic + interaction harnesses already use.
- **(later) `@ValueSemanticTests` peer macro** — mirrors `@InteractionInvariantTests`
  (v2.5.0): auto-emit the CI test from a conformer. Optional; the harness can be
  wired by hand first.

### 5.2 Engine side (SwiftInferProperties)

- **`ValueSemanticDiscoverer` (Core)** — folds `TypeDecl`s, applies §4, emits a
  `ValueSemanticCandidate` (type name, mutation surface = the mutating methods,
  the reference-backed members + *why* each qualified, constructibility). Cross-
  file/extension-aware via the shared `SwiftSourceFiles.sorted(in:)` +
  `FunctionScanner.scanCorpus` fold, like `ViewModelDiscoverer`.
- **A new PRD section (NOT §8).** The original proposal said "§8," but PRD v2.0
  §8 is now **ActionSequenceGenerator** — that reference is stale. ValueSemantic
  is orthogonal to the seven interaction families (it is type-level, not a
  predicate over reducer state), so it gets its **own new section** (next
  available number) describing the type-level family.
- **Verify emission** — a `ValueSemanticStubEmitter` builds a verifier that
  imports the packaged corpus (`CorpusPackager` → `VerifierWorkdir` path-dep, the
  proven MVVM/algebraic mechanism), constructs the probe, drives each mutating
  op on a copy, and checks the original via `==`. Same `VERIFY_*` marker
  contract, `exit(1)` on FAIL, deterministic seed.
- **Shrink to a minimal repro (Chapter 9 §9.2.3).** A failure is only useful if
  it names the offending method. The book's target is shrinking a random
  copy/mutation sequence to the minimal **"copy, then call *this one* method"**
  reproduction. The kit's shrinking (landed v3.x, per the ValueSemantic
  proposal's workstream #2) already powers command-sequence shrinking via the
  stateful harness; the emitter should surface the shrunk script (the mutating
  method + its arg) in the FAIL disclosure, not just "some sequence leaked."
  Explainability is a first-class output (PRD §4.5), and here the shrunk repro
  *is* the explanation.
- **Tiering (conservative).** Surface at `.possible` by default (a new inference
  source ships default-hidden per the PRD posture), promoted on
  `measured-bothPass` through the existing verify-evidence fold
  (`InteractionVerifyEvidenceScoring`-style join) — never on the static signal
  alone. A measured `defaultFails` is a *real* found bug (the leak), surfaced.

## 6. Slicing (each slice independently landable + testable)

1. ✅ **SHIPPED (kit v3.4.0) — Kit protocol + single-step harness** (Examples 1–2).
   `checkValueSemanticPropertyLaws` with the `copyMutationDoesNotLeak` law;
   independent-twin comparison; deliberately-leaky + correct-CoW fixtures. *The
   load-bearing slice.*
2. ✅ **SHIPPED — Engine recognition.** `ValueSemanticDiscoverer` +
   `ValueSemanticCandidate` (corpus fold; closure / mutable-container / corpus-
   class shapes; pure-value/class/actor/unknown/no-surface guards), surfaced as a
   `discover-reducers` section (empty-sentinel when absent). No invariant emitted.
3. ✅ **SHIPPED — Verify emission end-to-end.** `ValueSemanticStubEmitter` emits a
   verifier that path-deps the packaged corpus + `PropertyLawKit`, retroactively
   conforms the imported struct (deriving `Mutation`/`apply` from the mutation
   surface), and runs the kit law. `SafeStore` → bothPass, `LeakyStore` →
   defaultFails; `.subprocess` measured test.
4. ✅ **SHIPPED (kit v3.5.0) — Multi-step (Example 3).** Second law
   `copyMutationDoesNotLeakUnderInterleaving` (interference-on-a-copy then own-
   script vs interference-free replay). `ClosureCounter` fixture → defaultFails,
   caught only by this law.
5. ✅ **SHIPPED — Productionize.** `@ValueSemanticTests` kit macro (v3.6.0) +
   shrunk minimal repro in FAIL output + the **`verify-value-semantics`
   command** (§11): a purpose-built command, NOT the evidence-join fold the plan
   first imagined — value semantics is *type-level* with *inverted polarity* (a
   `defaultFails` is the confirmed-leak payoff, not a suppression), so it must
   not ride the `InteractionInvariantSuggestion` machinery. Both reachability
   modes shipped: 5a (standalone packaging) + 5b (path-dep + `@testable` for real
   `internal` types; command defaults to 5b). See §11.
6. ⬜ **(optional companion) Identity stability for reference types** — the
   Chapter 9 §9.3 dual law (`===`/vended-id invariant under mutation, changed
   under copy) for `class`/`actor` candidates, same plumbing, different predicate.
   Not built.

## 7. Open questions / risks

- **Constructibility gate.** A probe instance must be buildable. Reuse the
  MVVM `constructibility` gate (`Type()` reachable, or dependency-fakeable). A
  struct requiring un-fakeable init args → **skip + disclose** (never a wrong
  verifier), the established posture.
- **Observability requires `Equatable`.** The original must be comparable to its
  pre-mutation snapshot. Non-`Equatable` `T` → gate (mirror the refint
  `IdentifiableResolver` skip), or snapshot a field projection. Decide in slice 1.
- **False positives on *correct* CoW.** A properly-implemented CoW struct MUST
  pass — the harness compares observable state, and correct CoW is observably
  independent, so this is sound *if* the mutation surface is driven faithfully.
  Guard with a correct-CoW fixture in the slice-1 corpus (positive control).
- **Enumerating the mutation surface.** Use the `ViewModelDiscoverer` action-
  detection precedent (a method that mutates a stored member). Getters/`private`
  helpers excluded.
- **Value in a given codebase scales with reference-backed surface.** High for
  SDK/framework/bridging code; low for a plain SwiftUI app. Not a universal win —
  worth stating in the PRD section's "when this applies."

## 8. Non-goals / scope boundaries

- **Classes/actors — for the copy-independence property.** Reference types by
  definition; out of scope for *that* property. They ARE the subject of the
  optional identity-stability companion (§1, slice 6) — a different predicate,
  not the copy-mutate-compare law.
- **Thread-safety / data races.** A different property (Sendable/actor isolation);
  not this.
- **Proving the *absence* of a leak for `.unknown` members.** Conservative skip,
  not a claim.
- **Retrofitting `§5` function-level templates.** This is a new type-level
  section; the two don't share a template shape.

## 9. Prerequisites & sequencing

- Kit slice 1 is the only hard prerequisite for engine slices 3–5 (the verifier
  imports the kit protocol). Engine slice 2 (recognition) can land against a
  stubbed protocol or none.
- The multi-step harness (slice 4) depends on the shipped v2.2.0–v2.5.0 stateful
  surface — already available; no new kit primitive required beyond the
  `ValueSemantic` protocol itself.
- Recommended order: kit §5.1 slice 1 → engine slice 2 → engine slice 3 → slice 4
  → productionize. Ship Examples 1–2 first; defer Example 3 until the single-step
  path is proven end-to-end.

## 10. What shipped (2026-07-06)

Built in the order above; the actual sequencing matched the plan. The plan's
"§8" reference was stale (PRD v2.0 §8 is ActionSequenceGenerator) — ValueSemantic
remains a new type-level section, unassigned here. During slice 1 the kit's
`v3.3.0` tag was found to already exist (composedGenerator); the ValueSemantic
work was released as **v3.4.0** instead (the commit message's "(v3.3.0)" is a
known mislabel, corrected by the v3.4.0 tag notes).

### Kit (`SwiftPropertyLaws`)

| Release | Adds | Key files |
|---|---|---|
| **v3.4.0** | `ValueSemantic` protocol + `checkValueSemanticPropertyLaws` (single-step `copyMutationDoesNotLeak`) | `PropertyLawKit/Public/ValueSemantic.swift`, `ValueSemanticLaws.swift` |
| **v3.5.0** | second law `copyMutationDoesNotLeakUnderInterleaving` (multi-step, Example 3) | `ValueSemanticLaws.swift` (+`ClosureLeak` fixture) |
| **v3.6.0** | `@ValueSemanticTests` peer macro (auto CI test) | `PropertyLawMacro/PropertyLawMacro.swift`, `PropertyLawMacroImpl/ValueSemanticTestsMacro.swift`, `Plugin.swift`, `Diagnostics.swift` |

Kit design notes: leak observation is **independent-twin comparison** (compare
`original == reference` after mutating only a copy — a value-copied snapshot
would share the leaky reference and hide the bug). The mutation surface is a
`CaseIterable` enum so `ActionSequenceFactory` (v2.2.0) samples/shrinks it. Both
laws are Strict; failures shrink to a minimal script (Ch. 9 §9.2.3).

### Engine (`SwiftInferProperties`)

| Slice | Files | Tests |
|---|---|---|
| 2 recognition | `SwiftInferCore/ValueSemanticCandidate.swift`, `ValueSemanticDiscoverer.swift`; `SwiftInferCLI/DiscoverReducersCommand.swift` (section) | `ValueSemanticDiscovererTests` (10), `DiscoverReducersCommandTests` (+3 render) |
| 3 verify emission | `SwiftInferCLI/ValueSemanticStubEmitter.swift`; `Tests/Fixtures/valuesemantic-verify-corpus/{SafeStore,LeakyStore}.swift` | `ValueSemanticStubEmitterTests` (4), `ValueSemanticVerifyMeasuredTests` (`.subprocess`) |
| 4 multi-step | `Tests/Fixtures/valuesemantic-verify-corpus/ClosureCounter.swift`; kit pin → 3.5.0 | measured test asserts `ClosureCounter` → defaultFails |

Discovery signal: `struct` + ≥1 reference-backed stored member (closure /
`NSMutable*`-family container / corpus `class`/`actor`) + ≥1 mutation-surface
method (`mutating`, or `Void`-returning non-`mutating` — the Example-1 shape).
The verifier retroactively conforms the imported corpus struct to `ValueSemantic`
(deriving `Mutation`/`apply` from the payload-free mutation surface), keeping the
packaged corpus dependency-free. Verify-readiness gates: non-`Equatable` or no
payload-free mutation → skipped.

**Known limitation (surfaced by a slice-2 dogfood):** a stored member declared
without a type annotation (`var storage = Storage()`) isn't classified — the
scanner captures declared type spellings only (engine-wide textual-type posture);
annotate to detect.

## 11. Slice 5 (remaining) — `verify-value-semantics` command (build plan)

The deferred half of slice 5. **Not** a fold into `discover-interaction`: value
semantics is type-level and its polarity is inverted from the interaction
families — a `measured-defaultFails` is the *payoff* (a confirmed leak), not a
suppression — so reusing the interaction evidence fold would hide the very bugs
the feature finds. The right shape is a **purpose-built verify command** that
turns recognition ("here are structs that *could* leak") into detection ("here
are the ones that *do*, with a minimal repro each").

### Goal
`swift-infer verify-value-semantics --target MyKit` → discovers candidates,
verifies each, and reports **confirmed leaks with the kit's shrunk minimal
repro**, safe types quietly, and honestly-skipped ones with a reason.

### Reuse (most of the pipeline already exists)
`ValueSemanticDiscoverer.discover(directory:)`, `ValueSemanticStubEmitter`
(the verify-readiness gate + emit), `CorpusPackager`, the verifier manifest,
`VerifierSubprocess.runSwiftBuild/runVerifierBinary`, `VerifyResultParser`. The
per-candidate loop in `ValueSemanticVerifyMeasuredTests.verify(...)` is
essentially the command's core already.

### Reachability decision — SPIKED ✅
Real targets aren't the self-contained, `public`, dependency-free fixture the
measured test packages; their types are usually `internal` with dependencies.
**Confirmed by spike (2026-07-06):** a verifier that `.package(path:)`-depends on
the user's package and uses **`@testable import <Target>`** reaches, extends, and
**retroactively conforms `internal` types** — because `VerifierSubprocess`
already builds with `-Xswiftc -enable-testing`, and the emitter's `public`
conformance witnesses satisfy an internal type's conformance (public ≥ internal).
The full retroactive `ValueSemantic` conformance on an `internal` type + kit
harness compiles and links across the path dependency. So the command can verify
real `internal` types, not just `public` ones — the key enabler for usefulness.

### Command surface
`SwiftInferCommand.VerifyValueSemantics` (mirrors `verify-interaction`):
`--target <name>` (resolves `Sources/<target>/`), `--fail-on-leak` (CI gate;
**default exit 0** per the advisory posture, PRD §3.5), later `--max-parallel`.

### Per-candidate result taxonomy (drives the report; polarity-correct)
1. **`confirmedLeak(repro)`** ← `defaultFails` — surfaced prominently; repro from
   `VERIFY_DEFAULT_INPUT` (kit's already-shrunk minimal script).
2. **`verifiedSafe`** ← `bothPass` — quiet.
3. **`notVerifiable(reason)`** ← emitter gate (non-`Equatable` / no payload-free
   mutation).
4. **`buildFailed(excerpt)`** ← verifier didn't compile.
5. **`error`** ← runtime/parse error.
A pure `render([CandidateOutcome]) -> String` (sorted, byte-stable) keeps it
unit-testable.

### Slicing
- **5a — ✅ SHIPPED.** `VerifyValueSemantics` subcommand +
  `ValueSemanticVerifier.verify(...)` (standalone packaging) + the
  `ValueSemanticVerifyResult` taxonomy + the byte-stable
  `ValueSemanticVerifyReport` renderer + `--fail-on-leak`. Emitter enriched to
  surface the kit's shrunk minimal counterexample (catch `PropertyLawViolation`
  → `CheckResult.counterexample`). Measured test drives the production verifier
  against `valuesemantic-verify-corpus/`.
- **5b — ✅ SHIPPED.** `ValueSemanticVerifier.verifyInPackage(...)`:
  `.package(path:)` on the user's package + `@testable import` (emitter `testable`
  flag) reaches real `internal` types; the command **defaults to 5b**
  (`--self-contained` selects 5a). One workdir reused → the path-dep + kit graph
  builds cold once, the rest incremental. Fixture
  `valuesemantic-package-corpus/` (a real package with INTERNAL PackageLeaky +
  PackageSafe) + `ValueSemanticPackageVerifyMeasuredTests`. Bounded parallelism
  left as an optional future add.

### Scope boundaries (v1 does NOT)
Multi-argument mutation payloads (gated, the value-generation slice); dependency
faking for non-constructible types (portable from MVVM slice 9 later); the
identity companion (slice 6).

### Effort
Medium, high value: slices 2–4 did the hard parts, and the 5b reachability
unknown is now spiked. This is productionizing a proven pipeline with
polarity-correct reporting.

## 12. Slice 6 — identity/copy laws for reference types (build plan)

The Ch. 9 §9.3 companion: value semantics is a *struct* property
(copy-independence); slice 6 is the *class* dual. Two laws, of which only the
first is recommended:

- **Law A — defensive-copy correctness.** A class's `copy()`/`clone()` must
  return an instance equal by value but a **distinct object**, and mutating that
  copy must not affect the original. Catches `return self` AND shallow copies
  that share a mutable reference member.
- **Law B — identity stability under mutation** (`==`/`hashValue` invariant under
  mutation). Subtler to discover; overlaps the kit's Hashable-consistency law
  (Ch. 8). **Shelved** unless specifically wanted.

### Key insight — Law A ≈ value semantics via `copy()`
Defensive copy decomposes into **A1 distinctness** (`x.copy() !== x`, catches
`return self`) + **A2 independence** (mutating `x.copy()` must not affect `x` —
*exactly* the value-semantics copy-mutate-compare law, with the copy operation
being `x.copy()` instead of `var b = a`). So the kit harness is a small variant
of `checkValueSemanticPropertyLaws`: same independent-twin comparison + mutation
scripts, but copy via `copyUnderTest()`, no `inout` (classes mutate in place),
plus the `!==` assertion.

### Reuse (nearly the whole stack)
Verify pipeline (`CorpusPackager`, `VerifierSubprocess`, `VerifyResultParser`,
the 5b path-dep + `@testable` mode, the warm-workdir loop), the result taxonomy +
renderer (polarity is identical — a confirmed bug is the payoff), and the
`FunctionScanner` corpus-fold (it already captures methods with return types +
containing type).

### Genuinely-new pieces
1. **Kit `DefensiveCopy` protocol + `checkDefensiveCopyPropertyLaws`** (v3.7.0):
   `AnyObject, Equatable`, `associatedtype Mutation: CaseIterable`, `makeProbe()`,
   `copyUnderTest() -> Self`, `apply(_:to:)`. Two Strict laws:
   `copyIsDistinctInstance` (`!==`) + `copyIsIndependent` (value-semantics check
   via `copyUnderTest()`).
2. **`DefensiveCopyDiscoverer`** (or extend `ValueSemanticDiscoverer`): a
   candidate is a **`class`** that declares a curated copy-verb method
   (`copy`/`clone`/`copied`/`duplicate`/`mutableCopy`/`deepCopy`) returning
   `Self`/its own type, is `Equatable`, and is constructible. High-precision —
   only classes with an explicit copy method.
3. **A stub-emitter variant** retroactively conforming the class to
   `DefensiveCopy` (`copyUnderTest()` = the discovered method).
4. **`@DefensiveCopyTests` macro** (kit, mirrors `@ValueSemanticTests`) —
   optional, later.

### Design decisions
- **Fold into `verify-value-semantics`** as a second candidate kind (unified
  report; matches the Ch. 9 pairing) rather than a sibling command.
- Copy-verb name-gating keeps precision high (conservative posture); a `Self`-
  returning method on a class is a strong structural signal but name-gated.
- Constructibility / Equatable gates reuse the value-semantics gates verbatim.

### Slicing
- **6a — kit `DefensiveCopy` protocol + harness** (v3.7.0). Fixtures: correct
  deep-copy (bothPass), `return self` (fails A1), shallow copy sharing a
  reference member (fails A2). *Load-bearing.*
- **6b — engine discovery.** `DefensiveCopyDiscoverer` + candidate + a
  `discover-reducers` line; precision guards (non-class / no copy method /
  non-Equatable excluded).
- **6c — verify wiring.** Emitter variant + fold into `ValueSemanticVerifier`
  (both modes) + report; measured `.subprocess` test.
- **6d — `@DefensiveCopyTests` macro** (optional).
- **6e — Law B** — shelved unless wanted.

### Scope boundaries (Law A v1 does NOT)
Multi-arg mutation payloads (gated); actors; `NSCopying`-only classes without an
in-type copy method (optional later); Law B.

### Effort
~2 days for Law A end-to-end — slices 1–5 built the verify machinery and Law A's
harness is a small variant of the value-semantics one.
