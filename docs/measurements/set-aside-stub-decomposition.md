# What is actually stopping 171 stubs — the first error is not the blocker

> **Status:** `measured` · **As of:** 2026-09-20

The corpus funnel classifies a set-aside stub by **the compiler's first error**, and
`corpus-funnel-census-2026-09-20.md` reports the whole corpus that way: 190 `private`, 91 no
generator, 27 other. **A stub usually carries more than one blocker, and which one the compiler
reaches first is not which one you have to fix.**

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
