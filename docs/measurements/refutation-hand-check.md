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

**This is `docs/measurements/same-name-differential-pairing.md`'s finding reached from the
other end** — that census measured *"the dominant FP is undeclared **role** interfaces"*
against a ≥50% bar and declined at 40%. Here the same mechanism accounts for **3 of 3**
`Likely` refutations. Two independent measurements, one cause: **`(T, T) -> T` is a type,
not a semantics, and this catalog reads it as one.**

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
