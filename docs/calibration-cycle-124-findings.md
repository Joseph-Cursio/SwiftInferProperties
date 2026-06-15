# Calibration cycle 124 — Phase B GREENLIT (relaxed partial-exploration ratified)

> **STATUS: DECISION (no binary change — ratifies the cycle-123 fork).** The
> owner made the precision call cycle 123 flagged: **allow relaxed
> partial-exploration.** Phase B of the `.tca` epic is greenlit on the
> relaxed framing — verify a constructible witness over the
> *constructible-action subset*, skipping non-derivable composition cases —
> accepting the weaker guarantee in exchange for ~4× reach (73 of 99 Action
> enums vs Phase A's 18). This cycle records the decision + its guardrails;
> implementation follows. Captured 2026-06-15. **No version bump.**

## The decision

Cycle 123 established that the only Phase B framing with real reach is
**relaxed/partial-exploration**, and that adopting it is a precision call,
not an engineering one — it weakens `measured-bothPass` from "held across
sampled sequences over all actions" to "…over the *constructible subset* of
actions," so a counterexample reachable only after a binding / nested /
delegate action is **missed** (a possible false `bothPass`).

**Ratified: relaxed partial-exploration is allowed.** The recall is worth
the weaker guarantee — *provided the guarantee is always disclosed* (below).
This is a deliberate, recorded shift from the strict
all-actions-or-reject posture, scoped to the `.tca` interaction-verify path.

## Guardrails (binding on the Phase B implementation)

1. **Explainability is mandatory and load-bearing (PRD §4.5).** Every
   verdict produced via partial exploration MUST carry the excluded set,
   e.g. `verified over 4 of 7 action types (excluded: binding, child,
   delegate)`. A partial-exploration `bothPass` rendered identically to a
   full-action-space one would let the weaker claim masquerade as the
   strong one — exactly the trust erosion §3.5 guards against. The detail
   rides the existing evidence `detail` field and the render path.

2. **The witness itself must be constructible.** Partial exploration only
   relaxes the *exploration* set, not the *witness*. The idempotence witness
   (and any per-step predicate's referenced actions) must be a payload-free
   or raw case. A witness with a non-derivable payload stays Phase-B-out.

3. **State still must be zero-arg `Equatable`.** Unchanged from Phase A —
   the verify shape needs `State()` + `==`.

4. **Non-empty constructible subset.** If *no* case is constructible, there
   is nothing to explore with → reject (architectural-pending), as today.

## Promotion semantics (the delegated sub-decision)

Cycle 123 left open whether a partial-exploration `bothPass` may still drive
idempotence `.likely → .verified`. **Ratified: yes, it promotes** — the
owner accepted relaxed exploration as valid evidence, so treating it as
promotable honors that decision — **but only with guardrail #1's annotation
attached**, so a human reviewing the `.verified` grade sees the partial
basis. A later full-action-space verification (e.g. once composition-case
generation exists) supersedes the partial record for the same identity.

*Mechanism note:* keep a single `measuredBothPass` outcome (no new evidence
case) and carry the excluded-actions list in `detail`; the scoring/promotion
path is unchanged, the render + evidence simply disclose the basis. Revisit
only if calibration shows partial-exploration false positives in practice.

## What this unblocks (Phase B implementation plan)

The relaxed framing is now the target. In dependency order:

1. **Richer discovery capture.** Replace Phase A's payload-free-or-bail
   (`ReducerCandidate.actionCaseNames`) with per-case payload *types* (the
   cycle-119 `EnumCaseDecl { name, [payloadType] }` shape). Keep the
   payload-free fast path; add raw-payload classification. Withhold only the
   *non-constructible* cases, not the whole enum.
2. **Composed constructible-action generator.** Emit `Gen.one(of: […])` over
   the constructible cases — `Gen.always(.free)` for payload-free,
   `rawGen.map(Action.rawCase)` for raw payloads (per-payload scalars
   delegated to `DerivationStrategist`, PRD §11). Skip non-derivable cases;
   record them as the excluded set.
3. **Witness gate + excluded-set plumbing.** Verify only when the witness is
   constructible; thread the excluded action-type list into the verdict
   `detail` (guardrail #1) and the evidence record.
4. **Proof.** A `.subprocess` test: a real TCA reducer with a *mixed* Action
   (payload-free witness + a `child(Child.Action)` / `binding` case) →
   `measured-bothPass` with the excluded set disclosed.

Phase C (corpus-scale survey over real tca-10/tca-25) is now unblocked in
principle but still needs per-reducer source slicing (co-compiling ~100
unrelated files won't work) + a real witness-detector pass.

## Record updates

CLAUDE.md "Design decisions baked in" gains the relaxed-partial-exploration
ratification (so it isn't re-litigated). Cycle-123's "shelved pending a
decision" is superseded by this greenlight.
