# Error laws: which ones does a LINTER owe, and which ones do property tests owe?

> **Status:** `proposed` · **As of:** 2026-08-19

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
