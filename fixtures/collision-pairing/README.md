# Collision pairing — does deriving the second operand buy refutations?

> **Status:** `measured` · **As of:** 2026-08-20

Harness: `swift test --package-path fixtures/collision-pairing`. Standalone package; it
deliberately does **not** depend on the tool it is scoring.

**Measured YES, but only on a WIDE domain — and on a narrow one a bigger trial budget is
the cheaper fix.** Scored in mutants killed, following `fixtures/integer-division-generator/`.

---

## The scorecard

3 refutable mutants of a keyed merge. Non-commutativity lives entirely in the tie-break,
which only runs when the operands share a key.

| key space | independent @100 | @1,000 | @20,000 | **overlapping @100** |
|---|---|---|---|---|
| **narrow** (10⁴ keys) | 1/3 | **3/3** | 3/3 | **3/3** |
| **wide** (10⁹ keys) | 1/3 | **1/3** | **1/3** | **3/3** |

`RoundTripStubEmitter.TrialBudget` is **100** (`.small`, the V1.42 default) or **1,000**
(`.standard`). 20,000 is not a budget this tool runs and is present only to locate the
crossover.

---

## What the two rows mean

**Narrow: the gap is a budget effect and closes without pairing.** Keys from a finite
range do collide; at ~2.5 keys per side against 10,000 the per-trial probability is
~6×10⁻⁴, so a thousand trials find it. **For a domain this size, raising the trial budget
beats building a pairing pass**, and `narrowSpaceGapIsABudgetEffect` exists to stop anyone
claiming otherwise on this fixture's evidence.

**Wide: no budget closes it, and pairing is the only lever.** A billion keys is the
analogue of what `CommutativityStubEmitter` actually emits — `Complex<Double>` drawn from
`-1_000_000.0 ... 1_000_000.0`, where two independent draws never collide at any budget
reachable in a test. **This row is the entire case for building the pairing**, and it is
the row that matches the shipped emitter.

---

## The premise this fixture started with was FALSE

The first version asserted that independent draws never make two dictionary operands
share a key, so a tie-break mutant survives. **Measured, independent draws killed 3 of 3.**

The error was scoring at 20,000 trials — a budget the tool never runs — on a narrow
domain. The blind spot is not *"this domain cannot collide"*; it is **"this domain cannot
collide often enough to be found inside the budget the emitter uses, and only if the
domain is wide is that true at every budget"**. The correction added the key-space axis
and is the reason the recommendation below is narrow rather than sweeping.

**Recorded because the wrong version would have shipped a defensible-sounding claim.**
*"Independent draws cannot find collision-dependent failures"* is true-sounding, was
believed, and is false as stated.

---

## Two results worth keeping separate from the headline

**`permuted` is 2/3 everywhere — additive, not better.** It reuses the first operand's key
set exactly, so `drops-left-only` (a mutant that fails on ordinary distinct operands) is
unreachable by construction, while independent draws catch it at every budget. That is the
concrete form of *a derived pairing must be an additional pass, never a replacement*:
swapping the default would gain two mutants and silently lose one. `pairingIsAdditiveNotBetter`
asserts both halves.

**`identical` is 0/3, and that is not a defect.** `f(a, a) == f(a, a)` is a tautology for
any deterministic subject, so the diagonal cannot refute a commutativity law however wrong
the subject is. Pinned so nobody adds it to a commutativity pass expecting a gain; it earns
its place on other laws.

**The control is `min-on-collision`** — it collides on every shared key and is still
commutative. No pairing may kill it, and `commutativeSubjectsSurvive` checks every pairing
against every commutative subject. A scorer that kills everything measures its own
aggression.

---

## The recommendation

**Add an `overlapping` pass to the two-operand stub emitters** (`commutativity`, 51
discovery rows; `associativity`, 67), as an **additional** pass beside the independent
default — the same shape `docs/design/verify-edge-pass.md` settled for boundary values.

It is worth **+2 of 3 mutants at the shipped 100-trial budget on a wide domain**, which is
the domain those emitters actually use.

**Not built here.** This fixture measures the case; the emitter change is a separate piece
of work touching the stub emitters, the `VERIFY_*` marker vocabulary and the result parser.
A `OperandPairing` type was written and then **deleted before landing**: an unconsumed
public enum is the *findings with no consumer* smell this repo already recorded against the
soundness arm, and the type should ship with its consumer or not at all.

## What would reopen it

- **A wide-domain subject where `overlapping` falsely refutes.** The control covers
  commutative subjects on this fixture only; precision on real corpora is unmeasured.
- **Raising the default trial budget to `.standard`.** That closes the narrow-domain row
  for free and would shrink, though not eliminate, the case for pairing.
- **A subject whose failure needs three-way overlap.** `associativity` takes three
  operands and this fixture models two; the pairing vocabulary may not generalise.
