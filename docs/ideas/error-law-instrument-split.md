# Error laws: which ones does a LINTER owe, and which ones do property tests owe?

> **Status:** `declined` · **As of:** 2026-10-10

## Declined 2026-10-10 — read this before the body

The body below is the 2026-08-19 text, unchanged except for the status line and this
section. The measurement the body calls pending was taken the same evening, and on
2026-10-10 the doc's claims were checked against the code, four sibling repos and a
corpus census. Several did not survive. What does survive is in §A.6. This annotation
replaces nothing, because this repo corrects by annotation rather than by rewriting.

### A.1 The gate was answered the same day, and §5's first refuter fired in substance

- `docs/measurements/result-carrier-reach.md` is the three-arm measurement §4 waits for.
  It was committed in `d5b557e6`, about two hours after this doc's `7aa24284`, across the
  same 17 corpora. Masking `throws` (the ceiling arm) adds **+62 of 6,508 suggestions
  (~1%)**. The refactor that can actually be performed costs **−53**, an arm added the
  next day in `e17018cd`. Quote −53, never −218 or −66.
- Its §6 says *"the decline causes this tool has are not about the effect channel"*.
  That is §5's first refuter in substance, though not in letter. The ceiling is +62, not
  the zero §5 names, because `throws` does gate discovery (31 `!isThrows` checks across the
  templates). But +62 is about 1%, and the refactor that can be performed is negative.
- One reservation: it measured swapping the carrier under today's templates, not building
  new error-channel templates. §A.2 and §A.3 are why that second route is declined too.

### A.2 §2.2's identities do not hold under this repo's definitions

- **Atomicity is not conservation.** Conservation is a check on one state, an aggregate
  equal to its recomputation (`ConservationInteractionTemplate`:
  `state.<aggregate> == state.<collection>.count`). Atomicity compares the state before
  and after a failure.
- **Exhaustiveness is not cardinality.** Cardinality is "at most one presentation flag is
  set" (`CardinalityInteractionTemplate`). "Every error case is reachable" is an
  existence claim: a generator that never produces a case is not a counterexample, so no
  property test can refute it. That fails §3's own screening question. Only the second
  half, "none escapes as `.unknown`", is refutable.
- **Classification shares the connective with biconditional, not the terms.**
  Biconditional relates two fields of one state (`BiconditionalInteractionTemplate`).
  It is also, with cardinality, one of the two families Finding G measured at
  **33–50% acceptance**; biconditional itself held at 33%, 2 of 6, in cycle 104
  (`dcd6c882`). That is why both are pinned at `.possible` unless a measured `bothPass` at
  full action-space coverage overrules the pin
  (`InteractionInvariantFamily.swiftProjectLintDeferral`). It is the opposite of §5's
  "highest-yield".
- **Retry-safety is not interaction idempotence.** Idempotence there is `f(f(s))`.
  Retrying a failure is two calls with one input. That is the shape SwiftIdempotency's
  `assertIdempotentProperty` checks, but only on the success path: a throw fails the trial
  and is never compared with the retry. `docs/design-internal/swiftidempotency.md` records
  "idempotent" meaning three different things in this toolchain.
- **Four identities, not five.** Referential integrity maps to no error family.
- **"The templates exist; what is missing is a carrier."** The interaction machinery is
  keyed on reducer and MVVM carriers, and reducer discovery cannot see `throws`.
  `swift-infer discover-reducers` gave identical output for a throwing reducer and its
  non-throwing twin (2026-10-10).

### A.3 The headline family does not clear the bar

Partial swallowing (§1's corrected claim, §2.2's first row) was measured on 2026-10-10
over 14,608 `.swift` files in 53 repositories under `~/GitHub_projects` and
`~/xcode_projects`. Build products, `Tests/` and `test/` directories and `*Tests.swift`
files were excluded. About 985 fixture and test-target files remain in that count, and
none of them holds one of the 46 sites below.

| Stage | Sites |
|---|---|
| A `compactMap` / `flatMap` closure holding `try?` | 46 |
| …inside a function that throws or returns `Result` | 13 |
| …that actually drops rows | **7** |
| The spelling `.success(rows.compactMap { try? … })` | 0 |

Of the 7, three drop rows on purpose, three have a failure branch no generated test can
reach, and one looks like a real defect: SwiftLint's `NameConfiguration.apply`, read but
not run. Four of the 7 are in swift-package-manager. A seeded sample of 25 of the 46 sites,
almost all outside the honest-signature scope, found none suspicious; of the 16 that drop
rows, 11 read as intended and 5 as unclear. The only production `parseAll` in the corpus,
SwiftProjectLint's `ProjectLinter.parseAll(_:)`, does not throw, so §2.2's law cannot be
stated against it.

**This counts the closure spelling only.** Loop spellings (`guard let x = try? … else
{ continue }`, `catch { continue }`), `filter { try? … }` and `addTask { try? … }` add at
least a dozen more candidates inside throwing functions. They were counted but not
classified, so 7 is a floor for the family, not its population. One of them,
SwiftAssist's `CorpusIndexer+Incremental`, which removes a file's chunks and then silently
`continue`s when re-reading it fails, is a plausible second lead.

So the decline rests on **precision**, not population. The bar this repo uses for such
declines is **≥ 70% precision with a population of ≥ 5**
(`docs/measurements/whole-to-parts-partition-prediction.md`). The law holds of the intended
behaviour at 1 of the 4 sites where it can fail at all. The law "fails iff any row fails" is
a guess about intent, so §2.3's argument against *linting* this shape applies to the
property test as well.

### A.4 Smaller claims that are wrong as written

- **§1, "`Result` … makes it unwritable".** A compiled counterexample swallows totally
  behind a `Result` signature with `try?` and `??`, and never spells `case .failure`.
  `Result` makes the swallow *statable*, so a law can then catch it. It does not make
  the swallow unwritable.
- **§3's screening sentence is inverted.** A generator doing no work shows up as the
  never-errors implementation *surviving*. Read literally, the sentence labels §2.2's own
  first row decoration, because `.success(rows.compactMap { try? parse($0) })` never errors.
- **§3, swift-property-based 2.0.** Its attempt limit counts draws rejected by `filter`.
  It says nothing about whether a branch is reached, and PropertyLawKit samples with the
  unbounded `run(using:)` anyway. A reach guard of the kind §3 wants now exists for one
  template: since 2026-09-16 (`7859160c`) the `guard-domain` stub runs a coverage pass that
  reports `NOT APPLIED` when no draw entered the sub-domain. No other template, and no
  error law, has one.
- **§3's alphabet advice** (invalid UTF-8, boundary lengths) has shipped in
  `input-totality`'s caveats since 2026-07-29 (`44d1eaf4`). Totality laws, measured as the
  `predicate` template, refuted 0 of 102 on real code
  (`docs/measurements/template-refutation-rates.md`). The one real defect a totality law
  has reached, SwiftProjectLint's `RuleDocView.parseBlocks` hang, was reached by drawing the
  subject's own literals, not the malformed alphabet.
- **§2.3, "needs two declarations → a property test's".** SwiftProjectLint has a cross-file
  engine (`CrossFileAnalysisEngine`) running 37 registered cross-file visitors. The split
  that works is **"needs a value or an execution"**.
- **The falsifier `errorChannelClassification`** is an invented name of the kind
  `docs/measurements/falsifier-naming-failure-modes.md` shows going inert, and it covers
  one family of nine. A real discoverer could name its case anything. It is kept rather
  than deleted so the diff shows nothing was silenced, but read the deferral below as
  unguarded.

### A.5 §2.1, surveyed (§4's third bullet)

As of SwiftProjectLint `2567f79f`, SwiftLint 0.65.1 and the Swift 6.4 compiler:

| §2.1 check | Who owns it today |
|---|---|
| `(try? f()) ?? x` | **Nobody.** 144 sites in code across every repo under `~/GitHub_projects` plus SwiftProjectLint and this repo, about 120 outside tests, mostly deliberate best-effort reads. SwiftProjectLint flags the equivalent `do { return try f() } catch { return 0 }`, and its own rule docs disagree on whether `try?` already counts as handling. Filed upstream as a question: Joseph-Cursio/SwiftProjectLint#305 |
| Empty `catch { }` | SwiftProjectLint `Catch Without Handling`, on by default; SwiftLint's opt-in `no_empty_block` also fires |
| `catch { throw .unknown }` | Nobody. `Catch Without Handling` counts any `throw` as handling. §2.2's propagation and exhaustiveness rows claim the same defect for property tests, so the doc assigns one defect to both instruments |
| Unused `catch let error` | **The compiler** already warns |
| `f().value ?? x` | **Does not compile against the standard library**, whose `Result` has no `.value` (OpenAPIKitCore adds a public one). The standard-library spelling, `(try? r.get()) ?? x`, occurs 0 times |
| Untyped `throws` on a public boundary | Contradicts SE-0413, which keeps untyped `throws` as the default. About 89% of public throwing functions would fire (92% counting initializers) |

The two-instrument split also leaves out owners the toolchain already has: **the compiler**;
**SwiftIdempotency** for retry-safety on the success path (atomicity exists there only as
prose: its PRD, user guide and reference describe a `transactional_idempotent` tier that no
code checks); and **SwiftEffectInference**'s `NondeterminismSources` for time and locale
(hash order is owned by nobody). SwiftProjectLint already hands throwing functions to this
package as property-test candidates (`PropertyTestCandidacy`), so the instruments form a
pipeline, not a choice.

### A.6 What survives, and what would reopen it

**Survives:**
- Prevention (types) is not detection (tests).
- The assignment rule, restated: decidable from one declaration's syntax → the linter or
  the compiler; needs a value or an execution → a property test.
- "Do not lint for a composition".
- "Name an implementation this law rejects".

§2.2 stands as a list of laws a person can write by hand, read with §A.2's corrections.
It is not a build plan for this package.

**Would reopen it:**
1. A template that recognises `Result<T, E>` or typed `throws(E)`. Re-take
   `docs/measurements/result-carrier-reach.md`'s arms, per its §7. No arm has ever
   measured a typed-`throws(E)` carrier, and the scanner records `throws` only as a Bool.
2. A hand-classified census of partial swallowing across all its spellings, in which the
   law can fail at ≥ 5 sites and holds of the intended behaviour at 70% or more of them.
3. A test-suite census for §2.2's *"the one-sided test everyone writes catches half"*. It
   is unmeasured, and with §A.2 striking the shape argument, it is the only support left
   for the classification family.

---

Nothing here is built. This is a scope: it separates one topic — *stating laws about
the error channel* — into two instruments with different costs, and states the rule
for assigning a check to one of them.

---

## 1. The claim that started it, and the correction that made it usable

The opening claim was:

> Silent error-swallowing is the bug that error laws are uniquely good at catching,
> because the swallowing code passes every success-path test.

**That does not survive contact with the canonical case.** Take:

```swift
func load(_ data: Data) -> Config {
    (try? decode(data)) ?? .default
}
```

No error law catches this, because **there is no failure branch to state a law
about**. The swallow erased the error from the signature. `#expect(load(bad) ==
.failure(…))` cannot be written: `load` returns `Config`.

So `Result` does not *catch* that bug. It makes it **unwritable** — the swallow has to
be spelled `case .failure: return .success(.default)`, which is visible in review in a
way `try?` is not. That is **type-level prevention**, not **test-level detection**,
and conflating the two is what made the original claim sound stronger than it was.

The corrected claim, which is narrower and defensible:

> Error laws are uniquely good at catching **partial** error swallowing — where the
> signature admits failure and the body quietly does not produce it. **Total**
> swallowing is not caught by `Result`; it is prevented by it.

That correction is the whole reason this document exists: once prevention and
detection are separated, so are the instruments.

---

## 2. The split

### 2.1 What a linter owes — the spellings

A linter reads syntax, costs milliseconds, and runs on every file. It should own every
error-handling defect that is **visible in one declaration without executing
anything**:

| Check | Shape | Why static |
|---|---|---|
| `try?` discarding into a default | `(try? f()) ?? x` | One expression, no context needed |
| Empty `catch` | `catch { }` | Ditto |
| `catch` substituting a generic error | `catch { throw .unknown }` | The substitution is local and visible |
| Unused error binding | `catch let error { … }` with no use of `error` | Local dataflow |
| A `Result` immediately unwrapped with a default | `f().value ?? x` | Local |
| Untyped `throws` on a public boundary | signature-only | Signature-only |

These are **grep-able**, which is the point: a property test for any of them would be
paying execution cost for something a regex already decides. **This work belongs
upstream in SwiftProjectLint**, which already sits before this package in the
toolchain and already owns lint-shaped questions.

### 2.2 What property tests owe — the compositions

A property test executes code over generated inputs. It should own every error
defect where **every individual construct is legitimate and the composition is still
wrong** — the class a linter cannot see because there is nothing locally suspicious:

| Family | Law | What it rejects |
|---|---|---|
| **Partial swallowing** | `parseAll` fails iff any row fails | `.success(rows.compactMap { try? parse($0) })` — honest signature, lenient body |
| **Classification** (biconditional) | `f(x)` fails **iff** `P(x)` | Validators wrong in *either* direction; the one-sided test everyone writes catches half |
| **Atomicity** (conservation) | if `f` fails, observable state is unchanged | "mutate, then validate" ordering leaving a half-written record |
| **Retry-safety** (idempotence) | retrying a failure yields the same failure, no extra effect | non-idempotent retry paths |
| **Error determinism** | same input, same error, every run | error paths keyed on hash order, time or locale |
| **Earliest-error** | the reported error is the first one, and its position is in bounds | arbitrary-error reporting, off-by-one positions |
| **Exhaustiveness** (cardinality) | every error case is reachable; none escapes as `.unknown` | dead cases, and the catch-all that erases distinctions |
| **Propagation** | the error out names the stage that actually failed | a stage catching an inner failure and substituting its own |
| **Metamorphic invariance** | whitespace / key order does not flip success to failure | accidentally position-sensitive parsers |

**These are the same five shapes this toolchain already discovers over reducers** —
idempotence, cardinality, biconditional, referential integrity, conservation —
pointed at the error channel instead of the state channel. Atomicity *is*
conservation. Retry-safety *is* idempotence. Classification *is* biconditional.
Exhaustiveness *is* cardinality. That is an argument the idea is well-shaped, and a
concrete lead: the templates exist; what is missing is a **carrier that exposes the
failure branch**, which is what `Result` provides and `throws` does not.

### 2.3 The assignment rule

> **If the defect is decidable from one declaration's syntax, it is the linter's.
> If it needs two declarations, or a value, or an execution, it is a property test's.**

Two corollaries worth stating because they are the ones that get violated:

- **Do not write a property test for a grep.** It pays execution cost for a decision a
  regex already makes, and it will be slower and flakier than the regex.
- **Do not lint for a composition.** A static check for partial swallowing would have
  to decide whether `compactMap` over a throwing call is *intended* leniency, which is
  a semantic question wearing a syntactic costume. It would be a false-positive
  generator, which is the Daikon trap in its usual disguise.

---

## 3. The caveat that governs the whole property-test column

**Every law in §2.2 needs a generator that reaches the failure branch.**

If the generator draws well-formed input, `parseAll` never drops a row, and the
partial-swallowing law passes having exercised the defect **zero times** — a result
indistinguishable in the output from a law that genuinely holds. This is this repo's
standing rule in its sharpest form: *`measured-bothPass` means "no counterexample in
the generated domain," not "the property holds."*

So for error laws specifically, **the generator is the deliverable, not the law.**
Narrow the alphabet deliberately — truncated input, wrong-type payloads, boundary
lengths, invalid UTF-8 — and say so at the site. Note that `swift-property-based` 2.0
changed behaviour in a way that helps here: a generator that cannot produce valid
results now fails rather than spinning, so an unreachable branch surfaces instead of
hiding.

The screening question before writing any law in §2.2:

> **Name an implementation this law rejects.** If the only one you can name is
> "an implementation that never errors", the generator is doing no work and the law
> is decoration.

---

## 4. What is NOT decided here

- **Whether this package should discover any of §2.2's families.** That is gated on
  whether the toolchain can see a failure channel at all, which is being measured
  separately (three arms — baseline, `isThrows` masked, `Result`-wrapped returns —
  across the 17 corpora `CorpusManifest` resolves). **Do not start building templates
  before that number exists**: the closest adjacent question, *"would refactoring
  toward purity put more code within a law's reach"*, measured a ceiling of **zero
  rows moved**, because purity is not one of `UnverifiableCause`'s eight causes.
  "The subject throws" is not one of them either.
- **Whether `Result` or Swift 6 typed `throws(E)` is the better carrier.** Typed
  throws gives the typed error branch without the wrapping, and may be the better
  target for a discoverer. Unmeasured.
- **Which linter checks already exist upstream.** §2.1 is written from the shape of
  the problem, not from a survey of SwiftProjectLint's current rules. Somebody should
  check before proposing any of them as new.

---

## 5. What would refute this document

- **A measured population of zero.** If the pending three-arm measurement shows the
  toolchain's decline causes are untouched by the failure channel, §2.2 is a
  taxonomy of laws a *human* can write and this package cannot discover — still
  useful, but not a build plan, and this doc should be restatused `declined` for the
  discovery half.
- **A static check that decides partial swallowing without false positives.** §2.3's
  second corollary asserts one cannot exist. A counterexample moves the whole
  partial-swallowing row into the linter's column.
- **A measured false-positive rate on the classification family.** Biconditional laws
  are claimed here as the highest-yield family; that is an argument from shape, not a
  measurement, and it is exactly the kind of claim this repo has had to retract
  before.

> Deferred: no discoverer for any §2.2 family (falsifier: `errorChannelClassification`)

The falsifier is the `TemplateName` case a discoverer for §2.2's classification family
would have to declare. The day it exists, the sentence above is wrong and
`DeferralFalsifierTests` says so — which is the point: a deferral that cannot be
refuted by the tree is prose, not a claim.
