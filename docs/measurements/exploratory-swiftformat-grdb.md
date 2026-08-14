# Exploratory runs — swift-format and GRDB

> **Status:** `measured` · **As of:** 2026-08-14

**Not road tests.** No frozen fixture, no answer key, nothing scored. The question was *what
does the toolchain reach on subjects it has never met*, asked immediately after row-level run
retention shipped so the arms could be diffed rather than remembered. Numbers are of their
date; the diagnoses are the durable half.

**Two subjects in one document on purpose.** The central finding spans both, and four of the
five instrument defects were found on one subject and would have been found on the other. A
per-subject split would have put the shared narrative in whichever file was written first and
left the other quoting it — the summary-drift shape this repo keeps catching.

**Both runs are banked** at `fixtures/verify-runs/2026-08-14-SwiftFormat.json` and
`fixtures/verify-runs/2026-08-14-GRDB-staged.json`, comparable row-by-row via
`swift-infer survey-diff`. See `fixtures/verify-runs/README.md` for why they are committed.

---

## §1 The results

`prove-then-show --target <T> --budget small --max-parallel 4`, fresh worktree per run, no
`--corpus-module` (per that command's doc: omit it when proving the package you stand in).

| | picks | Proven | Refuted | Unverifiable | Inconclusive |
|---|---|---|---|---|---|
| `SwiftInferCore` @ `c998752` *(control)* | 159 | **87** | 2 | 61 | 9 |
| swift-format `SwiftFormat` @ `d2bd4b3` | 129 | **1** | 1 | 101 | 26 |
| GRDB `GRDB` @ `b83108d10` *(staged)* | 307 | **5** | 1 | 277 | 24 |

**The own-repo row is the control and reads as the outlier for a reason.** 87 of 159 laws
execute on the codebase the catalog was built alongside, against 1 of 129 and 5 of 307 on
subjects it had never met. **Recall on unfamiliar code is the finding, not the pass rate**, and
it is not visible from a single-corpus run — which is the argument for doing this at all.

**Zero defects in either subject.** Both refutations are generator artifacts (§6). That is the
weaker kind of result: absence of refutation over a generated domain is not proof, and both
subjects are mature and correct at HEAD, the population where a clean bill says least.

---

## §2 The pattern that governed the day

Four fixes unblocked rows. In every case most of what was freed hit a **second** obstacle that
had been hidden behind the first.

| fix | rows unblocked | reached execution |
|---|---|---|
| verifier platform floor (§3) | 39 | **2** |
| hand-written `Row.gen()` (§7) | 10 | **2** |
| syntax-node generators (earlier work, `roadtest-self-dogfood-2026-08-08.md` §9.3) | 9 | **1** |
| stub kit import (§5) | 1 | **0** |

*A refuter that fires first hides every refuter behind it* is a standing rule in this project's
own design notes. It was relearned four times in one day, on four different mechanisms.

**The practical consequence is a reporting rule: state gains as ROWS MOVED, never as LAWS
GAINED.** A decline-reason count is an upper bound on what fixing that reason buys, and on this
evidence the ratio is roughly 5:1 against.

---

## §3 The platform floor — 100% of picks on most of the ecosystem

`PropertyLawKit` declares `.macOS(.v14)`. The verifier mirrored the **corpus's** floor, so a
package at 13.0 produced an executable SwiftPM refuses to link:

```
the executable 'V…' requires macos 13.0, but depends on the product
'PropertyLawKit' which requires macos 14.0
```

swift-format is at 13.0 and GRDB at 10.15 — both wholly ordinary. **Every pick that reached a
build died here.** It is invisible on this repo's own corpora, which sit at 14.0 and agree with
the kit by construction, so no amount of self-dogfooding would have surfaced it.

**A regression, and the docstring shows how.** The 2026-08-05 fix replaced a hardcoded
`.macOS(.v14)` because a corpus at `.macOS(.v26)` failed all 60 picks on SwiftProjectLint —
correct about the corpus-is-*higher* direction. But the constant it removed satisfied the kit
*by construction*, so the corpus-is-*lower* direction worked before that change and not after.
The docstring framed the rule as *"agreement with the corpus"*; it is agreement with the corpus
**and** the kit. Floor is now `max(corpus, kit)`.

### §3.1 The fix went into the wrong copy first, and only an A/B said so

| arm | result |
|---|---|
| A — pre-fix | 129 picks, 0 Proven, 0 Refuted, 90 Unverifiable, 39 Inconclusive |
| B — `VerifierWorkdir.macOSPlatformLine` fixed | **byte-identical to A** |
| C — `SharedVerifierPackage.platformLine` also fixed | 1 Proven, 1 Refuted, 101 Unverifiable, 26 Inconclusive |

The rule had **two implementations**, and the survey runs the one that was not fixed first.
Arm B moved 0 of 129 rows. This is `TemplateName`'s standing hazard — five separate
enumerations of the template vocabulary must agree, and missing one is silent in a different
way each time — reproduced on a new pair.

**Arm B is also the first thing row-level retention caught.** Comparing bucket summaries would
have shown `0 / 90 / 39` twice, with no way to separate *the fix did nothing* from *I ran the
same binary twice*. The diff reported the runs identical at row level and said so in words.

---

## §4 The advice a new user is most likely to read does not compile

The remedy shown for every `unsupported-carrier` row said:

> add `static func gen() -> Gen<T>` for that carrier in your target

`Gen` is `public enum Gen<Value> {}` — an uninhabitable namespace holding static factories.
Nothing can return one. The real type is `Generator<T, some SendableSequenceType>`, which the
**kit has always documented**: `PropertyLawCore/TodoReason.swift` emits exactly that signature
and `PropertyLawMacro` carries it in its docs. Two tools in one toolchain gave contradictory
instructions for the same task, and the wrong one was downstream.

**Narrow, and worth stating precisely:** `Gen<Int>.int(in:)` in *expression* position is
correct and every emitted recipe uses it. Only return-type position was wrong, in one string.

**Scale is why it matters.** `unsupported-carrier` is the most-shown remedy on unfamiliar code
— **138 rows on GRDB, 18 on swift-format, 5 on this repo**. It is what the tool says to a new
user more than anything else, and it is invisible from inside, where nobody needs telling how
to write a generator.

**Found by following it literally**, which is the one check neither repo performs. The first
attempt guessed `Gen.array(of:)` and `Gen.zip`, collected four compile errors, and needed the
package read to find the real API — so the advice is not merely wrong, it leaves no thread to
pull.

It also hid a cost it now states: a `gen()` returning a `Generator` needs `import
PropertyBased`, so following the advice makes swift-property-based a dependency of the
**production target** under test.

**This is issue #256's class** — a refusal advertising `--extra-import`, a flag that does not
exist — and **#256's guard cannot catch it**: `RefusalFlagVocabularyTests` asserts every
`--flag` parses, and this is a type name. `GenAdviceCompilesTests` closes the gap by reading
the signature out of the kit rather than restating it.

---

## §5 A stub could not name the generators it emitted

A memberwise or enum-payload recipe embeds each member's generator expression **verbatim**,
then declares a fixed `["Foundation", "PropertyBased"]` import list. `Gen` is PropertyBased's;
`Gen<Data>.data()`, `Gen<URL>.url()`, `Gen<UUID>.uuid()`, `Gen<Decimal>.decimal()` and
`Gen<Date>.date()` are extensions in `PropertyLawKit`. So a carrier with one `Data` field emits
a kit call from a code path that never decided to make one.

Measured: GRDB's `DatabaseValue` rendered
`Gen<Data>.data().map { DatabaseValue.Storage.blob($0) }` into a stub importing Foundation and
PropertyBased only — `type 'Gen<Data>' has no member 'data'`, for a generator that exists at
`v3.28.0` and a product the generated target **already links**.

**Third occurrence of one class**, which is why the fix is a single shared constant and not a
third patched route: `.algebraic` lacked the *product* until 2026-08-04 (open-threads → *The
`Gen<URL>` defect*), and the composite path lacked the *import* until its own fix, whose
comment states that a verify stub "imports `PropertyBased` and nothing else". Each repaired the
route in front of it.

**Two wrong readings are recorded so nobody repeats them.** It is *not* the kit calling a
generator that does not exist (`data(of: ClosedRange<Int> = 0 ... 256)` is there), and it is
*not* version skew — a tag check spelled `3.28.0` instead of `v3.28.0` reported the file absent
and nearly produced a false finding. **Check the tag spelling before writing up skew.**

Result: the `Gen<Data>` error is gone corpus-wide (1 → **0** across 307 picks) and **no row
changed bucket** — `databaseValue()` is still Inconclusive behind a later error. §2 again.

---

## §6 Both refutations are generator artifacts, on two independent corpora

| subject | law | counterexample |
|---|---|---|
| swift-format | `Indent.count()` non-negativity | `tabs(-1491761683272755080)` |
| GRDB | `DatabaseBackupProgress.completedPageCount()` | `totalPageCount: -485790543525831844` |

Neither value is constructible by the code under test. **Two fresh corpora, the same
unbounded-draw artifact both times**, which makes it the most common false refutation on
unfamiliar code and the strongest candidate for the next fix. It is the same weakness
`roadtest-self-dogfood-2026-08-08.md` records as `SourceLocation(line: -691367222)`, now with a
second and third witness from code this project does not own.

---

## §7 GRDB could not be surveyed at all, and the workaround is not a fix

GRDB declares `path: "GRDB"`, so its 167 sources sit at repo root. `prove-then-show --target X`
resolves `Sources/<target>` unconditionally and, unlike `discover`, has **no `--sources`
escape hatch** — so the package is unreachable. The run was obtained by
`git mv GRDB Sources/GRDB` plus deleting one manifest line in a throwaway worktree: two edits,
package otherwise untouched, builds clean.

That is the MacCloud shim precedent (CLAUDE.md's `--sources` row) reused for a **SwiftPM
library** rather than an Xcode project. **The gap is open**: reach is unchanged for any package
laid out this way, and a human moved the files. GRDB is widely used, so the population is not
exotic (falsifier: `ProveThenShowSourcesReachTests`).

**The falsifier is named for a guard, not for the option**, and the first draft got this
wrong in the way `falsifier-naming-failure-modes.md` predicts. `ProveThenShow.sources` resolves
**today** — three other commands already declare a `sources` property, and the resolver matches
the last dotted component anywhere in the target — so it would have read as *closed* the day it
was written. `XcodeSourcesReachTests` is the guard the existing `--sources` work carries; the
fix here must add its counterpart, and that name exists nowhere yet.

**Everything in §1's GRDB row is therefore a STAGED subject** and must never be quoted as
GRDB-as-shipped.

### §7.1 "Generatable in principle" — tested, and worth less than the count suggests

GRDB's Unverifiable profile **inverts** against swift-format's:

| | no generator | subject private | no composer |
|---|---|---|---|
| GRDB | **138** | 84 | 41 |
| swift-format | 18 | **70** | 1 |

Top ungeneratable carriers are the domain itself — `Database` 17, `SQLExpression` 12,
`Association` 11, `Row` 10, `SQLRelation` 10. A `Database` is a live connection and correctly
ungeneratable. `Row` is a `public final class` with a public dictionary initialiser, so one
generator was written by hand to test the claim rather than assert it.

Of `Row`'s 10 blocked rows: **2 reached execution and Proved** (`Row.copy()` idempotence,
`Row.hasColumn(_:)`), 5 hit `instance-method-shape-not-supported`, 2 failed to compile, 1
wanted a conformance. So the claim holds and buys little — §2's ratio again, and the reason
the 138 must not be read as 138 recoverable laws.

**Prediction stated before the run and wrong: accessibility would dominate.** It is second.

### §7.2 41 laws discovery proposes and verify cannot attempt

`inverse-pair` 17, `identity-element` 14, `input-totality` 4, `functor-identity` 3,
`state-machine` 3. No composer exists, so **nothing the user writes unblocks these** — the
largest such population measured on any corpus, against 1 on swift-format.

### §7.3 `involution` fired for the first time

Eight proposals, one Proven — `EqualityOperator.negated()`. The catalog census lists
`involution` among the templates that never fire, with five still at zero after `homomorphism`
was revived.

**This is not evidence it was broken.** That census covered eight corpora and GRDB was not one
of them, so this is the first direct evidence separating *correctly silent for want of
population* from *dead* — a distinction the census itself says is invisible from outside. The
census row is worth updating; the template needs nothing.

---

## §8 What these runs do not claim

- **Zero defects is the weak result.** Absence of refutation over a generated domain is not
  proof, and both subjects are correct at HEAD.
- **`Proven` means no counterexample in the generated domain**, not that the property holds.
- **GRDB is staged.** Not GRDB-as-shipped.
- **swift-format's ceiling is accessibility, not tooling** — 70 of 129 picks are `private`
  subjects, which is §2's *lift the law to the nearest reachable caller*, a design question for
  the subject rather than a gap here.
- **Three of the five instrument defects were in code shipped hours earlier the same day**, and
  two fixes moved nothing on their first attempt. Same-day work is the least settled part of
  this record.

## §9 Method notes worth stealing

- **A/B the artifact, not the intention.** Arm B looked like a fix and moved nothing; only a
  row-level diff of two retained runs said so. Bucket counts could not have.
- **Follow your own remediation advice literally, once, on a subject you do not own.** It found
  §4, which no test in either repo can reach.
- **Check the tag spelling before writing up version skew** (§5). `3.28.0` and `v3.28.0` are
  different answers, and one of them invents a finding.
- **Run in a fresh `git worktree`** so `.swiftinfer/` is absent by construction, and so the
  subject's own checkout is never touched.
