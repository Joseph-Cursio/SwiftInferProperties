# Do generated inputs reach a boundary bug? — the 13 unexercised mutants, re-run

> **Status:** `measured` · **As of:** 2026-09-25

The mutation check (`funnel-mutation-check.md`, 22 September) planted boundary and off-by-one bugs — M1
*relational boundary* and M4 *integer off-by-one* — and **13 of their 17 were UNEXERCISED**: no generated
input made the mutant's output differ from the original's. The behaviour-law funnel
(`behaviour-law-funnel.md`) had just shown that reach through the stub pipeline is largely exhausted, so
the remaining lever for a passing law is whether its inputs reach the bug. These are the recorded mutants,
re-run with `scripts/literal_mutant_rerun.py <old> <trees> <out> M1,M4` against census 16's stubs.

## The answer

**Of the 13, seven sit under a totality law, which can never kill a mutant however well its inputs
reach it** — it asserts only that the call returns. Reaching them turns UNEXERCISED into DIVERGED at best.
That is a limit of the law, not of the generator, and no generator work changes it.

**Of the six that a value-comparing law could catch:**

| subject | law | 22 Sep | today's toolchain | after the `[String]` fix |
|---|---|---|---|---|
| `PackageTargetSources.normalized` | idempotence | UNEXERCISED | **KILLED** | — |
| `RuleParameterParser.deindent` `?? 0 → ?? 1` | idempotence | UNEXERCISED | UNEXERCISED | **KILLED** |
| `RuleParameterParser.deindent` `> 0 → >= 0` | idempotence | UNEXERCISED | UNEXERCISED | UNEXERCISED — **equivalent** |
| `ThinkingRecipeExtractor.extract` | guard-domain | UNEXERCISED | UNEXERCISED | — |
| `ThinkingAnalyzer.analyze` ×2 | guard-domain | UNEXERCISED | UNEXERCISED | — |

`normalized` is killed by today's toolchain alone — most plausibly the subject-literal draws of kit 4.8.0,
which postdate the recorded run. `deindent`'s second mutant is **equivalent**: with a minimum indent of 0
the function drops zero characters, so `minIndent >= 0` changes no output on any input, and no generator
can kill it.

## The `[String]` fix — one generator defect, found by reading one stub

`deindent(_ lines: [String])` reads each line's leading spaces. Its stub drew lines from
`Gen<Character>.letterOrNumber.string(of: 0...8)` — **no line ever began with a space**, so the minimum
indent was 0 on every draw and both mutants sat on a branch no input entered. A top-level `String` carrier
already gets `RawType.edgeBiasedGeneratorExpression` (spaces, newlines, markers, the subject's own literals);
**the elements of a top-level `[String]` got the plain form**, because the kit composes arrays from the
member path, which deliberately stays plain.

Now a top-level `[String]` draws its elements from the String carrier's own generator — edge-biased, or
hostile on the totality path — with the subject's literals, at the kit's `0...8` length. Dictionaries,
other arrays and nested arrays keep the kit's form, and struct members are untouched.

**Measured: `deindent`'s killable mutant goes UNEXERCISED → KILLED**, with the original still passing.
32 compiled stubs across 12 repositories take a `[String]` argument — 16 of them behaviour laws.

**And it costs nothing elsewhere — same-code A/B, old binary against new, nine repositories** (census 16
for six whose code had not moved; census 17b re-run with the old binary for SwiftProjectLint, whose `main`
had moved, and for SwiftFormatRuleStudio and pbt-workbook-corpus, which census 16 did not cover): **stubs,
compiles, passes and failures identical in every repository, and the failure sets identical test for
test** — no law that passed before fails now, so no hand-check was owed. The prediction written before the
run was 0 to 3 new failures and compiles unchanged. 20 compiled stubs draw the new element form; the 15
still carrying the plain one are almost all `[String]` **members** of a derived struct, which stay plain
by design. ⚠ **Not covered: `[String]?`** — `nearMissLines` and `mergedWith(existing:)` take an optional
array and keep the plain elements; 2 stubs, left unwidened rather than changed unmeasured.

## What is not reached, and why

- **`isSwift6OrLater`** (predicate) needs a major version of exactly 6; alphanumeric strings rarely
  parse as an `Int` at all. Digits near the body's numeric literals would reach it — but it is a
  totality law, so it could only diverge.
- **`GitCommit.parse`** needs a header with four `\0`-separated fields — also totality.
- **`analyze` / `extract`** (guard-domain) are **outside the law's scope**. A guard-domain law
  characterises ONE guard — here `!trace.isEmpty ⟹ result == .neutral` / `== nil` — and returns `true`
  for every other input. All three mutants sit in code only a non-empty trace reaches — `analyze`'s
  later `wordCount > 0` guard, and `extract`'s comparison choosing between two candidate lists — where
  the law says nothing. No generator makes this law catch
  them; only a law about the non-empty case could.

## So what bounds discrimination here

| of the 13 | why unexercised | can a better generator help? |
|---:|---|---|
| 7 | under a **totality** law, which asserts only that the call returns | no — DIVERGED at best |
| 3 | outside the one guard their **guard-domain** law characterises | no |
| 1 | **equivalent** to the original | no |
| **2** | genuinely unreached | **yes — and both are now killed** (`normalized` by today's toolchain, `deindent` by the `[String]` fix) |

**Generator reach bounds 2 of 13; the law's scope bounds 10.** The boundary bugs the mutation check
planted are mostly in code the emitted law does not claim anything about. Finding more of them means laws
that compare outputs across the whole domain, which is the catalogue question
`behaviour-law-funnel.md` ends on, not a generator one.
