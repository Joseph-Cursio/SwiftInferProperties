# What is actually stopping 171 stubs — the first error is not the blocker

> **Status:** `measured` · **As of:** 2026-09-22

The corpus funnel classifies a set-aside stub by **the compiler's first error**, and
`corpus-funnel-census-2026-09-20.md` reports the whole corpus that way: 190 `private`, 91 no
generator, 27 other. **A stub usually carries more than one blocker, and which one the compiler
reaches first is not which one you have to fix.**

The sections through the replication were taken 2026-09-20; § *Corpus-wide* is the 2026-09-22 re-take over all 19 repositories.

This reads the stubs themselves, on **SwiftProjectLint `f93d9edf`** — 45% of the corpus's stubs —
by joining each stub's first error to what its own emitted header says about access.

## The decomposition

171 set aside, of 424 emitted.

| first compiler error | subject `private`? | stubs | what it takes |
|---|---|---:|---|
| the subject is `private` | yes | **42** | widen |
| a type is not in scope | yes | **30** | imports, **then** widen |
| no generator for an argument | yes | **43** | a generator, **then** widen |
| a type is not in scope | no | 28 | imports |
| no generator for an argument | no | 18 | a generator |
| the subject is `private` | **no** | 5 | see below |
| a syntax error in emitted text | either | 2 | two uncharacterised emitter defects |
| other | either | 3 | — |

**118 of 171 have a `private` subject**, against the 42 the first-error classification reports.
The census's headline figure for this cause is a floor, not a count.

⚠ **They are not one job.** The census's own ordering rule is what splits them:

> ⚠ **Access and derivation must fall in that ORDER.** Widening a subject whose arguments still
> have no generator frees nothing: measured directly, 137 widenings in SwiftProjectLint bought
> **1** compile until the receiver generator landed, and then the same widenings were worth
> **+121**.

So of the 118: **42 are ready to widen now**, 30 need an import first, and **43 would free nothing**
because a generator is still missing. Widening all 118 would be 76 edits to subject code for no
measurable return.

⚠ **The 5 that report `private` with no access note in their header** are a different symbol — a
helper or a nested type the law reaches, not the subject the header is about. Not traced.

> ⚠ **CORRECTED 2026-09-22 — traced, and this reading was wrong.** All 5 DO carry an access note;
> it is the *enclosing-type* note, which the join above did not match. The protection error names
> the enclosing type because that is what blocks: `SensitiveReferenceFinder` (2 stubs),
> `TypeMemberCollector` (1), `LocalBindingCollector` (2), each a `private` nested class. The
> subject is the one the header is about. See § *Corpus-wide*.

## The 42 were widened, and every one converted

[SwiftProjectLint #243](https://github.com/Joseph-Cursio/SwiftProjectLint/pull/243) widened exactly
the 42 — `private func` → `func`, 42 insertions and 42 deletions across 20 files, no signature
touched. Re-run on the same census binary, subject `f93d9edf` → `fbf82dc9`:

| | before | after |
|---|---:|---:|
| seeds / named / stub file written | 1,029 / 746 / 424 | identical |
| **stub compiles** | **253** | **295** |
| **law passes** | **250** | **292** |

**+42 compiles and +42 passes, from 42 widenings.** 42 stubs freed, **0 newly set aside, 0 reasons
changed**, and every other cause identical to the digit: no generator 61, a type not in scope 58, a
syntax error 2, other 3.

✅ **The ordering rule predicted the conversion exactly.** Its claim is that widening pays only
where derivation has already landed, and selecting on *the compiler reports access first* is a
sound test of that — none of the 42 hit a further blocker, where the 137-widening cycle that
preceded the receiver generator converted 1.

✅ **And it confirms the five.** The `private` bucket went **47 → 5**, and the 5 that remain are
exactly the ones flagged below as reporting a protection-level error with no access note in their
header — a different symbol, not the subject. They did not move, because nothing about the subject
was what stopped them.

> ⚠ **CORRECTED 2026-09-22**: not a different symbol — the subject's enclosing `private` class, which
> widening the subject cannot reach. The conclusion stands (widening the subject would not move them);
> the reason given was wrong.

⚠ **A pass still means no counterexample in 100 draws.** The 42 new passes are `predicate` totality
over syntax nodes, the arm `template-refutation-rates.md` measures at **0 refutations of 102**.
What they establish is that these helpers do not crash on realistic Swift.

## Replicated on a second subject: 6 of 8, and the rule survives the miss

42 of 42 is one package, and SwiftProjectLint is an unusual one — a Swift analyser whose subjects
are syntax visitors. **SwiftUMLStudio is the second subject.** The same selection — *the compiler
reports access first, and the stub's own header confirms the subject is private* — picks **8**
declarations there ([#46](https://github.com/Joseph-Cursio/SwiftUMLStudio/pull/46), 950 tests
unchanged).

| | before | after |
|---|---:|---:|
| stubs | 43 | 43 |
| **compiles** | **13** | **19** |
| **passes** | **11** | **16** |

**6 of 8 converted, against 42 of 42.** Six freed, none newly set aside, and **both misses are
defects in `swift-infer`, not in the selection**:

- `CoreDataModelExtractor.contentsURL` — the subject `throws`, and **the emitted stub calls it
  without `try`**: `call can throw, but it is not marked with 'try'`.
- `DagreLayoutEngine.fallbackLayout` — `idempotence` was proposed over `LayoutGraph`, which is
  **not `Equatable`**, so the law cannot state itself: `referencing operator function '==' on
  'Equatable' requires…`. `UnverifiableCause.carrierNotEquatable` exists for exactly this and did
  not fire.

✅ **So the rule held and the promise did not, which is the distinction this page already drew**:
*that is a claim about what the compiler now REPORTS, never a promise of N compiles — a widened
subject can fail on the next thing behind it.* Both of these did, and **both were invisible until
access stopped hiding them** — #499's mechanism at a third site.

⚠ **Read the rate as 48 of 50 across two subjects, not as 100% and then 75%.** The two misses are
one throwing-subject defect and one gate that failed to fire; neither is a property of the
selection, and neither would have been found without the widenings. **A second subject was worth
it for the two defects alone.**

## The import fix buys zero compiles here, and that is the finding

The receiver-construction work
([`receiver-construction-local-inlining.md`](receiver-construction-local-inlining.md)) moved 10
stubs onto `cannot find 'SyntaxPattern' in scope` (5) and `cannot find 'Parser' in scope` (5).
Both are correct Swift: the harvested construction names a type from a package dependency and the
stub does not import it. `SyntaxPattern` is declared in the nested package
`SwiftProjectLintVisitors`, and the scan that emitted the stub indexed 440 types without it —
checked in `sourceFileByTypeName`, which is what `VerifyImportSet` resolves modules from. So
`#492`'s existing machinery cannot reach these, exactly as its own note says of the 507.

**All 10 are also `private`.** Fixing the import would move each one onto the access error and free
none of them.

✅ **So the import half is not a yield lever on this subject — it is enabling work for the 30**,
which need it before widening pays. Stated as its own recommendation rather than folded into a
compile count, because *rows moved* and *laws gained* are different claims and this is neither yet.

## The syntax errors were three defects, and the largest is fixed

12 stubs failed with `expected ',' separator` or `expected ')' in expression list` — a **syntax**
error in code the reader did not write, which also hides the derivation-reason marker sitting
beside it. Read, they are three unrelated causes:

| emitted text | stubs | cause |
|---|---:|---|
| `some SyntaxProtocol.gen()` | **10** | an **opaque parameter**, fixed below |
| `(Syntax.gen()` | 1 | a type name split at a comma without balancing parentheses |
| `?.gen()` | 1 | a type name that is the single character `?` |

✅ **The opaque case is `#497`'s defect in sugar, and it is now gated.** `func isTopLevel(_ decl:
some SyntaxProtocol)` is `func isTopLevel<T: SyntaxProtocol>(_ decl: T)`, and the scanner records
the sugar — `parameterTypeNames` reads `some SyntaxProtocol` while `genericParameters` is empty, so
neither half of `GenericSubjectGate` saw it.

**Same-binary A/B on the same subject: stubs 434 → 424, compiles 253 → 253, passes 250 → 250.**
Exactly the 10 withdrawn, **zero other stubs moved and zero reasons changed** — so it costs no
laws, which is the whole argument the availability gate and `#497` were shipped on.

⚠ **`any P` is deliberately not gated.** An existential names a real type a stub can spell, so one
that fails is an ordinary missing generator rather than an unbindable name. The test asserts it,
and a third asserts that `HandsomeValue` is not matched — the token is the keyword, not a
substring.

⚠ **The remaining 2 are characterised and NOT fixed.** `(Syntax` is a parenthesis-unbalanced split
of a type name and `?` is a type name that is one punctuation mark; both are defects in how a
parameter's type text reaches the emitter, and neither cause was traced to its source here. They
are recorded as two separate findings rather than swept by a parse check, because a stub that does
not parse is a symptom and these are two different diseases.

## Corpus-wide, 22 September: 154 private subjects, 15 ready

Everything above is SwiftProjectLint plus one replication. **Re-run over all 19 repositories** on
one `swift-infer` binary (`dd4ccfce`, the two accept-path gates of #554 included), subjects at their
current heads (SwiftProjectLint `fbf82dc9`, SwiftUMLStudio `73d7823`):

| | 20 Sep, all-resolve | 22 Sep |
|---|---:|---:|
| named / any law / refutable | 2,738 / 1,921 / 939 | identical |
| stub file written | 905 | **902** |
| **compiles** | 634 | **640** |
| **passes** | 547 | **552** |
| failed · trapped · unaccounted | 58 · 23 · 6 | 59 · 23 · 6 |

**All of the movement is SwiftUMLStudio**: the 8 widenings of its #46 (compiles 13 → 19, passes
11 → 16, one new failure) and the two #554 gates withdrawing 3 of its stubs that had never
compiled (43 → 40). The other 18 repositories are identical to the digit, and the four outcome
columns sum to 640.

### What stands in front of the private subjects

262 stubs set aside. **154 have a `private` subject by their own header; 18 report access first.**
Classified by the rule this page established — *access first, and no `no generator derived`
marker* — and split by where the keyword sits:

| what it takes | stubs | where |
|---|---:|---|
| a generator, then widen | **106** | SwiftProjectLint 70; the rest ≤ 7 per repo |
| an import, then widen | **30** | SwiftProjectLint 22, SwiftLintRuleStudio 7, SwiftAssist 1 — ⚠ **only 7 were imports; see § *The import bucket, taken apart*** |
| ✅ **widen the declaration** | **4** | SwiftIdempotency 2, pbt-book 2 |
| ✅ **drop `private` from an extension** | **8** | SwiftUMLStudio, all 8 |
| ✅ **widen a `private` nested type** | **3** | SwiftProjectLint 2, SwiftPropertyLaws 1 |
| other | 3 | — |

**15 are ready, against 42 last time — and only 4 of them are the one-keyword edit this page
measured.** The rest of the ready set is a different edit:

- **SwiftUMLStudio's 8 are `private extension` members of `public` types** — `ERScript`,
  `StateScript`, `ActivityScript`, `DepsScript`, `ComponentScript`, and `private extension String`.
  The type needs nothing. Deleting the extension's keyword widens *every* member of it; moving the
  8 functions into an unmarked extension widens only them.
- **The 3 are members of `private` nested classes** (`TypeMemberCollector`, `LocalBindingCollector`,
  SwiftPropertyLaws' `TargetDecl`) — widening a type, a larger change than widening a function.
- **pbt-book's 2** are `FileSystem.exists` / `isAncestor` in a chapter-25 case study, where `private`
  may be part of what the chapter teaches.

⚠ **The ready set is yield, not bug-finding.** Every one of the 15 is `predicate` or `idempotence` —
the arm at 0 refutations of 102 and the template at 18 of 18 hand-checked refutations false.

### The header gave wrong advice on 11 of the 15, fixed in #555

The stub's edit line read the declaration's own line alone:

- for a **`private extension`** member — no keyword on its line — it printed no edit, while the
  remedy said *widen the enclosing type*, a type already `public`. All 8 SwiftUMLStudio stubs.
- for a **`private` member of a `private` class** it printed `Delete private at …:129` — the member —
  one line below a remedy calling that edit a no-op. `SensitiveReferenceFinder`, 2 stubs.

`RestrictedScopes` now finds every blocking keyword where it is written, and the edit names each —
`Delete private at ERScript.swift:101 (extension ERScript)`, with the note that this widens the
extension's other members. **Same-binary re-run on SwiftUMLStudio and SwiftProjectLint: stubs,
compiles and passes identical; exactly 29 headers change, all enclosing-scope cases, all 29 now
carrying an edit** (8 extension, 21 class or struct), and no stub body moves.

⚠ **Instrument note.** 150 headers first read as changed; 121 differed only in the scratch
directory's path, which the header embeds. Diff headers with the run directory normalised.

### The import bucket, taken apart — 7 of the 30 were imports

Read by the name each stub could not find, the 30 are four different things:

| missing name | stubs | what it actually is |
|---|---:|---|
| `Collector`, `ClosureWriteTargetCollector` | **12** | **file-private TYPES, not imports.** A top-level `private` type is reported `cannot find '…' in scope`, not *inaccessible*, so the first-error classifier filed them here. They need the type widened. |
| `MockSwiftLintCLIActor`, `IsolatedUserDefaults`, `SwiftLintCLIActor` | **7** | **real imports** — a test-support and a backend target the package builds, named by a construction copied from a test |
| `SyntaxPattern`, `Parser` | **10** | names **no copied import can reach**: the constructing test gets `SyntaxPattern` only through `@testable import Core`, and `SwiftParser` is not a dependency of `SwiftProjectLintRules` at all |
| `SkillAuthorMockBackend` | 1 | declared inside a test file — unreachable from any other file |

✅ **The 7 are fixed, in #557**: a copied construction now brings its test file's imports, keeping only
modules the package's own code builds with (`TestTargetScope.buildModules`). **Same subjects, full
19-repository census: compiles 640 → 641, passes 552 → 553, upstream stages identical; 21 stubs move
from *not in scope* to their real next blocker.** All 7 SwiftLintRuleStudio stubs land on the access
error — so they join the ready set — and one more of its stubs compiles outright. ⚠ **#557's own
description says 6; it is 7**, re-read from the stubs.

⚠ **The build-module cut is load-bearing, and the census found that, not a review.** The first
version emitted every import the test file had. Test files import what only a test target can see —
the root package's `Core`, `ViewInspector`, `VaporTesting` — and **`SwiftProjectLintRules` went from
230 compiles to 0**: `no such module 'Core'` stops a module's compile after a few files, so the
harness's set-aside loop exhausted its rounds and the whole package read as unbuilt. Three other
repositories lost one compile each the same way.

So the ready set is now **22**, by the edit it takes:

| edit | stubs | where |
|---|---:|---|
| delete `private` on the declaration | **9** | SwiftLintRuleStudio 5, SwiftIdempotency 2, pbt-book 2 |
| delete `private` on an extension, or move the member out | **10** | SwiftUMLStudio 8, SwiftLintRuleStudio 2 (one extension) |
| widen a `private` nested type | **3** | SwiftProjectLint 2, SwiftPropertyLaws 1 |

plus the **12 file-private types** above, which need a type widened and were never in the ready
count. ⚠ **Still yield, not bug-finding** — every one is `predicate`, `input-totality` or
`idempotence`.

### The 22 were widened, and every one converted

Six pull requests, one per subject — [SwiftUMLStudio #47](https://github.com/Joseph-Cursio/SwiftUMLStudio/pull/47),
[SwiftLintRuleStudio #49](https://github.com/Joseph-Cursio/SwiftLintRuleStudio/pull/49),
[SwiftIdempotency #22](https://github.com/Joseph-Cursio/SwiftIdempotency/pull/22),
[pbt-book #207](https://github.com/Joseph-Cursio/pbt-book/pull/207),
[SwiftProjectLint #244](https://github.com/Joseph-Cursio/SwiftProjectLint/pull/244),
[SwiftPropertyLaws #56](https://github.com/Joseph-Cursio/SwiftPropertyLaws/pull/56) — each with its own tests
green. Re-run over those six on one binary against the post-#557 baseline:

| | before | after |
|---|---:|---:|
| stubs | 681 | 681 |
| **compiles** | **478** | **500** |
| **passes** | 415 | 439 |
| failures | 36 | 36 |

**22 freed, 0 newly set aside, all 22 pass** — 48 of 50 before, **70 of 72** now. Passes rise by 24,
not 22: two of pbt-book's four come from the `--skip` fix (#559), which also accounts for its 3 extra
traps and unaccounted 5 → 0. Corpus-wide that makes **compiles 641 → 663** and
**passes 553 → 577**.

⚠ **The edit was not always one keyword, and the header's advice was not always the edit.**
SwiftUMLStudio's 8 and two of SwiftLintRuleStudio's were **moved** out of their `private extension`
into an unmarked one — deleting the extension's keyword, as the header offers first, would have
widened every other helper in it. And `TypeMemberCollector` **cascaded**: its stored property is typed
by the `private` struct `TypeMembers`, which the enclosing catalog reads, so a second type had to be
widened for one law. Three keywords bought SwiftProjectLint's two.

⚠ **Still yield, not bug-finding.** All 22 are `predicate`, `input-totality` or `idempotence`, and all
22 pass.

## Scope

⚠ **One subject**, chosen because it is 45% of the corpus's stubs. The proportions above are this
package's, and SwiftProjectLint is a tool that analyses Swift — its subjects are syntax visitors,
which is why its `private` and dependency-type buckets are as large as they are. The opaque-
parameter gate is a rule about Swift rather than about this package, but **its measured cost — 10
stubs, 0 laws — is a reading here and not a rate.**

## Reproducing

```
python3 scripts/corpus_funnel.py <out-dir> <swift-infer> <SwiftProjectLint CLI> SwiftProjectLint
```

The join is each stub's first error in `packages[].set_aside` against the access note in the stub's
own header under `aside-SwiftProjectLint/`.

⚠ **Match the access note by its `// Access:` prefix, not by a phrase inside it.** The enclosing-type
remedy words it differently from the declaration remedy, and a phrase match is what misread the 5
above as a different symbol. The 22 September classifier was a session script over the same
`result-*.json` and `aside-*/` layout; the rule is in the section above.
