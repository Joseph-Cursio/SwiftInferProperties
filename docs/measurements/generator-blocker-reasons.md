# Why does no generator derive? Five causes, not one

> **Status:** `measured` · **As of:** 2026-09-19

**Instrument:** the emitted stubs themselves, after `GeneratorResolver.resolutionFailure` was
threaded into the `.todo` marker. Seven repositories, **768 markers**.

> **Answer: 92% of "missing generators" is two things that should NOT be built** — a type the
> scan never saw (51%, and 91% of *that* is one repository) and a class or actor, which
> memberwise derivation excludes by design (41%). The genuinely actionable remainder is **~35
> stubs across seven repositories**.

## The decomposition

| cause | count | share |
|---|---:|---:|
| `T` is not among the scanned types | **393** | 51% |
| memberwise derivation supports structs only (class/actor) | **315** | 41% |
| a stored property's leaf is not a recognised stdlib type | 22 | 3% |
| unexplained — the resolver had no failure to report | 25 | 3% |
| the user `init` declarations don't support derivation | 8 | 1% |
| ambiguous — more than one scanned type has that name | 4 | 1% |
| no user `init` derives | 1 | — |

## Why this could not be read before

Every stub rendered the same sentence. Measured on the 2026-09-19 corpus run: **656 markers, all
identical.** Five different problems were indistinguishable to a reader, to a `grep`, and to a
census.

**The kit had the answer and this repository discarded it.**
`GeneratorResolver.resolutionFailure(forTypeName:)` has returned one case per `nil` path since
**v4.7.0 — the version already pinned** — and `.noStrategy` carries the strategist's own sentence
verbatim. The kit's own commit measured the cost downstream, naming this repository: the
missing-generator census *"had to reconstruct two of the `nil` paths and guess the third, and left
370 of 2,016 unresolved types (18.4%) unexplained for that reason alone"*.

**Fourth time in this sequence that the fix is a RENDER, not a derivation** — after `__genMesh`
(240 → 160 errors), `willSet`/`didSet` (160 → 40) and the private carrier (40 → 0), all in
`kit-scaffold-conversion.md`.

## ⚠ The biggest bucket is one repository, and the lever for it is already priced

*Not among the scanned types* looks like a scanning gap that a wider scan would close. It is not:

| | |
|---|---:|
| SwiftProjectLint | **357 of 393 (91%)** |
| four other repositories | 36 |

The types are almost entirely SwiftSyntax nodes — `Syntax` 71, `FunctionCallExprSyntax` 53,
`VariableDeclSyntax` 28, `ExprSyntax` 27. This is the concentration
`corpus-funnel-census-2026-09-16.md` already warned about: *"a tool that analyses Swift code
naturally carries SwiftSyntax nodes as carriers, so this is not a general population."*

**And the lever exists and was measured.** `index --scan-dependencies` ships today, and wiring it
([#492](https://github.com/Joseph-Cursio/SwiftInferProperties/issues/492)) measured **3 rows
across two subjects** against the 159 first projected from this same data.

⚠ **Scanning them would not make them derivable anyway.** A randomly generated
`FunctionCallExprSyntax` is not a meaningful input to a property test. Bringing these types into
the universe moves them from *not in scope* to *no strategy*; it does not produce a law anyone
would run.

**This corrects a claim made while reading the first decomposition** — that widening the scan
might close the largest bucket. Measured, it is one subject's carrier vocabulary and a lever
already priced at roughly 50:1 against its projection.

## The second bucket is a stated boundary, not a gap

315 markers read *"memberwise derivation supports structs only (class/actor reference semantics
complicate the synthesized-init contract)"*. That is a design decision of the kit, not a missing
feature — and the stub now prints the exact signature to hand-write instead of leaving the reader
to infer one.

## What is actually actionable

**~35 stubs**: 22 whose stored-property leaf is unrecognised, 8 whose `init` is failable,
throwing, access-restricted or unsafe to call with independent arguments, 4 ambiguous names, 1
whose `init` takes a parameter that does not resolve. Small, specific, and each one now says which
member or parameter is responsible.

**25 unexplained remain**, where the resolver reported no failure at all — worth chasing, and far
smaller than the 370 this replaces.

## What would reverse this

A corpus whose *not in scope* types are ordinary value types rather than one tool's AST
vocabulary. The four non-SwiftProjectLint repositories contribute 36 between them, so that corpus
is not this one.

Re-run: emit stubs with `discover --include-possible --interactive`, then
`grep -rho "no generator derived — [^;]*"`.
