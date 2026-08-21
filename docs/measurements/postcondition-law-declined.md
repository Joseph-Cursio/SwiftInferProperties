# The postcondition law on normalisers — right law, absent population

> **Status:** `shipped` · **As of:** 2026-08-21

Harnesses: `fixtures/branch-reaching-generator/` (law comparison) and
`CatalogHealthCensusMeasuredTests.normaliserPairCensus` +
`GuardPostconditionCensusMeasuredTests` (two independent population routes).

**The law is measured 4× stronger than the one the tool emits.** Two routes that
**discover** the predicate are declined on population. **A third route — where the
catalogue SUPPLIES the predicate from a recognised role — has a population of 36 and is
live.** See §4.

> ⚠ **This document was first filed `declined`, and that was too broad.** Both declined
> routes try to *find* the predicate in the subject's code. Neither is how the one
> postcondition template that already works finds its predicate, and that route was not
> tested before generalising from the two that failed.

---

## 1. The law is right

`fixtures/branch-reaching-generator/` §4, six law shapes against four real bugs in a
legalise-shaped subject, narrow domain, 100 trials. Control holds: no law refutes the
correct implementation.

| law | bugs killed |
|---|---:|
| **postcondition — `isValid(f(x))`** | **4/4** |
| oracle — vs an independent implementation | 4/4 |
| metamorphic — prefix noise | 2/4 |
| metamorphic — suffix noise | 2/4 |
| **idempotence — what the tool emits** | **1/4** |
| identity-on-normal | 0/4 |

**`HTTPField` declares `isValidValue` immediately above `legalizeValue`.** The tool
emitted the 1/4 law and walked past the 4/4 one in the same file.

**Five of the nine common shapes cannot apply**: round-trip, inverse, commutativity,
associativity and identity-element need an inverse or a second operand, and a normaliser
is lossy and unary; monotonicity has no order. The catalogue's algebraic core is
structurally blind to this subject family.

---

## 2. Route A — pair the predicate to the normaliser by NAME. Declined.

**349 `(T) -> Bool` beside `(T) -> T` pairs across 2,926 containers; 35 share a trailing
noun; a hand-check of the 12 printed found ONE clearly genuine**
(`ViewModelNameHeuristics: isOptional / stripOptional`) **and one plausible**
(`Substring: _isValidIndex / index`). The rest merely share a suffix —
`formCharacterIndex / utf16AlignIndex` both end in `Index`.

**Population ~1–5.** Same verdict as `parameter-role` (2 of 118) and
`cross-type-roundtrip` (1.1%).

**Two instrument limits, stated rather than buried.** The binary-op exclusion compares
against the container's *name*, so `OrderedSet.isDisjoint(Self)` leaks and the 349 is
still contaminated. And the first name rule stripped verb prefixes, giving `validvalue`
against `value`, so **the motivating example itself would not have counted** — caught by
reading sample rows, not the summary line.

---

## 3. Route B — read the guard out of the BODY. Better, still declined.

The predicate does not need finding by name. `legalizeValue` opens with
`if _isValidValue(value) { return value }` — **the guard IS the postcondition**, inside
the function the law is about.

**25 normalisers `(T) -> T` open with a call-bearing guard mentioning their parameter,
across 17 corpora.** All 25 printed, so the hand-check covers the whole population rather
than a sample.

| | count | examples |
|---|---:|---|
| **genuine postcondition** | **~13** | `FileOperations.resolve` ⟵ `path.starts(with: "/")`; `StringGuts.ensureMatchingEncoding` ⟵ `hasMatchingEncoding(i)`; `unescaped` ⟵ `hasPrefix("`")`; `RawSyntaxArena.intern`; the `validate*Index` family |
| control decision | 4 | `shouldFormatterIgnore(node)` ×3, `OneVariableDeclarationPerLine` |
| dedup / membership | 2 | `InputOrigin.inserting`, `VerifyCorpus.adding` |
| validates the ARGUMENT, not the output | 1 | `appendingPathExtension` |
| performance branch | 4 | `_fastPath(isFastUTF8)`, `_slowPath(isForeign)` ×2, `swift_retain` |

**Precision ≈ 52%**, against the ≥50% bar that declined `same-name-differential-pairing`
at 40%. That clears it.

### What declines it is CONCENTRATION

**9 of the ~13 genuine hits are one file** — `StringIndexValidation.swift`'s `validate*`
family, one idiom repeated eight times. Remove it and the distinct population across
seventeen corpora is **about four sites**.

**A template justified by this is justified by one stdlib file.** That is the
`parameter-role` shape verbatim: *the 3-of-3 that motivated it was 3 of the 5 rows that
exist.*

### The distinction the detector cannot make

`shouldFormatterIgnore(node)` is structurally identical to a postcondition guard — return
the input unchanged when the predicate holds — but *"should be ignored"* is a **control**
decision, not a property of the output. **Re-applicability is the test**: a postcondition
must be assertable of `f(x)`. Nothing syntactic separates the two, and a template would
emit both.

**The optional-binding class was the first run's dominant false positive** — `guard let
initializer = node.initializer` satisfies *contains a call* and is not a predicate at all.
Excluding `let` / `case` took 44 hits to 25 and precision from ~24% to ~52%.

---

## 4. Route C — let the CATALOGUE supply the predicate. Population 36, and live.

**`measure-non-negativity` does not discover `>= 0`.** It recognises a *role* — `count` /
`size` / `magnitude` — and the catalogue supplies the law. It has **401 rows across the 17
corpora**, among the largest in the catalogue. The working pattern is:

> role recognised by name → predicate supplied by the catalogue → asserted on the output

That sidesteps both declines: no pairing, no guard reading, and **no
control-versus-postcondition ambiguity, because the template writes the check** rather
than inferring intent from an expression.

`RolePostconditionCensusMeasuredTests`, name-and-signature only:

**62 candidate sites, of which 36 are EXACT-name matches** where the supplied law applies
unmodified.

| role | sites | exact | law the catalogue supplies |
|---|---:|---:|---|
| `sorted` | 12 | **8** | `isSorted(result)` |
| `clamped` | 6 | **5** | result lies within the bound |
| `reversed` | 5 | 5 | `result.count == input.count` — weak |
| `lowercased` / `uppercased` | 8 | 6 | no remaining opposite case |
| `rounded` | 3 | 3 | result is integral |
| `trimmed` / `trimming` | 16 | **2** | no leading/trailing whitespace |
| `normalized` | 5 | 2 | result is in normal form |
| `escaped` / `unescaped` | 4 | 2 | no unescaped occurrence |
| `deduplicated` | 1 | 1 | no duplicates |
| `shuffled` | 2 | 2 | a permutation — weak |

**The exact/prefix split is the finding, not a detail.** `trimmingLeadingWhitespace` leads
with `trimming`, and the supplied law *"no leading OR trailing whitespace"* is **too
strong for it** — the suffix narrows what was trimmed, and
`trimmingSuperfluousNewlines` trims newlines rather than whitespace at all. **A catalogue
that ignores the suffix supplies a FALSE postcondition, which would refute correct code —
the worst failure this tool has.** 14 of the 16 `trimmed`/`trimming` sites are prefix
matches, so this single distinction moves the usable population from 62 to 36.

**Concentration is healthy**, which is what declined route B: hits are spread over **11
corpora**, and the largest single container is `swift-syntax:SyntaxProtocol` at **7 of
62 (11%)** — against route B's 9 of 13 in one file.

**36 would sit mid-catalogue**, above `equivalence-relation` (29),
`set-relation-model-law` (25), `normal-form` (17) and eight other shipping templates.
Dropping the two weak laws — `reversed`'s count preservation and `shuffled`'s permutation
— leaves **~29 with strong, refutable postconditions**.

## 5. The verdict

**Routes A and B are declined. Route C has a population and is the one to pursue.**

- **Route A** (pair by name): ~1–5 genuine of 349. Declined.
- **Route B** (read the body guard): ~13 genuine of 25, precision ≈52% which clears the
  bar, **declined on concentration** — 9 of 13 in one stdlib file.
- **Route C** (catalogue supplies from a role): **36 exact sites, ~29 strong, 11 corpora,
  11% max concentration.** Live.

**Precision measured 2026-08-21 by hand-checking all 38 exact-name declarations across
the corpora: ~92% raw, ~97% after two systematic exclusions.** The three failures were not
random:

- **`SyntaxProtocol.trimmed(matching filter:)`** — an exact name match that trims *trivia
  a caller selects*, not whitespace. **The only false law in 38**, and the reason the
  template gates on parameter labels.
- **`normalized` × 2** — the supplied law would be *"the result is in normal form"*, which
  **is not a checkable predicate**. One site returns a `(Set<String>, [String: String])`
  tuple. **`normalized` is excluded from the role table entirely.**

**BUILT 2026-08-21** as `RolePostconditionTemplate` / `RolePostcondition`, with both
exclusions as gates and eight tests, two of which are those false positives.
**VERIFIABLE 2026-08-21** for the two roles whose check needs no unproven conformance. The weak
roles (`reversed`, `shuffled` — they pin size and membership, not content) fire below the
strong ones and **disclose their own weakness in a caveat** rather than being dropped.

The remaining unmeasured question A name match is a candidate: `sorted` needs its comparator resolved, and none of
the 36 has been filtered for test visibility. **Reading a population as a precision is
the mistake `parameter-role` made**, and the exact/prefix split above is a warning that
this family has real false-law hazards.

## 6. What would reopen A and B

- **A corpus with normalisers at volume** — a validation-heavy or parsing-heavy package
  where the guard idiom is house style rather than one file's.
- **A syntactic separator for control-vs-postcondition guards.** §3 asserts none exists;
  a counterexample would raise precision above 52% and shrink the false class.
- **The `validate*` family being typical rather than idiosyncratic.** It is 9 of 13 here.
  If other stdlib-scale corpora show the same density, the concentration objection weakens.

---

## 7. The law RUNS, for two of ten roles

Shipped discovery-only first, then wired to verify. Proven end to end on a planted
subject — a `lowercased()` that lowercases everything **except the first character**:

| subject | outcome |
|---|---|
| the mutant | **`measured-defaultFails`**, counterexample `Text(raw: "D")`, trial 1 |
| the correct implementation | **`measured-bothPass`**, 100 default + 100 edge trials |

Both directions checked. A pass with no failing case would be a law that cannot fail.

### Two of ten, and the eight are a decision

`lowercased` and `uppercased` return `String` in every Swift spelling, so their check —
*does the result contain the opposite case?* — needs no conformance the tool must prove
and no argument the stub does not hold.

The other eight stay advisory **because emitting a check the emitter cannot justify is the
measured failure**, not the cautious one: `criterion-a-unmet-subject.md` found **89% of
output failing to compile** on an unmet subject, from exactly that. `sorted` needs
`Element: Comparable`; `deduplicated` needs `Hashable`; `clamped` needs the caller's
bounds; `reversed` and `shuffled` need the input beside the result; the escaping pair has
no universal scheme. `composeRolePostconditionPass` returns `nil` for all of them, so
verify records `unsupported-template` rather than a stub that will not build.

### A template needs admitting in TWO places

Adding `role-postcondition` to `TemplateName.verifiable` was **not enough** — the survey
still reported `unsupported-template`. That list gates the *template check*;
`resolveFunctionCalls` gates *call resolution*, and the survey path consults the second.
**Missing either produces the identical error message**, which is why this was found by
running a planted subject rather than by reading the code.
