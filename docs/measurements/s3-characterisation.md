# S3 characterised — the catalog reads signatures, the missing laws are in bodies (2026-09-13)

> **Status:** `measured` · **As of:** 2026-09-13
> **Method:** [`docs/plans/corpus-pipeline-walk-scope.md`](../plans/corpus-pipeline-walk-scope.md)

S3 is *"catalog gap — no template names the shape"*. After two subjects it holds
**21 rows**, and the walk's stop rule — *"a stage is worth a fix when it has three
rows across two subjects"* — is satisfied. Thirteen filings have shipped and not
one of them touched it; every one was plumbing between the catalog and the
compiler.

This reads the 21 together and asks what they have in common.

## They are not a grab bag. Three shapes cover 17 of 21.

**A — the output is part of the input** (4)
`P2` body is a suffix of the source · `Q2` result is a suffix of the input ·
`L1` every range indexes back to its own literal · `R3` a match implies a
case-insensitive substring.

**B — every element of the output satisfies a predicate** (7)
`T1` location ≥ 0 · `T2` length ≥ 0 · `T3` location + length ≤ bound ·
`P3` no tag is empty and each equals its trimmed self · `P4` the title never
begins or ends with a quote · `L3` no capture contains `[`, `]` or `|` ·
`G2` the output is a valid regex.

**C — on a stated sub-domain, the function is the identity or a constant** (6)
`P1` not front-mattered ⟹ the body is the source unchanged · `Q3` a `#` run
without a following space leaves the line alone · `Q4` seven hashes are
untouched · `Q5` a trailing newline survives · `T5` a range already in range is
returned unchanged · `R1` an empty query matches every node.

The remaining four are singletons: `L2` order and disjointness, `R2`
insensitivity to padding, `L4` a cross-function claim, `T4` idempotence.

## The finding: these are facts about BODIES, and every template reads a SIGNATURE

Cluster C is the clearest, because **the law is already written in the code, as a
guard.** Predicted by hand for `FrontMatter.parse(from:)`:

> `!s.hasPrefix("---")` ⟹ `parse(from: s) == (FrontMatter(), s)`

and the function's first line is

```swift
guard source.hasPrefix("---") else { return (Self(), source) }
```

Same for `GraphViewModel.matchesSearch`, predicted as *"an empty or
whitespace-only query matches every node"*:

```swift
let trimmed = searchQuery.trimmingCharacters(in: .whitespaces)
if trimmed.isEmpty { return true }
```

Neither was proposed. Both are readable without conjecture — **not guessed from a
name, stated by the author.**

Cluster B is the same story one level down. `T1` and `T2` — location and length
are non-negative — are not domain knowledge about ranges; they follow from
`max(0, …)` appearing twice in the body. `Q4` (six hashes, not seven) is `{1,6}`
in a regex literal. `P3` (no empty tag) is a `.filter { !$0.isEmpty }`.

Classifying all 21 by where the evidence lives:

| evidence | rows |
|---|---|
| **the body** | **15** |
| the docstring | 3 (`G2`, and `Q3`/`Q5` state theirs as well as implying them) |
| two functions at once | 1 (`L4`) |
| the signature — what the catalog reads | **2** |

**That is the shape of S3.** It is not that the catalog is small. It is that the
catalog is looking at the wrong half of the declaration.

## Measured: how big is the body-derivable population?

Across SwiftUMLStudio, SwiftMarkdownWiki, SwiftInferProperties and
SwiftProjectLint, non-test sources:

| | |
|---|---|
| functions scanned | 3 358 |
| opening with an early-return guard of any kind | 537 (15%) |
| **opening with a PREDICATE guard that returns a value** | **121 (3%)** |

The 15% is the wrong number and worth saying why: most are `guard let x = y else
{ return nil }`, which is optional propagation rather than a claim about the
function's domain. Filtering to a guard whose condition is a **predicate** — no
`let`, no `case` — and whose `else` returns a value leaves 121, and a random
sample of sixteen reads as the shape every time:

```
absolutePath:          relative.isRoot            ⟹ path
verifyEvidenceLeftPad: value.count >= width       ⟹ value
layout:                graph.nodes.isEmpty        ⟹ graph
promoted:              !(strong && bothPass)      ⟹ self
utf16Offset:           line < 1                   ⟹ 0
render:                advice.isEmpty             ⟹ ""
```

## The honest limit, stated before anyone builds it

**A law read from a guard is tautological against the code it was read from.**
It cannot find a bug that exists today; the guard satisfies it by construction.
What it catches is an **edit** — a later refactor that drops the guard, reorders
it after a mutation, or normalises the value it used to return untouched. That is
a characterisation test, and it is worth having, but it is a different claim from
what `predicate` or `comparator` make.

Two things follow from that, and both are the opposite of intuition:

1. **It is role-entailed, and unusually so.** `idempotence` is a conjecture read
   off a name, and a correct implementation can fail it — which is why it sits
   below the cut and why both of this walk's running laws were false alarms. A
   guard-derived law cannot be false of the code, because the code *is* its
   source. It can be shown above the cut without crying wolf.
2. **It needs no docstring and no generator insight.** The sub-domain is the
   guard's condition; the expected value is the guard's own `return`. Both are
   already in the syntax tree the scanner walks.

So the yield is not "finds bugs" — it is "states, as a runnable law, the
behaviour the author deliberately wrote and nothing currently protects."

## What this does not propose

Cluster A and the `L4` cross-function row are untouched by any of this. A body
can say `max(0, …)`; it does not say *"the result is a suffix of the input"* in
any form a scanner recognises, and that cluster needs either a docstring or
domain knowledge. `G2` likewise.

So closing cluster C would address **6 of 21 rows**, plus whatever share of the
121 corpus-wide sites is worth stating. It is the largest mechanically reachable
slice, not the whole of S3.
