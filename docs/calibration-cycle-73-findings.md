# v1.76 Calibration Cycle 73 — Findings (V2.0.M2: kit-side ActionSequence)

Captured: 2026-05-15. swift-infer at v1.76. SwiftPropertyLaws at v2.2.0 (local tag).

## Headline

**First cross-repo v2.0 cycle.** v1.75 closed M1 (reducer discovery
complete across A/B/C). v1.76 ships **V2.0.M2** — the kit-side
additive surface that M3's in-process verify path will consume.

Two new public types land in SwiftPropertyLaws v2.2.0:

- `StatefulGuard<Action>` — per-element filter protocol
  (`wouldAllow(_ next: Action, given history: [Action]) -> Bool`).
- `ActionSequenceFactory` — namespace housing the primary
  `actionSequence(from:length:statefulGuards:)` entry (any
  `Generator<Action, _>` → `Generator<[Action], _>`) and the
  convenience `actionSequence(forCaseIterable:length:statefulGuards:)`
  entry (CaseIterable enums only).

Default sequence length is `0...16` per PRD v2.0 §8.1. Per-element
filtering (not per-sequence rejection) terminates by construction
under arbitrarily restrictive guards.

Cycle-66's **52/103 = 50.5% measured-execution** carries forward
unchanged — no v1 emitter / resolver / carrier path touched.

## The architectural fork that got settled

The v2.0 PRD §8.1 originally sketched the new entries as a
`DerivationStrategist` extension. A closer look at the kit's actual
shape:

- `DerivationStrategist` lives in **PropertyLawCore** — the
  plan-only layer. It consumes a `TypeShape`, returns a
  `DerivationStrategy` enum. **No `Generator` in scope.**
- `Generator<...>` lives in **PropertyLawKit** (`@_exported import
  PropertyBased`). The runtime-Gen path.

A literal `public extension DerivationStrategist { ... } -> Gen<[A]>`
would either break the PropertyLawCore plan/runtime boundary or
require moving DerivationStrategist up a layer. **Recommended (and
adopted) resolution:** put the new APIs in a new
PropertyLawKit-level namespace (`ActionSequenceFactory`). The PRD
wording will get amended at the next PRD revision; the prose
predated a careful look at the kit's module layering.

## Where the cross-repo work lives

| Repo | Commits |
|---|---|
| **SwiftPropertyLaws** (`../SwiftPropertyLaws`) | `feat: ActionSequenceFactory primary entry + StatefulGuard protocol` → `test: convenience CaseIterable actionSequence entry coverage` → `docs(v2.2.0): CLAUDE.md note` → tag `v2.2.0` |
| **SwiftInferProperties** (this repo) | cycle-73 findings + version 1.75.0 → 1.76.0 (this commit) |

## The kit-tag-publication gap

The kit's `v2.2.0` git tag exists **locally**. The repo's
`Package.swift` pin stays at `from: "2.1.0"` in this cycle because
SwiftPM resolves from the remote (`github.com/Joseph-Cursio/SwiftPropertyLaws`),
which doesn't yet have the v2.2.0 tag. Bumping the pin now would
break the build.

This is normal release coordination, not a M2 failure. The
**next-action** at the user's call:

1. Push the kit's local commits + the `v2.2.0` tag to remote:
   ```
   cd ../SwiftPropertyLaws
   git push origin main
   git push origin v2.2.0
   ```
2. In this repo, bump the pin to `from: "2.2.0"`:
   ```diff
   -        .package(url: "https://github.com/Joseph-Cursio/SwiftPropertyLaws.git", from: "2.1.0"),
   +        .package(url: "https://github.com/Joseph-Cursio/SwiftPropertyLaws.git", from: "2.2.0"),
   ```
3. Add the smoke test to confirm the consumed API compiles + runs.
   Drafted content (place at
   `Tests/SwiftInferCoreTests/ActionSequenceFactorySmokeTests.swift`,
   add `PropertyLawKit` product to the test-target deps):

   ```swift
   import Testing
   import PropertyLawKit
   import PropertyBased

   @Suite("ActionSequenceFactory smoke — V2.0 M2.C kit-pin wiring")
   struct ActionSequenceFactorySmokeTests {

       enum SmokeAction: CaseIterable, Sendable {
           case one, two, three
       }

       @Test("convenience entry is reachable + produces sequences")
       func convenienceEntryReachable() {
           let gen = ActionSequenceFactory.actionSequence(
               forCaseIterable: SmokeAction.self,
               length: 5...5
           )
           var rng = Xoshiro(seed: (0x01, 0x02, 0x03, 0x04))
           let sequence = gen.run(using: &rng)
           #expect(sequence.count == 5)
       }

       @Test("ActionSequenceFactory.defaultLength == 0...16")
       func defaultLengthIsZeroToSixteen() {
           #expect(ActionSequenceFactory.defaultLength == 0...16)
       }
   }
   ```

These three steps are the M2.D follow-up that ships when the kit
tag is published. The kit-side commits are the load-bearing
deliverable; the repo-side pin is a one-line follow-up.

## Test count

This repo: **2633 → 2633 (+0)** — no repo-side code shipped this
cycle (kit pin reverted to 2.1.0 pending publication). The
*kit-side* count gained **+15 tests** across
`ActionSequenceFactoryTests` covering `applyGuards` (6 tests,
internal pure helper) and both `actionSequence` entries (9 tests,
default length / guard threading / shorter-under-restrictive /
delegation). Kit-side count growth lives in the kit's commit log,
not this repo's.

§13 budgets unchanged — no repo-side code path affected.

## What v2.2.0 gives M3

Once the kit tag is published and the pin lands, M3's in-process
verify path will be able to:

- Synthesize action sequences for any `Action: CaseIterable`
  enum via the convenience entry. Covers most TCA examples.
- For payload-carrying Action enums (out of CaseIterable's reach),
  the user constructs a `Generator<Action, _>` via the kit's
  existing per-payload generators and passes it to the primary
  entry. Same "no silently-wrong code" hard guarantee as
  `DerivationStrategist`'s `.todo` posture.
- Filter sequences through user-supplied `StatefulGuard`s for the
  common case "don't fire `.delete(id)` after `.delete(id)` on the
  same id." Curated guards are deferred — v2.0 ships the protocol
  shape only.

## What's next — M3 scope conversation

M3 is the in-process verify path (PRD v2.0 §7.2). For pure reducers
(no `Effect` / async / `Task` references in body):

1. Generate a sequence of N actions via M2's primary entry.
2. Apply each action to a starting State via the discovered
   reducer's signature shape (M1's `signatureShape` field branches
   here: `(S, A) -> S` calls directly; `(inout S, A) -> Void`
   needs a copy-then-call wrapper; `(inout S, A) -> Effect<A>`
   needs the same wrapper plus `.none`-return acceptance).
3. Check the candidate invariant at each step.
4. Shrink on failure to a minimal reproducing trace.
5. Emit outcome in the same five-category scheme as v1.42+ verify.

Worth a scope conversation. M3 is naturally the biggest v2.0
sub-cycle because it ties together M1's discovery, M2's
generators, and a new invariant-checking mechanism. PRD v2.0 §15
also calls for a perf target: "1k action sequences (default
length distribution; ≤ 16 actions each) in < 100ms wall on a 2024
MacBook Air for a 5-case-Action 10-field-State reducer."

## Artifacts

- Kit-side (`../SwiftPropertyLaws`):
  - `Sources/PropertyLawKit/Public/StatefulGuard.swift`
  - `Sources/PropertyLawKit/Public/ActionSequenceFactory.swift`
  - `Tests/PropertyLawKitTests/ActionSequenceFactoryTests.swift`
- Repo-side (this repo):
  - Cycle-73 findings (this file)
  - Repo version 1.75.0 → 1.76.0
- Prior cycle: `docs/calibration-cycle-72-findings.md` (M1 complete).
- v2.0 PRD: `docs/SwiftInferProperties PRD v2.0.md` (§8 wording
  will get amended at the next PRD revision to reflect the
  ActionSequenceFactory namespace; current draft still says
  `DerivationStrategist` extension).
