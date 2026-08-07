# Edge pass on composed carriers — the A/B streams (2026-08-07)

The raw `verify --all-from-index` records behind the table in
`docs/design/verify-edge-pass.md` → *Composed carriers — the sentinel's remaining 27%*.

**Committed because the arms are not re-derivable from the repo alone.** Both were run
against `/.swiftinfer/index.json`, which is gitignored (see `.gitignore:104`), so the
entry set the two binaries saw exists nowhere in version control. Without these files
the doc's `−35 / +35` is a remembered count, which this project's standing rule says
carries no record of the flags it was taken with.

## Files

| file | what |
|---|---|
| `2026-08-07-before.jsonl` | 56 records, binary at `0a4f034` |
| `2026-08-07-after.jsonl` | 56 records, same 56 entries, binary with the sweep |

Bucket either stream with `analyse.py` from `fixtures/whole-corpus-survey/`, or diff the
two by `identityHash` — that is what produced the table.

## Provenance — everything needed to re-run

| | |
|---|---|
| subject | `SwiftInferProperties@0a4f034` + the `boundarySweep` change |
| where the change landed | on `39db5ac`, which `main` advanced to after the arms were taken — the intervening commits are the idempotency track (`FunctionScanner`, `ReplayIdempotenceTemplate`) and touch nothing this A/B measures |
| BEFORE binary | `0a4f034`, `swift build -c release` |
| AFTER binary | same tree + the change, `swift build -c release` |
| command | `swift-infer verify --all-from-index --index-path <filtered> --max-parallel 4` |
| BEFORE arm | 2026-08-07 21:03–21:07 UTC · 56 entries · ~3 min |
| AFTER arm | 2026-08-07 21:14–21:17 UTC · 56 entries · ~2 min |

**The index was filtered, not whole-corpus.** It is `/.swiftinfer/index.json` (282 entries,
the same index behind `fixtures/whole-corpus-survey/`) cut to 56: the 37 entries the frozen
2026-08-05 stream reported as `measured-bothPass` with `edgeTrials=0`, plus a 19-entry
control of rows that already ran an edge pass or that refuted. Filtering by
`identityHash` reproduces it.

## Two things to know before citing these numbers

1. **A filtered A/B cannot show a regression outside its filter.** The control arm is what
   stands in for that, and it is 19 entries, not a corpus. The structural argument is that
   the change is gated on a raw-type generator literal appearing in the composed
   expression, and a carrier that already had a carrier-level boundary set takes the
   earlier branch untouched — but that is an argument, not a measurement.
2. **The gain is `unchecked → checked`, not `bug found`.** 35 entries moved from a
   zero-trial sentinel to a real 100-trial boundary pass; **no entry became
   `measured-edgeCaseAdvisory`**, and no verdict changed. The `mergedBound`-class
   refutation the pass exists to catch has not yet fired on a composed carrier.
