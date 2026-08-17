# Why did `make docs-drift` not catch a doc arguing against the code?

> **Status:** `measured` · **As of:** 2026-08-17

Answers open-threads item 39. The row asked a two-way question and the answer is
**neither branch** — a third possibility it did not consider, and the one that
generalises.

---

## The staleness, verified first

`PBT_EFFECT_VOCABULARY_SURVEY.md` makes two claims that the code contradicts.

| the survey says | the code says |
|---|---|
| SEI *"has no `pure`"*, and lists **"add `pure` below `observational`"** as Idea-#4 next-step work | `Effect.swift:67` — `case pure`, at **rank 0**, with the full lattice rationale |
| SwiftInferProperties consumes SEI: **"No (parallel)"** — it has *"its own"* vocabulary | `Package.swift` declares the dependency; `SoundPurity` composes SEI's `PurityInferrer` with this repo's `ReducerPurityAnalyzer` |

Both stale. The survey is dated well before the extraction it proposes actually
happened, and it reads as live design work.

**But the row is right that this is not the interesting half.** A doc going stale
is ordinary. A *detector built to notice* that, not noticing, is the finding.

---

## The question the row asked

> Either the survey carries no provenance trailer, or it does and the drift check
> does not cover cross-repo claims. Worth knowing which before trusting the
> detector elsewhere.

**Neither.** The survey lives at `~/xcode_projects/PBT_EFFECT_VOCABULARY_SURVEY.md`
— in the **workspace parent, outside every git repository**. `xcode_projects` is
not a repo. No per-repo check can reach it, whatever trailer it carried.

And underneath that, the more useful fact: `scripts/docs_drift.sh` reads

```sh
DOCS_DIR="${DOCS_DIR:-docs/design-internal}"
for doc in "$DOCS_DIR"/*.md; do
```

**One directory, non-recursive, one repo.** So the answer to "which of the two" is
that the detector's scope was never the question — it was never in scope at all.

---

## The blind region, measured

| | count |
|---|---|
| `.md` files under `docs/` | **91** |
| …in scope for `docs-drift` (`docs/design-internal/*.md`) | **9** |
| …out of scope | 82 |
| **out-of-scope docs naming a sibling repo** — the class of claim this check exists to verify | **49** |
| orphan docs in the workspace parent | 7 (`GEMINI.md`, six `PBT_*.md`) |
| …of those, making cross-repo claims | **6** |

So the detector checks 9 of 91 in-repo docs, and 49 unchecked in-repo docs make
exactly the kind of claim it was written to catch. The survey that prompted the
item is in neither count.

### Why the summary line made this invisible

```
9 doc(s) checked · 6 drifted · 0 unresolved · 1 stale checkout(s)
```

A count with **no denominator**. It reads as a coverage report and is a tally of
one directory. This project already has the rule that forbids exactly this —
*"a census's zero cannot be read without its corpus list"* — and the tool that
reports on documentation was the thing breaking it.

That is the same shape as the standing warning in `CLAUDE.md`: *"Sweep
`docs/**/*.md`, not `docs/*.md` — the non-descending glob is exactly how seven
`design-internal/` docs stayed invisible."* Same class of defect, different
check, and the second one was not caught by having written down the first.

---

## What was changed

`scripts/docs_drift.sh` now prints its own denominator:

```
scope: docs/design-internal/*.md only — 9 of 91 docs under docs/. 49 out-of-scope doc(s) name a
sibling repo and are NOT checked here; docs outside the repo are invisible to it.
```

**Deliberately not fixed by widening `DOCS_DIR`.** All 82 out-of-scope docs lack a
provenance trailer, so a recursive glob prints 82 `?` rows and the signal drowns.
The check would become the thing nobody reads — the failure mode two other rows
in the open-threads doc already record, and reaching it while trying to fix a
coverage gap would be a poor trade.

The gap is now **stated** rather than closed, which is the honest state: a reader
of the session-start hook can no longer mistake nine green rows for ninety-one.

---

## What is left, and it is a decision rather than a task

**`PBT_EFFECT_VOCABULARY_SURVEY.md` cannot be maintained where it is.** It is
outside version control, so it has no history, no review path, and no detector.
Three options, none of them mine to pick:

- **Move it into `docs/archive/`** here, with a status header marking it
  superseded by the shipped `Effect` lattice. It becomes reviewable, gets an
  index row under the standing rule, and stops arguing with the code.
- **Delete it.** Its proposal shipped; the argument it makes is settled.
- **Leave it**, having now recorded that it is stale on two specific claims.

The same question applies to the other five workspace-parent docs making
cross-repo claims, which have never been checked by anything.

### What would reopen this

- **A doc in `docs/design-internal/` goes stale without the check firing.** That
  is the check failing at its actual job, rather than outside its scope.
- **The out-of-scope count with cross-repo claims grows past ~50** without any of
  them gaining a trailer, at which point stating the gap stops being enough and
  the trailer needs to become cheap enough to add by default.
