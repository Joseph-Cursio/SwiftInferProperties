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
path, and `DocCitationTests` asserts every one resolves — **case-sensitively**,
because `FileManager.fileExists` is not. APFS is case-insensitive by default, so a
citation spelled `docs/Design/foo.md` for a directory named `design` passes every
local check and 404s on GitHub and on Linux CI. That is not hypothetical: a sweep of
SwiftProjectLint reported three paths as fine when its directory is `Docs/` and all
three said `docs/`, including the README's own front-door index. If you move a doc, that test
tells you what you broke. If you *delete* one, cite it through the SHA it last
existed at rather than dropping the reference — `git show 31a347a:docs/foo.md` —
because the diagnosis outlives the file.

**Docs citing docs is guarded too, and was not until 2026-08-07.** `DocCitationTests`
read Swift comments and markdown *link* syntax; the backtick-in-prose form — which is
how these docs cite each other nearly everywhere — was checked by neither. The
reorganisation that moved 64 docs left 130 dangling occurrences over 60 paths with
every check green. `DocProseCitationTests` now scans the live docs plus CLAUDE.md.
Two conventions come with it. A pruned doc may be **named in prose** as long as its
recovery pointer sits on the same line:

> Post-v0.1.0 perf-tuning candidates are recorded in `docs/perf-baseline-v0.1.md` (pruned in `59bc93b`; recover with `git show 59bc93b^:docs/perf-baseline-v0.1.md`).

Keep both halves on one line — the pairing is matched per line, so a wrap between the
name and its pointer reads as an ordinary dangling citation. And a doc
in a sibling checkout must carry the repo **in the path** — `SwiftProjectLint/docs/rules/…`,
not a bare `docs/…` with the repo named in the surrounding sentence, which reads as
though it points here.

History is deliberately out of scope: `docs/archive/`, `CHANGELOG.md` and the root
`README.md` record what was true when written, so a citation to a since-pruned doc is
*correct* there and repointing it would be the actual mistake.

**A deferral should name what would refute it.** Writing *"X is deferred"* states
something unfalsifiable: nothing can ever report that it stopped being true. Writing

> Deferred kit-side: `CommutativeGroup` (falsifier: `SwiftPropertyLaws/checkCommutativeGroupPropertyLaws`)

says *if that symbol appears, this sentence is wrong* — and `DeferralFalsifierTests`
checks it, failing the day the kit ships one. The symbol is a name in this repo's
`Sources/`, or `Repo/Name` for a sibling checkout, the same repo-in-the-path
spelling the citation guards use.

This exists because prose could not be guarded. `docs/measurements/stale-summary-guard-declined.md`
records four text detectors for stale summaries, all refuted, and the reason is
structural: **we correct by annotation, not by rewriting**, so a fixed doc still
contains the wrong sentence and a text detector fires on it forever. A falsifier is
checkable against the tree instead of against another sentence. Deleting one to
silence the guard is possible, but it shows up in the diff — which is the most a
guard can ask.

Note the limit of that guard: it only sees **this** repo. Sibling repos in the
toolchain cite these paths too, and nothing checks those.
