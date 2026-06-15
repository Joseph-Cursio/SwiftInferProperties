# Calibration cycle 117 — free-function reducer pin disambiguation

> **STATUS: SHIPPED (v1.124.0).** Fixes the cycle-116 finding: a free-
> function reducer named `reduce` couldn't be uniquely pin-resolved
> alongside same-named type methods, so the `--all` survey couldn't verify
> it. Pin resolution now prefers an exact qualified-name match, which
> disambiguates the free function while preserving the bare-name
> convenience and the correct ambiguous-pin error for methods. The
> cycle-116 workaround (renaming the Elm reducer) is reverted — the corpus
> now carries a realistic free `func reduce` as the regression guard.
> Captured 2026-06-14.

## The bug (cycle-116 finding, recap)

`VerifyInteractionPipeline.resolveCandidate` resolved a `--reducer` pin via
`ReducerPin`'s lenient match: a bare pin (no type prefix) matches any
candidate whose `functionName` equals it, regardless of enclosing type. A
free-function reducer's `qualifiedName` *is* its bare function name
(`reduce`), so pinning it required the bare pin `reduce` — which also
matched every method named `reduce`. In the widened corpus (5 reducers, all
with a `reduce` method) the survey failed:

```
verify-interaction: pin 'reduce' is ambiguous — matches 5 reducers …
```

The free function was the one reducer shape that could not be uniquely
pinned.

## The fix

`resolveCandidate` now **prefers an exact `qualifiedName` match** before the
lenient pin match:

```swift
let exact = candidates.filter { $0.qualifiedName == pinRaw }
if exact.count == 1 { return exact[0] }
// else: ReducerPin.parse + lenient (functionName, optional typeName) match
```

Why this is the right shape, and why it's backward-compatible:

- **Free function disambiguated.** A free `reduce` has `qualifiedName ==
  "reduce"`; a method has `"Foo.reduce"`. So the bare pin `reduce`
  exact-matches *only* the free function. Fixed.
- **Bare-name convenience preserved.** `--reducer body` against `Inbox.body`:
  no candidate's qualifiedName equals `"body"`, so exact-match misses and
  the lenient `functionName` match resolves it — unchanged.
- **Method ambiguity preserved.** `reduce` against `InboxA.reduce` +
  `InboxB.reduce`: neither qualifiedName equals `"reduce"`, so exact-match
  misses (count 0) and the lenient match still yields two hits → the correct
  `ambiguousPin` error. Same for the genuinely-ambiguous two-free-functions
  case (`exact.count == 2` → not 1 → falls through).
- **Fully-qualified pins** resolve directly via the exact path (same result,
  one fewer parse).

The change is additive: it only resolves cases that previously errored;
every prior resolution is unchanged. All four existing `resolveCandidate`
pin tests pass untouched.

## Corpus: workaround reverted

The cycle-116 Elm fixture was renamed `reduceElmCounter` to dodge the
ambiguity. With the fix it's back to the idiomatic `func reduce(_:_:)`
(Hand06 / Elm convention) — and now serves as the **end-to-end regression
guard**: the widened measured survey runs a real free `reduce` alongside
four `Foo.reduce` methods and resolves + verifies it.

## Verification

- **Fast (`VerifyInteractionPipelineTests`, +3):** a free `reduce` pin
  resolves to the free function (not the same-named methods); a
  fully-qualified `Foo.reduce` pin resolves alongside a free `reduce`;
  bare-name `body` still resolves `Inbox.body` via the lenient fallback.
  The pre-existing ambiguous-methods and no-match tests pass unchanged.
- **Discovery (`IdempotenceSurveyCorpusTests`):** the Elm identity is back
  to `reduce .refresh`.
- **Measured (`IdempotenceSurveyCorpusMeasuredTests`, `.subprocess`,
  ~115s):** the full widened survey (now with a free `reduce`) records
  11 `bothPass` + 1 `defaultFails` and promotes the survivors — proving the
  pin fix through the real `--all` survey path.
- **Suites:** full fast suite green (3194 tests; only the known §13 perf-
  budget timing flakes under load). SwiftLint clean.

## What's next — the three-cycle promotion run

Both cycle-116 follow-ups are now closed (corpus widened, pin fixed). The
remaining A1 work is the **three-cycle `.likely → .strong/.verified`
promotion run**: with measured evidence driving the tier, run discover over
the corpus across the documented three calibration cycles and confirm the
promotion holds — the empirical sign-off A1 was built to produce. Further
widening toward the literal ~39 still needs a value-generator path for
associated-value Action cases; per-invariant workdir isolation (parallel
survey) and a `CorpusPackager` `dependencies:` thread remain optional
accelerators. Default (no-evidence) idempotence stays `.likely`.
