# Does moving from `throws` to `Result` put more code within a law's reach?

> **Status:** `measured` · **As of:** 2026-08-19

Re-derivable at any time — `ResultCarrierReachMeasuredTests` *is* the harness, and
`make batch5` runs it. It costs **~28 minutes**, which is real and is the price of
three discovery passes over 28,274 functions.

**Measured NO, and the sign is negative.** The headline is **−218 suggestions
(−3.3%)** against a ceiling of **+62 (+0.95%)**. But the headline over-states the cost
by a factor of four, and the reason is the finding — see §4.

**The performable refactor costs −53** (§4.1, measured 2026-08-20). Quote that figure,
not −218 and not the −66 this document previously derived by subtraction.

---

## 1. The question, and why it is not the one people ask

The claim in circulation is *using `Result` helps property-based testing*. That claim
is about **statability**: the failure branch becomes part of the value, so a human can
write a law about it. `docs/ideas/error-law-instrument-split.md` argues it and is not
disputed here.

This measures a different thing — **reach**: does the refactor move anything **this
tool** produces? Statability and reach are separate, exactly as *prevention* and
*detection* were separate in that doc, and conflating them is the error this census
exists to avoid making in the other direction.

**Suggestion count is not law quality.** These arms bound whether the toolchain can
see a subject at all. Whether the resulting laws are worth running is a different
question and this does not ask it — the standing rule is to score refutability, not
suggestions.

---

## 2. Provenance

| | |
|---|---|
| corpora | the **17** `CorpusManifest` resolves; one root each, the largest |
| population | 28,274 functions · **2,830 throwing (10.0%)** · 6,508 baseline suggestions |
| SEI pin | `3ea25f2` |
| harness | `Tests/SwiftInferCoreTests/ResultCarrierReachMeasuredTests.swift` |
| control | item 34's `withThrowsMasked` **+2**, reproduced unchanged on item 34's three corpora |

Three arms:

| arm | transform | models |
|---|---|---|
| baseline | none | today |
| `throws` masked | `isThrows = false` | the **ceiling** — stop advertising partiality, pay nothing |
| `Result`-wrapped | `isThrows = false`, `T` → `Result<T, Error>` | the **actual refactor** |

Only *throwing* functions are transformed; converting a total function to `Result` is
not what the advice means. A `Void`-returning throwing function becomes
`Result<Void, Error>` rather than being skipped — dropping those would quietly exclude
the largest single shape among throwing functions.

---

## 3. The numbers

```
TOTAL  functions 28274 · throwing 2830 · baseline suggestions 6508
CEILING  (throws masked):   +62
REFACTOR (Result-wrapped):  -218
```

**Not one corpus gains from wrapping.** Every non-zero `Result` delta is negative:
swift-foundation −120, swiftlang-swift −50, swift-collections −21, swift-infer-core
−10, swift-package-manager −8, swift-nio −5, swiftformat-rule-studio −3,
swift-format −1.

Both arms clear `isThrows`, so the decomposition is:

- the **flag** is worth **+62**
- the **return type** is worth about **−280**
- net **−218**

**The arm tracks its own population, which is the control that matters.**
swift-syntax has 5,852 functions and **9** throwing, and moves 0 in both arms.
swift-project-lint has 0 throwing and moves 0. swift-foundation has 1,282 throwing and
moves the most in both directions. A transform that moved rows in corpora with nothing
to transform would be measuring something else.

---

## 4. **70% of the loss is a refactor Swift will not let you perform**

The per-template attribution is where the headline breaks:

| template | Δ |
|---|---|
| **`codable-round-trip`** | **−152** |
| `normal-form` | −14 |
| `monotonicity` | −13 |
| `round-trip` | −12 |
| `idempotence` | −11 |
| `functor-identity` | −7 |
| `inverse-pair` | −5 |
| `dual-style-consistency` | −5 |
| `state-machine` | −3 |
| **`input-totality`** | **+4** |
| 26 others | 0 |

`codable-round-trip` fires on a hand-written **`encode(to:)`** paired with
**`init(from:)`**. Those are `Codable` protocol requirements. Their signatures —
`func encode(to encoder: any Encoder) throws` and
`init(from decoder: any Decoder) throws` — are **fixed by the protocol**. You cannot
return `Result` from them; the conformance would not compile.

So **152 of the 218 lost rows model a transform that is illegal in Swift.** The arm
applied it because the arm rewrites summaries, not source, and a summary has no idea
its signature is load-bearing for a conformance.

**Corrected reading, first cut — and it was 20% wrong.** This document originally
said the performable loss was *"about −66 rather than −218"*, reached by subtracting
`codable-round-trip`'s 152 from the 218. §7 flagged that as arithmetic standing in for
a measurement. It has since been measured, and the derivation was off by 13 rows.

## 4.1 The measured figure: **−53**

`ResultCarrierReachMeasuredTests` now carries a fourth arm that **does not perform the
illegal transform at all**, rather than performing it and subtracting afterwards:

```
CEILING     (throws masked):            +62
REFACTOR    (Result-wrapped):          -218
PERFORMABLE (free signatures only):     -53
  conformance-fixed throwing functions skipped: 466
```

**466 of the 2,830 throwing functions — one in six — cannot change their signature**
because a protocol they conform to fixes it. That is a larger population than
`codable-round-trip`'s rows alone, which is exactly why the subtraction under-recovered:
it credited back only the rows of one template, while the fixed population also holds
rows of `round-trip`, `inverse-pair` and others.

**So the derived −66 over-stated the performable cost by 13 rows (~20%).** The verdict
does not move — a performable `Result` refactor still costs suggestions rather than
gaining them — but the figure is now measured, and the one it replaces was the kind of
number this repo has been burned by before: right in direction, wrong in magnitude, and
indistinguishable from a measurement once written down.

**The classifier is structural, and biased against itself.** A function counts as
conformance-fixed only when its `(name, labels)` matches a **throwing requirement** of
some protocol **and** its containing type declares conformance to that protocol —
requirements read both from a built-in stdlib table and from the corpus's own protocol
declarations, whose bodies `FunctionScanner` deliberately skips. Name alone is not
enough, and `nameAloneIsNotEnough` asserts an identically-named method on a
non-conforming type stays free; that guard was watched failing against a deliberately
name-only classifier before being trusted. Its blind spots — cross-module conformances,
`typealias` conformances, `override` / `@objc` / C-interop signatures — **all err
toward calling a function free**, so 466 is a floor and −53 is an upper bound on the
cost. The instrument cannot manufacture the correction it exists to check.

### `encode(to:)` has now distorted three separate measurements

This is the third time these same functions have bent a number in this repo:

1. **`purity-refuted-bucket`** — 23 of 53 refuted subjects were `propagatedTry` only,
   ten of them `encode(to:)`, throwing because `Encoder` throws rather than from
   impurity.
2. **`purity-veto-precision`** — a naive `.refuted` veto removed 20 rows including
   **10 passing laws**, 8 of them `encode(to:)` under the only 100%-yield template.
   That is why the shipped veto is witness-scoped.
3. **Here** — −152 of −218.

The transferable rule: **`throws` on a protocol requirement is a fact about the
protocol, not about the function.** Any instrument that reads `isThrows` as a property
of the subject will over-fire on `Codable`, and this repo has now paid for that three
times.

---

## 5. The one template that gains

**`input-totality: +4`** is the only positive row, and it is the family that *should*
gain: making the failure explicit is precisely what a totality law wants. It is small,
and 4 rows is not a business case. But it is the right sign in the right place, which
is weak corroboration that the arm measures something real rather than carrier noise.

It is also the only measured contact between this census and
`docs/ideas/error-law-instrument-split.md`'s nine families — **eight of which this
toolchain cannot see at all**, because the templates that would carry them do not
exist.

---

## 6. The verdict

**`Result` does not put more code within this toolchain's reach, and a naive reading
of the refactor makes things worse.** Three findings, in order of what they change:

- **The ceiling is ~1%.** Removing the partiality signal entirely, paying nothing,
  moves 62 of 6,508. This lands in the same range as
  `docs/measurements/purity-refactoring-reach.md`, which forced every purity verdict
  to `.pure` — a strictly larger intervention — and moved **zero**. Both say the same
  thing: **the decline causes this tool has are not about the effect channel.** Not
  one of `UnverifiableCause`'s eight cases is *the subject throws*.
- **The measured refactor is negative, and mostly for an invalid reason.** −218
  gross, ~−66 for transforms that could actually be made.
- **The advice is not wrong; it is about a different thing.** `Result` makes error
  laws *statable by a human*. It does not make them *discoverable by this tool*, and
  nothing here suggests it would after a carrier were added — that would take a
  template, and the templates for eight of the nine families do not exist.

**Do not refactor toward `Result` to make swift-infer find more.** Refactor toward it
to state laws about failures, which is a claim this census does not touch.

---

## 7. What would reopen it

- **A `Result` carrier in the templates.** The entire −280 return-type cost is "the
  templates do not recognise `Result<T, E>`". Teach one to unwrap it and the arm must
  be re-taken; the answer could go either way and this document cannot predict it.
- ~~**Excluding protocol requirements from the transform.**~~ **BUILT 2026-08-20**, and
  it moved the number: −53 measured against −66 derived. See §4.1. What remains open is
  the classifier's stated blind spots — a conformance declared in another module, or
  behind an arbitrary `typealias`, and the non-protocol reasons a signature is fixed
  (`override`, `@objc`, C interop). Each would raise the 466 and shrink the 53.
- **A corpus with a large `Result`-returning surface.** Every corpus here is
  `throws`-shaped, so the baseline arm has never seen what the tool does with a
  codebase already written the other way. That is a real blind spot in this census.
