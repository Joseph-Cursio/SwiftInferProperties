# Idea: a refuted high-confidence guess is a candidate bug, not just a bad guess

## Status

**Idea only.** A *posture* extension, not a bug fix — read the "posture" section
before scoping. Sibling to the measured-verify machinery that already exists
(`docs/measured-verify-architecture.md`, `docs/prove-then-show.md`).

## The observation

The measured-verify loop already resolves one fork automatically: `discover`
guesses a property statically, `verify` / `prove-then-show` execute it, and a
disproven pick is **dropped** (in `prove-then-show`, shown in the *Disproven*
bucket with its counterexample; in the default discover render, suppressed). The
framing is always **"my guess was wrong"** — the disproof protects precision by
removing a false suggestion.

But a disproof has *two* possible causes, and the tool currently assumes only the
first:

1. **The guess was wrong** — the heuristic over-reached (e.g. the verb "combine"
   scored `+40` for commutativity, but `combine` is left-biased). Drop it. This
   is the case the tool handles.
2. **The guess was right and the code is wrong** — the property genuinely *should*
   hold, and execution found a counterexample because the implementation has a
   bug.

The higher the *static confidence* of a guess that execution refutes, the more
likely it is case 2. A `set*`-named action the model rated `.strong` for
idempotence, disproven on a two-step sequence, is not obviously a bad guess —
it's the shape of a real idempotence bug. **That is precisely the workbook's
thesis** (`pbt-book/planning/workbook-*`): a property that *should* hold but
doesn't is how PBT finds bugs.

## The enhancement

When a pick with **high static confidence** is **measured-disproven**, surface it
as a **candidate defect** — a distinct outcome from the low-confidence disproof
that just means "bad guess." Concretely:

- A new classification alongside the existing buckets, e.g.
  `disproven-but-high-confidence` → **"Suspected bug"**, gated on
  `staticTier >= .strong` (or a tunable threshold) **and** `measured-defaultFails`.
- Render it with the counterexample already captured (the Disproven bucket
  already shows it) but a different verdict line: *"You'd expect `join` to be
  commutative; it isn't — counterexample `(medium, low)`. Either the law doesn't
  apply here, or this is a bug."* — surfacing the fork rather than silently
  resolving it to "bad guess."
- Keep it **out of the default `discover` view** (which is a suggestion feed);
  make it a mode / flag (e.g. `--suspect-bugs`) or a `prove-then-show` bucket, so
  the suggester posture is unchanged unless asked.

## Why this is a posture decision, not just a feature

The whole tool is built on *"prefer silence to a wrong guess"* (Ch16
high-precision posture). This enhancement deliberately keeps a disproven pick
*visible* instead of dropping it — the opposite reflex — so it must be opt-in and
clearly separated, or it reintroduces exactly the false-positive noise the
precision posture exists to suppress. The value is real (a suggester that also
flags likely bugs), but it changes what the tool *is* in that mode, so it's a
product call, not a silent default.

## Precision risks (why the gate matters)

- **Most disproofs really are bad guesses.** Without a *high-confidence* gate,
  every refuted heuristic becomes a "suspected bug" and the mode is pure noise.
  The static tier is the filter: only guesses the scorer was confident about earn
  a bug verdict.
- **Coverage honesty carries over.** A *partial*-coverage disproof
  (`excludedActionCount > 0`) can be a false-fail from the excluded action space
  (§4 of the verify architecture) — do **not** call that a bug. Gate suspected-bug
  on *full* action-space coverage, the same soundness bar the gate-overrule uses.
- **The counterexample must be real, not a generator artifact.** Reuse the
  existing constructibility / non-trapping guarantees; a trap or an
  un-constructible carrier is `Unverifiable`, never a bug.
- **A refuted guess in a documented-partial law is expected.** If the property is
  only claimed under a precondition the verifier didn't honor, that's a
  false-fail, not a defect — reuse any precondition/domain gating before emitting
  a bug verdict.

## Relationship to existing pieces

- **Rides `measured-defaultFails`** — the counterexample and the disproof already
  exist; this only *reclassifies* a subset of them by static confidence + coverage.
- **`prove-then-show`** is the natural home: it already tests everything and
  renders buckets; add a fifth verdict (Suspected bug) between Disproven and
  Proven.
- **Cross-refs** `docs/ideas/Contract-as-Oracle execution variant.md` (the other
  "execute, then act on the result" idea) and the book's
  `planning/workbook-contracts-and-strength.md` §A′ (assertion mining — same
  "a survivor is a candidate" logic, here applied to the *non*-survivors).

## Open questions for sign-off

1. **Threshold.** `.strong` only, or `.strong` + `.verified`-adjacent? Tunable?
2. **Default-off vs. prove-then-show-only.** Is this ever allowed near the default
   suggestion feed, or strictly a `prove-then-show` / `--suspect-bugs` surface?
3. **Blame wording.** How hard to lean on "bug" vs. "the law may not apply" — the
   tool can't know which; the verdict should present the fork, not assert the bug.
4. **Regression corpus.** The verify corpora already ship deliberate false
   positives (§7) — extend them with a "high-confidence guess that is actually a
   code bug" fixture so the suspected-bug path has a true-positive to test against.

## Rough cost

Small–medium. The disproof + counterexample + coverage flag all exist; this is a
reclassification + a new render verdict + a gate + a corpus fixture. No new
execution machinery.
