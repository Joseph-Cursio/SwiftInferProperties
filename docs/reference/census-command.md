# Catalog census (`swift-infer census`, V1.149)

> **Status:** `reference` · **As of:** 2026-08-15


Counts rows per template across several registered corpora and writes a run that records
**which corpora** — by registry id, with the revision each checkout actually stood on and the
flags the pipeline used.

```
swift-infer census --corpus swiftlang-swift --corpus swift-collections … \
    --label "catalog health census" --out fixtures/census-runs/2026-08-15.json
```

## Why it exists

A census concludes things of the form *"6 of 39 templates never fire"*. That is a claim about a
**corpus list**, and the list used to live in prose written afterwards. Twice the prose turned
out not to match the run, and neither failure was visible from the numbers:

- **`involution` was filed as never-firing** while a witness sat in a ninth corpus this project
  had already measured — recorded in another doc a fortnight *before* the census. The count was
  right. The denominator was not the world.
- **Four registry entries claimed membership** in the eight-corpus sweep and only one was in it,
  while an actual member had no entry at all. Two prose records of the same denominator
  disagreed about half its contents, and settling it took reading an A/B table row by row.

Both are the same shape: a correct count under a misremembered list. So the list is now the
first thing the artifact records, and the report prints it before the counts.

## What it does not do

**It does not say which templates never fired.** A zero is *absence*, and absence is not in the
counts — naming it needs a catalog of every template that could have fired, and no trustworthy
runtime source for one exists. `TemplateName` is 18 cases against ~92 template files;
`TemplatePack.allTemplateNames` is 10; both reject tags that are correct. Printing a zero list
against either would manufacture exactly the over-confidence the command exists to prevent.

`CensusRun.zeroRowTemplates(against:)` takes the catalog as an argument, so the reader supplies
what they mean and the zero stays attached to the list that produced it. The rendered report
says so on every run, with the corpus count in the sentence:

> A template absent from that list fired ZERO times ACROSS THESE 8 CORPORA — which is not the
> same as never firing.

## Three refusals, and each is a confident zero it declines to report

| refusal | why |
|---|---|
| no `--corpus` | a census over zero corpora prints a table of zeros, indistinguishable from a catalog in which nothing fires |
| scan path is not a directory | same shape, one corpus at a time — and it is how the first run failed, see below |
| corpus names neither `sources` nor `target` | nothing to scan, and guessing a path would invent the previous row |

## `sources` is a LIST, and summing is not the same as widening

A subject's code is not always in one place. `SwiftProjectLint` keeps **425 of its 874**
non-vendored files under `Packages/` and 48 under `Sources/`, so the registered
`Sources/Core` reached 11 files and reported **1 row**. It now scans `["Sources", "Packages"]`
and reports **399**.

**Each path is scanned separately and the counts summed — deliberately not the same as scanning
their union.** Cross-function pairing spans whatever is in scope at once, so a wider scan does
not merely add rows from more files, it *creates pairs a narrower scan cannot see*:

| scan of SwiftProjectLint | rows |
|---|---:|
| `Sources/Core` (the old entry) | 1 |
| `Sources` | 9 |
| `Packages` | 390 |
| `["Sources", "Packages"]` — summed | **399** |
| the enclosing repo root | **776** |

The root's extra 377 is **365 `inverse-pair` rows that appear in no sub-scan**, all `Advisory`,
pairing across the test/product boundary. That is a Daikon-shaped flood rather than signal, so
the root is not the right answer either.

Summing is the conservative reading: it counts what each path supports on its own and never
invents a pair across a boundary the author did not ask to cross. **`CensusRun.Member.scanPaths`
records the choice**, because two censuses of the same corpus at the same revision can differ
twofold on the scan path alone — and without the field that reads as a change in the catalog.

## A census scans a DIRECTORY; `prove-then-show` builds a TARGET

This is why `census` resolves its own scan path instead of reusing `CorpusRunPlan`, and the
difference is not cosmetic. `CorpusRunPlan` resolves `Sources/<target>` unconditionally, which
is right for a survey that must compile the subject. A census only reads source, so it can reach
code no SwiftPM target names — and the original sweep did exactly that, running
`discover --sources <path>`.

**`swiftlang-swift` is the witness.** The compiler repo has no `Sources/` directory at all; its
stdlib sits at `stdlib/public/core`, three levels down, under no target. Routing the census
through the target resolver pointed it at `Sources/stdlib`, which does not exist — and the
failure surfaced as *"The file couldn't be opened because it isn't in the correct format."* A
decode error, from a path that was not there.

So the entry now carries `sources: "stdlib/public/core"` and `target: null`, which is also more
truthful than what it said before: there is no SwiftPM target named `stdlib`, and
`prove-then-show` correctly refuses the corpus rather than pretending it could build it.

## What lands in the artifact

| field | why it is recorded |
|---|---|
| `corpora[].id` | the denominator, resolvable through the manifest to a remote — **not a path**, because every earlier retained run recorded a scratchpad that no longer exists |
| `corpora[].revision` | read from the checkout **at run time**, not copied from the manifest: a manifest revision records what some *earlier* measurement used |
| `corpora[].dirty` | the rows count uncommitted work and the revision does not fully name what was surveyed |
| `corpora[].pin` | a stable token (`at-pin`, `moved-off-dirty`, …), never the rendered sentence — those get reworded, and two censuses a month apart must stay comparable |
| `flags` | a remembered count carries no record of them; this project has published a "drift" finding that was entirely `--include-possible`, 96 against 80 on one binary, one afternoon, one corpus |

Dirty and off-pin are **warned on stderr as well as stored** — a caveat only in the artifact is
one the person watching the run does not see.

## Related

- `fixtures/corpora/README.md` — the registry, and what a revision means
- `fixtures/verify-runs/README.md` — the same durability problem for `prove-then-show`
- `docs/measurements/swiftorg-property-test-study-findings.md` §10 — the census this replaces the loop for
