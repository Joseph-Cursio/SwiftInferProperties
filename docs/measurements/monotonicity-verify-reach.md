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
error table. At 11% of one template on one corpus it is not a curiosity, and **it is
template-independent** — it is how a single-argument labelled call is rendered, so it blocks every
template equally. `open-threads.md` row **73**.

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
