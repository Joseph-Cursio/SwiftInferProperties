# Which laws would have caught the bugs our laws missed? — the 25 law-blind mutants

> **Status:** `measured` · **As of:** 2026-09-25

The mutation check (`funnel-mutation-check.md`) found **25 mutants that changed the subject's output and
passed their law anyway**: the inputs reached the bug, and the law did not ask about it. Two measurements
since (`behaviour-law-funnel.md`, `boundary-reach.md`) both ended on the same conclusion: catching more
bugs needs different laws, not more reach. This names, for each of the 25, a law the code **owes** that the
mutant would break, groups them by shape, and sizes each shape before anything is built.

**A snapshot law is not the answer, and it would score 25 of 25.** DIVERGED means the output changed on a
drawn input, so recording today's outputs and comparing catches every one by construction — while pinning
every bug the code has today. Only laws a correct implementation owes are counted.

## The 25, by the law that would catch them

| shape | mutants | examples | the owed law |
|---|---:|---|---|
| **A. a ternary that swaps one literal** | 2 | `renderStateToken` (`name == "*" ? "[*]" : name`), `sanitizeLabel` (`raw.isEmpty ? "relates" : raw`) | `cond ⟹ f(x) == literal` — exactly `guard-domain`'s law, written as a ternary |
| **B. a string-rewrite postcondition** | 3–4 | `safeAlias` ×2 (a dropped / emptied `replacingOccurrences`), `parseCommaDelimitedList` (separator emptied) | the replaced token is absent from the output; no element contains the separator |
| **C. a predicate that agrees with something checkable** | ~5 | `isInstalled`, `isMatching`, `containsControlCharacters`, `includes`, `isSwift6OrLater` | agreement with a stdlib equivalent, or monotonicity over an ordering — each specific to its subject |
| **D. a syntax-tree predicate** | ~9 | `occurs`, `hasExemptMember` ×2, `isCoherentProjection` ×2, `delegatesToSelf`, `isFunctionLocal`, … | nothing nameable beyond examples — only a test's own witnesses pin the answer |
| **E. other** | ~4 | `camelCaseToKebab`, `suppressionKey` (collision-dependent), `sha256` (output shape), one `round-trip` over single-line input | case by case |

**15 of the 25 ran under `predicate` totality**, which cannot catch an inverted answer at all — the
mutation check's *inverting a predicate's answer changed output 12 times and was caught 0 times*.

## The mechanical shapes, sized

A text scan (labelled as such: a sizing pass, not a census), over the 20 resolving manifest corpora and the
19 funnel repositories, `Sources/` only:

| shape | raw candidates | for scale |
|---|---:|---|
| **A** — unary function whose whole body is a ternary naming its parameter | 23 + 27 | the existing `guard`/`if` early-return shape: 1,106 + 638 raw, which yields ~156 `guard-domain` rows after the reader's filters |
| **B** — a `String → String` replacement chain whose replacements cannot reintroduce a replaced token, or a `String → [String]` split on a literal | 2 + 9 replacement, 2 + 8 split (the lists overlap on SwiftProjectLint) | the replacement-chain census found 10 pure chains in app code |

Both are **small — on the order of 20 laws each once filtered** — and neither is where most law-blind
mutants live: the largest group (D, 9 of 25) has no law to template, and C is subject by subject.

## What is worth building, and what is not

- **A is the cheapest real law in reach.** `GuardDomainReader` reads a leading `guard` or `if` and never a
  ternary, so `name == "*" ? "[*]" : name` is invisible to a law already written, already emitted and
  already guarded against passing vacuously. Reading the ternary reuses the whole writer. Against the two
  mutants it would fail as soon as `"*"` (a subject literal) or `""` (an edge token) is drawn. ~20 laws.
- **B needs a new template** for a similar population. Worth it only after A shows what such a law buys.
- **C and D are not templates.** C's laws are specific to each subject; D's only witnesses are the
  examples a test already asserts, which a lifted law would re-check rather than add.

**The honest summary: there is no large family of missed bugs waiting behind one law.** The law-blind
mutants spread over five shapes, the two mechanical ones hold ~20 laws each, and the biggest group has no
general law at all.
