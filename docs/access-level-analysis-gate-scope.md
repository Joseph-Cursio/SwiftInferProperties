# Scope: stop gating *analysis* on access level — score it instead

**Status: measurement done (§4a), scoring change not started, and it is now BLOCKED on
a `comparator` precision fix.** Un-gating before that lands puts 8 known-false `Likely`
claims on this repo's own default surface. §5 is kept as the method, but its "run this
first" has been run — read §4a before planning anything.

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

**Sequencing therefore inverts from §5's assumption: tighten `comparator` first, then
remove the gate.** Un-gating today would put 8 false `Likely` claims on the default
surface of the repo we dogfood. The fix has a ready shape — a **symmetry
counter-signal**: `areComplementary` announces itself in prose and
`DocstringPropertyCorroborator` already exists, while `sameType` announces itself
structurally as a single `==` return. Either kills most of the 8.

**Not examined.** `round-trip` goes 53 → 438, the largest single delta, and no sample
was read. Do not assume it behaves like `comparator`; measure it before un-gating.

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
