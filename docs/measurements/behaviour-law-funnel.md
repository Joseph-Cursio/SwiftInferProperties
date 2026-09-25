# Where do behaviour laws die? — mostly correct declines, and a long tail

> **Status:** `measured` · **As of:** 2026-09-25

Recent rounds raised compiles on the nine widened repositories 531 → 600, and nearly all of it was
*does-not-crash* laws (`predicate`, `input-totality`, `determinism`), which the mutation check measured at
1 kill in 18. Behaviour passes moved 89 → 106. Every fix had been chosen by stub count, and totality
dominates stub count. This splits the funnel by law class instead, across all 19 repositories (census 16
for the nine widened ones, census 14 for the rest), using the census's own classification
(`DOES_NOT_CRASH_TEMPLATES`).

## The answer

| | proposed | written | set aside | compiled | passed |
|---|---:|---:|---:|---:|---:|
| **behaviour** | 1,040 | **507** | 106 | 401 | 241 |
| does not crash | 668 | 627 | 119 | 508 | 505 |

**Behaviour laws are lost before a stub is written, not at the compiler** — half never become a file,
against 6% for totality. But the declines are, almost entirely, right:

| declined | why | verdict |
|---:|---|---|
| 85 | `round-trip` pairs `encode` from one implementation with `decode` from ANOTHER — all in the three pbt-workbook teaching repositories, which declare several conformers of one codec protocol | correct: no one owes a round trip across two receivers |
| 73 | `normal-form` writes no stub by design | correct (`normal-form-state-machine-writers.md`) |
| 59 | `value-round-trip` has no writer: the law is `read(write(v)) == v` and only the author knows `write` | correct: guessing `write` with `String(describing:)` would make false laws of every parser with its own format |
| 76 | `monotonicity` over a collection or Optional (31), a type nothing makes `Comparable` (30), a SwiftSyntax node (15) | correct |
| 27 | a generic or opaque parameter that names no type at the call site | correct (#493) |
| 14 | a throwing subject in an arm that cannot propagate | correct |

**The written-but-set-aside behaviour stubs are a long tail.** 82 of the 106 carry a generator the tool
could not derive; 13 of those are the PRD's deliberate `?.gen()` placeholder for a lifted law whose type
was not recovered, and **no other type blocks more than 2 stubs on its own**.

And the stage after compiling is mostly false laws: `idempotence` compiles 169 and passes 104, the
difference being the named mechanisms `refutation-hand-check.md` already records.

## What this means

**No fix in the pipeline moves behaviour laws much.** Reach has been pushed to where the remaining
behaviour declines are the tool being right. The levers that are left are not in the stub path:

- **Proposing more refutable laws on real code** — the catalogue side. Behaviour passes outside the
  teaching repositories are dominated by `idempotence`, the template with the worst hand-check record.
- **Making passing laws discriminate** — the mutation check found half the planted bugs were never
  reached by the generated inputs; a law that passes on inputs that miss the bug checks little.

⚠ **One cleanup, not a lever:** discovery could stop proposing `round-trip` across two different
receiver types, withdrawing 85 noise rows and freeing no laws.

## Method

Per template: *proposed* is `Template:` lines in each scan group's `discover` transcript; *written* is
stub files in the census tree's `Generated/` plus its `aside-*` directory; *set aside* and *passed* come
from `result-*.json`. **Decline notes are counted by their text, not attributed by position** — they go
to stderr while suggestions go to buffered stdout, so a note often lands inside the NEXT suggestion's
block, and a first cut that attributed by position read 13 behaviour declines instead of ~530.
