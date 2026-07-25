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

## Also shipped — the `CaseIterable` mapping family (fix 2)

Two templates, wired as a shapes-aware pass:

- **`caseiterable-key-injectivity`** — a key-named mapping out of a `CaseIterable`
  enum into a scalar owes `Set(allCases.map(\.key)).count == allCases.count`.
- **`caseiterable-case-coverage`** — a classifier into another enum that carries a
  sink case (`other`, `unknown`, …) owes that the cases landing in the sink equal
  a written-down exception list.

Both are **name-conjectured and Possible-tier**, deliberately, and the reason is
the whole design: *a mapping out of an enum is usually many-to-one.* The subject's
own `category` maps 197 rules onto 11 categories — correct code that a naive
injectivity proposal would fail. So the two laws split on what the mapping is
*for*, read off the name and the codomain, and a test asserts they are mutually
exclusive.

The sink is **found, not assumed**: the template reads the codomain enum's own
case list and stays silent when there is no sink case to be false against.

Measured on the subject: **exactly 2 firings across ~37k lines**, both on the
candidates that motivated it (`suppressionKey` → injectivity, `category` →
coverage), zero false positives, and no cross-firing. The generator side was free
as predicted — `discover` resolves `.derivedCaseIterable` for these carriers with
no additional work.

Both caveat sets say the same load-bearing thing: **check it exhaustively, not by
sampling.** For a 197-case domain a `propertyCheck` has to be lucky to draw the
one colliding pair, and it reports success when it misses. This is the rare shape
where a loop strictly dominates a generator, and the emitted advice is the whole
product.

Only the injectivity half is admitted to `Refutability.roleEntailedTemplates`.
A member called `…Key` / `…Identifier` / `…Slug` claims to *identify* the case,
so a collision is a bug or a lie about the name — the same standard
`filter-subset` was admitted under, and the reason the noun list was narrowed
(`name` is out: two cases sharing a *label* is ordinary code). Coverage is
deliberately left below the cut, because routing cases to a sink can be entirely
correct and a law that cries wolf is worse than none.

Scored effect, without rewriting the frozen result:

| Configuration | On the day | Now |
|---|---|---|
| `discover` default (templates only) | 1 (K8) | **2** (K2, K8) |
| `discover --include-possible` | 2 (K8, K9) | **4** (K2, K8, K9, K10) |
| `discover` default, all surfaces | — | **9** (everything but K7) |

> **Correction.** The subject repo's write-up first gave the default run as
> 2/10. That was the `--include-possible` figure: K9's proposal is
> `idempotence`, which is Possible-tier and *not* role-entailed, so it is hidden
> on a default run. Caught while verifying this fix. Corrected there, with the
> two runs now on separate rows.

Fix 2 did not widen reach — the union across surfaces is unchanged at 9. It
moved two candidates into the catalog proper and promoted one above the default
tier cut. Robustness, not reach, and worth less than the headline sounds.

One unplanned interaction, in the good direction: once
`caseiterable-key-injectivity` became role-entailed, `suppressionKey` **dropped
out of the docstring advisory** (5 functions → 4). `DocstringAdvisor`'s fourth
rule already says that a self-contained role-entailed law serves the function
and that repeating the docstring would only cost trust. So the two surfaces
compose rather than double-reporting, without either knowing about the other —
which is a small piece of evidence that the role-entailment axis is carrying
real weight rather than being a visibility flag with a principled name.

## Findings not yet acted on

Ranked in the subject repo's write-up; the ones that land in *this* package:

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
