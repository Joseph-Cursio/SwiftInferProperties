# Idea: Contract-as-Oracle — the execution variant (AutoTest-style)

## Status

**Idea only. More aggressive than, and a sibling to,
`docs/production-assertion-discovery-signal.md`** — read that first. That note
mines production `precondition`/`assert` *statically*, as a signal to *suggest* a
property the user then inspects. This note records the other, more aggressive
design it deliberately does not cover: using the contract itself as a live
**oracle**.

## The distinction

Two ways to turn a production contract into a property:

1. **Static signal (the existing note).** Read `precondition(x > 0)` and a
   trailing `assert(result >= 0)`, and *emit a suggested property* — advisory,
   provenance-tagged, user decides. No execution.
2. **Execution oracle (this note).** *Run* the function on generated inputs that
   satisfy the (inferred or source) precondition, and treat a **trapped
   precondition** or a **failed trailing assert** as the falsifying
   counterexample. No property is authored — the contract *is* the property.
   This is "property-based testing where the property is the contract" — exactly
   AutoTest (Meyer's group) and the *Contract Driven Development = TDD − Writing
   Test Cases* thesis the book's Preface §"PBT vs. Design by Contract" cites.

## Why the execution variant is genuinely hard (the load-bearing constraint)

Swift's `precondition(_:)` and `assert(_:)` **trap** — they abort the process.
The book's own toolchain note (`manuscript/.../Package Workflow`) states the
consequence plainly: the shipped property forms record a Swift Testing issue
*"rather than trapping on a `precondition`… because a process that dies can't
shrink."*

So an execution oracle cannot just call the function and let it crash: the first
counterexample would abort the run and destroy the shrink search that is PBT's
whole payoff. It would need a **non-trapping harness** — intercept the
contract violation (e.g. run the subject in a way that converts a trap into a
recorded failure, or instrument the assert sites) so generation + shrinking to a
minimal witness are preserved. That interception is the real cost, and the reason the
static-signal note is the cheaper first cut.

## The three contract legs, mapped

- **Precondition** → the generator's input domain (constrain, don't falsify) —
  already the `PreconditionHint` / static-note slot.
- **Postcondition** (trailing `assert` relating result to inputs) → the oracle
  check. Carry the precondition into the claim: the property is *"given the
  precondition, the postcondition holds,"* never unconditional.
- **Class invariant** (an `assert`/`precondition` over `self` state, not a
  parameter) → **not** a single-call oracle. It is Meyer's object-wellformedness
  invariant, which maps to the *stateful* machinery: check it after **every**
  command in a sequence — i.e. the existing `InteractionInvariant` /
  interaction-invariant-suggestion path, not this scanner. The static note's
  "gate on references-a-parameter-not-`self`" rule is exactly the fork between
  these two designs.

## Recommendation

Ship the static-signal note first (lower risk, no runtime harness). Treat this
execution variant as a later, opt-in mode — its value is full automation (no
test to lift, no property to author), but it is gated on solving the
non-trapping-oracle problem above. Prior art to mine before building: AutoTest
(ETH), *Programs That Test Themselves*, Hillel Wayne *Finding Property Tests* —
all in the book's Preface "Related reading".

## Cross-references

- `docs/production-assertion-discovery-signal.md` — the static sibling.
- Book Preface §"PBT vs. Design by Contract" — the passive-vs-generative framing
  and the prior art.
- `pbt-book/planning/workbook-continuum.md` — the assertion → contract → PBT →
  formal-verification ladder this sits on.
