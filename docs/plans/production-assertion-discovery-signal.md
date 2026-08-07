# Scope: mining production-code assertions as a property-discovery signal

## Status

**Not built. Design note only — needs sign-off before implementation.**

## Motivation

swift-infer does **not** currently read production-code assertions
(`precondition`, `assert`, `require`, `preconditionFailure`,
`guard … else { fatalError }`) as a signal for discovering properties. Verified
against the code (2026-07):

- **TestLifter reads *test* assertions, not production ones.** The
  assertion-scanning detectors (`AssertOrderingPreservedDetector`,
  `AsymmetricAssertionDetector`, `AssertCountChangeDetector`) live in
  `SwiftInferTestLifter/` and parse XCTest / `#expect` bodies. Where they say
  "precondition" they mean the *logical setup inside a test* (`a < b` paired
  with `f(a) <= f(b)`), not a production `precondition(_:)` call.
  `asymmetricAssertion` is emitted from `TemplateRegistry+CrossValidation.swift`
  — a test-cross-validation signal.
- **`PreconditionHint` infers input domains from test-fixture literals**
  ("every observed Int at this argument was positive across N test sites →
  suggest `Gen.int(in: 1...)`"). It is data-driven from observed literals,
  advisory only, and constrains a **generator** — it never parses a
  `precondition()` statement and never names a property.
- **`BodySignalVisitor` walks `FunctionCallExpr` only for reducer/algebraic
  ops** (`recordReducerOp`); it steps past any `guard` / `assert` /
  `precondition` in the visited source.

So the production-source discovery path is signature-driven (type shapes) +
structural body signals (`selfComposition`, `reduceFoldUsage`, `fixedPointName`)
+ annotations. **Production assertions are an untapped seam.**

A production `precondition` *is* a lightweight contract, and a trailing
`assert(postcondition)` *is* a candidate invariant. This is exactly the
"derive properties from contracts" idea (Hillel Wayne, *Finding Property
Tests*; Leitner et al., *Contract Driven Development = Test Driven Development
− Writing Test Cases*, ESEC/FSE 2007 — see the book's Preface "Related
reading"). We mine that seam from the **test** side but not the **production**
side.

## What it would do

A new production-source scanner (in `SwiftInferCore`, sibling to
`BodySignalVisitor`) walking function bodies for two distinct shapes:

1. **Entry precondition → domain constraint (+ partiality signal).**
   `precondition(x > 0)` / `guard x > 0 else { preconditionFailure() }` at the
   top of a function, referencing a **parameter** (not `self` state), yields a
   generator constraint on that parameter. This fills the same slot as
   `PreconditionHint` but *directly from source* rather than inferred from
   literals — and it is a source of truth, so when both fire, source wins. It
   also marks the function **partial**: the declared-but-unemitted
   `Signal.Kind.partialFunction` case (`Signal.swift:36`, no current emitter)
   is the natural home.

2. **Post-computation assertion → candidate postcondition-as-property.**
   A trailing `assert(result >= 0)` / `assert(output.count == input.count)`
   that relates the **result** to the inputs is a candidate invariant worth
   surfacing as a property suggestion (likely a new `Signal.Kind`, e.g.
   `assertedPostcondition`, with a PRD weight row).

Provenance, per PRD §3.5 conservative bias: advisory, rendered as a
`// Derived from production precondition/assertion:` line, no score/tier bump —
mirroring how `PreconditionHint` renders today. User inspects and decides.

## Precision risks (why this is non-trivial)

- **Not every `assert` is a property.** `assert(index < count)` is a bounds
  guard, not a general invariant. Must distinguish parameter-domain
  preconditions from result-relating postconditions; only the latter should
  emit a *property*.
- **`self`-state vs input-domain.** A `precondition` over stored properties is
  Meyer's *class invariant* (object well-formedness), not an input constraint —
  the exact §2.2.4 distinction. It must **not** narrow a generator. Gate on
  "references a parameter identifier, not `self`."
- **Domain-narrowing that hides the bug.** Source preconditions are
  authoritative for the domain (good), but the *property* is "**given** the
  precondition, the postcondition holds" — never "the postcondition holds
  unconditionally." Emitting the postcondition without carrying the
  precondition would test a narrower claim than the code promises.
- **Effectful / interprocedural asserts.** An assertion that calls other
  functions or reads globals is not a pure postcondition; reuse the existing
  purity/side-effect gating before admitting it.
- **`assert` compiles out in release; `precondition` does not.** Fine as
  *signals*, but the two carry different runtime semantics; the provenance line
  should not imply the check ships.

## Relationship to existing pieces

- **Complements `PreconditionHint`** (inferred-from-literals) with a
  declared-in-source path. Same rendering posture; source is the tiebreaker.
- **`partialFunction`** (`Signal.swift:36`) is the pre-reserved, currently
  unemitted signal slot for shape (1).
- **Cross-references the book** Preface "PBT vs. Design by Contract" — this is
  the tool-side realization of the "properties from contracts" prior art.

## Open questions for sign-off

1. **One feature or two?** Domain-constraint-from-precondition (lower risk,
   generator-only) and postcondition-as-property (higher value, higher noise)
   are separable. Ship (1) first?
2. **Do we emit a property from an `assert`, or only a generator constraint
   from a `precondition`?** The former is where the value is, but asserts are
   noisy; may want it behind a calibration flag initially.
3. **Precision gate:** which assert shapes to admit — result-referencing only?
   Minimum confidence? How to carry the precondition into the emitted property
   so we don't test a weaker claim.
4. **Conservative-bias interaction (PRD §16 #4 — no silently-wrong code):**
   advisory-only for the first cut, matching `PreconditionHint`.

## Rough cost

New production-source visitor + `Signal.Kind` wiring (+ PRD weight row for the
postcondition case) + provenance rendering + unit/measured tests. Medium.
Scope deliberately rather than starting on impulse.
