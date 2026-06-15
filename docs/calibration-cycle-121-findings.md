# Calibration cycle 121 — CorpusPackager `dependencies:` thread scoping

> **STATUS: SCOPING (no binary change — investigation + decision record).**
> Scopes the "What's next" follow-up: threading a `dependencies:` parameter
> through `CorpusPackager` so it can package the dependency-bearing TCA
> corpora (not just zero-dependency sources). **Finding: the thread is
> mechanically trivial but has no standalone payoff** — every real TCA
> `@Reducer` is a `.tca` carrier that `verify-interaction` rejects *before*
> building, so a buildable TCA corpus package buys zero measured
> verification on its own. It is a prerequisite gated by the `.tca` carrier
> wall. Captured 2026-06-14. **No version bump** (documentation only —
> same posture as cycles 108 / 118 / 119).

## Why this was scoped

A1 is signed off (cycle 118); the parallel survey shipped (cycle 120). Of
the remaining optional follow-ups, the `CorpusPackager` `dependencies:`
thread was the candidate with apparent reach: it is the named prerequisite
to run the measured survey against the *real* TCA calibration corpora
(`tca-10`/`tca-25-discovery`) rather than only the hand-staged
dependency-free fixtures — and thus, potentially, to move the
measured-execution rate off its **50.5% (52/103), frozen since cycle 66**.

Before committing engineering, this cycle answers: **does a buildable,
dependency-bearing TCA corpus actually unlock any measured verification?**

## What the thread mechanically is (small, greenfield, zero blast radius)

Confined entirely to `CorpusPackager.swift`. Today its `manifestSource`
renders a dependency-free manifest (`CorpusPackager.swift:128-139`):

```swift
let package = Package(
    name: "\(moduleName)",
    products: [.library(name: "\(moduleName)", targets: ["\(moduleName)"])],
    targets: [.target(name: "\(moduleName)")]
)
```

The feature:

1. **New descriptor** (none exists — `VerifierWorkdir` hardcodes deps as raw
   `.package(url:from:)` strings):
   ```swift
   public struct ExternalDependency: Equatable, Sendable {
       public let url: String            // git URL
       public let requirement: String    // verbatim `from: "1.17.0"` (or an enum)
       public let packageName: String    // identity for .product(package:)
       public let productNames: [String] // e.g. ["ComposableArchitecture"]
   }
   ```
2. **Thread `dependencies: [ExternalDependency] = []`** through both
   `package(...)` overloads. The `= []` default leaves **all 7 existing
   call sites compiling unchanged** (all test-side; no CLI caller today).
3. **`manifestSource`** renders the `dependencies:` array + the target's
   `.product(name:package:)` list. Empty array → byte-identical to today.
4. Tests: +1 unit (TCA dep block renders) + ideally +1 measured packaging a
   real TCA source and building it.

Effort ≈ half a day; risk low (additive string templating, default-empty).

## The critical finding: no standalone payoff

A buildable TCA corpus does not unlock measured verification, because the
blocker is upstream of packaging:

- **Every real TCA `@Reducer` is a `.tca` carrier, rejected before build.**
  A real reducer puts its logic in `var body: some Reducer { Reduce { state,
  action in … } }`. The discoverer tags that `.tca` (`ReduceClosureWalker`),
  and `ActionSequenceStubEmitter.validate` throws `unsupportedCarrier` on
  `.tca` (`ActionSequenceStubEmitter.swift:206-207`). The packaged corpus
  builds, but the survey records `.measuredError` for every reducer in it.

- **Prevalence (both TCA corpora, 92 CA-importing `.swift` files):**

  | Shape | Count | Verifiable? |
  |---|---|---|
  | `var body: some Reducer` (`.tca` closure carrier) | **58** | ❌ rejected |
  | `@Reducer` macro | 42 | ❌ (`.tca`) |
  | plain free/static `func reduce(` | 11 | ✅ in principle |

  The verifiable plain-`func reduce` shape is essentially absent from real
  TCA case studies; the 11 hits are largely preview/helper noise, not the
  `@Reducer` bodies.

So packaging-with-dependencies is a **prerequisite with no standalone
payoff** — the same shape as cycle 119 (an easy enabler gated by an upstream
wall).

## What it is actually a prerequisite *for*

"Verify real TCA reducers" is a three-part epic; this thread is the easiest
third:

1. **CorpusPackager `dependencies:`** (this item) — corpus package builds.
   *Easy.*
2. **`VerifierWorkdir` external-deps thread** — to exercise a `.tca` reducer
   the stub must instantiate it and call `.body` / `reduce(into:action:)`,
   which means naming `some Reducer<State, Action>` → the verifier's *own*
   `Package.swift` + stub need `import ComposableArchitecture` as a
   **direct** dependency, not merely transitive through the corpus. Needs a
   new `WorkdirMode` (or a dep-list threaded into
   `renderDependenciesBlock` / `renderTargetDependenciesBlock`). *Medium.*
   (The earlier assumption that "VerifierWorkdir is unchanged" holds only
   for the *rejected* current path; the useful path needs this.)
3. **`.tca` carrier path in `ActionSequenceStubEmitter`** — closure-relative
   invocation, the deferred "separate scope" work. *The hard, load-bearing
   part.*

Encouraging detail: a real `Counter`'s Action is payload-free
(CaseIterable-able) and its State is zero-arg `Equatable` — so the *only*
thing blocking it is the `.tca` carrier rejection, **not** the shelved
value-generator path (cycle 119). Lifting `.tca` (items 2+3) would make a
real class of TCA reducers verifiable *without* needing value-gen.

## Decision

**Do not ship this thread alone** — it adds a parameter nothing can yet
benefit from. Two honest options:

- **(A) Shelve** until the "verify real TCA" epic is greenlit, then do
  items 1+2+3 together (1 is trivial once inside that work). Matches the
  cycle-119 "don't build gated enablers in isolation" posture. **Default
  recommendation.**
- **(B) Greenlight the epic**, starting with item 3 (the `.tca` carrier
  closure-relative invocation) to de-risk the hard part; items 1+2 are
  mechanical follow-ons. This is the *only* path that moves measured
  coverage onto real TCA corpora — and the data says it is the real lever:
  **58 `.tca` reducers currently unmeasurable, most blocked solely by the
  carrier rejection**, not by value-gen.

Given A1 is signed off and the frozen 50.5% is the only coverage number left
to move, **(B) is the genuinely high-value direction** — but it is a
multi-cycle epic whose center of gravity is the `.tca` carrier work, not
this packaging thread. The thread should ride along, not lead.

## Verification

No binary change. Prevalence reproduction:

```sh
cd ~/xcode_projects/calibration-corpora
grep -rl "some Reducer<" --include="*.swift" . | wc -l   # 58 (.tca closure carrier)
grep -rl "@Reducer"      --include="*.swift" . | wc -l   # 42
grep -rl "import ComposableArchitecture" --include="*.swift" . | wc -l  # 92
```

Suite green (3197) as of v1.125.0 (cycle 120); this cycle ships no code.

## What's next

Unchanged minus this item's clarification. Remaining optional: the **shared
prebuilt user-package artifact** (cross-reducer cold-build reuse — the
residual perf tail cycle 120 flagged). The real coverage lever is the
**`.tca` carrier epic** above, should it be greenlit. Value-generator path
stays shelved (cycle 119).
