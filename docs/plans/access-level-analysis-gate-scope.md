# Scope: stop gating *analysis* on access level — score it instead

**Status: measurement done (§4a). The `comparator` blocker is CLEARED (`c9324d8`, §4b).
The scoring change is still not started, and one prerequisite remains: `round-trip` is
unmeasured (§4c).** §5 is kept as the method, but its "run this first" has been run —
read §4a–§4c before planning anything.

## 1. The position this replaces, and why it is provisional

`c14c748` ("Access level gates verification, not analysis") drew the right
distinction and applied it in two places — `SeedKind.isAnalysable` and
`scannedFiles` — then left the same conflation standing one level up:

> An unseeded private function still stays hidden — that is a default about
> unsolicited noise, not a judgement about testworthiness, and a seed overrides it.

That sentence *is* access level gating analysis. It is conditioned on a seed rather
than absolute, which softens it without changing its kind. The rescue built on
2026-07-29 (a seed now reaches the **templates**, not just the `determinism`
fallback) made the remainder more visible rather than less: everything a seeded
private function now earns, an unseeded one still cannot.

Three arguments were offered for keeping the gate. Recorded here with what is wrong
with each, so they are not re-offered:

| argument | why it fails |
|---|---|
| "It is the recorded decision." | Deference, not justification. A commit is not a proof. |
| "The seed is evidence of purity, which the law needs." | True for `determinism` — purity cannot be read off a signature, so the seed *is* the justification. **False for template laws**, which are inferred from shape and name and already fire on `internal` / `public` functions with no purity vouch at all. The seed's weight was borrowed from the fallback law and silently extended to laws that never depended on it. |
| "A private law cannot be run, so do not volunteer it." | The only real consideration — but a **gate is the wrong instrument**. The catalog's own rule: *"too many suggestions → raise thresholds, don't pile on filters."* Volume is the tier system's job. |

## 2. The design

Analyse access-restricted functions **always**. Express "this cannot be run until
the access widens" as a **score penalty** plus the caveat that already exists
(`withAccessRestrictionCaveats`), tuned so an access-restricted candidate lands in
`.possible`.

The visibility outcome is then *identical to today* — hidden by default, shown with
`--include-possible` — reached with the instrument the project already uses, and
with three things the gate currently throws away:

1. **The law stays in the record.** `metrics` can answer "how many laws is access
   level hiding?" That question is unanswerable today, which is precisely why the
   noise claim in §1 has never been tested.
2. **Role-entailed laws can still be promoted** past the cut by
   `promoteTierHiddenLaws` — the existing machinery for "looks weak, is genuinely
   owed". A `private` predicate owes totality no less than a public one.
3. **No seed required.** The tool stops depending on a sibling linter to see logic
   sitting in front of it.

## 3. Blast radius — wider than the seeded rescue, and this is the risk

Removing the gate puts restricted functions into `summaries`, which feeds more than
suggestions:

- `EffectAnnotationAdvice` — would start advising `@lint.effect pure` on private
  functions. May be desirable; is a behaviour change nobody asked for. Decide
  explicitly.
- `insights`, `index` / `SemanticIndex` — both grow. `index` growth is the one to
  watch: `verify --all-from-index` builds **one full SwiftPM workdir per entry**
  (a survey of this repo's own 85-entry index left 3.4 GB in
  `.swiftinfer/verify-workdir/`).
- `docc` — safe. Verified-only, and an access-restricted law cannot reach
  `.verified` without the refactor.
- §13 perf budgets — more summaries means more scan work. Run `make perf` in
  isolation after, per its own rule.

The 2026-07-29 rescue deliberately merged rescued summaries into `discover`'s
*input* and **not** into `summaries`, to avoid exactly this. That workaround should
be removed by this change, not preserved alongside it.

## 4. What the current gate is actually worth — measured

**These numbers are a correction.** The first version of this table reported 3% and 5%
for the first two rows and concluded the gate was "load-bearing in one of four
corpora." That was wrong: the count matched `private func` **adjacently**, and this
codebase writes `private static func` 767 times out of 853. Recounted with the
modifiers admitted:

| corpus | private | all funcs | share |
|---|---:|---:|---:|
| SwiftInferProperties/Sources | 853 | 2,459 | **35%** |
| SwiftProjectLintRules | 532 | 1,132 | **47%** |
| swift-syntax/SwiftParser | 92 | 590 | **16%** |
| MacCloud macOS client (app) | 51 | 345 | **15%** |
| swift-foundation/FoundationEssentials | 507 | 4,032 | **13%** |

So the gate is **not** a negligible filter that matters in one place. It suppresses
13–47% of every function population measured. The "unsolicited noise" framing has to
answer for that much of a codebase, and the "we might be hiding real laws" concern is
correspondingly larger than first stated.

It also does not match the story `SeededPrivateFunctionTests` tells ("libraries skew
to trivial glue, apps invert it"): the app is the *second lowest* row. That docstring
has already retracted its own statistical framing — *"privateness is a proxy for the
wrong thing and no threshold fixes that"* — which is the conclusion this scope reaches
from the other direction.

## 4a. The measurement ran — and it moved the plan

Ran §5's method on this repo (853 private functions seeded, `--include-possible`).

**Volume.** 293 suggestions → ~1,167 template suggestions, but default-visible only
**24 → ~66**; the rest land in `.possible`. The 567 `determinism` rows a seeded run
also produces are an artifact of seeding, not of un-gating — that law is
seed-justified and needs a manifest either way. So volume alone does not justify the
gate.

**Precision, on the slice that matters.** All 19 default-visible `comparator` laws the
gate currently hides, classified by reading the code:

| verdict | count | examples |
|---|---:|---|
| genuinely owed | **11** | `lessThan(Suggestion, Suggestion)` (compares location, then template name — a real sort predicate; a non-strict-weak-ordering can trap `sorted(by:)`), `locationLessThan`, `sortCandidates` |
| **false** | **8** | `sameType(_:_:)` is `lhs.trimmed == rhs.trimmed` — symmetric, so a **correct** implementation fails asymmetry. `areComplementary(_:_:)` has a docstring that literally says *"Order-insensitive"*. Also `matches`, `curatedActiveToPastParticiple`, `curatedActiveToPresentParticiple`, `curatedFormPrefixToBare`, `isCanonicalInversePair`, `initializerPairAdmissible` |

58% precision, and the 8 are the worst category the catalog names: *"a tool that
proposes a false law is worse than one that proposes nothing."*

**So the gate has been masking a template precision bug, not preventing noise.**
`comparator`'s docs claim its positional-operand requirement separates a comparator
from a binary predicate — but `sameType(_:_:)`, `matches(_:_:)` and
`areComplementary(_:_:)` are all fully positional *and* symmetric. The heuristic does
not hold on private helpers, because this codebase uses `(_:_:)` for both roles.

*(Read §4b before acting on the paragraph above: "masking" turned out to be half
wrong — three of the false claims were already visible. And the fix that shipped was
not the symmetry counter-signal sketched here but an ordering-**name** requirement,
which separated all 22 candidates cleanly where a symmetry test would have reached
only the four symmetric ones.)*

**Sequencing therefore inverts from §5's assumption: tighten `comparator` first, then
remove the gate.** — done, `c9324d8`. Un-gating before it would have put 8 false
`Likely` claims on the default surface of the repo we dogfood, on top of the 3 already
there.

## 4b. The `comparator` blocker — cleared, and it was not what this scope thought

Shipped as `c9324d8`. A `-25` counter-signal (`unsupportedComparatorShape`) when the
name carries no ordering stem: 40 → 15, below the `.possible` floor of 20, so a
shape-only candidate is suppressed rather than quietly downgraded. Follows the
`unsupportedAlgebraicShape` idiom.

| corpus | comparator before → after | |
|---|---|---|
| this repo, visible surface | 3 → **0** | all three were false |
| this repo, private seeded | 19 → **11** | exactly the 11 §4a classified true |
| swift-syntax/SwiftParser | 1 → **0** | `at(_ spec1:, _ spec2:)` — false |
| FoundationEssentials | unchanged | |
| SwiftProjectLintRules | unchanged | |

**12 false positives removed, 11 true kept, 0 true lost.**

**§4a called this "the gate masking a template precision bug", and that was half
wrong.** Three of the false comparators — `areComplementary`,
`isCanonicalInversePair`, `initializerPairAdmissible` — are `internal` or `public`, so
they had been on the default surface at `Likely` the entire time. The gate was hiding
eight *more* of the same defect, not the defect itself. Comparator's precision on this
repo's **visible** surface was 0 of 3.

The lesson generalises past comparator and is the reason §4c is not optional: **a
template's false-positive rate is not a fact about the access-level gate**, and
measuring the gate is what happened to expose it. Any template whose reach grows when
the gate lifts deserves the same 30-sample read before it grows.

Two things it deliberately did not fix, both pinned by tests rather than left implicit:

- **A suppressed candidate earns NO law, not a weaker one.** `PredicateTemplate`
  excludes anything matching `isComparator`, and that gate reads the *shape*, which
  still matches — the measurement proved it, `predicate` held at 114 and 197 while
  comparator fell by 3 and 8. Whether these should become predicates is real
  (`sameType` does owe totality) but widens the largest template on every corpus at
  once, so it is its own calibration decision.
- **Role-carrying positional operands remain a hole.** The template's docs claim the
  label test catches them, citing `isImmediateChild(_ path:, of parentPath:)` — which
  works only because it has a *label*. `_ x: T, _ y: T` has none, and four of the
  eleven false positives were that shape. The ordering-name rule catches them today by
  luck; `sortsBefore(_ item:, _ pivot:)` would pass both gates and still be no
  ordering. `roleCarryingOperandsAreStillAHole` pins it.

## 4c. `round-trip` — the remaining prerequisite, NOT measured

`round-trip` goes **53 → 438** when private functions are admitted, the largest single
delta of any template and 8×. No sample has been read.

Do not assume it behaves like `comparator` — and after §4b, do not assume it behaves
*well*: the one template that got measured turned out to be 50% false on the same
population, and half its false claims were already shipping. 385 new `round-trip`
suggestions is a bigger surface than all 22 comparator candidates combined.

Method: §5, unchanged — sample ~30 of the delta, classify real-law / glue / wrong, read
the code rather than the name. Most are `.possible`, so the default-surface risk is
smaller than comparator's was; the volume risk is much larger.

## 5. Prerequisite measurement — run this FIRST

The penalty weight is a calibration number and must not be guessed. The question is
not "how many suggestions appear?" but **"how many of them are laws worth stating?"**

Method — now cheap, because the rescue path exists:

1. For a corpus, generate a seed manifest naming **every** `private` /
   `fileprivate` function (`kind: "restricted-function"`).
2. Run `discover --include-possible` with and without it; diff the suggestion sets.
3. Read a sample of the delta — 30 or so, sampled not cherry-picked — and classify
   each: **real law** / **trivial glue** / **wrong**.
4. Run it on at least the 3% corpus and the 45% corpus. If the answer differs
   sharply between them, that is itself the finding, and it means the weight cannot
   be one global constant.

Score refutability, not count: `f(x) == f(x)` on a private helper is not a win.

**Guardrail.** Do not run this alongside `make test` or the §13 perf suites — a
corpus scan sharing the box is how the load flakes in `MemoryCeilingPerformanceTests`
happen.

## 6. How to know it worked

- Every suggestion an unseeded `private` function earns is either `.possible` or
  promoted for a documented role-entailment reason — never `.likely` on shape alone.
- `SeededPrivateFunctionTests` still passes with the *seed-specific* assertions
  removed: the point of this change is that the seed stops being what unlocks
  analysis. Its remaining job is vouching for purity on the `determinism` fallback.
- `metrics` can report the count of access-restricted candidates. It cannot today.
- `.swiftinfer/verify-workdir/` growth after `index` is measured and stated, not
  discovered later.
- **Every template whose reach grows has had a 30-sample read first.** Added after
  §4b: the one template that got measured was 50% false on this population, and half
  its false claims were already shipping. "Its reach grows and we did not look" is not
  a state this change may ship in.

## 7. Ledger

| item | status |
|---|---|
| §5 measurement on this repo | **done** (§4a) — 853 private functions seeded |
| private-share recount across 5 corpora | **done** (§4) — corrected from 3%/5% to 35%/16% |
| `comparator` precision fix | **done**, `c9324d8` (§4b) — 12 false removed, 0 true lost |
| `round-trip` 53 → 438 sample read | **NOT DONE** (§4c) — the remaining prerequisite |
| the scoring change itself (§2) | not started |
| remove the rescue's `discover`-input workaround (§3) | not started, do it *with* §2 |
| `predicate` admitting comparator-shaped binaries | open question, own calibration (§4b) |
| operand-interchangeability test on internal names | open hole, pinned by test (§4b) |

