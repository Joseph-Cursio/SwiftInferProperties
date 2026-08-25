# Are the survey's refutations real bugs? And does the TIER predict it?

> **Status:** `measured` · **As of:** 2026-08-19

Hand-check of all **15** refutations in
`fixtures/whole-corpus-survey/2026-08-19-whole-corpus.jsonl`. Not re-derivable by a
harness — reading a law against its subject is the judgement a harness cannot make, which
is why the reasoning per row is below rather than a count.

**Measured: 15 of 15 are FALSE LAWS. Zero real bugs.**

**And the tier does not predict which is worth reading** — all **3** of the `Likely`
refutations are false laws, which is the inference the index has been carrying since
2026-08-05.

---

## What the standing rule said, and what survives

The index quotes 2026-08-05: *"all 4 real bugs are `Likely`; all 5 `Possible` refutations
are false laws."* The useful inference people take from that is **a `Likely` refutation is
worth reading first**.

**That inference is measured false here: 3 `Likely` refutations, 0 real bugs.**

**What is NOT refuted is the original statement.** *Real bugs ⊆ `Likely`* is untested
today, because there are no real bugs to place — most likely the 2026-08-05 bugs were
fixed and what remains is the false-law tail. **A rule with an empty antecedent is neither
confirmed nor broken**, and reporting this as "the rule is wrong" would claim more than
the evidence carries.

Set beside `fixtures/planted-defect-arm/README.md`, which measured that the **template**
does not predict whether a refutation is a bug: **neither tier nor template predicts it.**

---

## Every refutation fails at `trial=0`

Not one is an edge case found deep in a search. All 15 fail on the **first** trial, which
is itself the tell: a law that is false of its subject *by construction* fails
immediately, and a law that is true-but-for-a-corner does not.

**That is a cheaper signal than the tier**, and it is already in the stream as
`outcomeDetail`. It is not proposed as a filter here — a single corpus with 15 rows cannot
support one — but it is the first thing to check on the next survey.

---

## The 12 `Possible` — idempotence over a DERIVATION, not a projection

`idempotence` assumes `f` normalises: applying twice equals applying once. Every one of
these has a `T -> T` signature and **derives** instead.

| subject | why `f(f(x)) ≠ f(x)` |
|---|---|
| `defaultPath(for:)` ×5 — Baseline/Decisions/InteractionBaseline/InteractionDecisions/VerifyEvidence loaders | `root` → `root/.swiftinfer/x.json`, then appends the suffix again |
| `SubjectFingerprint.of(bodyText:)` | digest of a digest |
| `LiftedTestEmitter.regressionFileHash(for:)` | SHA256 prefix of a SHA256 prefix |
| `SwiftInferCommand.Verify.seedString(for:)` | derives a seed hex from a hash; feeding the seed back derives another |
| `BuildIdentity.versionString(_:)` | `"1.0 (abc)"` → `"1.0 (abc) (abc)"` |
| `MinedTraceSelector.markovSynthesized(from:)` | re-synthesises from a Markov model |
| `LiftedTestEmitter.codableRoundTripGenerator(for:)`, `ViewModelActionSequenceStubEmitter.seedTuple(from:)` | code emitters |

**The distinction the template is missing is projection vs derivation.** A normaliser
(`trimmed`, `sorted`, `canonicalised`) is idempotent; a hash, a path-builder, a formatter
and an emitter share its *type* and none is idempotent. Type symmetry is the whole
evidence, and it does not carry the claim.

## The 3 `Likely` — operands with distinct ROLES

`commutativity` and `associativity` assume interchangeable operands. These are **code
emitters** whose parameters land in different syntactic positions:

- **`StrategistDispatchEmitter.pairShrinkPhase(carrier:oracle:)`** — `carrier` is
  interpolated into a *type* position (`func stillFails(_ a: \(carrier), …)`), `oracle`
  into an *expression* position (the body). Swapping them cannot produce equal output, and
  would not compile.
- **`StrategistDispatchEmitter.tripleShrinkPhase(carrier:oracle:)`** — same shape, three
  operands.
- **`CollisionPass.ternarySweep(functionCall:carrier _:)`** — **the second parameter is
  unused**. `f(a, b)` ignores `b` entirely, so any law relating the two operands is false
  before the body is read.

**`(T, T) -> T` is a type, not a semantics, and this catalog reads it as one.**

> **A claim made here on 2026-08-19 was too strong, and is corrected the same day.** It read:
> *"this is `same-name-differential-pairing.md`'s finding reached from the other end … two
> independent measurements, one cause."* **They are not one cause.** That census is about a
> shared **function name** naming a role across types — `emit` on 16 types, where differing
> bodies are the point — and its false positive is *pairing two functions*. This is about two
> **parameters of one function** carrying distinct roles, and its false positive is a
> *commutativity law over non-interchangeable operands*.
>
> Both are undeclared conventions the tool cannot see, and the word "role" fits both. That
> makes them **analogous, not identical** — and calling them one cause would license
> re-opening a recorded decline on evidence that is not about it. The overlap is real and
> worth noticing; the identity was invented.

---

## What this does NOT establish

**That the tool finds no real bugs.** It found four on 2026-08-05 by this same route.
What is measured is that *this* corpus, at *this* commit, yields none — and a codebase
whose bugs were fixed two weeks ago is the expected place to find that.

**That `trial=0` is a usable filter.** 15 rows, all on one side, is not a base rate. It is
a hypothesis for the next survey, not a gate.

**That the false laws should be suppressed.** Naming the mechanism is not the same as
having a veto that separates a normaliser from a hash by signature — `defaultPath(for:)`
and a genuine canonicaliser are indistinguishable at the type level, which is exactly why
this is hard. `docs/design/…` has no such discriminator today and none is proposed here.

---

## The verdict

**Nothing to fix in the subject code.** All 15 rows are the catalog proposing a law its
subject never owed.

**Two things to carry into the next survey**, both cheap and neither built here:

1. **Stop quoting tier as a triage signal for refutations.** It did not work today, and
   template already did not. The index row is corrected to say so.
2. **Check `outcomeDetail` first.** Every false law here failed at `trial=0`. If that
   holds on a corpus with a real bug in it, it is a better first cut than either.

---

> ⚠ **This document's headline — *the template does not predict* — is annotated by
> `docs/measurements/template-refutation-rates.md` (2026-08-23).** Over a wider pool the
> template *does* predict for two of three arms: `predicate`/totality refutes **0 of 102**, and
> `idempotence` refutes **~1 in 5 on two independent corpora with 18 of 18 checked false**. The
> conclusion below was drawn from 15 refutations that were **all `idempotence` or
> `commutativity`** — a population containing one or two templates cannot answer whether the
> template predicts. The `codable-round-trip` arm remains unmeasured (0 of 10 here, 1 of 4 on
> `mcp-swift-sdk`).

## Addendum 2026-08-24 — 1 of 19 becomes 1 REAL of 28, and a FOURTH mechanism is named

**Nine new refutations, all false, all one mechanism, all from one generated codebase.**
`MacPaw/OpenAI` @ `a532be8`, after a leaf-spelling fix took it from 0 to 15 executing rows.
`docs/measurements/module-qualified-leaf-spelling.md` §5.

**The mechanism, joining the three this document already names:**

> **Round-trip over a type whose optional fields carry an undeclared mutual-consistency
> invariant.**

All nine counterexamples set **both** `value1` and `value2` on `swift-openapi-generator`
`anyOf`/`allOf` wrappers. `encode(to:)` writes only
`encodeFirstNonNilValueToSingleValueContainer([value1, value2])`; `init(from:)` tries to decode
both from that one value. Traced in full on `ModelIdsShared`: encode writes `"L0eZAui"`, decode
restores `value1` and drops `value2`, and `Hashable` sees it. **The `valueN` fields are
alternative views of ONE JSON value and must be mutually consistent — and the public memberwise
initializer does not enforce that**, so the generator draws states the real domain excludes. One
counterexample nests `ModelIdsShared(value1: nil, value2: nil)`, which the type's own
`verifyAtLeastOneSchemaIsNotNil` rejects by design.

**Why this does NOT weaken the 2026-08-23 hypothesis below, though it is `codable-round-trip`.**
The distinction is between the two ways a round trip can fail:

| | |
|---|---|
| `ToolChoice` (**real**) | a contradiction **inside the type's own stated semantics** — its doc comment says an omitted `mode` *means* `.auto`, the encoder agrees, and `Equatable` does not. Nothing outside the type is needed to see it |
| these nine (**false**) | the law **over-quantifies** — the type never claims the fields are independent, and the invariant that says otherwise is undeclared. Same failure as `idempotence` over a derivation |

So the template still separates *a law the code owes* from *a conjecture*; what this adds is that
a law the code owes can still be **stated over the wrong domain**.

⚠ **Hand-check honesty: the mechanism was traced in full on ONE of the nine and pattern-matched
on the other eight** by their shared both-set counterexample signature and identical generated
shape. That is weaker than nine independent hand-checks and is not equivalent to the 15 below,
each of which was read against its own subject.

⚠ **And nine instances of one pattern is not nine data points.** The tally reads **1 real of 28**,
but the denominator is now dominated by a single generated codebase emitting one shape repeatedly.
**No filter proposed** — the same pattern appears in every `swift-openapi-generator` client, which
makes it a high-volume false-law source and therefore a *presentation* question (attach the
mechanism to the refutation) long before a suppression one.

## Addendum 2026-08-23 — 18 of 18 becomes 1 REAL of 19, and the template is the difference

**The first hand-checked refutation that is a real defect.** `codable-round-trip` on
`CreateSamplingMessage.ToolChoice` in `mcp-swift-sdk`: `encode` omits the key for both
`mode: nil` and `mode: .auto`, `init(from:)` maps a missing key to `.auto`, so the round trip
does not preserve `nil` — and the synthesized `Equatable`/`Hashable` distinguishes two values
the type's own doc comment calls the same thing. Reproduced independently against the package;
their 551-test suite passes and never mentions the type. `criterion-a-quality-mcp.md`.

**This document's headline finding was that the TEMPLATE does not predict.** That was measured
across 15 refutations, and it should now be read with its population stated: **every one of the
18 false laws was `idempotence` or its operand form, and there were no `codable-round-trip`
refutations in the set at all.** A conclusion of *template does not predict*, drawn from a
population containing one template, could not have found the distinction it was testing for.

The distinction that suggests itself, on one data point and stated as a hypothesis:

| | |
|---|---|
| `idempotence` | a **conjecture read off a shape** — the tool's own caveat says so, and `f(f(x)) == f(x)` is false for any one-shot stripper |
| `codable-round-trip` | a law the code **owes** — the type declares `Codable` *and* `Equatable`, and those two conformances make the claim between them |

**Not upgraded to a finding.** 1 of 19 is an existence proof, not a rate, and the honest next
step is more codable-round-trip refutations from unmet subjects rather than a re-reading of
this one.

## Addendum 2026-08-22 — 15 of 15 is now 18 of 18, and the mechanism repeated

Three refutations have been hand-checked since, all false laws, and **two of the three share
one mechanism** this document named:

| refutation | subject | verdict | mechanism |
|---|---|---|---|
| `pushing(_:)` idempotence-in-operand | `swift-system` | **false law** | takes-operand idempotence is right for *absorbing* ops (merge, union) and wrong for *accumulating* ones (push, append) — both are `(Self, T) -> Self` |
| `removingLastComponent()` idempotence | `swift-system` | **false law** | one-shot stripper applied twice strips twice |
| `selectionStem(_:)` idempotence | home corpus | **false law** | one-shot stripper applied twice strips twice |

**The last two are the example the tool prints against itself.** `IdempotenceTemplate`'s
*"why this might be wrong"* text reads: *a `T -> T` need not be idempotent (a one-shot suffix
strip applied twice removes two suffixes)*. The catalogue names this failure mode in the
caveat it ships beside the suggestion, and then emits the suggestion anyway — twice, on two
different corpora, found only by execution.

**Both were found by RAISING THE TRIAL BUDGET**, not by a new template or filter:
`removingLastComponent` passes at 100 and fails from 250; `selectionStem` fails at trial 164.
Neither is visible at the budget that shipped until 2026-08-22.

**Still: tier does not predict.** The `selectionStem` row is `Possible`, the swift-system pair
were `Possible` and `Likely`. Nothing in the score separated them from the 163 that held.

