# Is the name really the contract? — `filter-subset` / `selection-subset` role-entailment (#476)

> **Status:** `measured` · **As of:** 2026-09-15
> **Instrument:** `swift-infer discover --sources … --include-possible` over the seventeen
> sibling repositories that resolve a `Sources/` directory, and
> `CatalogHealthCensusMeasuredTests` over the twenty manifest corpora. Same binary either side
> of the change; both universes re-taken rather than carried.

**Two files classified these templates in opposite directions, and the tie was broken by a
counterexample rather than by argument. The standard was right and the GATE was wrong.**

---

## 1. The contradiction, and where it reached a reader

- `FilterSubsetTemplate` and `SelectionSubsetTemplate` both called the law a **name-conjecture**,
  and `FilterSubsetTemplate` said so explicitly: *"It is not marked role-entailed for exactly this
  reason: a correct `map` would fail it."*
- `Refutability.roleEntailedTemplates` listed **both**, under *"the NAME is the contract, so a
  correctly-named implementation cannot fail the law."*

`Refutability` is the one that runs, and since #462/#466 it decides more than a display order: the
stub header (`ENTAILED — a correct implementation cannot fail this` against `CONJECTURE — a CORRECT
implementation can fail it`), `isWorthSurfacingBelowCut`, and the seed-focus rescue. So a reader
got `SUBSET IS NAME-CONJECTURED … is a false positive` in the terminal and `ENTAILED` in the file
they kept.

**Chronology does not settle it.** Both templates landed on 2026-07-22 (`748dd81`, `288fdc4`); the
promotion to role-entailed came the same day in `52a16d79`, with a rationale and tests, and the doc
comments were never revisited. The prose is stale rather than a competing live position — but
staleness is not an argument for the set being right.

## 2. What settled it: a counterexample, in the corpus

`pbt-book/code/Sources/Ch17Templates/Templates.swift:107`:

```swift
/// The trap: reordering the composition introduces an order-dependence the parts
/// didn't have — filtering the raw values first changes which survive.
public func filterThenMap(_ values: [Int]) -> [Int] {
    values.filter { $0 > 10 }.map { $0 * 2 }
}
```

`[11] -> [22]`, so `Set(result) ⊆ Set(input)` is **false**. The function is correct and the name is
**honest** — it says *then map*. The shipped binary proposed the law anyway:

```
Template: filter-subset          Score: 35 (Possible)
  ✓ filterThenMap(_:) ([Int]) -> [Int] — …/Templates.swift:107
  ✓ Curated filter/selection verb match: 'filterThenMap' — it selects, so it owes `result ⊆ input`
```

on a run carrying **no `--include-possible`** — which is the role-entailed default path, not a
score cut. Confirmed directly against the predicate as well: `isFilter` true, `isRoleEntailed` true,
`isWorthSurfacingBelowCut` true.

This is the `get(key) -> key.count` counterexample, for a template promoted on the grounds that no
such counterexample exists. **One counterexample is all the claim can survive**, because
role-entailment is a universal: *no correctly-named subject can fail this law*.

## 3. The mechanism, and why it is specific rather than general

`filter-subset` matched `hasPrefix` against a lowered verb list. **A verb prefix does not bound a
compound name** — verbs lead in English method names and the tail can revoke what the verb
promised.

Contrast the sibling admitted under the identical standard. `caseiterable-key-injectivity` matches
`hasSuffix` against nouns (`…Key`, `…Identifier`, `…Slug`), where the matched token *is* the head of
the name and nothing can follow it. Its write-up already records the noun list being narrowed
(`name` excluded, because two cases sharing a label is ordinary code) — the same move, made once
before, on the noun side.

So the resolution keeps both templates role-entailed and makes the gate carry the weight the
standard puts on it.

## 4. What shipped

**`FilterSubsetTemplate.nameAnnouncesASecondOperation`**, applied by both templates:

- a **connective** token in the tail — `and`, `then`, `plus` — announces a second operation
  whatever it is. What it turns out to *be* does not matter: `sort` preserves subset and `map` does
  not, and the point is that the name no longer bounds the promise.
- a **transform verb** in the tail — `map`/`mapped`/`mapping`, `transform(ed)`, `convert(ed)`,
  `derive(d)`, `normalize(d)` (both spellings), `rewrite`/`rewritten`, `expand(ed)`.

Matched as whole camelCase tokens via `StreamConsumption.camelCaseTokens`, never as substrings —
the tokeniser the monotonicity subject census settled on, where an exact whole-name match missed
`_cos` and a substring match read `distance(to:)` as trig. `filterAndroidTargets` tokenises to
`android` and survives.

**The transform list is deliberately short.** The cost of a wrong entry is a real law withdrawn, so
only tokens with no plausible noun or adjective reading are admitted. `build`, `make`, `render`,
`format`, `compute`, `generate` and `resolve` are **excluded** — `filterBuildSettings` and
`filterRenderedLines` are ordinary filters whose tail is a noun phrase, and withdrawing them to
catch a hypothetical would be the Daikon trap relocated into the gate.

**`selection-subset` lost three verbs: `collect`, `gather`, `resolve`.** These name accumulation and
derivation, not choice among what a container already holds — nothing about
`collectParticipants(diagram)` or `resolveLinks(index)` promises the result's elements came out of
the container, so they could never carry role-entailment. `layer` / `chain` / `ancestor` /
`lineage` / `descendant` stay: each names a walk that *returns nodes of the structure it was
handed*, and `layerChain` is the subject the template was built for.

## 5. What it cost — measured on both corpus universes, same binary either side

### The seventeen sibling repositories — **12 rows → 11, exactly −1, and the −1 is the false law**

`swift-infer discover --sources … --include-possible` over every `Sources/` directory at depth ≤ 4
in the nineteen corpus-funnel subjects; seventeen resolve one (`SwiftMarkdownWiki` and
`MacCloud_client_MacOS` are Xcode apps with none). Same binary, the fix stashed and restored.

| | before | after |
|---|---:|---:|
| `filter-subset` | 11 | **10** |
| `selection-subset` | 1 | **1** |
| total | 12 | **11** |

Removed: **`pbt-book · filterThenMap · Templates.swift:107`** — and nothing else. Every other row
survives, named:

`filterReports` · `filterConcurrencyDiagnostics` (SwiftAssist) · `filterViolations` (the
SwiftLintRuleStudio road-test subject the template was built for) · `filterIssuesByEnabledRules` ×2
· `filter` (SwiftProjectLint) · `matching` (pbt-book) · `keep` ×3 (pbt-workbook-corpus) ·
**`layerChain`** (SwiftLintRuleStudio).

`layerChain` surviving is the load-bearing half of the `selection-subset` trim: it is the only
`selection-subset` row that exists anywhere, and dropping `collect` / `gather` / `resolve` did not
touch it.

### The twenty manifest corpora — **zero rows moved**

`CatalogHealthCensusMeasuredTests`, one scan each side, suite green both times.

| | before | after |
|---|---:|---:|
| total rows, all templates | 6,200 | **6,200** |
| `filter-subset` | 4 | **4** |
| `selection-subset` | 0 | **0** |

The four are `selectionSorted(_:by:)` (leaderboard-sort), `filter(_:to:declaredSubjects:)`
(this repo's own `SeedFocus`), `filter(_:fileContent:)` (swift-project-lint) and
`filterTemplates(_:)` (swiftlint-rule-studio). **No home baseline moves**, which is why this needed
no re-take of `AlgebraicSurveyCorpusMeasuredTests` or `batch3` — the trap the involution gate fell
into, where `batch8` was A/B'd and `batch4` was not.

⚠ **Read the manifest's zero as a fact about that corpus list, not as a fact about the rule.** The
manifest is Apple-adjacent library code and holds **no** name with a transform tail; the exhibit
came from teaching code. Sixth payment of *a census is only as wide as its corpus list* — and here
the two universes disagree in the informative direction, the wider-but-shallower one carrying the
counterexample the deeper one cannot.

## 6. What the population also showed, and is recorded rather than acted on

⚠ **`selectionSorted(_:by:)` is admitted by a coincidence, and its law happens to be TRUE.**
`hasPrefix("select")` matches the noun `selection` — as in *selection sort* — so the name promises
no selection at all. Subset nevertheless holds, because a sort returns a permutation, so this is
not a false law and not a defect. It is recorded because it is the same flaw as `filterThenMap` in
the other direction: **a verb-prefix match admits names that promise nothing**, and here it landed
on a true law by luck.

**The obvious fix is not available.** Matching the verb as an exact first *token* would exclude
`selection` — and would also exclude `filtered`, `filters`, `keeps` and every other inflection,
which are ordinary filter names. Prefix-on-first-token re-admits `selection`. There is no
tokenisation that separates them, so the shape is left alone rather than patched with a rule that
costs more than it buys.

## 7. What this does NOT claim

- **It is not a precision measurement of `filter-subset`.** 11 surviving rows were not hand-checked
  against their bodies; only the removed one was, and it was removed *because* it was checked.
- **`selection-subset` is n = 1 everywhere.** The verb trim rests on what the three removed verbs
  *mean*, not on rows it moved, because it moved none.
- **A gate cannot make the standard true, only keep it from being trivially false.** Role-entailment
  remains a universal claim over every correctly-named subject in every codebase, and one
  counterexample retires it. The standing obligation is now written where the set is declared, and
  `SubsetNameContractTests` holds the counterexample that was found.
