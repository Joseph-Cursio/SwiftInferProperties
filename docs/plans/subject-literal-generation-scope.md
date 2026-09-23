# Drawing a subject's own literals — scope, gated on one measurement

> **Status:** `shipped` · **As of:** 2026-09-23

`funnel-mutation-check.md` §8 mixed each subject's own string literals into its law's string generator
and refuted **7 of 52** passing behaviour laws — all false laws, no defects — which made literal
drawing the one generator change measured to make the funnel more honest rather than larger. This
scopes building it, and finds that the case has changed since.

## 1. Where string generators come from today

The kit already has **two tuned `String` generators**, each chosen for a LAW, and swift-infer picks one
from the type name alone:

| expression (`PropertyLawCore.RawType`) | tuned for | tokens |
|---|---|---|
| `edgeBiasedGeneratorExpression` | idempotence / structural laws | YAML and Markdown markers, blanks — doubled, because repetition falsifies idempotence |
| `hostileGeneratorExpression` | totality | delimiters, escapes, Latin-1, long ASCII — measured 6 of 6 planted traps against the edge-biased 3 of 6 |

Both token lists are fixed. **What §8 added was a SUBJECT-tuned list** — the `&`, `"`, `css` the function
itself handles. So the design splits along PRD §11: the kit takes extra tokens and stays ignorant of
subjects; swift-infer, which knows the subject, harvests its literals and passes them in.

## 2. The measured payoff has mostly been taken already

Four of §8's seven false laws were escapers, and `ReplacementChainClassifier` (#568) now withdraws
exactly those. Among behaviour laws, literal drawing would still refute **three**: `mimeType`,
`GlobTool.translate`, and pbt-book's ASCII-only round trip. **Three laws do not carry a cross-repository
change** — a kit release, a pin bump, and stub text moving under every `String` carrier.

## 3. The payoff that has NOT been measured: totality

The funnel's **451 totality passes** can only fail by trapping, and a parser traps on its own
delimiters — which are its literals. The kit's own `hostileGeneratorExpression` measurement found the
worst miss was exactly this: *"`WikilinkParser` exists to parse `[[…]]`, so its real trap bugs live in
bracket handling, and the edge-biased generator cannot produce a single bracket."* A fixed hostile list
guesses at delimiters; a subject's literals are its delimiters.

**If subject literals make totality laws trap, that is bug-finding** — the axis nothing this cycle has
moved: every lever so far raised yield or removed false passes. And it can be measured before anything
is built: `literal_reach_check.py` over the totality laws instead of the behaviour ones.

## 4. The gate

**Run the totality arm first.** Every newly trapping law is hand-checked, and a trap is only a finding
if the input could reach the function in real use — a parser that traps on its own delimiter is a
defect; one that traps on a literal it never receives unescaped is not.

| result | decision |
|---|---|
| ≥ 1 real trap | **build**: the kit takes extra tokens, swift-infer harvests and passes them |
| traps, all unreachable in real use | decline for totality; the behaviour case (3 laws) does not carry it |
| no traps | decline; record that subject literals do not reach totality failures on this corpus |

## 4a. The gate, run 2026-09-22 — BUILD

`literal_reach_check.py --totality` over every passing totality law:

| | laws |
|---|---:|
| totality stubs, compiled and not failing | 454 |
| draw strings from the kit's generators | 178 |
| — subject has no string literal | 95 |
| **ran with the subject's literals, 1,000 trials** | **83** |
| held | 82 |
| **hung** | **1** |

**The one is a REAL DEFECT, reachable in shipped use.** `RuleDocView.parseBlocks` (SwiftProjectLint) loops
forever on any `#` line `singleLineBlock` does not recognise — H1, H4–H6, a bare `#` — because the paragraph
loop stops on `#` without consuming the line. **29 of the 213 rule docs the app bundles carry a `####`
heading, so opening any of their documentation froze the app on the main actor.** Its `input-totality`
law passed as emitted: the totality generator draws delimiters and Latin-1, never a line starting with `#`.
The subject's own literal `"#"` hung it on the first run. Fixed in
[SwiftProjectLint #257](https://github.com/Joseph-Cursio/SwiftProjectLint/pull/257), with tests watched
hanging on the old code; the per-law record is `fixtures/mutation-check/literal-reach-totality-2026-09-22.jsonl`.

**Per §4's table: ≥ 1 real trap, so build.** It is the first defect this line of work — the funnel census,
the mutation check, the literal-reach runs — has found in shipped code, and it came from the arm measured
to refute nothing: totality.

## 4b. Built, and measured 2026-09-23

SwiftPropertyLaws **v4.8.0** (`edgeBiasedGeneratorExpression(subjectTokens:)`,
`hostileGeneratorExpression(subjectTokens:)`, the subject arm in the alphanumeric baseline only) and, in
this repository, `SubjectLiterals` plus the accept path passing them for top-level `String` carriers.

**The defect reproduces from a PLAIN stub.** On SwiftProjectLint `2b292e8f` — before its fix — the stub the
tool now emits for `RuleDocView.parseBlocks` draws `["\n", "[←", "```", "#", "---"]` and **hangs at its
shipped 100 trials**. The census recorded the same law as passing before this change.

**Same-everything census A/B**, 19 repositories, binary from `main` against the gated one, one seed CLI:

| | A | B |
|---|---:|---:|
| stubs · compiles | 900 · 661 | 900 · 661 |
| passes | 575 | **573** |
| — behaviour | 124 | **122** |
| — does not crash | 451 | 451 |
| failures | 59 | **61** |

- **Newly failing: exactly the three §2 predicted** — `GlobTool.translate` and `KaTeXSchemeHandler.mimeType`
  idempotence, and pbt-book's ASCII-only round trip. All three hand-checked false laws; no defect.
- **Newly passing: one, and it is a coverage gain** — SwiftPropertyLaws' `componentTypeNames` `guard-domain`
  law failed *NOT APPLIED* (no draw ended in `?`, so the guarded sub-domain was never entered); drawing the
  subject's own `"?"` reaches it, and the law, now actually checked, holds.
- Upstream stages identical; nothing else moved.

⚠ **The first B moved NOTHING, and that was a defect in this build, not a null result.** The accept path's
custom-generator closure answers before `chooseGenerator` does, and the resolver reports `String` as
`.notInUniverse`, so the closure rendered `String`'s generator itself — without the literals. The unit test
had called `chooseGenerator` without the closure the accept path always supplies. Fixed (a raw type falls
through), with a test through the real closure that fails on the old code with exactly the census's symptom.

## 4c. §5's second check — the recorded literal mutants, re-run 2026-09-23

§5 said `run-2026-09-22.jsonl`'s literal mutants should change outcome. All 23 M6 (*empty string
literal*) mutants were re-applied from their recorded patches against census B's stubs — the ones this
build regenerated — and scored by `mutation_check.py`'s own `evaluate` and `score`
(`scripts/literal_mutant_rerun.py`; record `fixtures/mutation-check/literal-mutants-rerun-2026-09-23.jsonl`).
**Predictions were written before the run**: the one behaviour law §7 said literals would reach moves
UNEXERCISED → DIVERGED and is *not* killed; HTMLEscaping's law is gone; nothing KILLED un-kills; new
kills 0.

| | mutants |
|---|---:|
| recorded | 23 |
| did not compile in the recorded run | 1 |
| law withdrawn since (`HTMLEscaping.escape`, the replacement-chain gate) | 1 |
| **re-run** | **21** |
| same outcome | 17 |
| UNEXERCISED → DIVERGED | **2** |
| KILLED → UNEXERCISED | **1** |
| DIVERGED → UNEXERCISED | **1** |

- ✅ **New kills: 0, as predicted. Literals bought REACH on this set, not kills.** `mermaidEscape`
  (idempotence) and `CallSiteEffectInferrer.isMetricReceiver` (a totality `predicate`) now draw the
  literal the mutant emptied and see the output change. Neither law can fail on it: `mermaidEscape`
  stays idempotent when it stops escaping `"`, and a totality law cannot notice a wrong answer.
- ⚠ **ONE KILL WAS LOST, and it was not predicted.** `CaptureMutationChecker.isShorthandParameter` is a
  `guard-domain` law: *`!name.hasPrefix("$")` ⟹ result is `false`*. The subject literal is `"$"` — **the
  guard's own prefix — so every literal draw lands OUTSIDE the sub-domain the law checks**. From the
  stub's own weights: the one arm that can draw a killing input (non-`$` alphanumerics, e.g. `a5`) fell
  from **3/8 of draws to 3/16**, half its weight now spent on `$`-prefixed strings the guard skips. At
  the scored 100 trials the mutant survives; **at 1,000 it is still killed**. So this is a budget-sized
  loss, not a blind spot — but it is a real cost, in exactly the template the feature was expected to
  help, and it generalises: **a `guard-domain` law's literal is usually its guard's own literal, which
  spends draws on the side the law says nothing about.** Not fixed here.
- ⚠ **The other change is an error in the 09-22 RECORD, not a change in behaviour.**
  `SwiftFormatConfig` parse/serialized was recorded DIVERGED and now reads UNEXERCISED. Re-run on the
  **old stub, in the old tree, at the recorded commit**, it reads UNEXERCISED too: 100 of 100 probe lines
  identical, baseline deterministic. The probe wraps only the outer `serialized()`, whose output equals
  the input whenever the law holds — so it cannot see this mutant at all. Why the recorded digests
  differed is not recoverable (the old probe clone is gone). Quote this row as UNEXERCISED.
- Not moved, as predicted: `RoundTripFinder.signature` draws a syntax node, which no string literal
  reaches. Three totality rows whose input is a `String` (`GitCommit.parse`,
  `InlineSuppressionParser.parse`, `OllamaModelMatching.isInstalled`) also stayed UNEXERCISED, so
  *some totality rows move* held for one row of four.
- ⚠ Two trees sat at later commits than recorded (SwiftProjectLint `0d10011f` against `2b292e8f`,
  SwiftPropertyLaws `004b1dde` against `23af53bf`); every patch applied cleanly, and each row carries both
  commits.

**What it decides.** §4b showed literals make the *passes* more honest, removing false laws. This check
shows they do not make a passing law catch more planted bugs: net −1 kill at the shipped budget, 0 at
1,000. The `guard-domain` cost is the actionable part. A literal the guard *tests for* should be drawn
mostly on the checked side (e.g. with the prefix removed or embedded after other characters), not added
as-is. That is a follow-up.

## 5. If it is built

- **Kit (SwiftPropertyLaws):** `RawType.edgeBiasedGeneratorExpression(extraTokens:)` and
  `hostileGeneratorExpression(extraTokens:)` — the subject's tokens join the curated list, doubled and
  embedded as the existing arms already do. Existing call sites pass none, so goldens do not move.
- **swift-infer:** the accept path reads the subject's string literals from its body — the harvest
  `literal_reach_check.py` already does, moved into Swift — and passes them for top-level `String`
  carriers only, the kit's own stated scope for the biased expressions.
- **Measured by the committed records:** `literal-reach-2026-09-22.jsonl` should reproduce its seven
  refutations with no clone, and `run-2026-09-22.jsonl`'s literal mutants should change outcome.

## 6. Not in scope

- Literals for non-`String` carriers — integer literals are §7's *unreached boundaries*, and they sit on
  derived counts, not parameters.
- A subject-literal token list that replaces the curated ones: the law-tuned lists are measured correct
  for their laws, and this only adds to them.
