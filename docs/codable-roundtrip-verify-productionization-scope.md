# Scope — productionize codable-round-trip into `verify --all-from-index` (2026-07-20)

The `codable-round-trip` template ships with **discover** + a **corpus-fixture
measured verify** (`CodableRoundTripStubEmitter`, driven by
`CodableRoundTripCorpusMeasuredTests`). This scopes the remaining
productionization: wiring it into the live-index `verify --all-from-index` path so
`swift-infer verify` runs it on a user's own `.swiftinfer/index.json`, generating
values via `DerivationStrategist` instead of a hand-written `valueExpression`.

## Where codable-round-trip stands at each pipeline stage

The measured-verify pipeline is: **discover → index (project Suggestion →
`SemanticIndexEntry`) → verify (resolve → emit stub → build workdir → run →
parse)**.

| Stage | Status | Work |
|---|---|---|
| **1. Index projection** (`IndexCommand+Projection`) | **Works as-is** — projection is generic (`templateName: suggestion.templateName`) and already attaches the carrier's `typeShape` + `carrierTypeName` (both set by the template's `carrier`/`carrierType` closures). A codable-round-trip suggestion indexes with everything the generator needs. | **0 code** |
| **2. Verify dispatch** (`VerifyCommand+TemplateDispatch`, `StrategistDispatchEmitter`) | **The gap.** `codable-round-trip` is in neither `supportedTemplates` nor `autoDerivable`, has no `resolveFunctionCalls` branch, and no `compose*Pass`. | see below |
| **3. Generator resolution** (`StrategistDispatchEmitter.recipe` → `DerivationStrategist.strategy(for:)`) | **Reuses the strategist wholesale** — a Codable carrier resolves through the existing `.caseIterable` / `.memberwiseArbitrary` / `.userGen` / `.rawRepresentable` strategies from its `typeShape`, exactly as the algebraic round-trip (`Move`) does. | **0 new code**, bounded by existing gates |
| **4. Workdir** (`VerifierWorkdir`, `WorkdirMode.algebraic`) | **Rides `.algebraic` + `--corpus-module`** — that mode already declares pointfree-`swift-gen` (for `Gen<T>.run(using:&rng)`) + the `userPackage` path-dep (the corpus type). `Foundation` (for JSON) is free. | **0 new mode** |

## The Stage-2 work, itemized

1. **Register the template** — add `"codable-round-trip"` to `supportedTemplates`
   and `autoDerivable` (the `--all-from-index` inclusion lists). *Trivial.*
2. **`composeCodableRoundTripPass`** — one new compose function in
   `StrategistDispatchEmitter+Templates.swift`, mirroring `composeRoundTripPass`
   but swapping the oracle from `inverse(forward(value)) != value` to
   `JSONDecoder().decode(T.self, from: JSONEncoder().encode(value)) != value`. It
   reuses the shared `let value = defaultGenerator.run(using: &rng)` scaffolding +
   `VERIFY_*` markers, and must add `import Foundation` to the stub's import set
   (`recipe.imports`). *Small (~30 lines).*
3. **Carrier-only dispatch threading** — the **real friction**. Every current
   template resolves a forward/inverse (or single) *function call* via
   `resolveFunctionCalls`; codable-round-trip has **no function pair** — the oracle
   is the carrier's own `Codable` conformance, invoked through JSON. So the
   dispatch needs a branch that supplies an empty/sentinel `functionCalls` and
   routes to `composeCodableRoundTripPass` on `carrierType` alone (the emit switch
   at `StrategistDispatchEmitter.swift:341` gets a `case "codable-round-trip"`).
   This breaks the "every entry has a callable pair" assumption and is the piece
   that needs care. *Medium.*
4. **Equatable gate** — the JSON oracle compares `decode(encode(x)) == x`, so `T`
   must be `Equatable`. A non-`Equatable` custom-Codable carrier should record
   `architectural-coverage-pending` (reuse the `EquatableResolver` /
   `unsupported`-shape pattern the `inverse-pair` template already uses), never a
   spurious build failure. *Small.*

## New gates / caveats

- **Equatable required** (gate above) — a clean skip, not a false positive.
- **Generatability wall (shared with all algebraic verify).** The strategist can
  build `T` only when it is a `CaseIterable` enum or a struct with a **public**
  memberwise/`init` (a struct relying on the *synthesized* memberwise init hits
  `.todo` — the init is `internal`, unreachable across the corpus-module boundary)
  → `architectural-coverage-pending`. Real custom-Codable types are frequently
  **generic** (`OrderedDictionary<Key, Value>` — the strategist can't generate an
  unbound generic) or lack a public init, so `--all-from-index` verifies only the
  **concrete, public-init, Equatable** custom-Codable subset. Discover still
  surfaces all of them (the primary, human-reviewed output).
- **Top-level JSON fragment** — a `singleValueContainer` carrier encodes to a bare
  JSON scalar, which older `JSONEncoder` rejected as a top-level fragment. Keyed
  containers (the corpus uses them) sidestep it; note it in the caveat.

## Effort & reach

- **Effort: ~1 focused session, medium, mostly mechanical.** The compose function,
  Foundation import, and list registrations are small; the carrier-only dispatch
  threading (item 3) is the one non-mechanical wrinkle. No strategist, workdir, or
  index-schema changes.
- **Reach: modest incremental.** The corpus-fixture path (shipped) already
  regression-guards the verify *logic*. Productionization's marginal value is
  running codable-round-trip on a user's **live index** without hand-writing a
  corpus — but bounded by the generatability wall above to the concrete/public-init
  subset. The high-value output for the gated (generic / no-public-init) majority
  is the **discover** suggestion, which already ships.

## Recommendation

Worth doing **if** you want `swift-infer verify` / `--all-from-index` surveys to
include codable-round-trip on live indexes; otherwise the shipped corpus path
already proves and guards the mechanism. It extends the default measured-verify
surface, so recommend **owner sign-off** first (the PRD §3.5 posture, as with the
cardinality/biconditional carve-outs). Build sequence, each committed with
`make test-fast` green:

1. `composeCodableRoundTripPass` + a `StrategistDispatchEmitter` unit test (assert
   the emitted stub's JSON oracle + Foundation import).
2. Carrier-only dispatch threading + template registration + the Equatable gate.
3. Reindex the `codable-roundtrip-corpus` under a module and add a
   `verify --all-from-index --corpus-module` measured test (Temperature
   `measured-bothPass` → promote; ScaledRatio `measured-defaultFails` → suppress) —
   the end-to-end live-path proof, superseding the hand-`valueExpression` corpus
   test.

**Pre-build validation:** confirm the corpus's `Temperature` / `ScaledRatio`
(which carry a custom `init(from:)` *and* a public `init(value:)`) resolve to a
generatable strategy and not `.todo`; if the custom decode-init shadows the
memberwise one, the corpus types may need a `CaseIterable` or explicit-`Gen` shape,
exactly as the algebraic `Move`/`Confidence` carriers were shaped for verifiability.
