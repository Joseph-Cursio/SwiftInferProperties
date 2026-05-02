# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository state

**M1 + M2 + M3 + M4 + M5 + M6 + M7 shipped; v0.4 M8 (algebraic-structure composition cluster) next.** M7 (RefactorBridge + Option B prompt + monotonicity / invariant-preservation templates per PRD v0.4 §5.8) is complete on `main`. Sub-milestones M7.1–M7.6 landed as individual `feat(M7.x):` commits on top of the M1.1–M1.7 + M2.1–M2.6 + M3.1–M3.6 + M4.1–M4.5 + M5.1–M5.6 + M6.1–M6.6 series. M7 ships **MonotonicityTemplate** (M7.1 — `T → Comparable U` with curated codomain set + `length`/`count`/`size`/`*Count`/`*Size` naming, Possible-by-default per the §5.2 caveat); **InvariantPreservationTemplate** (M7.2 — annotation-only, fires only when `@CheckProperty(.preservesInvariant(\.foo))` is detected by the FunctionScanner extension; macro impl recognises the case and emits no peer per M7.2.a deferral; CheckPropertyKind drops to `@unchecked Sendable` because `AnyKeyPath` isn't Sendable in Swift 6.1); **LiftedTestEmitter monotonic + invariantPreserving arms** (M7.3 — multi-line sample for monotonicity's pair-sort, byte-stable goldens; the makeTestStub family was generalized to take both sample + property expressions); **LiftedConformanceEmitter** (M7.4 — pure-function emit of `extension TypeName: Protocol {}` with §4.5 explainability comment header; arms ship for `Semigroup` and `Monoid`; `writeoutPathPrefix` and `relativePath(typeName:protocolName:)` helpers per PRD §16 #1); **RefactorBridgeOrchestrator + [A/B/s/n/?] interactive prompt + decisions schema v2** (M7.5 — orchestrator scans suggestions, returns per-type proposals via `RefactorBridgeProposal` carrying `relatedIdentities`; per-type aggregation collapses subsequent suggestions to `[A/s/n/?]` after a B-decided type; B-arm route writes `Tests/Generated/SwiftInferRefactors/<TypeName>/<ProtocolName>.swift`; `Decision.acceptedAsConformance` case + schema v2 bump with v1 records loading cleanly). **The §5.8 M7 acceptance bar (a–h) is met (M7.6):** monotonicity surfaces under `--include-possible`, invariant-preservation gates strictly on annotation, both lifted-test arms are byte-stable, both lifted-conformance arms are byte-stable, the `[A/B/s/n/?]` extension surfaces only when a proposal is attached to the suggestion, the v2 decisions schema round-trips byte-identically through the new case, the §13 perf budget holds at 0.566s synthetic / 1.485s swift-collections *with M7's two new templates active*, and the §16 #1 hard-guarantee extension confirms RefactorBridge B accepts write only under `Tests/Generated/SwiftInferRefactors/<TypeName>/<ProtocolName>.swift`.

**Kit-side coordination.** M7 emits `extension TypeName: Semigroup {}` / `Monoid {}` against `import ProtocolLawKit` — neither protocol existed in stdlib or in earlier kit releases. They were added kit-side in **SwiftProtocolLaws v1.8.0** (commits `362322e`/v1.8.1 Semigroup + `88cc4a1`/v1.8.2 Monoid + `6c4ec2a`/v1.8.3 macro/discovery integration + `1b3af7d`/v1.8.4 release docs), the kit's first kit-defined protocol cluster. SwiftInferProperties consumes the kit via versioned dep (`from: "1.8.0"`) as of commit `c143258` (2026-05-02); the local-path dep used through M7 development is retired.

**M8 kit-side expansion (planned).** M8.0 (per `docs/M8 Plan.md`) extends the kit cluster with three more protocols — **`CommutativeMonoid: Monoid`** (`combineCommutativity` law), **`Group: Monoid`** (`inverse` requirement + `combineLeftInverse` / `combineRightInverse` laws), **`Semilattice: CommutativeMonoid`** (`combineIdempotence` law) — shipped as SwiftProtocolLaws **v1.9.0**, mirroring the v1.8.0 four-commit cadence. Once v1.9.0 lands, SwiftInferProperties bumps `Package.swift` from `from: "1.8.0"` to `from: "1.9.0"` and M8.5 emits real kit-defined writeouts for those three arms (vs the previously-planned claim-only comment-block fallback). PRD §5.4's kit-protocol-target column will need a corresponding refresh post-M8.0 to drop the "(no kit protocol yet — claim only; M8)" language for Group / Semilattice. Out of v1.9.0 scope: kit-side `Ring` (two-op shape — bigger design surface, deferred to v1.1+), kit-side `CommutativeGroup` (rare in idiomatic Swift, defer until corpora justify), kit-side `Group acting on T` (function-space carrier doesn't fit the existing kit shape).

**Cross-validation `+20` from a real TestLifter is still gated** on TestLifter M1 in this repo (no TestLifter target started); M3.5's `crossValidationFromTestLifter` parameter remains dormant. The next milestone is **M8 — algebraic-structure composition cluster** (PRD v0.4 §5.4): the multi-template signal-accumulation pass that promotes `Semigroup` claims to `CommutativeMonoid` (commutativity + associativity + identity), `Group` (Monoid + inverse), `Semilattice` (commutativity + associativity + idempotence), `Ring` (two compatible structures); `inverse-pair` template for non-Equatable cases; and the LiftedTestEmitter arms for `commutativity` / `associativity` / `identity-element` so M6.4's "no stub writeout available for template X in v1" diagnostic finally retires across the whole template surface.

## What this repo is

**SwiftInferProperties** — type-directed property inference for Swift. Surfaces idempotence, round-trip pairs, and algebraic-structure (semigroup / monoid / group / semilattice / ring) candidates from function signatures, cross-function pairs, and existing unit tests. All output is human-reviewed; nothing auto-executes.

The package is a one-way downstream of [SwiftProtocolLaws](https://github.com/Joseph-Cursio/SwiftProtocolLaws):

```
SwiftInferProperties → SwiftProtocolLaws (PropertyBackend, DerivationStrategist) → swift-property-based
```

`Package.swift` references SwiftProtocolLaws via a versioned URL dep (`from: "1.8.0"`) as of commit `c143258`. The local-path dep used through M1–M7 development was retired once kit v1.8.0 shipped the Semigroup/Monoid cluster M7.4 needed.

## Where to look

| Question | File |
|---|---|
| Product scope, milestones (M1–M8), success criteria | `docs/SwiftInferProperties PRD v0.4.md` |
| **Current milestone execution plan** | `docs/M8 Plan.md` (v0.4 §5.4 + §5.8) |
| Closed milestone plans | `docs/archive/M1 Plan.md` ... `docs/archive/M7 Plan.md` |
| What v0.3 changed vs v0.1/v0.2 | The `Supersedes:` line points at git history of the SwiftProtocolLaws repo, where v0.1 and v0.2 lived before the split |
| ProtocolLawKit / ProtoLawMacro source of truth | the SwiftProtocolLaws repo, not this one |

## Design decisions baked into v0.3

A future Claude implementing the package should follow these decisions rather than re-litigate them. They live in the PRD; this is a quick map.

- **Conservative inference engine — high precision, low recall.** PRD §3.5. False positives are more damaging than missed opportunities; when in doubt, default to whichever option produces fewer suggestions.
- **All output is opt-in and human-reviewed.** Never auto-applies, never auto-executes, never auto-commits. Even in CI mode (PRD §9), it emits warnings, not failures.
- **The Daikon trap is the failure mode to avoid.** If benchmark calibration shows we're producing too many suggestions, the answer is to raise thresholds, not to add filters on top.
- **Three v1 contributions, one v1.1.** TemplateEngine + RefactorBridge + TestLifter ship in v1. SemanticIndex is deferred to v1.1 with the Constraint Engine, Domain Template Packs, IDE integration, and Semantic Linting bridge listed as the v1.1+ trajectory in PRD §20.
- **Explainability is a first-class output.** Every suggestion ships both "why suggested" and "why this might be wrong." PRD §4.5.
- **Generator inference delegates to SwiftProtocolLaws.** Don't reimplement the priority list — call into the shared `DerivationStrategist`. PRD §11.

## Build & test

- `swift package clean && swift test` (per the global `~/CLAUDE.md`) on session start.
- The skeleton expects `../SwiftProtocolLaws` to exist as a sibling checkout of [Joseph-Cursio/SwiftProtocolLaws](https://github.com/Joseph-Cursio/SwiftProtocolLaws). CI checks both repos out side-by-side; locally, your `~/xcode_projects/` should already have both.
- SwiftLint config lives at `.swiftlint.yml`; `swiftlint lint --quiet` should be silent.
