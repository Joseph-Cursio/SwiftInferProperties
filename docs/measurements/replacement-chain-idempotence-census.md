# Idempotence over a replacement chain — which escapers is it false for, and how many are there?

> **Status:** `measured` · **As of:** 2026-09-22

`funnel-mutation-check.md` §8 found six passing `idempotence` laws that are false, four of them
escapers: `HTMLEscaping.escape` rewrites `&` to `&amp;`, whose output contains `&` again, so escaping
twice escapes the escape. This sizes the population behind a proposed rule — *idempotence except for
escape* — before anything is built.

## The shape and the rule

**A pure replacement chain**: a `String -> String` function (or `var …: String`) whose whole body is
`x.replacingOccurrences(of: a₁, with: b₁)…replacingOccurrences(of: aₙ, with: bₙ)`. `idempotence`
applies to every `(T) -> T`, so under `--include-possible` every such chain is proposed the law.

**Whether the law is true is decided by EVALUATING the chain**, not by a text rule. The obvious rule —
*false when some replacement contains some pattern* — is wrong in one direction: `x → y` then `y → z`
has an output containing a later pattern and is idempotent, because the later step rewrites it in the
same pass. So `scripts/replacement_chain_census.py` checks `f(f(s)) == f(s)` over every string up to
length 3 drawn from the chain's own characters plus a neutral one — exact on that domain, and any
counterexample it finds is real. Six positive controls, including that `x → y → z` case, must all be
decided correctly before a number is printed.

## The census

| universe | files | pure chains | NOT idempotent | idempotent | replacement inside a longer body (not classified) |
|---|---:|---:|---:|---:|---:|
| manifest, 20 of 22 corpora | 2,929 | **0** | 0 | 0 | 10 |
| the funnel's repositories | 2,259 | **10** | **5** | 5 | 20 |

| chain | idempotent? | witness | literal-reach (§8, by execution) |
|---|---|---|---|
| `String.xmlEscaped` | ✗ | `"` | refuted |
| `ActivityScript.plantUMLEscape` | ✗ | `"` | refuted |
| `String.htmlEscaped` | ✗ | `"` | refuted |
| `HTMLEscaping.escape` | ✗ | `"` | refuted |
| `AuditEvent.markdownCell` | ✗ | `\|` | not run — Tuist repo, never emitted |
| `nomnomlEscaped` · `mermaidId` · `mermaidEscape` · `safeAlias` · `stripMarkTags` | ✓ | — | held, all five |

✅ **The evaluation and the execution agree 9 of 9** where both reach: every chain the census calls
not idempotent was refuted by drawing the subject's literals, and every one it calls idempotent held.
Two independent instruments, one answer.

## What it says

- **The population is small and it is APP code.** Zero pure chains in 20 library corpora; ten in the
  funnel's application repositories. Escaping for output formats — HTML, XML, PlantUML, Mermaid,
  Markdown tables — is what applications do and libraries leave to their callers.
- **Half the chains are escapers that re-escape, and half are sanitisers that do not.** The split is
  exact, it is decidable at discovery time by the same evaluation, and a gate on it **costs no laws**:
  the five idempotent chains keep their law.
- **The gate covers 4 of the 6 false laws §8 found, not all 6.** `GlobTool.translate` is a character
  loop and `KaTeXSchemeHandler.mimeType` a `switch` — false for the same underlying reason (the output
  is a different language from the input) but not replacement chains.
- **The law these ten DO owe is identity on input they have nothing to rewrite**: when `x` contains
  none of the patterns, `f(x) == x`. It holds for all ten by construction, and it is refutable — a
  change that also trims, lowercases or rewrites a safe character fails it.

## Recommendation

1. ✅ **Build the gate** — built, below: `idempotence` is not proposed for a pure replacement chain the
   evaluation shows is not idempotent. Zero cost in laws, measured; four known false laws withdrawn. The same posture
   as the availability gate, which shipped on 24 rows because it cost none.
2. **Hold the new law** until it has more than ten subjects. It would be proposed for ten functions in
   four repositories, all application code; a template for a ten-row population is the Daikon trap
   the catalogue avoids.

## Built: the gate

✅ **Shipped 2026-09-22.** `ReplacementChainClassifier` runs the same evaluation at discovery time and
returns `IdempotenceReturnShape.reappliesItsRewrite(witness:)`; `idempotence`'s existing return-shape
veto withdraws the law and names the witness. Computed properties gain **only this arm** — they had
carried no body signals at all, which is how `xmlEscaped` and `htmlEscaped` escaped the veto — so the
existing `.extendsInput` veto is not switched on for properties by this change.

**Same-source A/B**, `discover --include-possible` over every source directory of the funnel's 14
repositories, a binary from `main` against the gated one: **79 directories, 75 byte-identical. Exactly
the five chains this census calls not idempotent lost their `idempotence` suggestion — `xmlEscaped`,
`plantUMLEscape`, `htmlEscaped`, `HTMLEscaping.escape`, `markdownCell` — none was added, and the five
idempotent chains kept theirs.** Full `make test` green with every batch count unchanged (4 · 111 · 31 ·
7 · 14 · 4 · 9 · 35), as a manifest with zero pure chains predicts.

## Reproducing

```
python3 scripts/replacement_chain_census.py
```

It needs the manifest corpora and the funnel repositories checked out as siblings; it runs its
controls first and stops if any is decided wrongly.
