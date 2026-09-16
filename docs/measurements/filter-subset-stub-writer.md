# The `filter-subset` stub writer — does the law it writes run, and can it fail? (#476, #468)

> **Status:** `measured` · **As of:** 2026-09-15
> **Instrument:** a scratch SwiftPM package against the pinned kit (SwiftPropertyLaws `4.2.0`,
> swift-property-based `2.0.0`, Swift 6.3.3 from swift.org), plus `discover --interactive
> --dry-run` over the sibling repositories that carry `filter-subset` rows.

`#468` measured **244 refutable suggestions** reaching `default: return nil` in the accept
dispatch — *"no stub writeout available for template '…' in v1"* — **148 of them carried by
role-entailed templates**, the ones the tool itself privileges below the confidence cut.
`filter-subset` was 13 of that 148. `#476` blocked the writer on a classification question, because
the stub's own header depends on the answer (`ENTAILED` against `CONJECTURE`). That is settled:
the law is entailed, and `SubsetNameContractTests` holds the gate that keeps the claim true.

---

## 1. What the writer emits

For `Analyzer.filterViolations(_ violations: [Violation], allowed: [Int]) -> [Violation]`:

```swift
// Law class: ENTAILED — a correct implementation cannot fail this, so a pass is a
//            statement about the code.

// The element type's `Equatable` conformance is NOT verified by this tool. If this file
// does not compile, that is what to check first — the law is sound, the check needs `==`.
@Test func filterViolations_returnsOnlyElementsItWasGiven() async {
    …
    sample: { rng in
        let arg0 = ((zip(Gen<Int>.int(), Gen<Character>.letterOrNumber.string(of: 0...8))
            .map { Violation(line: $0.0, message: $0.1) }).array(of: 0 ... 8)).run(using: &rng)
        let arg1 = ((Gen<Int>.int()).array(of: 0 ... 8)).run(using: &rng)
        return (arg0, arg1)
    },
    property: { args in
        let selected = Analyzer.filterViolations(args.0, allowed: args.1)
        return selected.allSatisfy { args.0.contains($0) }
    }
}
```

Three choices in that are decisions rather than defaults.

### `contains`, not `Set` — `Equatable` is enough

`Set(result).isSubset(of: Set(haystack))` is the rendering #476 proposed and needs the element to
be **`Hashable`**. `result.allSatisfy { haystack.contains($0) }` states the identical law and needs
only **`Equatable`**. The two cannot disagree, and `Equatable` is satisfied by strictly more element
types, so the weaker constraint is the one taken — **no reach is spent on a conformance the law
does not need**. An empty result is vacuously a subset, which is correct.

### The draw is an array per collection argument, resolved at the ELEMENT

Asking the resolver for `[Violation]` answers `.todo`: the type universe holds a shape named
`Violation` and none named `[Violation]`. So a collection argument is resolved at its element and
wrapped in the kit's instance `.array(of:)` — the idiom `composeHomomorphismPass` and
`idempotence-lifted` already use, and the one that exists in every language mode (there is no
static `Gen.array`). Applied to **every** array argument, not only the haystack: a filter's other
arguments are collections just as often, and resolving one at its element while the rest fall to
`.todo` would be arbitrary.

### `0 ... 8`, so the empty input is reachable

A filter that substitutes a default, a sentinel or a fallback row when nothing survives is the most
likely way this law fails, and it only shows up on an input that selects nothing.

## 2. Does it run, and can it fail? — **yes to both, measured**

A scratch package, built and run against the pinned kit.

| arm | subject | result |
|---|---|---|
| control | `filterViolations` correct, `keep` correct | **compiles, 2 of 2 pass** |
| mutant 1 | `filterViolations` returns `[Violation(line: 0, …)]` when nothing survives | **RED**, counterexample printed |
| mutant 2 | `keep` returns `values.filter { $0 > 0 } + [-1]` | **RED**, counterexample printed |
| control, restored | both correct again | **2 of 2 pass** |

Both mutants are the bug classes the template's own caveat names — *"a `filter` that quietly maps,
appends a default, or reads from another source"*. **A passing law that cannot fail is worth
nothing**, which is why the control alone would not have been evidence.

⚠ **One mutant had to be rewritten to measure anything.** The first spelling of mutant 2 was
`values.filter { $0 > 0 }.map { $0 * 2 }`, and the run died with **SIGTRAP**: `Gen<Int>.int()` draws
full-range `Int`s and `$0 * 2` overflows. That is a fact about the mutant, not about the law — but
it is the same *generator draws outside the subject's domain* shape this project has now recorded on
`swift-system`, `Euclid` and the kit scaffold, arriving here in a scratch fixture.

## 3. The natural experiment — a corpus that ships its own bugs

`pbt-workbook-corpus` declares three `Keeper`s, one correct and two with bugs its own doc comments
describe. **All three were written to break `idempotence`, not subset**, which is what makes them a
better test than any mutant planted here.

| subject | body | subset law |
|---|---|---|
| `CorrectKeeper` | `input.filter { $0 % 2 == 0 }` | **passes** |
| `FlipSurvivorsKeeper` | `input.filter { … }.map { $0 + 1 }` | **FAILS** — fabricates elements |
| `DropFirstKeeper` | `Array(input.filter { … }.dropFirst())` | **passes** |

`DropFirstKeeper` passing is the informative cell. It *is* buggy — it drops a survivor per pass —
and it is **not** a subset violation, because everything it returns was in the input. A law that
went red on it would be a law that fires on the shape rather than on the claim. **The instrument
discriminates.**

⚠ **The three receiver generators were supplied by hand to run this** — see §4, which is
where the reason lives and where it is counted against the reach figure rather than hidden in it.

## 4. Reach — how many rows write a file, and how many of those compile

`discover --sources … --include-possible --interactive`, each scan given its own output directory,
over the five sibling repositories carrying `filter-subset` rows.

| | |
|---|---:|
| rows | 10 |
| **write a file** (was: *"no stub writeout available"*) | **10** |
| declined | 0 |
| …of those, carrying a **fully derived** generator | **3** |
| …carrying a `.todo` marker on at least one argument | 7 |

**Quote both numbers.** *Ten of ten write* is the gap #468 measured, closed. *Three of ten compile
as written* is what a reader actually gets, and the difference is entirely **generator derivation**,
which PRD §11 delegates to the kit and which this arm does not touch. Two causes, counted apart:

- **Five are the RECEIVER** — an instance method's own type. `WorkspaceAnalyzer` and
  `ContentViewModel` are stateful service and view-model types; the three `Keeper`s are **stateless
  structs**, and that case is a minimal, reproducible gap: a four-line probe shows
  `struct Stateless {}` resolving to `Stateless.gen() /* TODO */` while
  `struct HasMembers { let n: Int }` resolves to `Gen<Int>.int().map { HasMembers(n: $0) }`. A type
  with no stored members has the trivial generator `Gen.always(Stateless())` and is not given one.
  **Not fixed here** — it belongs to `DerivationStrategist`, it affects every template rather than
  this one, and the house rule is to call the kit rather than reimplement it.
- **Three are the ELEMENT**, all `LintIssue` — and that one is **an artifact of this measurement,
  not a tool gap**. `LintIssue` is declared in `SwiftProjectLintModels` while the scan was pointed
  at `SwiftProjectLintConfig`, so the type universe genuinely did not contain it. A whole-package
  scan would.

⚠ **The first run of this measurement shared one `--output-dir` across every repository**, so
`decisions.json` accumulated and later scans skipped suggestions already decided under an earlier
one. Caught by a count that disagreed with the discovery scan, re-run isolated. The instrument
answered *"how many rows are newly decided"* when the question was *"how many rows write a file"*:
the standing shape, paid again.

⚠ **And the first attempt to read the results used `grep` over output containing UTF-8 box glyphs**,
which returned empty where python counted three. Every figure above is counted in python.

## 5. What is NOT written, and why

**`selection-subset` still declines.** It is the sibling half of the same law and it is deliberately
out of scope here: its haystack lives *inside a container argument* (`result ⊆ ConfigTree.configs`),
so the stub has to reach a stored member rather than an argument, and it needs a generator for the
container rather than for a collection. It is **one row across every corpus measured**, so it is
left for a row of its own rather than built on a population of one.

**A `.notEquatable` element declines with a reason** rather than emitting a file that cannot
compile: a function type, `Any`, `AnyObject` or an existential cannot host value equality, so
`contains` cannot be spelled over it.

⚠ **That check is `EquatableResolver`'s corpus-INDEPENDENT half and nothing more.** The resolver is
built over an empty declaration list on purpose — the accept context carries `TypeShape`s rather
than `TypeDecl`s, so the corpus-derived arm has nothing to read — and the curated-shape veto is the
part that needs no corpus. A project type therefore reads `.unknown` and **emits**, which is the
caveat-don't-drop posture `EquatableResolver`'s own header records. The stub says so on its own
line, so a reader whose file will not build is told where to look rather than left to work it out.
