# Road test — SwiftProjectLint (2026-07-24)

Toolchain-facing summary of the **first scored** road test in this series. The
full record — answer key, per-candidate scoring, bugs, all nine prioritised
fixes — lives in the subject repository:

> `SwiftProjectLint/Docs/roadtest/README.md`
> answer key frozen at `9abcfde`, subject SHA `feeea0f`

This file records only what it changed *here*.

## What made it different

The MacCloud road tests asked "does the loop find bugs?" The SwiftLintRuleStudio
road test asked "why did it recommend so little?" and was explicitly **not
scored** — no answer key, because an answer key has to predate the tools.

This one is scored. A hand-written key of 10 law-bearing kernels (39 laws) was
committed to the subject repo **before** the first `discover` or `pbt-seeds` run,
with predictions logged in the same commit. Subject: `Sources/Core` plus seven
nested packages, ~37k lines, a compiler-adjacent codebase.

## The number

Of 10 keyed candidates, reached **with a refutable law**:

| Surface | Reached |
|---|---|
| `discover` default | **2** |
| `discover --seeds` (linter manifest) | **2** — seeding added 14 `f(x)==f(x)` and no new laws |
| linter seed manifest alone | **6** — 588 seeds |
| `discover --docstring-advice` | **8** |
| union of shipping surfaces | **9** |

The pre-logged prediction was 3. The default run gave 2.

**The finding is the spread, not the 2.** Every configuration in that table was
already shipping. The candidates were not out of catalog and not out of reach —
they were behind a flag nobody passes.

## What shipped from it

**`--docstring-advice` is now on by default** (`Config.docstringAdvice`, CLI
`--docstring-advice` / `--no-docstring-advice`, config
`[discover].docstringAdvice`; precedence CLI > config > default, mirroring
`includePossible`).

Read the justification narrowly. Appendix C labels this feature *built and
unverified* on the strength of a six-reader A/B that came back **flat on reader
lift** with a control arm that turned out contaminated — the baseline tool
already told every reader to state the reference definition. **That result is not
refuted here.** This is a different metric: *reach* against a frozen key —
candidates surfaced, not bugs found and not readers helped. The advisory still
hands over a sentence and says "encode THAT"; a human writes the property.

A capability worth +6 candidates on the one measurement we have should not be
opt-in. That is the whole argument, and it does not extend further.

## Findings not yet acted on

Ranked in the subject repo's write-up; the ones that land in *this* package:

2. **No `CaseIterable` type-level law family.** Two keyed candidates are
   `RuleIdentifier -> X` mappings over a 197-case enum whose laws are about the
   *mapping across all cases* (injectivity; no case falling into a sink), not
   about a function's inputs. One of them guards a **runtime trap**:
   `Dictionary(uniqueKeysWithValues:)` over the key mapping crashes on the first
   collision. Generator side is free — the engine already derives from
   `CaseIterable`. Also: for a finite case list the emitted check should be an
   **exhaustive loop**, not 100 sampled trials.
3. **`extractable-kernel` seeds are not analysable**, so `discover --seeds`
   cannot focus on them. Three keyed candidates die exactly here. This is
   Finding B's kind-granularity gap, reproduced on a fresh subject. Caveat before
   building: the kind is non-analysable *because* the symbol names the enclosing
   function — a location, not a subject — so splitting it is only safe where the
   linter can name the callable boundary itself.
4. **60% of suggestions print `not derived`.** Structural for this subject: the
   kernels take SwiftSyntax nodes, which no `Gen` constructs. The workaround a
   human reaches for immediately is to generate a *proxy* representation and map
   in (`String` → `Parser.parse` → `SourceFileSyntax`). The tool has no notion of
   that recipe; adding one would unlock most of the 60%.
5. **The advisory reads only the function's own docstring.** The best candidate
   in the key states its law in prose on the **type** doc and on a **private**
   helper; the public entry point's own docstring is uninformative. Hoist prose
   from the enclosing type and from private callees.
7. **A spurious `round-trip` pairing still gets through** — two unrelated
   `String -> String` functions paired on type symmetry alone. The label-stem
   admission gate does not cover this shape.
8. **The `--seeds` extractable-kernel advisory is not scoped to `--sources`** —
   identical 202-line output for four different scan scopes.

## Honesty note carried back

The frozen key was wrong in four places, all recorded rather than edited:
a keyed idempotence law that is false; an over-claimed exhaustiveness law the
compiler already enforces; a predicted defect that does not exist; and **two pure
kernels the key walked past that the tools found** — logged unscored, per the
Appendix C rule that a tool may not grade its own homework.

And the sharpest single result, which cuts against the templates rather than for
them: on the one keyed function that actually had a bug, the only law the
template catalog proposed — `T -> T` idempotence — **held under the bug and fails
under the fix**. It did not miss the defect; it ratified it. The law that found
the bug came from the docstring.
