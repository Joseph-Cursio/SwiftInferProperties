# Carrying what a template matched — and is `guard-domain`'s writer feasible? (#477, #468)

> **Status:** `measured` · **As of:** 2026-09-15
> **Instrument:** `FunctionScanner.scanCorpus` + `TemplateRegistry.discover` over the twenty
> manifest corpora, in process. Every figure counted in python from one scan.

**Four templates computed a structured match, rendered it into a sentence, and dropped it.** This
carries the match as data, and measures whether the one template with a population worth a writer
can actually have one.

---

## 1. What was being discarded

| template | computed | where it went |
|---|---|---|
| `guard-domain` | condition, returned expression, quantified parameter, guard direction | one signal detail |
| `selection-subset` | container type, collection member, element type | a caveat sentence |
| `diff-disjointness` | diff type, member pair, element type | a caveat sentence |
| `partition` | tiler form, tiler, index parameter, progress member | two signal details |

A writer had two options: parse the sentence back apart, or emit nothing. **It emitted nothing** —
`guard-domain` alone was 62 declined suggestions in the corpus funnel census, the largest
population of the nine templates #468 found without a writer.

Parsing it back is the option that must not be taken, and this project has recorded the shape
often enough to name it: *a measurement that pattern-matches on text measures the text.*
`Evidence.parameterTypeNames` exists for exactly this reason on the evidence side.

## 2. What shipped

`Suggestion.match: TemplateMatch?`, threaded through `Constraint` and `ConstraintRunner`, set by
each template **at the point it already computes the value** — so the payload and the prose are
built from one value and cannot disagree. A test asserts that agreement rather than assuming it.

Three decisions worth naming.

**A closed enum, not four optional fields.** Per-template optionals would put four properties on
`Suggestion` of which at most one is ever non-`nil`, with nothing saying so. The enum says *exactly
one template's match, or none*, and a writer cannot read `partition`'s fields off a `guard-domain`
row.

**One definition per payload, not a mapping layer.** `SelectionSubsetTemplate.Match` and
`DiffDisjointnessTemplate.Match` became typealiases to the Core types, and
`PartitionShape.TilerForm` a typealias to `PartitionTilerForm`. A mapping between a template's
private struct and a carried twin is a second place for the same rule to live, which is the
drift trap the module-qualified leaf-spelling fix already paid for once.

**No `FunctionSummary` crosses onto the `Suggestion`.** `PartitionShape` holds two whole summaries;
`PartitionMatch` holds names. That is `Evidence`'s own rule — *captured as text rather than a
pointer back to the `FunctionSummary` so renderer output is decoupled from the parsing pipeline* —
applied one layer out.

### It populates, and it populates exactly where it should

One scan over the twenty manifest corpora, every suggestion classified by template and by whether
it carries a payload:

| template | rows carrying a payload | rows carrying none |
|---|---:|---:|
| `guard-domain` | **156** | **0** |
| `partition` | **2** | **0** |
| every other template (37 of them) | 0 | 6,042 |

**The zeros in the right-hand column are the assertion.** A template wired in one place and not
another would show as a split, and none does. `selection-subset` and `diff-disjointness` produce
no rows at all here — they are two of the four the catalog-health census records as still
unwitnessed on this corpus list — so their payloads are carried and unexercised, which is stated
rather than hidden.

**`guard-domain`'s 156 reproduces the independent reading below to the row.** One instrument reads
`bodySignals.guardDomain` off the scanned summaries; the other reads `Suggestion.match` off the
produced suggestions. They agree exactly, which is the cross-validation a single number could not
give.

**Total rows: 6,200 — unchanged.** This is additive: it moves no discovery output, so no
`*MeasuredTests` corpus baseline needed re-taking.

⚠ **Three of the four have a measured population of one or zero** (`selection-subset` 1,
`partition` 1, `diff-disjointness` 0 on the funnel census). They are carried anyway because the
cost is one enum case each and a seam built for one template looks arbitrary — **but their
presence is not evidence that a writer for them is warranted.** Read the population.

## 3. Is `guard-domain`'s writer feasible? — the numbers say yes, with three named jobs

`guard-domain` is the prize, and its writer's risk is specific: the condition and the returned
expression are **source text over the declaration's own names**, so a stub has to rebind them.

**156 statable sites across the 20 manifest corpora** (166 matched; 10 are `throws`/`async`/
`mutating`/`Void` and the template declines them). That is a larger population than the funnel
census's 62, because it is a different and wider corpus universe.

### What the returned expression is

| | sites |
|---|---:|
| a literal (`nil`, `[]`, `0`, `false`, `true`, `.case`) | 64 |
| the parameter, or an expression over it | 20 |
| mentions `self` | 57 |
| mentions `Self` | 8 |
| other | 7 |

### Can a stub bind every name? — **129 of 156, 83%**

Counting the free identifiers in `condition + returnedExpression` and asking whether each resolves
to a declared parameter, `self`, `Self`, or a literal:

| | sites |
|---|---:|
| **every name binds** | **129** |
| has a free name a stub could not bind | 27 |

The 27 are almost entirely underscored internal storage and type references — `_fastPath`,
`_slowPath`, `_root`, `_count`, `_elements`, `_Chunk`, `_AttributeStorage`.

### The three substitutions, all mechanical

| substitution | sites needing it |
|---|---:|
| a parameter name → its drawn value | 147 |
| `self` → the drawn receiver | 57 |
| `Self` → the declaring type | 8 |

Spread over **14 corpora**, headed by swift-collections (34), swift-foundation (27),
swiftlang-swift (25), swift-project-lint (18) and this repository (13).

### A fourth job the issue did not name: the law is CONDITIONAL, so it can pass vacuously

The law asserts only on the sub-domain the guard carves out. A draw that never enters that
sub-domain satisfies it without checking anything — and one of the sampled conditions is
`self === other`, which independent draws reach approximately never.

**That is the same failure `checkStrictWeakOrderingLaws` guards against** by reporting a
conditional law that was never applied through `Issue.record` rather than passing it. A
`guard-domain` stub needs the same guard, or it ships a green tick that means nothing — which is
the `mimeType_idempotence` shape (#453) this project already has on record.

## 4. What this measurement does NOT say

- **It does not say 129 stubs would compile.** Binding every *name* is necessary and not
  sufficient: the subject still has to be visible to a `@testable import`, and the receiver and
  parameter types still need generators. Both cut hard — the `filter-subset` writer measured
  **10 of 10 rows writing a file and 3 of 10 carrying a derivable generator**, and many of these
  sites are `internal` fast paths in swift-collections and swift-foundation.
- **It does not say the laws are worth having.** `guard-domain` is a **characterisation** law and
  its own caveat says so: it cannot fail against the code it was read from, so it finds no bug
  that exists today. It catches an edit. The stub header should say that, as the `TAUTOLOGY` line
  does for `determinism` — a reader who takes a green tick here for a correctness result has been
  misled by the tool.
