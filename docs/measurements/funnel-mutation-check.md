# What is a passing law worth? — the funnel's laws against planted bugs

> **Status:** `measured` · **As of:** 2026-09-22

Run to the scope in `docs/plans/funnel-mutation-check-scope.md`, with the harness
`scripts/mutation_check.py` and the sample `fixtures/mutation-check/sample.json`, frozen and committed
before any mutant ran. **Planted bugs measure sensitivity, not a bug rate** — nothing here says how
many real defects the funnel's laws would find.

## The answer

**49 passing laws, 72 mutants, 68 compiled. Of the 68, 34 changed the subject's output on the laws'
own drawn inputs, and 34 did not change it on a single one.** Of the 34 that changed it, the laws
caught **9**.

| template | killed | output changed, law passed | output never changed | kill rate, of changed | predicted |
|---|---:|---:|---:|---:|---|
| `predicate` (totality) | 1 | 15 | 7 | **6% of 16** | ≤ 10% ✅ |
| `input-totality` | 0 | 2 | 11 | **0% of 2** | ≤ 10% ✅ |
| `idempotence` | 3 | 6 | 8 | **33% of 9** | 20–50% ✅ |
| `guard-domain` | 4 | 0 | 8 | 4 of 4 | high on guard mutants ✅ |
| `round-trip` | 1 | 1 | 0 | 1 of 2 | — |
| `caseiterable-key-injectivity` | 0 | 1 | 0 | 0 of 1 | — |
| `commutativity` / `associativity` | — | — | — | **untested** | ≥ 50% ❓ |

**Every prediction that could be tested held.** The one that could not is the one that mattered most
for the relational templates: the stratum's single law had no applicable mutant (§4).

## 1. A totality law cannot see a wrong answer

**Inverting a predicate's result — `return x` → `return !(x)` — changed the output 12 times and was
caught 0 times.** Every one was under a `predicate` or `input-totality` law, which asserts only that the
call returns. The single totality kill was an integer off-by-one that **trapped**, which is the only
way such a law can fail.

This was the prediction, and it is not a defect in the laws — a totality law claims *does not crash*,
and that is all it checks. The finding is about the **headline**: totality is **75% of the funnel's
passing laws** (391 `predicate` + 63 `input-totality` of ~604 compiled), so **"577 laws pass" is
three-quarters "577 functions do not crash on generated input"**. Every widening and generator fix this
cycle raised that number, and a function returning the opposite answer would not have lowered it.

## 2. Half the planted bugs were never reached

**34 of 68 mutants left the subject's output unchanged on every drawn input** — the same count as those
that changed it. By operator, the unreached share tracks how *specific* the planted change is:

| operator | changed output | never changed |
|---|---:|---:|
| M3 invert a Bool result | 12 | 4 |
| M6 empty a string literal | 11 | 11 |
| M2 negate a condition | 6 | 4 |
| M4 integer off-by-one | 2 | 8 |
| M1 relational boundary | 2 | 5 |
| M5 drop a chained call | 1 | 2 |

**Boundary and off-by-one changes are the ones generators miss** — M4 8 of 10, M1 5 of 7 unreached.
Those are exactly the edge values a realistic generator does not aim at, which is CLAUDE.md's standing
caveat (*a pass means no counterexample in the generated domain*) measured on this corpus rather than
asserted. ⚠ **`guard-domain`'s 8 survivors are all unreached**, and that one is structural: its law
checks only inputs inside the guarded sub-domain, so a mutant outside the guard is out of its reach by
design.

## 3. A bigger budget bought nothing

**Every law also ran at 1,000 trials. Zero additional kills.** Nothing here was budget-limited: a
mutant the drawn domain does not reach at 100 trials is not reached at 1,000 either, because the
generator decides *which* inputs are drawn, not how many. Contrast `criterion-a-quality-swift-system.md`,
where a real defect died at 500 — that was a rare input the generator *could* produce.

## 4. What the sample could not test

- **The relational templates are almost absent outside teaching code.** Excluding pbt-book and the
  workbooks, the corpus has **1 passing `commutativity`/`associativity` law and 3 `round-trip`s**, so
  the sample is 49 laws against the scope's 60. The associativity law's subject had no applicable
  mutant. **Whether relational laws notice behaviour changes is unanswered here**, and the reason is
  population, not the harness.
- **7 of 49 laws had no applicable mutant** — bodies with no condition, literal or chain to change.
- **The numbers are small**: 34 exercised mutants in all, single digits outside totality. The
  totality result (1 of 18) is the only one with enough behind it to act on.

## 5. Instrument defects found on the way

Three, each caught before it could reach a number:

1. **Hash order.** A `Dictionary`-valued subject probed differently between two runs of the
   *unmutated* code, so every such law would have read as diverged. Test runs set
   `SWIFT_DETERMINISTIC_HASHING=1`; all 49 baselines then probed identically twice.
2. **Free functions.** Stubs for free functions have no type prefix, and the harness dropped their only
   name, crashing the first run after 24 laws. The sample's membership was unchanged; the fix and the
   amendment are recorded in `sample.json`.
3. **Probe reach.** The first probe read one line of the property closure and one level of parentheses,
   leaving 9 laws unprobed — every `guard-domain` law among them. Re-measured after the fix, **all 12 of
   their survivors are unreached**, so the first table's *unscorable* column was hiding generator
   blindness, not law blindness.

## 6. What it decides

Per the scope's §8:

- ✅ **Totality kills ≈ 0 of what it exercises**, so the funnel's *passes* should report totality laws
  on their own line — *does not crash* — rather than as yield. ✅ **Done 2026-09-22**: the census harness
  now reports `passed_behaviour` and `passed_does_not_crash` beside `passed`, and a test-only re-run of
  every repository's latest census tree splits today's figure — **577 = 126 behaviour + 451 does not
  crash (78%)**, every repository reproducing its census count to the digit. SwiftProjectLint, 51% of
  the passes, is **276 of 294 (94%) does not crash**. ⚠ *Behaviour* is the complement, not a
  guarantee: it still holds `idempotence` conjectures and `guard-domain` characterisations, which
  §1's table shows notice some changes and miss others.
- ✅ **Unreached mutants equal exercised ones**, so generator reach is as large a lever as the laws
  themselves — and it is boundary values specifically that go unreached.
- ❓ **Where to put writer effort** stays open: the templates that notice changes (`idempotence`,
  `round-trip`, `guard-domain`) have single-digit samples, and the relational ones have none.

## The record

**`fixtures/mutation-check/run-2026-09-22.jsonl` keeps every mutant permanently** — 121 rows, one per
law baseline (49) and per mutant (72), across 10 repositories:

- the subject repository and **its commit**, with repo-relative paths, so a row names code that can be
  checked out rather than a scratch tree that no longer exists;
- the mutant **as a unified diff**, regenerated from the restored source by the functions that
  planted it and checked against every recorded mutant (72 of 72);
- the law's result at 100 and 1,000 trials, the outcome, and the probe as a digest — the raw dumps run
  to megabytes and only their equality is ever read.

**What it is for: re-running the same mutants after a change and comparing row by row.** A generator
fix that reaches boundary values should turn *never changed* rows into *changed* or *killed* ones, and
this is the baseline that says which. Without it, every re-run draws a fresh sample and a gain cannot
be told from sampling noise — the reason `fixtures/verify-runs/` exists for survey runs.

⚠ **It is not a list of bugs.** Every row is a planted change to correct code. Read an outcome as
*what the law noticed*, never as *what the code got wrong*.

⚠ **Not a test.** Nothing in `make test` runs it: re-applying a patch needs the subject at the
recorded commit and a census tree to build it in, so it is re-run on demand, when a change is meant to
move it. ⚠ `sample.json` still names scratch paths — it is the frozen pre-registration and is left as
committed; the record is what carries portable identities.

## Reproducing

```
python3 scripts/mutation_check.py sample fixtures/mutation-check/sample.json <census-dirs…>
python3 scripts/mutation_check.py run    fixtures/mutation-check/sample.json <out.jsonl>
python3 scripts/mutation_check.py report fixtures/mutation-check/sample.json <out.jsonl>
python3 scripts/mutation_check.py record fixtures/mutation-check/sample.json <out.jsonl> <record.jsonl>
```

⚠ The sample names paths inside the census's scratch worktrees, so a fresh run needs census trees at
the recorded commits.
