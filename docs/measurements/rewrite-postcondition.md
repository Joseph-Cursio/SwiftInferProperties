# The rewrite-postcondition law — built, and it catches the three mutants it targets

> **Status:** `measured` · **As of:** 2026-09-25

The second shape `law-blind-mutants.md` sized: a function that rewrites a string owes an output lacking
the tokens its own body removes, and three of the mutation check's law-blind mutants broke exactly that
while passing `idempotence` or `predicate` totality. Built after the ternary guard-domain law showed what
the first shape bought (`ternary-guard-domain.md`).

## The law

```swift
static func safeAlias(_ name: String) -> String {
    name.replacingOccurrences(of: "-", with: "_").replacingOccurrences(of: " ", with: "_")…
}
func parseCommaDelimitedList(_ string: String) -> [String] {
    string.components(separatedBy: ",").compactMap { …trimmed, or nil… }
}
```

state `!safeAlias(s).contains("-") && !safeAlias(s).contains(" ") && …` and *no element of
`parseCommaDelimitedList(s)` contains `","`*. A characterisation law like `guard-domain`: read from the
body, satisfied by today's code, catching an edit.

**Two shapes, deliberately narrow.** A pure replacement chain on a `String` parameter
(`ReplacementChainClassifier.steps`, the idempotence gate's own extraction); and a split on a literal
separator, optionally followed by one `map` / `compactMap` / `filter` whose closure only trims, tests
emptiness or drops the element.

## A false law, found by hand-checking the census, and the rule that replaced it

The first version decided which patterns a chain removes by **evaluating** it over short strings. Run
over the corpus it proposed that `stripMarkTags` never returns `<mark>` — **false**: removing an inner
`<mark>` from `<ma<mark>rk>` forms a new one, and a 12-character witness is far past what a bounded search
over an 8-letter alphabet can reach. Replaced by a rule that holds for every input: **a single character is
absent when a step replaces exactly it and no replacement from that step on contains it** — every
occurrence is rewritten away, nothing later writes one, and removing text joins characters but never
creates one that is gone. A longer pattern is never claimed.

## Measured

**Population: 6 laws across 33,150 functions** (the 20 resolving manifest corpora plus the 19 funnel
repositories, `Sources/` only) — 5 replacement chains, 1 split. The text scan had suggested ~20; the gap is
the reader's narrowness, which is the point. All six follow from the rule above; the four in SwiftUMLStudio
were also run against the real code and pass.

| subject | recorded mutant | old law | now |
|---|---|---|---|
| `ComponentScript.safeAlias` | drop the `" "` replacement | idempotence, DIVERGED — passed | **KILLED** at `"  -  -."` |
| `ComponentScript.safeAlias` | empty the `"-"` pattern | idempotence, DIVERGED — passed | **KILLED** |
| `parseCommaDelimitedList` | empty the `","` separator | totality, DIVERGED — passed | **KILLED** at `"ikA,fje."` |

The originals pass before and after. The counterexamples contain the replaced tokens because the String
carrier's generator draws the subject's own literals (kit 4.8.0) — a law about a token no input contains
would pass without checking anything.

⚠ **Not written for an instance method** — its receiver would have to be built too; the six found are all
static or free functions.
