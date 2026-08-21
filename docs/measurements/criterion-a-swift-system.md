# Criterion A on `swift-system` — the ratified bar, answered

> **Status:** `measured` · **As of:** 2026-08-21

Subject: **`swift-system` @ `6a63f08`** (release/1.7.0). Genuinely unmet — **zero mentions
in `fixtures/corpora/manifest.json` and zero across all of `docs/`**, checked before use.
Re-derivable: run `swift-infer verify --all-from-index` from the package root, which
reindexes `Sources/` on demand.

**Criterion A still FAILS, and every reason given in the first version of this document was
wrong.** Read §0 before anything else.

---

## 0. ⚠ This document's first answer was an instrument defect, not a result

The version committed at `647fc7c0` reported **0 of 41 laws running**, **36
`unsupported-carrier`**, **15 of them on `FilePath`**, and concluded that the binding
constraint was carrier construction — recommending an `ExpressibleByStringLiteral`
generator route as the fix.

**21 of those 36 declines were a module-resolution bug in this repo.** They read:

```
unsupported-carrier: System is not a library product of swift-system (vended: SystemPackage)
```

swift-system declares `.target(name: "SystemPackage", path: "Sources/System")`.
`VerifyTargetInference.module` consulted the `Sources/<module>/` convention first and the
manifest only on failure — and here the convention does not fail. It **succeeds and is
wrong**, reading the module back as `System`, which is neither a target nor a product.
Fixed in `Sources/SwiftInferCLI/VerifyTargetInference.swift` (2026-08-21); the manifest now
wins wherever a text scan of `Package.swift` says it could disagree.

**The two lessons, both of which this document is the evidence for:**

1. **A decline bucket's NAME is not its cause.** The quarantine reports a product-resolution
   failure under the `unsupported-carrier:` prefix. Fifteen rows carried `FilePath` in their
   `carrier` field while declining for a reason that had nothing to do with `FilePath`, and
   the first reading grouped by carrier and believed the grouping. **Group by the reason
   string, not by the bucket label.**
2. **`FilePath` was constructible the whole time.** After the fix, *not one* of the
   remaining `unsupported-carrier` rows is `FilePath`. The recommendation that followed from
   believing otherwise is retracted in §5.

---

## 1. The result

Re-taken 2026-08-21 with the module fix, and with nothing else changed.

| outcome | rows | what it means |
|---|---:|---|
| `unsupported-carrier` | **15** | a genuine carrier the tool cannot construct |
| **generator trap (SIGTRAP)** | **9** | the law compiled and ran; a generated input killed it |
| **`build-failed`** | **6** | the emitted stub does not compile |
| `unsupported-template` | 4 | `inverse-pair` ×2, `input-totality` ×2 |
| `instance-method-shape-not-supported` | 2 | |
| **executed to a verdict** | **2** | `measured-edgeCaseAdvisory` on `dup` / `system_dup` |
| **executed, verdict DISCARDED** | **2** | see §4 — these printed `PASS` |
| `not-a-candidate` | 1 | `private` subject, no test can name it |
| | **41** | |

**Laws that reached the build stage: 19 of 41, up from 0.**
**Laws that ran to completion: 4 of 41 — and the parser threw two of them away.**

Discovery is unchanged and still looks healthy: 41 suggestions across seven templates —
`idempotence` 18, `predicate` 9, `round-trip` 5, `monotonicity` 4, `inverse-pair` 2,
`input-totality` 2, `measure-non-negativity` 1 — with one `Strong` and four `Likely`. A far
better spread than `swift-http-types`, which was 91% `idempotence` with no `Strong` row.

**A still fails**, because 4 executing laws over 41 suggestions is not a bar any planted
defect can be fairly offered to. But it fails for three *newly named* reasons rather than
one imagined one.

---

## 2. The largest real bucket is the generator's domain, not the carrier

Nine rows compiled, linked, ran, and **trapped**:

```
Swift/UnicodeScalar.swift:358: Fatal error: Code point value does not fit into ASCII.
```

Seven are on `FilePath` (`lexicallyNormalized`, `removingRoot`, `removingLastComponent`,
`pushing(_:)`, `starts(with:)`, `ends(with:)`, `length`), two on free functions
(`isSeparator(_:)`, `isPrenormalSeparator(_:)`).

This is exactly the failure class `RefutationRenderer`'s own message names — *a derived
generator wider than the code assumes*. swift-system's path internals are byte-oriented and
assume ASCII in places; the derived generator draws the full domain. **It is evidence about
the generator, not about the law**, and the tool says so rather than reporting a refutation.

That makes it the single most actionable finding here, and it is the same lever
`fixtures/branch-reaching-generator/` was built to study. **It is also the first time that
lever has been pointed at by a third-party subject rather than by a fixture.**

---

## 3. Six build failures, one previously unnamed emitter defect

| error | rows | subject |
|---|---:|---|
| `cannot call value of non-function type 'String'` | 4 | `description`, `debugDescription`, `string`, `_portableDescription` |
| `cannot call value of non-function type 'FilePath'` | 1 | `dirname` |
| `binary operator '!=' cannot be applied to two '_Lexer' operands` | 1 | `_Lexer.clear` |

**Five of the six are one defect: a computed property emitted as a method call.**
`FilePath.description`, `.string`, `._portableDescription` and `.dirname` are
`public var`s; the stub renders `value.description()`.

`FunctionSummary.isComputedProperty` exists and is carried all the way through
`SemanticIndexEntry` to `StrategistDispatchEmitter.Inputs`. Exactly **one** composer reads
it — `composeSelfReturningInvolutionPass`, which does
`let accessor = isComputedProperty ? "" : "()"`. The idempotence and round-trip composers
hardcode `()`. This is a fourth member of the emitter-defect family
`criterion-a-unmet-subject.md` opened, and the cheapest one yet: the bit is already in hand
and simply not consulted.

The sixth is a missing gate: `_Lexer` is not `Equatable`, and `UnverifiableCause` already
has `carrierNotEquatable` for precisely this. It should have declined, not emitted.

---

## 4. Two laws passed and the result parser discarded them

```
parse-error: verifier subprocess exited with code 0, stdout (last 5 lines, pipe-joined):
VERIFY_DEFAULT_RESULT: PASS | VERIFY_DEFAULT_TRIALS: 100
```

On `close(_:)` and `system_close(_:)`. The verifier compiled, ran 100 trials, passed, and
exited cleanly — and the row is reported as `measured-error`.

The default pass printed; no edge pass did. A reader looking at the bucket table sees an
error where the tool actually has a result. **This is why §1 quotes "reached the build
stage" and "ran to completion" as two different numbers**: collapsing them would have hidden
this entirely.

---

## 5. Retracted: the `ExpressibleByStringLiteral` route

The first version of this document recommended building it, on the strength of 15
`FilePath` rows that turned out to be the module bug.

**It was built anyway, and measured. It moves zero rows.**

`Sources/SwiftInferCore/StringLiteralCarrier.swift` plus an emitter fall-through at the
strategist's `.todo`, together with a widening of `TypeShapeBuilder` to merge conformances
from unconditional extensions in *any* file (`FilePath`'s `ExpressibleByStringLiteral`
conformance is declared in a different file from the type). A probe confirmed both halves
worked — the shape carries the conformance and the index JSON records it.

Re-running the full survey with and without the route gives **row-for-row identical
results**: same 41 records, same outcome and same detail string for every one. Zero
differences. The route was never the constraint, because `FilePath` was never blocked.

Not shipped. Per this project's standing rule, a gain is stated in **rows moved**, and this
one moved none. The code is recorded here rather than kept, so the next person to reach for
the same idea reaches for it with a number attached.

---

## 6. What this answers, and what it does not

**Answers A on this subject: it fails.** 4 of 41 laws execute; a bar about killing mutants
cannot be evaluated against that.

**Does not measure whether the laws are any good.** The four that ran say nothing about the
thirty-seven that did not.

**Does not generalise.** One subject, an existence check that came back negative.
`fixtures/planted-defect-arm`'s rule holds in this direction too.

**Three subjects have now been tried and none reached the point where law quality could be
judged** — the first blocked by emitter defects, the second by a module-resolution bug, and
this one, underneath it, by generator domain. **A has still never been evaluated on a corpus
where enough laws ran.**

---

## 7. What follows, in measured order

1. **The generator-domain trap, 9 rows.** The largest real bucket and the one with a
   fixture already built for it.
2. **The computed-property emitter defect, 5 rows.** The bit is already carried; three
   composers do not read it.
3. **The `Equatable` gate, 1 row.** `carrierNotEquatable` exists and was not consulted.
4. **The discarded-PASS parser gap, 2 rows.** Costs nothing to fix and currently reports a
   result as an error.
5. **The 15 remaining carrier declines** — `Range<_Index>` 3, `FileDescriptor` 3,
   `CInterop.Mode` 2, and eight singletons, most of them pointers. These are the honest
   carrier gap, and they are pointer- and C-interop-shaped rather than value-type-shaped.
   Nothing cheap is on the table here.

**Do not re-quote the `647fc7c0` figures.** They are superseded, not merely stale.
