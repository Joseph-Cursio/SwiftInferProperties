# The postcondition law on normalisers — right law, absent population

> **Status:** `declined` · **As of:** 2026-08-21

Harnesses: `fixtures/branch-reaching-generator/` (law comparison) and
`CatalogHealthCensusMeasuredTests.normaliserPairCensus` +
`GuardPostconditionCensusMeasuredTests` (two independent population routes).

**The law is measured 4× stronger than the one the tool emits. Both routes to finding it
are declined on population — the second on CONCENTRATION rather than precision.**

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

## 4. The verdict

**Declined. The law is right, the signal is readable, and the population is not there.**

Route B is materially better founded than route A — 52% against ~5%, and it finds the
motivating case, which route A's first instrument could not. It still fails on a
population of about four distinct sites.

**What is worth keeping**: the postcondition is **4× stronger than idempotence** on
normalisers, and the guard in the body is a real, measured signal for finding it. If a
corpus ever exhibits the shape at volume, the route is measured and waiting.

## 5. What would reopen it

- **A corpus with normalisers at volume** — a validation-heavy or parsing-heavy package
  where the guard idiom is house style rather than one file's.
- **A syntactic separator for control-vs-postcondition guards.** §3 asserts none exists;
  a counterexample would raise precision above 52% and shrink the false class.
- **The `validate*` family being typical rather than idiosyncratic.** It is 9 of 13 here.
  If other stdlib-scale corpora show the same density, the concentration objection weakens.
