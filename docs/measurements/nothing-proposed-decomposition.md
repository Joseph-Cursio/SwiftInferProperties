# "Nothing proposed" is not a catalogue gap — decomposing the funnel's 643 (2026-09-17)

> **Status:** `measured` · **As of:** 2026-09-17
> **Corpus:** the 19-repository corpus funnel of [`corpus-funnel-census-2026-09-16.md`](corpus-funnel-census-2026-09-16.md), same seeds, worktrees and `discover` output.

The corpus funnel scores a named seed as **nothing proposed** when no suggestion of any kind —
not even the `determinism` fallback — names it. The census reported it as the gap between
*named seeds* (2,723) and *any law proposed* (2,080): **643 seeds, 24%**, labelled *"No template
names the shape"* and owned by the catalogue.

**That label is wrong for almost all of it.** Most of the 643 are seeds the determinism
fallback was built to catch and turns away at one of its own gates; the largest single group is
computed properties, which the fallback rejects as if they had no input. The shapes no template
names are a far smaller, far more specific population, and §3 measures it.

⚠ **It did not move between runs, which is itself a finding.** 637 on 14 September, 643 on
16 September — `guard-domain` shipped in between and reached none of it.

## 1. Where the 643 go

`scripts/nothing_proposed_census.py` re-derives the stage and classifies every seed in it. It
finds **639**: four fewer than the census, because it also credits a seed whose stub is a
non-determinism template, where the census credited stubs of the tautology only.

| | seeds | mechanism |
|---|---:|---|
| **computed property, rejected by the no-parameters gate** | **428** | `makeSummary(fromComputedProperty:)` models a read-only getter as a **nullary** `self -> T` method, `parameters: []`. It reaches the fallback and fails `summary.parameters.isEmpty == false` (`Discover+GenericLaws.swift:129`) — a gate that exists because `f() == f()` states nothing for a free function. For a property **the receiver is the input**, and the gate cannot see it. |
| **same-named overload in the same file** | **90** | The fallback keys on `(file, symbol)` — the name without its parameters — and skips a key already `seen` or `covered` (`:53`). One overload claims the key; its siblings get nothing (`parseEffect` ×3, `execute` ×2, `refutation` ×2). **Inferred** from that code path plus co-occurrence — 90 of the 104 seeds that pass every gate share their name with another function in the file — and not yet A/B'd. |
| nullary method, same gate | 9 | The gate doing what it was written for. |
| passes every gate, no overload | 14 | Not traced one by one; they include `@MainActor`, generic, `@escaping`-closure and `@available(deprecated)` signatures. |
| `restricted-function` seeds | 91 | Not classified here. |
| `idempotency` seeds | 7 | Not classified here. |

### The join was checked before any of this was believed

The stage is a JOIN — seed `(basename, line)` against suggestion locations — and a blind join
reports every seed as nothing. Two routes could hide a proposal:

- **`determinism` rows print no source location**, so the census credits them through each
  stub's `// Source:` header. That route is sound: **1,083 proposals, 1,072 stubs, every stub
  with a header** — at most 11 seeds miscredited.
- **A collapsed row names one declaration for several** (*"Collapsed 6 suggestions over 6
  DIFFERENT declarations"*). Across the run, 13 collapsed rows hide **25** declarations, 10 of
  them lifted from tests rather than seeded.

So at most ~36 of the 643 are the instrument. The rest are real.

## 2. What fixing the two large buckets would buy — very little

**Both fixes land in the tautology.** The fallback proposes only `f(x) == f(x)`, which the funnel
already scores as a miss and `Refutability.tautologicalTemplates` lists. Admitting computed
properties would move ~428 seeds from *nothing* to *determinism only*: the funnel's `any` would
rise and `refutable` would not move. The overload key is a real correctness defect and small, and
it buys the same tautology for its ~90.

**State it as rows moved, never laws gained** — and here the ratio is not ~5:1 against, it is
∞:1: zero refutable laws for ~500 rows.

## 3. The 428 computed properties — what they compute, and what they owe

`scripts/computed_property_shapes.py` brace-matches each getter out of the source and assigns the
**first matching** body-shape rule; the rule order is part of the definition. **Hand-checked on a
seeded random sample of 24: enclosing type right 24 of 24, body shape right 23 of 24** — the miss
is `commandDefinitions`, an `allCases.map { … }` building dictionaries, filed under *formats a
string*.

| body shape | properties | share |
|---|---:|---:|
| **`switch self` — a per-case mapping** | **142** | 33% |
| forwards another member (`id → identifier`) | 82 | 19% |
| other multi-statement body | 41 | 10% |
| a boolean or comparison over other state | 40 | 9% |
| a literal constant (`false`, `.warning`) | 38 | 9% |
| other single expression | 33 | 8% |
| formats a string | 26 | 6% |
| derived from a collection | 26 | 6% |

By declared type: `String` 181 (42%), `Bool` 88, `String?` 45, another type 46, numeric 31,
collection 24. By enclosing declaration: struct 208, **enum 152**, class 39, extension 29. **78%
implement no protocol requirement** — they are the type's own API; the rest are `Identifiable.id`
(48), `LocalizedError` (27) and `CustomStringConvertible.description` (20).

**120 of the 428 are structurally law-less** — 82 forward a member and 38 return a constant. A
law over either restates the body.

### 3.1 The 142 per-case mappings

**107 map every case to a literal**, 35 compute at least one arm. Of the 107, none repeats a
value across arms and none has an empty-string arm — the 35 were not read for either. By what
the name says the value *is*:

| role | mappings |
|---|---:|
| label / message / icon (`displayName`, `icon`, `errorDescription`) | 82 |
| other | 44 |
| ordinal (`sortOrder`, `rank`, `trustWeight`) | 6 |
| a `Bool` predicate over the case | 5 |
| key-like — `CaseIterableMappingTemplate.curatedKeyNouns` | 5 |

**The obvious law is already a recorded decline, and it stays one.** Injectivity over a label is
not owed — *"two cases legitimately sharing a human-readable label is ordinary code, not a bug"*,
which is why `CaseIterableMappingTemplate` deliberately leaves `name` off its key nouns. 82 of the
142 are exactly that.

**A second tempting law is FALSE on this corpus**: *a per-case optional is never `nil`*. Nine
mappings return `nil` for some case, and every one reads as deliberate — the two `LocalizedError`
members (`recoverySuggestion`) answer only for `.notFound`, `disclosure` is `nil` for
`.available`, `previous` is `nil` for the first onboarding step, `indicator` is `nil` past the
access levels it draws. A template stating it would refute correct code.

### 3.2 What IS owed, and its size

Read case by case, the laws a correct implementation owes and nothing proposes:

| law | site | why it is owed |
|---|---|---|
| `a < b ⟺ a.rank < b.rank` | SwiftUMLStudio `DetectionConfidence.rank` | the type is **`Comparable`** and publishes its own ordinal |
| `x.next?.previous == x`, and the mirror | SwiftLintRuleStudio `OnboardingStep.next` / `.previous` | a pair of inverse moves on a **`CaseIterable`** enum — finite, exhaustively checkable |
| `init(rawValue: x.rawValue) == x` | SwiftProjectLint `PatternCategory.rawValue`, SwiftUMLStudio `Theme.rawValue` | a **hand-written** `rawValue`, which the compiler no longer keeps consistent with the initializer — if one exists |

**Four sites across 428.** The catalogue gap this stage was named for is real, and on this corpus
it is about **1%** of the population the label was attached to.

⚠ **Only the 142 mappings were read for owed laws.** The *boolean over other state* (40),
*derived from a collection* (26), *formats a string* (26) and *other* (74) buckets are sized by
shape and not read — a `var isEmpty: Bool` beside a `count` owes a consistency law, and none was
looked for here.

### 3.3 A defect in a shipped entailed template, found on the way

All five key-like mappings missed `caseiterable-key-injectivity` at its first gate — none of their
enums is `CaseIterable`. **But three of the five are named `symbol`, and all three return SF
Symbol names** (`"checkmark.seal.fill"`, `"exclamationmark.triangle.fill"`). An icon is a label;
two cases sharing one is ordinary. Yet `symbol` is a **curated key noun**, and the template sits in
`Refutability.roleEntailedTemplates` — so the day any of those enums conforms to `CaseIterable`,
the tool proposes a law a correct implementation can fail, under a header saying it cannot.

That is #476's mechanism at a second site: `subset-name-contract-gate.md` records that admitting a
name-gated template to the entailed set is *"falsifiable by one counterexample in any corpus"*.
Here are three. **Not fixed in this change** — narrowing a curated list withdraws rows and needs
the same-condition A/B across every survey that the involution gate skipped.

## 4. Recommendation

1. **Relabel the stage** wherever it is quoted: *nothing proposed* splits into *turned away by the
   determinism fallback* (527 of the 639: the 428 properties, 90 overloads and 9 nullary methods)
   and *no template names the shape* (bounded above by the 14 unexplained plus the unclassified
   98). Quoting 643 as a catalogue gap sends the next census after the wrong cause.
2. **Do not widen the fallback to computed properties to shrink this number.** It moves ~428 rows
   and adds zero refutable laws.
3. **Fix the `(file, symbol)` key** as a correctness defect, with an A/B confirming the 90.
4. **Remove or narrow `symbol` in `curatedKeyNouns`** (§3.3), with the A/B.
5. **The owed laws of §3.2 are three templates' worth of work for four sites.** Read the unread
   buckets before building any of them — the population may be larger there, or may not exist.

## Reproducing

```
python3 scripts/nothing_proposed_census.py <census-dir>    # §1 — writes <census-dir>/nothing.json
python3 scripts/computed_property_shapes.py <census-dir>   # §3 — writes <census-dir>/props.json
```

`<census-dir>` is the corpus funnel harness's directory (`seeds/`, `wt/`, `out/`). The harness is
still uncommitted, as the census page records; the two classifiers are committed because their
rules decide every count above.
