# Does a `monotonicity` row ever reach a verdict? — the run that was pre-registered and did not get its arm

> **Status:** `measured` · **As of:** 2026-08-29

**Subject: `swift-collections` @ `899809d3`**, `verify --all-from-index --template monotonicity`,
default budget (N=1000), `--max-parallel 4`. Subject left clean — `.swiftinfer/` was untracked
(513 MB), confirmed with `git status` before removal.

## 0. The question, and the rule fixed before the data

`monotonicity-subject-census.md` reopened row 69's trig/hash gate: the decline rested on *no
population* and the population is **26 rows of 339**. What it could not say is whether those rows
buy anything. The `involution` gate's stated value is specific — one withdrawn row was returning
`measured-bothPass` on a false law, and **a passing false law is believed** — and that argument
needs the rows to execute.

**Pre-registered before the run:**

| outcome | decision |
|---|---|
| any of the 26 reaches `measured-bothPass` | build the gate |
| they execute but only refute | weak case — cheapness, not soundness |
| none reaches a verdict | decline; they cost nothing to leave alone |

## 1. The result — and the arm never ran

| outcome | rows |
|---|---:|
| `architectural-coverage-pending` | 52 |
| `measured-error` — build failed, in **our** stub | 10 |
| `measured-defaultFails` | 2 |
| **`measured-bothPass`** | **0** |
| total | 64 |

Decline causes: **30 `instance-method-shape-not-supported`**, 21 `unsupported-carrier`, 1
`internal-api-not-accessible`.

⚠ **THE HASH ARM DID NOT RUN, so the third branch does not apply to it.** Only **3 of the 26** are
in this corpus. One declined at `unsupported-carrier: RigidDictionary.Element`; the other two —
both `_rawHashValue(seed:)` — **failed to build in our own emitter**, `cannot find 'UniqueSet' in
scope` and `cannot find 'RigidSet' in scope`. **The remaining ~22 are in `swiftlang-swift`, which
cannot be verified at all**: it is the compiler and standard library, not a package the verifier
can path-depend on.

**So "none reached a verdict" is true and reading it as the pre-registered third branch would be
wrong.** The population never got to run: two of three attempts died on our side, and the rest are
structurally unrunnable. *A refuter that fires first hides every refuter behind it* — here the
first refuter is our own stub.

## 2. The third branch was mis-specified, independently of that

It said *they cost nothing to leave alone*. That embeds **no verdict ⇒ no consumer**, and the
census data refutes it: these rows enter `discover` output and `.swiftinfer/index.json`, which
`insights` reads and authors read. That is unlike `.pureButPartial`, which has **no consumer at
all** (`partial-purity-consumer-declined.md`: no template gates on `purityVerdict`), and unlike
the blocking-callee index, which lands in a tier nothing reads.

**The cost of the 26 is 26 false suggestions in author-facing output. That is a real cost and the
rule as written denied it.**

## 3. What follows for the gate

Execution is **permanently unavailable** for this population — not pending a fix, but because the
corpus holding 22 of 26 is the standard library. So the `involution` argument (*a passing false
law is believed*) can never apply here, and the decision must be made on author-facing output.

**There the availability gate is the precedent, and it fits exactly**: 24 rows of 4,161 (0.58%)
withdrawn, built, *small and worth doing because it costs NO laws* — and those rows were never
about verdicts either, they were about not proposing a law for a subject you cannot name.

| | availability gate | this |
|---|---|---|
| share of output | 24 of 4,161 (0.58%) | **26 of 5,883 (0.44%)** |
| costs laws? | no | **no** — the 8 monotonic shims (`_exp`, `_exp2`, `_log`, `_log2`, `_log10`, `_nearbyint`) survive |
| basis | an attribute in the syntax tree | **a name**, and that is the weaker half |
| generality | universal | `hashValue` / `hash(into:)` are **protocol requirements**; `sin`/`cos` universal — not one repo's convention |

**RECOMMENDED: build it, with its value stated as author-facing output and NOT as verdict
prevention.** Nobody should later cite this gate as having prevented a false `bothPass`; it
cannot, on this evidence.

⚠ **This DEPARTS FROM THE PRE-REGISTERED RULE, which is exactly the move pre-registration exists
to catch.** Recorded as a departure rather than folded in silently. The grounds are that the
experiment did not test what it was designed to test (§1) and that the branch it appears to
trigger contained a false premise (§2) — but a reader who thinks that is rationalisation is
reading it correctly as a risk, and the decline remains defensible.

## 4. The two refutations are FALSE LAWS, hand-checked

`_growUniqueArrayCapacity(_:)` and `_growUniqueDequeCapacity(_:)`, both `Possible`, both refuted
at trial 0 with large negative `Int` counterexamples — `(-2097918052031207816,
1781511024692177784)`.

```swift
internal func _growUniqueArrayCapacity(_ capacity: Int) -> Int {
  let c = (3 &* UInt(bitPattern: capacity) &+ 1) / 2
  return Int(bitPattern: c)
}
```

**`internal`, wrapping arithmetic on purpose, and called only with a real capacity** (`UniqueArray.swift:291`).
A negative `Int` is outside the domain it is ever called with, and `&*` / `&+` are the author
saying so. **Over-quantified domain** — the `UserDetectionStatus` mechanism, where the tool's
counterexample was a random `Int` against an `OptionSet`.

**Tally: `monotonicity` enters at 2 hand-checked, 0 real.** Beside `idempotence` 0 of 23 and
`predicate` 0 refutations of 102.

## 5. The finding worth more than the gate

⚠ **The emitter drops argument labels: 7 of 64 rows (11%) fail `missing argument label`** —
`'forScale:'` ×5, `'forOffset:'`, `'remaining:'`. It renders `f(x)` where the declaration is
`f(forScale: x)`.

**This is recorded once, as a one-row curiosity**, in `candidate-screening-pass.md`'s OpenAPIKit
error table. At 11% of one template on one corpus it is not a curiosity. `open-threads.md` row
**73**.

⚠ **AND THE CLAIM MADE HERE — *it is template-independent, so it blocks every template equally* —
IS WRONG, corrected 2026-08-29 by reading the code.** `labeledCallExpression` has existed since
V1.149 and `singleCallResolved` routes every other template through it.
**`liftedOrMonotonicityCalls` is the ONE arm that never did**: it rendered the bare reference with
`CallExpressionShape.render` and handed it to a composer that applies positionally. The blast
radius is **two templates — `monotonicity` and `idempotence-lifted` — not the catalogue.**

**The census this section called for was the wrong first step.** Reading the resolver answered the
scope question in minutes, and a census would have measured a population only two templates can
draw from. §7 is the fix and its A/B.

Two further emitter errors in the same run, not sized: `cannot find 'UniqueSet' / 'RigidSet' in
scope` (2 rows — the hash arm, §1) and `binary operator '>' cannot be applied to two '@Sendable
(_HashSlot) -> Int' operands` (1 row, the emitter selected a function-typed value).

**And the largest blocker is neither**: `instance-method-shape-not-supported` takes **30 of 64**.

## 6. What would refute this

- **A `monotonicity` row on any corpus reaching `measured-bothPass` on a definitionally false
  subject.** That restores the `involution` argument and makes §3 a stronger case, not a weaker
  one.
- **The two `cannot find … in scope` rows building after a fix.** Then the hash arm becomes
  testable and the pre-registered rule can be applied as written, which is the outcome to prefer.
- **A reading showing `discover` output is not consumed by a human for these tiers.** That would
  restore the third branch's premise and the decline with it.

---

## 7. The fix, and what it bought — 7 build failures, 0 real findings

**Fixed 2026-08-29.** `liftedOrMonotonicityCalls` now wraps through `labeledCallExpression`.
Two consequences had to be handled, and the code said so before the compiler did:

- **The OC/instance composer reads a method name off `functionCalls.first` with
  `split(".").last`**, which a closure literal (`{ Deque.index(after: $0) }`) answers nonsense
  for. Monotonicity now carries three elements — labelled call, un-stripped
  `primaryFunctionName`, raw call — and that composer takes the raw one, with a two-element
  fallback so a labelless subject is byte-identical.
- **`idempotence-lifted`'s composer already documents the other trap**: a closure literal applied
  inline leaves `$0` with nothing to infer from, which is why it binds to an explicitly typed
  local. The monotonicity value path applies to a value whose type is fixed by an explicitly
  typed generator, so it needed no annotation — **checked by running it, not by arguing it.**

**Same-subject A/B, `swift-collections` @ `899809d3`, same command:**

| outcome | before | after |
|---|---:|---:|
| `architectural-coverage-pending` | 52 | 53 |
| `measured-error` | 10 | **6** |
| `measured-defaultFails` | 2 | **5** |
| **`missing argument label` rows** | **7** | **0** |

**The 7 freed rows became 3 verdicts, 3 runtime traps and 1 build failure** — the standing ~5:1
decline-to-rows ratio landing at about 2:1, the best it has read in this line of work.

⚠ **AND THEY BOUGHT ZERO REAL FINDINGS.** All three new refutations are **false laws by
over-quantified domain**, the same mechanism as §4:

| subject | counterexample | why false |
|---|---|---|
| `wordCount(forScale:)` | `(-2144079696337046920, …)` | negative scale |
| `wordCount(forScale:)` | **`(81, 140)`** | see below |
| `minimumCapacity(forScale:)` | `(5256116255943241006, …)` | `1 &<< scale` masks the shift, wraps |

✅ **`(81, 140)` is the most instructive counterexample this family has produced, because it looks
PLAUSIBLE.** `wordCount(forScale scale: Int) -> Int { ((scale &<< scale) + 63) / 64 }` — `&<<`
masks the shift amount to 6 bits, so `81 &<< 81` is `81 << 17` and `140 &<< 140` is `140 << 12`,
and the larger input yields the smaller result. Two small positive integers, and a reader does not
see out-of-domain at a glance. **The counterexample's plausibility and the finding's reality are
independent axes** — `refutation-rate-third-fourth-subject.md` named that, and this is the
cleanest exhibit of it: every earlier false law in this doc announced itself with an absurd value.

⚠ **AND THE DOMAIN BOUND IS WRITTEN DOWN — ON A DIFFERENT FUNCTION.** `scale(forCapacity:)`, in
the same file, ends with `assert(scale >= minimumScale && scale < Int.bitWidth)`. So the legal
domain of every `…(forScale:)` function is stated in an assertion **on the producer, never on the
consumers**. That is a new wrinkle on row 72's generator-fidelity family: not *the invariant is
undeclared* (`Bounds`, `Color`) and not *it is one hop away through `self.init`* (`Plane`), but
**it is declared on the function that MAKES the value, and the tool is generating inputs to the
functions that CONSUME it.**

**The 3 new traps are the same cause.** `maximumCapacity(forScale:)` ×2 and `level(forOffset:)`
exit on signal 5: `1 &<< scale` masks and wraps, then `bucketCount * maximumLoadFactor.0` is an
ordinary multiply that **traps on overflow**. Out-of-domain input, one line later.

**The 1 remaining build failure is an availability floor** — `desiredNextChunkSize(remaining:)`
fails with `'BigString' is only available in macOS 26.0 or newer`. `availability-gate.md` covers
`unavailable` + `obsoleted:` **only**, and deliberately not version floors (gating on those would
sweep 1,163 `deprecated` rows). So this is known, deliberate non-coverage rather than a new defect.

**Tally: `monotonicity` 0 real of 5.**
