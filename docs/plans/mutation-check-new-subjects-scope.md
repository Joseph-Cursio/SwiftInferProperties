# Does a passing law notice a planted bug — on subjects the catalogue never met?

> **Status:** `proposed` · **As of:** 2026-09-26

The first mutation check (`docs/measurements/funnel-mutation-check.md`) ran on the funnel's own 19
repositories — the corpus every template and generator was tuned against — and left one stratum
untested: **relational laws** (`commutativity`, `associativity`) had one passing law outside teaching code
and no applicable mutant. Its re-score (§9) and the two body-derived templates built since
(`ternary-guard-domain.md`, `rewrite-postcondition.md`) were all measured on that same corpus. This runs
the same method on four subjects outside it, frozen before any law runs.

## 1. Subjects — outside the funnel corpus, chosen for what the first check could not answer

| subject | commit | why |
|---|---|---|
| `Euclid` | `a597cf5` | a geometry library that ran associativity 7 and commutativity 7 in `subject-euclid.md`: the relational coverage the first check lacked |
| `BigInt` | `63feef7` | arbitrary-precision arithmetic — the natural home of commutativity, associativity, monotonicity |
| `swift-algorithms` | `5b7143f` | collection algorithms — idempotence-shaped and order laws over generic code |
| `swift-http-types` | `bff4b69` | small value types that parse and normalise — a different code style from the rest |

All four are clean checkouts under `~/GitHub_projects`, none in `fixtures/corpora/manifest.json` or the
funnel's repository list. `Euclid` was measured once before, at `0b00927`, by `verify` rather than by
mutation; its commit here is later.

## 2. Method — the first check's, unchanged except where stated

1. **Census** each subject with `scripts/corpus_funnel.py` on the released binary (1.154.0 plus the
   underscore fix) — the stubs `discover --interactive` writes, compiled and run.
2. **Sample** compiled, passing laws with `scripts/mutation_check.py sample`, seeded, stratified, no
   subject above a third of any stratum — **frozen to `fixtures/mutation-check/sample-new-subjects.json`
   and committed before any mutant runs**.
3. **Run** each law's baseline, then its mutants (M1–M6, up to three per law), scoring KILLED / DIVERGED /
   UNEXERCISED with the same-seed probe; 100 and 1,000 trials. Record every row to
   `fixtures/mutation-check/run-new-subjects.jsonl`.

**Strata, changed from the first check** so the untested stratum is actually sampled and the two new
body-derived laws are represented (a stratum short of its quota is reported, not back-filled):

| stratum | templates | quota |
|---|---|---:|
| totality | `predicate`, `input-totality` | 12 |
| idempotence | `idempotence` | 10 |
| **relational** | `commutativity`, `associativity` | **15** |
| characterisation | `guard-domain`, `rewrite-postcondition` | 8 |
| round-trip | `round-trip`, `codable-round-trip` | 6 |
| other | `monotonicity`, `involution`, `equivalence-relation`, `caseiterable-key-injectivity`, `filter-subset`, `measure-non-negativity` | 9 |

## 3. Predictions — written before the census

Kill rate is over mutants that change output (KILLED + DIVERGED), never over all mutants.

| stratum | predicted kill rate | why |
|---|---|---|
| totality | **≤ 10%** | it can only fail by trapping — held at 1 of 18 on the funnel |
| idempotence | **20–50%** | 3 of 9 on the funnel |
| **relational** | **≥ 50%** | both arguments are compared, so most output changes break symmetry or grouping — the first check's untested prediction, stated again |
| characterisation | **high on mutants inside the guard or rewrite, ~0 elsewhere** | the law speaks only for its guarded branch or its removed tokens |
| round-trip | **≥ 50%** | a changed encoder or decoder breaks the pair |

**And three about the whole run:**

- **UNEXERCISED share 30–50% of mutants** — lower than the funnel's 50%, because arithmetic and
  collection subjects take numeric and collection inputs a generator reaches more easily than
  domain-specific strings.
- **1,000 trials add at most one kill** — the first check measured zero.
- **At least one stratum falls short of quota** — four subjects, and relational laws may not compile on
  all of them.

## 4. What this does not answer

It does not estimate a real-bug rate: a planted mutant has no base rate
(`fixtures/planted-defect-arm/README.md`). It does not hand-check whether the passing laws are true; a
false law that passes is a separate question (`funnel-mutation-check.md` §8). And four subjects are four
subjects — a stratum's rate here is a reading on these codebases, not a catalogue-wide figure.
