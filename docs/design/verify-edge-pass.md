# The verify edge pass

> **Status:** `shipped` · **As of:** 2026-08-07


**Date:** 2026-07-31 · **Status:** built · **Scope:** strategist-routed carriers only

## What was there

`StrategistDispatchEmitter.edgeSentinelSection()`, in full:

```swift
// --- Pass 2: edge-case-biased — n/a for strategist-routed carrier ---
print("VERIFY_EDGE_RESULT: PASS")
print("VERIFY_EDGE_TRIALS: 0")
print("VERIFY_EDGE_SAMPLED: 0")
```

A hardcoded PASS. Zero trials, nothing asserted. Every strategist-routed
carrier — `Int`, `String`, every custom type, i.e. everything outside
`Complex<Double>` / `Double` — got this. **23 of 23 `measured-bothPass` verdicts
in one full gate run went through it.**

The in-source justification was *"integral or `String` — no NaN/Inf semantic, no
edge pass needed."* That conflates **floating-point** edge cases with edge
cases. `Int.min` is the canonical arithmetic boundary: negation, `abs` and
magnitude fail there and nowhere else.

And the renderer said *"(integer carrier — edge pass not applicable)"*, which
reads as *this carrier has no edge cases* rather than *we did not check them*.

**Measured witness.** `fixtures/verify-refutability` contains `mergedBound(_:)`,
wrong *only* when one operand is `Int.min`. It was predicted REFUTED in the
frozen record and came back `measured-bothPass, edgeTrials=0 edgeSampled=0`. The
prediction was right; the tool was wrong.

## The approach that failed, and why it's recorded

The obvious fix is to mix the boundary values into the *default* generator —
exactly what V1.150 already does for `String`. It was built and measured:

- `mergedBound` flipped `bothPass` → `defaultFails` at trial 6, shrunk to
  `(0, Int.min)`.
- Three `VerifyPipelineLifted` integration tests flipped `bothPass` →
  `measured-error: the verifier trapped (signal 5)`.

`x + 1` traps at `Int.max`. `Gen<Int>.int()` spans `.min ... .max`, so that is a
~2⁻⁵⁸ event over 100 trials; at a 40% draw weight it is certain. **The repo
depends on this**, and says so:

> `x + 1` overflow-traps only at `x == Int.max` — probability ~100/2⁶⁴ over 100
> trials, effectively zero. Operations like `x * 2` would overflow ~50% of
> trials and crash.
> — `Tests/SwiftInferIntegrationTests/VerifyPipelineLiftedIntegrationTests.swift`

The reverted attempt's own docstring argued the change *"changes the frequency,
not the possibility."* Literally true, and wrong: frequency is the entire
mechanism the existing design rests on. **Boundary values cannot go in the pass
that produces the verdict.**

## What shipped

Boundary values live in a pass whose failure is **advisory** —
`VerifyOutcome.edgeCaseAdvisory`, the mechanism the floating-point path already
uses for `NaN`/`Infinity` for exactly this reason. The default pass keeps its
clean domain and its verdict; Pass 2 reports separately and cannot retract it.

### The law is composed once

Composers are pure `(Inputs, GeneratorRecipe) -> String` and read the generator
solely from `recipe.expression`. So Pass 2 is **the same composer** called with a
boundary-only recipe. No per-template duplication across the ~12 composers, and
the law cannot drift between passes because there is only one definition of it.

Two mechanical adjustments follow:

1. **Marker relabel** `VERIFY_DEFAULT_*` → `VERIFY_EDGE_*`. Safe because the
   marker vocabulary is a closed, documented contract (`VerifyResultParser`).
2. **`do { }` wrapper.** Both passes declare top-level bindings with the same
   names (`defaultGenerator`, `applyOnce`, …); a nested scope makes those
   shadow rather than redeclare, so the composer output is reused verbatim.

**The relabel fails closed.** A body carrying no default marker returns `nil`
and falls back to the sentinel — rather than emitting a pass that prints success
while asserting nothing, which is the defect being removed.

### A trap in Pass 2 does not discard Pass 1's verdict

Pass 1 prints its verdict before Pass 2 runs, and the stub sets
`setvbuf(_IONBF)`, so that marker survives a trap. Reporting `.error` would
throw away a verdict the run actually produced.

So: *default PASS + no edge result + signal* → `bothPass(edgeTrials: 0)`. A trap
with **no** Pass 1 verdict is still an error — the law was genuinely never
evaluated. Both halves are pinned by tests.

## Measured

`fixtures/verify-refutability`, all 44 entries:

| outcome | count |
|---|---|
| architectural-coverage-pending | 21 |
| measured-error | 13 |
| measured-defaultFails | 8 |
| **measured-edgeCaseAdvisory** | **1** ← `mergedBound` (EDGE) |
| measured-bothPass | 1 ← `canonicalizedOffset` (COLLISION) |

The original experiment's three-way hypothesis now holds with each class at its
correct **severity**:

| class | expectation | outcome |
|---|---|---|
| BROAD | refuted | `defaultFails` |
| **EDGE** | refuted | **`edgeCaseAdvisory`** — holds on the ordinary domain, fails at the boundary |
| COLLISION | survives | `bothPass` — correctly untargeted |

`combinedTally`'s `measured-error` is pre-existing and unrelated: `self - other`
over two full-range Ints overflows in the *default* pass.

## Composed carriers — the sentinel's remaining 27%, closed 2026-08-07

The limit below used to read *"carriers with no curated boundary set keep the
sentinel — `Bool`, enums, custom structs."* Measured against the frozen
whole-corpus survey (`fixtures/whole-corpus-survey/2026-08-05-whole-corpus.jsonl`,
281 records), that limit cost:

| `measured-bothPass` | entries |
|---|---|
| with a real Pass 2 (`edgeTrials=100`) | 95 |
| **with the zero-trial sentinel** | **35** |

**27% of the passing verdicts had a boundary domain nothing had checked** — the
same shape as the original defect, one level down. A struct is not a `RawType`,
so `edgeDomainValues` answers `nil` for the *carrier* — but the carrier's
boundary set is not a property of the carrier. It is the product of its
**leaves'**, and those are already curated.

### The first attempt reached nothing, and that is how the design was found

The obvious move is to carry `[MemberSpec]` on `GeneratorRecipe` and recompose
via the same `memberwiseRecipe` with boundary member generators — the exact
"same composer, different recipe" shape the top-level pass uses. It was built,
and an A/B over the 37 sentinel entries moved **zero of them**.

The reason is a fact about the corpus that reading the emitter cannot tell you:
**every struct in that population declares a user `init`**, so it takes Tier 6
`.initializerBased`, not `.memberwiseArbitrary` — and `InitArgument` carries no
`rawType` to key on. Threading each strategy's payload separately would mean a
branch per strategy and a silent gap every time the kit adds one.

What every strategy *does* have in common is the rendered expression, and every
one of them composes the same closed vocabulary of leaf generator literals
(`RawType.generatorExpression` — 14 exact strings, kit-owned). So the swap
happens there: `boundarySweep` replaces each leaf generator with its boundary-only
form, which reaches memberwise, initializer-based, enum-payload, tuple and
composite carriers at once — and reaches a strategy added later without being
told about it. Textual substitution is safe here for the same reason the
`VERIFY_DEFAULT_` → `VERIFY_EDGE_` relabel is: a closed vocabulary. A test pins
that no key is a substring of another (`Gen<Int>.int()` vs `Gen<Int8>.int8()`).

A recursive carrier falls out excluded for free — its expression is
`__genNode(3)`, which holds no leaf generator. Its helper *declaration* does, and
is deliberately not swept: it is emitted once and shared with Pass 1, so
sweeping it would move the domain the **verdict** was taken over.

### Measured (A/B, two release binaries, same afternoon, same index)

56 entries: the 37 sentinel `bothPass` rows plus a 19-entry control of rows that
already ran an edge pass or refuted. Both arms `verify --all-from-index` at
`--max-parallel 4`, 2026-08-07.

| bucket | before | after | Δ |
|---|---|---|---|
| `bothPass` edge=0 (sentinel) | 37 | 2 | **−35** |
| `bothPass` edge>0 | 12 | 47 | **+35** |
| `measured-defaultFails` | 5 | 5 | 0 |
| `measured-error` | 2 | 2 | 0 |

**35 of 37 converted; zero verdict changes, zero new errors, zero movement on
the control.** State the gain honestly: this is *unchecked → checked and held*,
not *found a bug*. No entry became `edgeCaseAdvisory`. The `mergedBound`-class
refutation this pass exists to catch has not yet appeared on a composed carrier;
what changed is that a run which reports one is now possible.

**The 2 that remain are correct.** `TargetDirectory.isDirectory(_:)` and
`VerifyHarness.isStale(indexPath:packageRoot:)` both take `URL`, whose generator
is a kit value-type form with no curated boundary set. A `URL` boundary set
(empty path, `file:///`, percent-encoding) is the obvious next entry and is not
guessed at here.

### Every eligible leaf at once — and what that does not reach

All eligible leaves are swapped in one pass, not rotated one at a time. Per-slot
rotation would need `Gen.oneOf` over n variants: the overload admitting
heterogeneous sequence types is `@available(swift 6.2)` and delegates to
`Gen.frequency`, which `GeneratorRecipeCompileSafetyTests` bans outright as not
compiling in an older language mode — and n variants of an n-leaf `zip` is n²
inlined generator expressions, in a repo that has already lost a release to a
type-check timeout on a 12-arm expression.

The cost is real: **a law that breaks on one leaf at its boundary with the others
ordinary is not reached.** The boundary sets are not degenerate (`0`, `1`, `-1`;
`"-"`, `"a\n- b"`), so mixed-magnitude combinations do occur — but that is
mitigation, not coverage. Rotation is the open follow-up, and it needs the
`Gen.frequency` ban resolved first.

## Scope and limits

- **Strategist-routed carriers only.** The v1.46 hardcoded emitters
  (`RoundTripStubEmitter`, `IdempotenceStubEmitter`, …) keep their own Int
  sentinel. Those Int composers are unreachable through the current router
  (`v146HardcodedCarriers` is `Complex<Double>` / `Double`), but the sentinel
  text is still there and still tested.
- **Carriers whose every leaf is uncurated keep the sentinel** — `Bool`,
  `Double`, `Float`, `URL`, and any carrier composed only of those. The renderer
  says the edge pass did not run instead of claiming it was inapplicable.
- **Boundary sets are per-carrier and hand-curated**: signed integers get
  `min`/`max`/`0`/`±1`, unsigned drop the negatives, `String` gets the
  empty/whitespace/newline set. Nothing derives them from the code under test.
- **Pass 2 draws uniformly from the boundary set**, so with 100 trials over a
  5-element set coverage is effectively certain — but it is sampling, not
  enumeration, and `edgeSampled` is not a coverage proof.
