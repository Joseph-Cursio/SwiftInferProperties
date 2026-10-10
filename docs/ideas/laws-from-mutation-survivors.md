# Candidate laws suggested by the SwiftUMLBridge mutation survivors

> **Status:** `proposed` · **As of:** 2026-10-10

Ten laws the catalogue does not have, each chosen because it would have caught specific mutants in
[`roadtest-swiftumlstudio-mutation.md`](../measurements/roadtest-swiftumlstudio-mutation.md).
They are listed by how much they would have caught in that run.

**Three entries are measured**: #8's reach check (the F2 A/B: 16 → 20 kills), and #3 and #4, prototyped
by hand on SwiftUMLBridge (see [Measured](#measured-2026-10-10-prototypes-of-3-and-4)). For every other
entry, the mutants it would catch are reasoned from the survivors and have not been run.

Each entry gives the law, the **signal** that lets the tool find candidate functions, the
**evidence** from the run, and the **closest existing** template.

## 1. Rendered output is well-formed

`renderSVG(x)` parses as XML; Mermaid and PlantUML output has matching start and end markers.

- **Signal:** returns `String` (or `[String]` that is joined), and the body contains format literals such as `"<svg"`, `"</svg>"`, `"@startuml"`, `"erDiagram"`.
- **Evidence:** catches mutants that delete an `append`, like `lines.append("</svg>")` in `ComponentSVGRenderer.renderSVG`, which guard-domain lets through (F5). Emitters are where most of SwiftUMLBridge's untouched mutants are.
- **Closest existing:** none. `rewrite-postcondition` checks text, not structure.

## 2. Every input element appears in the output

For each node or edge name in the input, `output.contains(name)`. A stronger form counts them: n input nodes give n `<rect` lines.

- **Signal:** a loop over an input collection that appends to the output.
- **Evidence:** catches removed or skipped appends, and conditions negated inside loops.
- **Closest existing:** loosely `bulk-incremental-agreement` and the conservation interaction family, but neither applies to emitters.

## 3. Output is accepted by the type it is meant for

`NSRegularExpression(pattern: globPatternToRegex(g))` does not throw. The same idea covers `URL(string:)`, `UUID(uuidString:)` and `JSONSerialization`.

- **Signal:** returns `String`, and the name or doc names the target format (`regex`, `url`, `json`, `pattern`).
- **Evidence:** law G2 in [`roadtest-swiftumlstudio.md`](../measurements/roadtest-swiftumlstudio.md); no existing template can propose it.
- **Measured:** **refutes the real code.** `globPatternToRegex("a[^\\")` is not a valid regex: brackets pass through unescaped by design, so an unbalanced one breaks the pattern. (`}` is now escaped; G2's `a}b` no longer refutes.) On bracket-free globs the law holds and kills 5 of 6 hand mutants, matching the hand-written suite.
- **Closest existing:** none.

## 4. IDs and aliases never collide

`x != y ⟹ mermaidId(x) != mermaidId(y)` over the generated inputs.

- **Signal:** `String -> String` named `*Id`, `*Alias`, `slug`, `identifier`, or `key`.
- **Evidence:** the point of a diagram ID is that it does not collide. Sanitizers that collapse characters (`a-b` and `a_b` both become `a_b`) silently merge two nodes. It is a conjecture and is likely refutable, which is what a law should be.
- **Measured:** **refutes the real code and found a real defect.** `mermaidId(">->") == mermaidId("-..")` and `safeAlias(" ") == safeAlias("+")`. Through the emitter, `Outer.Inner` and `Outer_Inner` were declared under one Mermaid id and drawn as one node. Fixed in [SwiftUMLStudio#52](https://github.com/Joseph-Cursio/SwiftUMLStudio/pull/52). It kills no hand mutant, by construction: dropping a replacement makes a sanitizer *more* injective.
- **Closest existing:** `caseiterable-key-injectivity`, which covers enums only.

## 5. Deduplication laws (`dedupe`, `unique`, `distinct`, `removingDuplicates`)

- No two output elements share a key.
- The set of keys in the output equals the set of keys in the input.
- The output is a subsequence of the input, so first occurrences are kept in order.

- **Evidence:** F3. Each mutant that turned `CoreDataModelExtractor.dedupe` into the identity or into `[]` passed idempotence; the second law alone catches all of them. It needs a generator that produces duplicates (element-level `CollisionBias`).
- **Closest existing:** `selection-subset` covers the third law only.

## 6. A sanitizer leaves already-safe input unchanged

If `x` already uses only the allowed characters, then `f(x) == x`. Pair it with the existing "output contains no forbidden characters" postcondition.

- **Signal:** the body filters or replaces against a character set (`CharacterSet.alphanumerics`, a replacement list).
- **Evidence:** catches the `ERScript.sanitizeType` mutant that always returns `"Unknown"` (L178). Idempotence lets that through, because a constant is idempotent.
- **Closest existing:** `idempotence` and `rewrite-postcondition`. This adds the half that stops the function from simply discarding its input.

## 7. Thresholds in the body (`count > N`, truncation)

- If `x.count <= N`, then `f(x)` equals the normalized `x`.
- `f(x).count <= N + len(ellipsis)`.
- Generators should draw lengths `N-1`, `N` and `N+1`.

- **Signal:** an integer literal compared against `.count`, followed by `prefix` / `dropLast` / `"…"`.
- **Evidence:** F4. The `ActivityGraphBuilder.compactText` `> 80` → `>= 80` mutant survived both suites.
- **Closest existing:** `documented-range` reads ranges from docs; this reads literals from the body.

## 8. A `contains`-based predicate splits over concatenation

If `P(xs) = xs.contains { … }`, then `P(xs + ys) == P(xs) || P(ys)`. For `allSatisfy`, use `&&`.

- **Signal:** a `Bool` body that is just `contains(where:)`, `first(where:) != nil` or `allSatisfy`. That describes `isStaticOrClass`, `isStatic` and `hasAttribute`.
- **Evidence:** F2. It replaces the `predicate` template's totality law, which no non-crashing mutant can fail (0 of 16 killed), with one that catches negations and `||` → `&&`. Ship it with the outcome-reach check. In the A/B, adding that check to the 3 predicates whose generators already reach `true` raised kills from 16 to 20.
- **Closest existing:** `homomorphism`, with `(Bool, ||)` as the target.

## 9. Layout geometry

- Every node rectangle lies inside the canvas size.
- No two node rectangles overlap.
- The first and last points of an edge lie on its source and target nodes.
- Adding a node never shrinks the canvas.

- **Signal:** returns rectangles, points or sizes, or is named `computeLayout`, `layout`, `edgePoint`.
- **Evidence:** F6, 460 mutants in functions that currently get only a determinism advisory. This is a new family, not a variant of an existing template.

## 10. A name generator never repeats

Calling `uniqName` n times returns n distinct values.

- **Signal:** a method with side effects whose name contains `uniq`, `fresh`, `next`, `generate`.
- **Evidence:** `DiagramContext.uniqName` was seeded, but nothing was proposed for it. It holds 22 mutants, and the hand-written suite kills most of them.
- **Closest existing:** fits the interaction families (cardinality).

## What to do first

- **#3** and **#4** are the most likely to find real defects rather than just catch mutants: #3 already has a predicted witness, and #4 targets a common way diagram tools break.
- **#5–#8** are cheap upgrades to templates already emitted, and they directly fix the weaknesses the run measured.
- **#1, #2 and #9** cover the most code, but they need new detection work.

## Measured 2026-10-10: prototypes of #3 and #4

Hand-written stubs on SwiftUMLBridge (SwiftUMLStudio `e36da59`), 1,000 trials each, run in the
funnel's scratch tree beside the 35 passing generated laws.

**swift-mutation-testing could not measure them: it generates no mutants in `globPatternToRegex`,
`mermaidId` or `safeAlias`.** Each is a chain of `replacingOccurrences` calls on string literals, and
the tool has no operator for a string literal or a dropped chained call. So kills were measured on
**15 hand-applied mutants** of that kind, the method `scripts/mutation_check.py` uses:

| Mutants | Law #3 | Existing generated laws | Hand-written suite |
|---|---|---|---|
| `globPatternToRegex` G1–G6: escapes dropped from the class, escape template broken, `?` replacement dropped, anchors dropped | **5 of 6** | none passing | 5 of 6 |
| `mermaidId` M1–M5: one replacement dropped each | – | **5 of 5** | 2 of 5 |
| `safeAlias` S1–S4: one replacement dropped each | – | **4 of 4** | 2 of 4 |

- **Law #3 matches the hand-written suite.** Four of its kills are its own (escapes dropped from the class, the escape template broken, the `?` replacement dropped). The anchors-dropped mutant is caught only because an empty glob then yields `""`, which `NSRegularExpression` rejects. Both miss the mutant that stops escaping `.`: an unescaped `.` is still valid, so catching it needs a law about what the regex *matches*.
- **The existing `rewrite-postcondition` laws beat the hand-written suite, 9 of 9 against 4 of 9**, on code the mutation tool cannot see. So the road test's 1.3% understates the generated laws on string-transform code.
- **#4's value is the defect, not kills:** a real, user-visible merge of two diagram nodes (fixed in [SwiftUMLStudio#52](https://github.com/Joseph-Cursio/SwiftUMLStudio/pull/52)).

The stubs and the hand-mutant driver lived in a session scratchpad and are not kept.
