# Predicate volume on the default surface

**Date:** 2026-07-31 · **Status:** fixed · **Trigger:** a stale comment that contradicted measured behaviour

## The contradiction

Two deliberate, well-argued decisions had drifted into conflict, and neither
author knew about the other.

**B3 — `PredicateTemplate`, weight 20.** Its comment read:

> Weight 20 — the lowest in the catalogue, and deliberately below the default
> tier, so a predicate suggestion is **HIDDEN** unless the reader asks for
> `--include-possible`. … Every `Bool`-returning function in a codebase is a
> predicate by shape … Surfaced by default, it would **bury the partition and
> comparator findings** under a list of everything that returns a `Bool`, and a
> category that fires on everything is a category people switch off.

**`3e38e34` (2026-07-14) — "A law the code OWES is never hidden."** It added
`predicate` to `Refutability.roleEntailedTemplates`, so
`isWorthSurfacingBelowCut` rescues it past the confidence cut. The commit was
earned from a real regression:

> a cold reader performed the extraction the linter demanded; … the focus found
> no match for the `partition` law discovery had produced, and dropped it. The
> sharpest law in the run vanished BECAUSE the reader complied.

Both are right. The later one silently overrode the earlier, and the earlier's
comment was never updated — so anyone reading `PredicateTemplate` was told the
opposite of what the tool does.

## Measured, default surface (no `--include-possible`)

| target | predicate | total | share |
|---|---:|---:|---:|
| `SwiftInferTemplates` | 56 | 64 | **88%** |
| `SwiftInferCore` | 46 | 77 | **60%** |
| `SwiftInferCLI` | 13 | 35 | 37% |

And the ordering made it worse than the share suggests. Output was in production
order, not score order:

```
positions  1–56 : predicate                 score 20
positions 57–64 : idempotence,
                  invariant-preservation,
                  differential-equivalence  score 80
```

**A reader scrolled past 56 score-20 suggestions to reach the first score-80
one.** That is B3's stated failure mode, arriving through the door `3e38e34`
opened for good reasons.

## The fix is ordering, not hiding

Hiding predicates would re-break what `3e38e34` fixed, and that rule was earned
from a real incident rather than reasoned from first principles. But B3's worry
was never about *presence* — it was about **burial**. Those are separable.

`Discover.strongestFirst` sorts the default surface by score descending. An owed
law stays visible and stays *below* the laws the reader came for. Neither
principle gives anything up.

After:

```
positions 1–8 : score 80   (differential-equivalence, invariant-preservation, idempotence)
positions 9+  : score 20   (predicate)
```

**Total and deterministic.** PRD §16 #6 requires byte-identical output across
runs and `sorted(by:)` is not a stable sort, so equal scores break ties on the
identity hash rather than on whatever order the templates produced. Verified:
two consecutive runs over `SwiftInferTemplates` (3,373 lines) are byte-identical.

`query` already ordered by score descending. `discover` — the primary surface —
did not.

## What this corrects in the record

`docs/verify-carrier-reach-census.md` and the CLAUDE.md row derived from it say
**"template reach is 65%, half of it `predicate`"**, framing the predicate share
as a *reach* deficit for `verify`. That reading is wrong twice:

- The census counted `--include-possible` output.
- More importantly, verify declining a **totality** claim is not a gap. There is
  no law there to measure beyond "it answers for every input", and
  `PredicateTemplate` says so itself: it is "the one role in this catalogue that
  carries **no free law**". A tool that invented one would be making it up.

The census's headline still holds — template reach *is* the binding constraint
on verify — but `predicate` is the wrong example to hang it on.

The census doc also describes predicate as "docstring-derived contracts". It is
shape-derived: any `Bool`-returning function, proposing totality.

## Still open

- **Is the score-20 volume itself a problem, now that it sorts last?** 88% of the
  surface is still 88% of the surface. Ordering makes it ignorable rather than
  obstructive, which was B3's actual concern — but nobody has asked a reader.
- The `--include-possible` surface is unsorted-by-nothing in the same way; this
  change sorts it too, since the cut and the sort are the same pipeline stage.
