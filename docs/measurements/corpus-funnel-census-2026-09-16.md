# Corpus funnel census, re-run — what four stub writers moved (2026-09-16)

> **Status:** `measured` · **As of:** 2026-09-16
> **Supersedes the counts in** [`corpus-funnel-census-2026-09-14.md`](corpus-funnel-census-2026-09-14.md), whose method this repeats. Read that page for the pipeline; read this one for the numbers.

Two days after the first census, four of the stub writers it found missing had shipped
(#474, #476, #477, #487) along with #467's filename fix. This re-runs the same funnel over
the same 19 repositories to say what that bought.

**It bought exactly what a writer can buy, and no more.** Stub emission went **3.2×** and
compilation doubled; **passing laws did not follow.**

## The funnel

| stage | 14 Sep | 16 Sep |
|---|---:|---:|
| named seeds | 2,716 | **2,723** |
| any law proposed | 2,079 | **2,080** |
| refutable law proposed | 1,010 | **1,019** |
| **refutable stub written** | **309** | **980** |
| stub compiles | 92 | **183** |
| law passes | 71 | **67** |

**The top three stages reproduce the first run to within single digits, and that is what
licenses believing the bottom three.** They are the stages the shipped work should not have
moved; they didn't.

**The binding constraint moved down the funnel.** *No writer for this template* is no longer
where most laws die — *does not compile* is. And the new compile failures are a different
population from the old ones, which is the finding in §3.

Excluding the five book repos: named 2,353 · any 1,784 · refutable 785 · stub 846 ·
compiles 112 · passes 63.

⚠ **The 643 between *named* and *any* is not a catalogue gap** — measured 2026-09-17 in
[`nothing-proposed-decomposition.md`](nothing-proposed-decomposition.md). 527 of the 639 it
classifies are seeds the `determinism` fallback turns away at its own gates: **428 computed
properties** rejected as parameterless although the receiver is their input, 90 same-named
overloads sharing a `(file, symbol)` key, 9 nullary methods. The laws no template names are four
sites across the 428 properties read. Do not quote this stage as *"no template names the shape"*.

## 1. Per repository

`status` is per package, so a repository with several can show more than one.

| repository | seeds | named | any | refutable | stub | compiles | pass | fail | status |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---|
| SwiftProjectLint | 1,029 | 746 | 660 | 410 | 434 | 31 | 19 | 0 | ok |
| SwiftAssist | 438 | 326 | 213 | 74 | 78 | 27 | 18 | 5 | ok |
| SwiftPropertyLaws | 327 | 287 | 235 | 51 | 52 | 20 | 7 | 0 | ok |
| SwiftLintRuleStudio | 292 | 234 | 152 | 63 | 56 | 3 | 2 | 0 | mixed |
| SwiftUMLStudio | 284 | 238 | 191 | 47 | 53 | 0 | 0 | 0 | **unresolvable** |
| pbt-workbook-corpus | 194 | 186 | 141 | 127 | 20 | 0 | 0 | 0 | ok |
| pbt-book | 152 | 144 | 123 | 84 | 108 | 68 | 4 | 2 | ok |
| SwiftFormatRuleStudio | 147 | 113 | 67 | 18 | 30 | 6 | 5 | 0 | ok |
| SwiftEffectInference | 114 | 103 | 72 | 32 | 32 | 5 | 0 | 0 | ok |
| SwiftMarkdownWiki | 103 | 84 | 62 | 26 | 34 | 10 | 7 | 2 | ok |
| SwiftLintRuleStudioTeam | 102 | 80 | 32 | 13 | 18 | 0 | 0 | 0 | **no manifest** |
| SwiftCloneDetector | 72 | 42 | 38 | 15 | 12 | 1 | 1 | 0 | ok |
| MacCloud_client_MacOS | 44 | 43 | 23 | 17 | 25 | 0 | 0 | 0 | **no manifest** |
| pbt-workbook-sampler | 26 | 25 | 24 | 21 | 4 | 1 | 0 | 1 | ok |
| LintStudioUI | 24 | 24 | 14 | 7 | 5 | 4 | 1 | 2 | ok |
| MacCloud_server | 22 | 21 | 16 | 6 | 11 | 3 | 3 | 0 | ok |
| SwiftIdempotency | 16 | 12 | 9 | 6 | 6 | 2 | 0 | 2 | ok |
| pbt-workbook | 12 | 8 | 7 | 1 | 1 | 1 | 0 | 1 | ok |
| pbt-workbook-grader | 8 | 7 | 1 | 1 | 1 | 1 | 0 | 1 | ok |

## 2. Two standing limits, recorded rather than worked around

**SwiftUMLStudio cannot resolve.** Its root pins swift-syntax `600.0.0..<601.0.0` and the kit
requires `602`. The first census worked around this with a trimmed `PropertyLawKit` copy; this
run did not, so its 53 stubs are emitted and never compiled. That is a limit of this run, not
of the tool.

**MacCloud_client_MacOS and SwiftLintRuleStudioTeam have no SwiftPM manifest** — Xcode and
Tuist respectively. 43 stubs emitted, none compiled, same as the first census.

`MacCloud_server` has moved since the first run (`7cfcd3e`, not `65cdc08`), so its 22 seeds
are not comparable with its 14.

## 3. Three times the stubs, twice the compiles, four fewer passes

This is the result worth reading, and it is the repository's own rule arriving:
**state a gain as ROWS MOVED, never LAWS GAINED.**

The writers did their job — 309 → 980 stubs is not in dispute. What the funnel says is that
moving a law past *no writer exists* lands it on *does not compile*, and the population
waiting there is not the one the writers were aimed at. Classified from every set-aside file's
first compiler error, 1,297 across 18 repositories at the time of the reading:

| cause | stubs |
|---|---:|
| a type other than the subject is not in scope | **666** |
| cannot infer the type of a closure parameter | 252 |
| inaccessible due to protection level | 132 |
| type has no member | 74 |
| the subject itself is not in scope | 51 |

Three of those became issues: the first is [#492](https://github.com/Joseph-Cursio/SwiftInferProperties/issues/492)
and [#493](https://github.com/Joseph-Cursio/SwiftInferProperties/issues/493); the identity
collapse found alongside it is [#490](https://github.com/Joseph-Cursio/SwiftInferProperties/issues/490),
now closed. **The 74 missing-member failures are unfiled and uncharacterised** — recorded here so
the next reader does not have to rediscover that they are the fourth-largest bucket.

✅ **The 252 closure-parameter failures were characterised and fixed the same day** — this page
first called them unfiled, and it was out of date within hours. A multi-argument stub's property
closure carried no annotation on its tuple
([#498](https://github.com/Joseph-Cursio/SwiftInferProperties/issues/498), fixed by
[#499](https://github.com/Joseph-Cursio/SwiftInferProperties/pull/499)). **It freed no laws, as
predicted**: 269 of the 288 stubs hitting that error also carry an underived generator, so the
annotation changes their error to the true one instead of removing it — which is what made
[`missing-generator-census.md`](missing-generator-census.md) measurable. 252 counts files whose
FIRST error was this one; 288 counts every stub that hit it.

## 4. What the 666 is, and why it is not one problem

Measured structurally, by checking each missing identifier against the subject's own source:

| | rows |
|---|---:|
| declared in a package **dependency** (`Syntax` 84, `FunctionCallExprSyntax` 71, `ExprSyntax` 45, …) | ~507 |
| a **generic parameter** of an enclosing declaration | 50 |
| a generic **receiver** written without its type arguments | 5 |
| everything else — same-package types, frameworks, free functions | remainder |

⚠️ **445 of the 507 are SwiftProjectLint alone** and only 4 of 19 repositories have any. A tool
that analyses Swift code naturally carries SwiftSyntax nodes as carriers; this is not a general
population, and it is why #492's wiring measured **3 rows across two subjects** rather than the
159 first projected from the same data.

## 5. Instrument, and the eight defects it had

| | |
|---|---|
| SwiftProjectLint | `eebf93de` |
| SwiftInferProperties | `main`, one binary for all 19 |
| Swift | 6.3.3-RELEASE (swift.org) |
| subjects | detached worktrees, nothing written to any subject repository |

The harness was rebuilt — the 14 Sep one lived in a session scratchpad and was never committed.
**Eight defects were found in it, seven caught by a number that could not be true**, and they are
listed because each is a way to get this measurement wrong:

1. **`.swiftinfer/decisions.json` carried between scan groups.** A recorded decision suppresses a
   suggestion, so every group after the first in a package was offered nothing — pbt-book's 29
   chapter targets would have reported 28 empty runs.
2. **Bare `swift` on `PATH` broke module resolution.** `swift-infer` resolves a subject's module by
   shelling out to `swift package dump-package`; on this machine `PATH` resolves to a SwiftPM whose
   manifest compile fails, so **0 of 70 pilot stubs carried `@testable import` against 70 of 70
   with the toolchain first on `PATH`**. A whole 2,914-stub pass was discarded.
3. **`compiled` counted stubs in packages that never built**, giving pbt-book 109 compiled against
   a package that failed to resolve.
4. **A duplicate dependency declaration** — adding `swift-property-based` by path while the package
   had it by URL — made ten repositories report `exhausted attempts to resolve the dependencies graph`.
5. **An unbalanced-paren manifest rewrite** emitted `.package(path: "…"))` and broke pbt-book's manifest.
6. **`passed` counted determinism tautologies while `compiled` excluded them**, which made passes
   exceed compiles — impossible, and the reason it was caught.
7. **An infinite loop** in the same manifest rewrite: the replacement is a `path:` declaration whose
   path contains the package name, so a widened pattern rematched its own output. pbt-book ran
   **2h29m with no child process** before this was noticed. The only defect here that cost real time
   rather than being caught by a wrong number.
8. **`discover.out` sent to `/dev/null`** during an unrelated A/B, which silently zeroed SwiftAssist's
   refutable count until the aggregate contradicted itself.

⚠️ **Two repositories were re-run on a different binary mid-measurement** and then reset, because
seventeen repositories on one binary and two on another is not a funnel. That is the same defect as
quoting counts from one run beside timings from another.

## Reproducing

The driver, grouping, stage-4 harness and aggregator ran from a session scratchpad and are again
not committed. The pipeline is [the first census's](corpus-funnel-census-2026-09-14.md); the eight
defects above are the parts that change a number.
