# Calibration cycle 116 — widen the verify-ready idempotence corpus

> **STATUS: SHIPPED (v1.123.0).** Widens the cycle-115 corpus from 3 to 5
> reducers across **three carrier shapes** — generic struct method, TCA-
> convention witnesses (`task` / `delegate` / `binding`), and an Elm-style
> **free function** — and confirms the measured baseline holds at scale:
> **12 identities → 11 `measured-bothPass` + 1 `measured-defaultFails`**.
> Surfaced (and worked around) a real pin-resolution gap for free-function
> reducers. Captured 2026-06-14.

## What shipped

Two reducers added to `Tests/Fixtures/idempotence-survey-corpus/`:

- **`TCAFeatureReducer`** — the three canonical TCA Action-name witnesses
  (`task`, `delegate`, `binding`, the cycle-93 V1.96 additions), modeled
  payload-free so `Action` is `CaseIterable`. All three idempotent
  (subscribe-stays-loading / parent-observed no-op / fixed-value setter).
- **`reduceElmCounter`** — an Elm-style **free-function** reducer
  (`.elmStyle` carrier), widening the corpus past the cycle-115 all-
  `.generic`-struct-method shape. Witness `refresh`.

The widened corpus is 5 reducers / 12 idempotence identities spanning all
three carrier shapes. The measured baseline holds: 11 `measured-bothPass`
(every genuine witness, across all carriers) + 1 `measured-defaultFails`
(the cycle-115 `setBadge` false positive).

## Finding — free-function reducers can't be uniquely pin-resolved

The Elm reducer was first written as `func reduce(_:_:)` (the Hand06
idiom). The survey failed:

```
verify-interaction: pin 'reduce' is ambiguous — matches 5 reducers:
reduce, NavigationReducer.reduce, SelectionReducer.reduce, … —
Lengthen the pin to disambiguate.
```

Root cause: the survey pins each identity by `reducerQualifiedName`, and a
free function's qualified name is just its bare function name (no type
prefix). `ReducerPin.parse("reduce")` yields `(typeName: nil, "reduce")`,
and `ReducerPin.matches` treats a nil type as "any enclosing type" — so it
matches every `reduce`, free or method. A free `reduce` is therefore the
one reducer shape that **cannot be uniquely pinned** when same-named
methods exist.

**This cycle's workaround:** name the free function uniquely
(`reduceElmCounter`) so the corpus is surveyable. The carrier coverage goal
is unaffected — `.elmStyle` is about free-function-vs-method, not the name —
and the Elm verify path is confirmed working (its `refresh` measures
`bothPass`).

**Follow-up (a real mechanism gap):** pin resolution can't disambiguate a
free function from a same-named type method. Candidate fix — let
`ReducerPin` express "free function only" (match `enclosingTypeName == nil`
when the pin has no type prefix), or have the survey bypass string-pin
re-resolution entirely by threading the already-resolved candidate through
`runWithInvariant`. The latter is cleaner (the survey already holds the
resolved identity) and would also shave a re-discovery per identity.

## Verification

- **Fast (`IdempotenceSurveyCorpusTests`):** discovery surfaces *exactly*
  the 12 intended identities across the three carrier shapes (equality
  assertion — locks the widened corpus shape, confirms the new TCA + Elm
  witnesses are found and the drivers produce none).
- **Measured (`IdempotenceSurveyCorpusMeasuredTests`, `.subprocess`,
  ~106s):** the survey records 11 `bothPass` + 1 `defaultFails` across all
  five reducers; 12 evidence records persisted; `discover-interaction`
  promotes the 11 survivors to `.verified` and suppresses `setBadge`.
  Confirms TCA-convention and Elm free-function carriers verify end-to-end.
- **Suites:** full fast suite green (3191 tests; only the known §13 perf-
  budget timing flakes under load). SwiftLint clean.

## What's next — the three-cycle promotion run (and the pin follow-up)

The corpus now spans the carrier shapes that matter and the baseline holds.
Remaining toward A1 sign-off:

1. **The three-cycle `.likely → .strong/.verified` run** — with measured
   evidence driving the tier, run discover over the corpus across the
   documented three calibration cycles and confirm the promotion holds.
2. **Free-function pin disambiguation** (this cycle's finding) — so a
   real-world `func reduce`/`func update` free reducer is surveyable
   without renaming.

Further widening toward the literal ~39 real identities still needs a
value-generator path for associated-value Action cases (`setColor(String)`
et al.) — out of scope until that lands; such identities survey as
`architectural-coverage-pending`, surfaced not dropped. Per-invariant
workdir isolation (parallel survey) and a `CorpusPackager` `dependencies:`
thread (TCA corpora) remain optional accelerators. Default (no-evidence)
idempotence stays `.likely`.
