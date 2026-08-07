# docs/ — how this directory is organised

> **Status:** `reference` · **As of:** 2026-08-07

Two independent axes. **Directory is what a doc *is*; the status header is where it
is in its life.** They are separate on purpose — kind is stable, lifecycle moves, and
encoding lifecycle in a path costs a rename (and a broken citation) every time it
changes. That is not hypothetical: `docs/glossary.md` moved once and left two source
comments pointing at nothing for a day, which is what `DocCitationTests` now exists
to catch.

## Kind — the directory

| Directory | What lives here | The question it answers |
|---|---|---|
| `docs/` (root) | The two PRDs, and nothing else | *What is this product meant to be?* |
| `reference/` | Command and feature docs | *How does this work today?* |
| `design/` | Design records for decisions that shipped, and spikes that deliberately did **not** ship | *Why is it built this way?* |
| `measurements/` | Road tests, backtests, censuses, findings — anything with a score in it | *What happened when we pointed it at something?* |
| `plans/` | Scopes, build plans, live trackers | *What are we doing next?* |
| `ideas/` | Unbuilt proposals | *What might we do?* |
| `design-internal/` | One doc per sibling repo in the toolchain, plus the glossary and open threads | *What does the other side of the seam do?* |
| `archive/` | Superseded, and shipped-then-archived design records | *What was the reasoning behind a decision we already made?* |
| `user/` | Tutorial, guide, reference | *How do I use the tool?* |

The split that matters most is **`design/` vs `measurements/`**: a diagnosis is
checkable and does not expire, a measurement is of its date and does. When a
`measurements/` doc disagrees with reality, re-run it; when a `design/` doc does,
argue with it.

## Lifecycle — the status header

Every doc carries one line directly under its title:

```markdown
> **Status:** `measured` · **As of:** 2026-08-01
```

`As of` is the date the doc was last substantively touched, not a promise that
anything in it is still true. **For a `measured` doc, read it as an expiry stamp.**

| Status | Means |
|---|---|
| `reference` | Describes current behaviour, and is kept in step with the code |
| `shipped` | The work landed. Read for the rationale, never for current counts |
| `open` | Live work, not finished |
| `proposed` | Written down, not started, no decision taken |
| `declined` | Investigated, with a recorded decision **not** to build. Do not "fix" the absence — read the reason first |
| `measured` | A scored record. The numbers are of the `As of` date |
| `withdrawn` | The measurements are retracted; the diagnoses may still stand. Read the doc's own header before citing anything from it |
| `superseded` | Replaced by something else |

The vocabulary is closed and `DocStatusHeaderTests` enforces it, so a typo'd or
missing status fails the fast suite rather than silently becoming a ninth category.

## Two rules that are easy to break

**Every doc must be reachable from CLAUDE.md's index.** A doc nobody opens is a doc
nobody maintains, and the last sweep found eleven unreachable files — two of which
held standing constraints on live code. Sweep `docs/**/*.md`, not `docs/*.md`: the
non-descending glob is exactly how seven `design-internal/` docs stayed invisible.

**Citing a doc from code is a real dependency.** 117 Swift files name a `docs/…`
path, and `DocCitationTests` asserts every one resolves. If you move a doc, that test
tells you what you broke. If you *delete* one, cite it through the SHA it last
existed at rather than dropping the reference — `git show 31a347a:docs/foo.md` —
because the diagnosis outlives the file.

Note the limit of that guard: it only sees **this** repo. Sibling repos in the
toolchain cite these paths too, and nothing checks those.
