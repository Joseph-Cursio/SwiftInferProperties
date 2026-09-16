# The `guard-domain` stub writer — does a characterisation law catch an edit? (#468)

> **Status:** `measured` · **As of:** 2026-09-15
> **Instrument:** a scratch SwiftPM package on the pinned kit (SwiftPropertyLaws 4.2.0,
> swift-property-based 2.0.0, Swift 6.3.3 from swift.org) for the behaviour arms, plus
> `discover --interactive` through the real accept path for reach.

**62 declined suggestions across 14 repositories — #468's largest writerless population.** #477
carried the match; this writes the law. It is the only arm in the catalogue whose law is **source
text the tool did not write**.

---

## 1. The three substitutions, and the one the issue did not name

The condition and returned expression are spelled in the declaration's own scope. A stub has
different names for the same values, so every free name is rebound: a parameter to its drawn value,
`self` to the drawn receiver, `Self` to the declaring type. `GuardDomainRebinding` owns that
rewrite and refuses three corruptions a naive `replacingOccurrences` causes — substrings of longer
identifiers, member names after a dot, and text inside string literals.

**A fourth substitution was needed and is not in #477's list: a type named in the subject's own
signature binds to itself.** The template's *documented example* returns `(FrontMatter(), source)`
— the concrete type, not `Self` — so without it the writer declines the case the template was built
for. It is sound because a test that can call the function can already name every type in its
signature. Scoped there deliberately: binding every capitalised name would admit `StmtSyntax`,
`NSData` and `_AttributeStorage`, from modules the stub does not import.

## 2. The law is CONDITIONAL — and the coverage guard is not optional

This law says nothing outside the sub-domain its guard carves out, so **a draw that never enters
the sub-domain passes without checking anything.** One condition in the measured corpus is
`self === other`, which independent draws reach approximately never.

The emitted stub counts entries over the **same four seed words** the check uses, and reports
`NOT APPLIED` when the count is zero. Verified on a subject built to be unreachable
(`guard value != 424242`):

```
✘ sentinelled_holdsOnItsGuardedSubDomain()
↳ NOT APPLIED — no draw entered the sub-domain in 100 trials, so the pass below means nothing.
  The law is: !(value != 424242) ⟹ Sentinel.sentinelled(_:) == -1.
```

Without it the same subject is a silent green tick — the `mimeType_idempotence` shape (#453), a law
that passed 100 trials while being false because its counterexamples were outside the generator's
reach.

## 3. Does it catch an edit? — **yes, and the true negative is the informative half**

`guard-domain` cannot find a bug that exists today; the guard satisfies its law by construction. The
claim is that it catches an **edit**. Measured against the two edits the template's own caveat
names:

| arm | edit | result |
|---|---|---|
| control | none — three subjects, all correct | **3 of 3 pass, all compile** |
| edit 1 | `guard scale > 0 else { return 0 }` → `return 1` — *"normalises the value it used to return"* | **RED**, law stated, counterexample given |
| edit 2 | `if self.items.isEmpty { return other }` **deleted** — *"a refactor that drops the guard"* | **passes** |
| control, restored | — | **3 of 3 pass** |

⚠ **Edit 2 passing is correct, and it sharpens the template's own caveat.** `Bag.merged`'s guard is
a redundant fast path: concatenating an empty array gives the same answer, so deleting it changes
no behaviour and no law should fire. A test that went red there would be firing on the guard's
**presence** rather than on the **answer** it names.

So the caveat's *"a refactor that drops the guard"* is true only when dropping the guard changes
the answer. **This template characterises the guarded answer, not the guard.** That is a narrower
and more honest claim than the one the template has been making since it shipped.

## 4. A hole in `GuardDomainReader`, found by measuring

`GuardDomainReader.mentionsOnly` already enforces the rule this writer needs — *"type names are
permitted because a test that imports the module can name them; lowercase free identifiers are
not"* — and it has a gap:

```swift
if !previousWasDot, current.first?.isLetter == true { free.insert(current) }
```

**An identifier starting with `_` has no first letter, so it is never counted as free.**
`_fastPath(value > 0)`, `_root`, `_count`, `_elements` and `_createCFStringFromASCIIString` all pass
a gate written to exclude exactly that shape. This is the whole of the 27-of-156 gap the #477
feasibility measurement found, arriving from the other side.

**Not fixed here, deliberately.** The reader is discovery: closing it removes rows from `discover`
output, which needs a same-condition A/B across *every* `*MeasuredTests` corpus survey — the
mistake the involution gate made when it A/B'd `batch8` and not `batch4`, leaving `main` red for
four commits. The writer declines those rows today with a named identifier, so no uncompilable stub
is emitted; the reader fix is a row of its own, and it is a **withdrawal** (fewer rows), like the
availability gate.

## 5. What this does NOT claim

- **Not that these laws find bugs.** They cannot, by construction. The emitted header says so in
  its own words — a new `CHARACTERISATION` law class, because the existing `ENTAILED` line
  ("a pass is a statement about the code") is false here and would mislead a reader who took a
  green tick for a correctness result. `Refutability.characterisationTemplates` is where that
  lives, a strict subset of the role-entailed set distinguished by what a **pass** means.
- **Not that every written stub compiles.** See §6 — 29 of 51 carry a `.todo` generator, and
  visibility is unmeasured here.

## 6. Reach — two readings, each with its instrument named

**Neither number is "the" reach, and quoting one without its instrument would be the shape this
project keeps recording.**

### All 20 manifest corpora, calling the arm directly

`entailedTemplateStub` over every `guard-domain` suggestion the registry produces, in process.

| | |
|---|---:|
| rows | 156 |
| **write a file** | **135** |
| declined, naming the identifier | **21** |

The 21 are `_fastPath`, `_slowPath`, `_root`, `_count`, `_elements`, `_predicate`, `_parseInfo`,
`_createCFStringFromASCIIString`, `_Chunk`, `_AttributeStorage`, `_CalendarGregorian`, `NSData` —
§4's reader hole, declined one at a time with the name in the sentence.

⚠ **This reading passed `customGenerator: nil`**, which is not what the CLI does, so its generator
figure would be a fact about the probe. It is not quoted.

### Six sibling repositories, through the real accept path

`discover --include-possible --interactive`, each scan its own output directory, so the
`GeneratorResolver` is supplied exactly as a user's run supplies it.

| | |
|---|---:|
| rows | 51 |
| **write a file** | **51** |
| declined | 0 |
| …of those, **fully derived** generator | **22 (43%)** |
| …carrying a `.todo` | 29 |

**43% derived is the best any writer in this line of work has measured** — `filter-subset` read 3
of 10. Zero declines here because these repositories do not carry the underscored-internals shape;
that shape is concentrated in `swiftlang-swift`, `swift-collections` and `swift-foundation`, which
the manifest reading covers and this one does not. **The two readings disagree on declines for a
reason, and the reason is the corpus list.**

⚠ **Written is still not compiling.** 29 of 51 carry a `.todo` generator, and visibility has not
been measured here at all. The end-to-end arms in §2 and §3 are four hand-built subjects, which is
where the *behaviour* claims come from and is not a reach claim.

## 7. Two guards that fired during this work, and what each says

**`LawClassLineTests` caught the new law class.** It is parameterised over template names and reads
the classification from `Refutability` rather than restating it, so adding CHARACTERISATION made it
red immediately — the four-way form now asserts the **precedence** as well, because characterisation
is a strict subset of role-entailed and the more specific line has to win. A `guard-domain` stub
labelled ENTAILED would tell a reader *a pass is a statement about the code*, which is the one
thing it is not.

**`GuardDomainRebindingTests` caught a numeric-literal bug before any corpus run.** `0x2F` scans as
the digit `0` followed by something beginning with a letter, so a scanner that only special-cases
identifiers reads `x2F` as a free name and declines a site over a hex literal. That is the kind of
defect a 156-row corpus pass would have reported as *declined* without ever saying why.

⚠ **A third defect was caught by neither, and only by compiling the output.** The law is the
author's own source text and it contains quotes: the documented example
`!(source.hasPrefix("---")) ⟹ …` closes the `Issue.record` string literal three characters in, and
the emitted file does not parse. **Unit tests over the emitter's string output did not see it, and
would not have** — this is why the round trip through a real compiler is an arm of this measurement
and not a nicety.
