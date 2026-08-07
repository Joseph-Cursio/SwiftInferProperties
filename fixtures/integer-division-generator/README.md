# `integer-division-generator` — Q4's before/after on generator coverage

Measured 2026-07-31 against `swift` @ `408632e59834c1a5ee4166ff61dd2c8b0585a1c5`
(the study's pinned corpus SHA).

**Subject:** `validation-test/stdlib/IntegerDivision.swift`, the
`"Int64 division inbounds"` arm. Apache-2.0 with Runtime Library Exception;
the parts reproduced here carry the Swift project's copyright and are used only
as the measurement's input.

Run it:

```
cd fixtures/integer-division-generator && swift test
```

No network dependencies — the standard library is the subject. ~0.3s.

## The question

Scope §Q4 says the conversion is close to pure gain because *"the human
supplied the law — the judgment part — and the generator is the mechanical part
that is measured weak."* Scope §8 resolved the target: **a local gated fixture**,
because the Swift repo vendors no property-based testing library and
`StdlibUnittest`'s whole randomness surface is the generator this study measured
as weak.

This is that conversion, on the file scope §Q4 named as the genuine candidate:
the law is forced to sample (unlike the exhaustive `Int8` arm) and the test has
an anchor shape the lifter can see (unlike `sort_integers`, which is
`lit`+FileCheck).

**The law is verbatim.** Build a 128-bit dividend as `divisor * quotient +
remainder`, divide it back, require both components unchanged. Same two
`expectEqual`s, same 65,536 trials, same nested-loop shape. Only the domain
changed.

## The corpus's generator is not careless — it is stratified for sign and blind to magnitude

Worth stating first, because "weak generator" invites the wrong picture. The
original draws

```swift
let b = bhi << 56 | Int64.random(in: 0 ..< step, using: &g)   // step == 2^56
```

over `bhi in -128 ... 127`. That is **stratification by top byte**, and it is
better than a naive full-range draw: it covers all four sign quadrants exactly
evenly (16,384 trials each), which uniform sampling would only do
approximately. Someone thought about this.

What it structurally cannot produce is a small magnitude. A divisor below 2^50
needs `bhi` in `{0, -1}` *and* 56 random bits to land low — about 2^-40 per
draw, against 256 draws. So:

| measured over the 65,536 trials | |
|---|---|
| distinct divisors | **256** |
| smallest \|divisor\| | **2^53.3** |
| smallest \|remainder\| | **2^43.4** |
| divisors below 2^50 | **0 of 256** |

The bottom 53 binades of the divisor domain are not under-sampled. They are
unreachable.

## Before/after — coverage

Every one of these is a subset of the domain some plausible divider gets wrong.
`divisor == 0` is deliberately excluded: it traps, and this arm is the
*inbounds* one.

| edge class | original | converted |
|---|---:|---:|
| `divisor == Int64.min` | **0** | 256 |
| `divisor == Int64.max` | **0** | 256 |
| `divisor == 1` / `== -1` | **0** | 256 each |
| `\|divisor\| <= 2` | **0** | 1,024 |
| `quotient == Int64.min` / `.max` | **0** | 2,304 each |
| `quotient == 0` | **0** | 2,560 |
| `remainder == 0` (exact division) | **0** | 4,768 |
| `\|remainder\| == \|divisor\| - 1` (maximal) | **0** | 4,832 |
| dividend fits 64 bits (`high == 0`) | **0** | 7,113 |
| **all 17 classes** | **0** | **all reached** |
| four sign quadrants | 16,384 each | 15,744 each |

Not "rarely" and not "under-samples" — **zero, all seventeen**. And the sign
stratification survives: the conversion keeps the half that works.

## Before/after — refutability, which is the measurement that matters

*"Score refutability, not suggestion count."* A coverage table only says the
boundary values are present now; it does not say the test can catch anything new.
So both domains were run against eight mutant dividers, each named for the defect
class it stands for. Cell = trial index of first refutation.

| mutant | original | converted |
|---|---|---|
| M1 exact-division off-by-one | **NEVER** | kill @0 |
| M2 unit-divisor shortcut | **NEVER** | kill @1 |
| M3 `Int64.min` divisor | **NEVER** | kill @40,960 |
| M4 `Int64.min` quotient | **NEVER** | kill @24 |
| M5 maximal remainder | **NEVER** | kill @0 |
| M6 64-bit dividend fast path | **NEVER** | kill @0 |
| M7 *control* — interior, low-word bit 17 | kill @1 | kill @7 |
| M8 *control* — interior, 1-in-4096 | kill @7,763 | kill @1,246 |
| **killed** | **2 / 8** | **8 / 8** |

Gained 6, lost 0. The two controls are why the table is a comparison rather than
a tally: spending a quarter of the trial budget on edges did **not** cost
interior detection. (M8 dies sooner in the converted domain, but that is an
artifact of which low words the substitutions happen to produce — noise, not a
result, and the gate deliberately does not pin it.)

## What is *not* claimed

**No defect was found.** The standard library answers correctly on every one of
the 65,536 converted trials, boundary cases included. The finding is about the
test's *reach*, not about `dividingFullWidth`.

**The mutants are hand-written.** They score the domain against *plausible*
defects, not against the observed defect distribution of real full-width
dividers. A mutant nobody would write inflates the converted score for free,
which is why each carries a `standsFor` naming its defect class — so a reader
can judge that independently. This is the honest limit of the measurement.

**The subject question was checked, not assumed.** Findings §4.4: *"a probe
which substitutes something other than the real subject proves nothing about the
real subject."* That rule bites when the claim is about `dividingFullWidth`.
Here the claim is about the **domain** — does this set of inputs distinguish a
correct divider from a buggy one — so the domain is the subject and the mutants
are what it must detect. The correct answer still comes from the real standard
library.

## The gate

Scope §8: *"The gate is what separates a fixture from the 'pile of local
rewrites' this risk names."* Every number above is asserted in
`Tests/IntegerDivisionGeneratorTests/GeneratorCoverageTests.swift`:

1. the law holds on **both** domains (the conversion did not break it);
2. the original reaches **zero** of the 17 edge classes;
3. the converted reaches **all** of them;
4. both keep all four sign quadrants, still near-balanced;
5. refutation power goes 2/8 → 8/8 **and nothing is lost**;
6. both interior controls still die.

**Verified it can fail**, per §4.3a's rule that compiling is not evidence:
forcing `edged = true` for both domains turns assertions 2 and 5 red (17
coverage issues, plus `killedBefore.count → 8` against an expected 2).

## What this settles, and what it does not

It settles Q4's stated deliverable for one suite: the generator *is* the
mechanical part, and replacing it is a strict improvement that can be measured
in refutation units rather than asserted.

It does **not** settle the §5 reframe, and pushes against it. §5 argues the
corpus is better used as *"a search index for where to point the catalogue"*
than as a source of conversions — humans mark where properties live, the tool
completes the set. On this file the completion half found nothing to add: the
law as written is already complete (the general division identity entails the
remainder bound and sign, because both are true of the constructed `r` that
equality is checked against), and `discover` proposes nothing on
`dividingFullWidth` at all. See `docs/measurements/swiftorg-property-test-study-findings.md`
§6 for that half and for the reach gap behind it.
