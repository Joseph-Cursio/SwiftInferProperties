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

## What is not reached, and why

- **`isSwift6OrLater`** (predicate) needs a major version of exactly 6; alphanumeric strings rarely
  parse as an `Int` at all. Digits near the body's numeric literals would reach it — but it is a
  totality law, so it could only diverge.
- **`GitCommit.parse`** needs a header with four `\0`-separated fields — also totality.
- **`analyze` / `extract`** (guard-domain) are not yet diagnosed.
