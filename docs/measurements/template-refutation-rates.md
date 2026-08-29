# Does the TEMPLATE predict whether a refutation is worth reading?

> **Status:** `measured` · **As of:** 2026-08-23

**Partly — and only two of the three arms are strong enough to act on.**

| template | ran | refuted | rate | every refutation hand-checked? |
|---|---:|---:|---|---|
| `predicate` (totality) | **102** | **0** | **0.0%** | nothing to check |
| `idempotence` | 65 | 14 | **21.5%** | **18 of 18 across history: FALSE LAWS** |
| `codable-round-trip` | 14 | 1 | 7.1% | **1 of 1: REAL** |
| `associativity` | 6 | 2 | 33.3% | unchecked |
| `commutativity` | 5 | 1 | 20.0% | earlier ones checked: false |
| `monotonicity` | **2** | **2** | — | **2 of 2: FALSE LAWS** — and the denominator is the point, see below |

Pooled over three streams — the home corpus at N=1000, `mcp-swift-sdk`, and `swift-system` —
counting only rows that reached a verdict (build failures, traps and parse errors excluded).

---

## 1. What is strong

**`predicate` / totality never refutes on real code: 0 of 102, across all three corpora.**
It is not that it rarely fires; it did not fire once. The only time a totality law has ever
refuted anything was against a **planted** mutant
(`criterion-a-quality-swift-system.md`). Safe, and so far uninformative.

**`idempotence` refutes about one time in five, and the rate holds across corpora:**

| corpus | ran | refuted |
|---|---:|---:|
| home | 60 | 13 (22%) |
| `swift-system` | 4 | 1 (25%) |
| `mcp-swift-sdk` | 1 | 0 |

**And every idempotence refutation ever hand-checked — 18 of them — is a false law.**
That is the robust finding here: **`idempotence` is where the noise lives**, measured on two
independent corpora rather than asserted from one.

The mechanism is named and repeats: a one-shot stripper applied twice strips twice
(`removingLastComponent`, `selectionStem`), and takes-operand idempotence is right for
*absorbing* operations and wrong for *accumulating* ones (`pushing(_:)`). **The template's own
caveat states this failure mode**, and the template emits the suggestion anyway.

---

## 1a. `monotonicity` — a rate cannot be quoted, and the reason is new

**2 ran, 2 refuted, both false.** `swift-collections` @ `899809d3`
(`monotonicity-verify-reach.md`). ⚠ **Do NOT read 100%.** The denominator is 2 out of **64 rows
attempted**, and it is small for a reason no other arm in this table has: the template's rows do
not reach the verifier.

| outcome | rows |
|---|---:|
| `architectural-coverage-pending` | 52 |
| `measured-error` — build failed in OUR stub | 10 |
| verdicts | **2** |

`instance-method-shape-not-supported` alone takes **30 of 64**. So where `predicate`'s 0-of-102
says *nothing will fire* and `idempotence`'s 21.5% says *this is where the noise lives*, this arm
says **almost nothing gets far enough to say anything** — a statement about reach, not about
truth.

Both refutations are one mechanism: `_growUniqueArrayCapacity(_:)` / `_growUniqueDequeCapacity(_:)`,
`internal` capacity-growth functions using deliberate wrapping arithmetic, refuted by a large
negative `Int` they are never called with. **Over-quantified domain** — the `UserDetectionStatus`
mechanism.

## 2. What is NOT strong, and must not be quoted as a rate

**`codable-round-trip`'s 7.1% is one refutation, and the arms disagree:**

| corpus | ran | refuted |
|---|---:|---:|
| home | **10** | **0** |
| `mcp-swift-sdk` | 4 | **1** |

Zero of ten here, one of four there. **That is not a rate; it is two small samples.** The
single refutation is real (`ToolChoice`, `criterion-a-quality-mcp.md`) and it is the only real
defect this project has found — but *n* = 1 on the arm that matters, and one real find does not
establish that the next one will be.

**The control does hold, and it is what makes even this much readable.** A synthesized `Codable`
conformance is symmetric by construction and **cannot** refute, so a population of synthesized
types would make the 13 passes vacuous. Checked: **all 14 carriers declare hand-written
`Codable`** — `SeedKind`, `MarkerPair`, `Vocabulary` and the rest put it in `extension` blocks.
Every one of the 14 *could* have failed. Thirteen did not.

⚠ **The first version of that control said 7 of 14, and was wrong.** It scanned 40 lines past
each type declaration and so missed every conformance living in a separate `+Codable.swift`
extension — including `SemanticIndexEntry`, whose custom `Codable` this session had already
read. Caught by disbelieving a result about a file I knew. **Sixth instrument failure of this
shape in one cycle.**

---

## 3. What this revises

`refutation-hand-check.md` concluded **the template does not predict**, from 15 refutations.
That conclusion is annotated rather than overturned, and the reason is a population limit it
could not have seen: **its 15 were all `idempotence` or `commutativity`, and it contained no
`codable-round-trip` refutation and no `predicate` refutation at all** — because `predicate`
produces none.

A study asking *does the template predict* over a population containing one or two templates
cannot find the distinction it is testing for. The wider pool says:

- the template **does** predict for `predicate` — it predicts *nothing will ever fire*
- the template **does** predict for `idempotence` — it predicts *one in five, and false*
- for `codable-round-trip`, **still unmeasured**

---

## 4. What follows, and what deliberately does not

**No filter is proposed.** This project's rule is to raise thresholds rather than pile on
filters, and a 21.5%-false-positive template is a candidate for **presentation** work — showing
an idempotence refutation with its known failure mode attached — long before it is a candidate
for suppression. Suppressing `idempotence` refutations would also have suppressed nothing of
value *and* nothing of harm, since none was real.

**The measurable next step is more `codable-round-trip` refutations from unmet subjects.** They
are scarce: 1 in every stream this project has frozen. Their population is bounded by
hand-written `Codable` — synthesized conformances cannot fail — so a subject is only a
candidate if it writes its own coders.

**Confound stated plainly**: the three templates were not measured over the same corpora in the
same proportions. `idempotence`'s rate is corroborated on two corpora; `codable-round-trip`'s is
not corroborated at all. Reading the table as one ranked list would overstate what the third row
supports.
