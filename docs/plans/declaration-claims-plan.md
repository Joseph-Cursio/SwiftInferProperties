# Inferring and applying declaration-level claims

> **Status:** `proposed` · **As of:** 2026-08-17

**Revised 2026-08-17** against measurements that landed the same day: see the two notes below the
trailer, §4's tier warning and premise checks, §6.3's frozen trip list, §8's discharged gate, and
§10's 1a/1b split.

> **The status was `plan`, which is not in the closed vocabulary** — `docs/README.md`'s table admits
> `reference` / `shipped` / `open` / `proposed` / `declined` / `measured` / `withdrawn` /
> `superseded`, and `DocStatusHeaderTests` enforces it against the fast suite. `plan` would have
> failed on the first commit. `proposed` is the fit: *written down, not started, no decision taken.*
> Move it to `open` when phase 0's scope decision is recorded.

Specs the inference and advisory surface for `@Pure`, ownership (`consuming` / `borrowing` /
`~Copyable`), `final`, and the rest of Swift's declaration-level claims. Written as claims that
can be falsified, not as a feature list.

**Book home:** the markers belong beside `@Pure` / `@ClockDeterministic` in Chapter 22 §22.6;
the empirical arm (§6) is Chapter 19's territory, not Chapter 26's.

<!-- doc-provenance date=2026-08-17 subject=SwiftEffectInference@3ea25f29de9e0fbb86a6a8f20b2c42ead58a039e observer=SwiftInferProperties@1b2def25681ec5972c38a59eae134fca77dd3f54 -->

> **`docs_drift.sh` does NOT cover this file, and the trailer above is therefore decorative.**
> Settled rather than left open: `DOCS_DIR` defaults to `docs/design-internal`, so `docs/plans/` is
> out of scope. Open item 39 was worked and **deliberately declined to widen the glob** — measured
> 2026-08-17, 9 of 91 docs under `docs/` are in scope and 49 of the 82 out of scope name a sibling
> repo, but all 82 lack a trailer, so a wider glob prints 82 `?` rows and the check becomes the thing
> nobody reads. The scope line `make docs-drift` now prints is that denominator.
>
> The SHAs are filled anyway, for two reasons: they record what was actually read, and if this doc
> ever moves into `design-internal` the trailer works on arrival instead of failing the check as
> UNRESOLVED. **Do not read their presence as a guarantee anything verifies them.**

> **Phase 0's measurement is DONE, and it changes this plan.** This document was written as though
> nothing had been measured. The split §8 gates Family A on — *of the refuted verdicts, how many
> carry a witness and how many are ignorance?* — exists:
> `docs/measurements/purity-refuted-bucket-census.md`, taken 2026-08-17 and re-taken at SEI
> `3ea25f2`.
>
> | | |
> |---|---|
> | corpus | **2,740** functions (was quoted here as 2,500) |
> | `.pure` | **2,396** (was 2,206) |
> | `.pureButPartial` | **37** (was 35 — quoted in §4, §5, §10, §11) |
> | `.refuted` | **307** (was 259) |
> | **witness-bearing** | **174** |
> | **ignorance-only** | **133**, 43%, all actionable, `noBody` structurally 0 |
>
> **Ignorance is not a rounding error, so falsifier #1 is resolved, item 30's axiom gap is real, and
> `@lint.purity refuted` has a consumer.** Family A is unblocked now; phase 0 reduces to the §2.1
> scope decision alone.
>
> **Every count above belongs to an SEI pin, not to a date.** It moved three times in one day —
> ignorance 152 → 135 → 133 — because a refuter added anywhere shrinks the bucket. Cite the census
> and re-run its harness; do not inline a figure from here.

---

## 1. The claim this plan rests on

**Three families, and treating them as one list is the trap.** They differ in who enforces the
floor, which decides whether the tool can be wrong.

| family | what it is | can the tool be wrong? | needs new vocabulary? |
|---|---|---|---|
| **A — effect claims** | `@Pure` and its negation | **yes** — a positive claim over a transitive call graph | already has some |
| **B — over/under-claim detection** | `mutating`, `async`, `throws`, `@escaping`, generic constraints, access, `final`, ownership | **no** — the compiler enforces the floor | **none** |
| **C — the B findings that feed A** | `final`, unnecessary `async`, typed `throws`, `borrowing` | inherits A's risk once consumed | none |

Swift's compiler already rejects a body that mutates `self` without `mutating`, throws without
`throws`, or uses a requirement without the constraint. **The floor is checked.** So Family B can
only find *"you promised more than your body needs"* — which cannot be a false alarm about
correctness. Worst case it is a style disagreement. Categorically cheaper to be right about than
purity, where a missed refuter makes SEI unsound.

**The architectural claim:** B feeds C feeds A. The over-claim detectors are cheap, sound, and
*manufacture the evidence the purity inferrer is missing*. Starting with `@Pure` inverts the
dependency.

---

## 2. Scope boundaries, stated before the phases

### 2.1 Protocol requirements — decide this first, it bounds everything

Nothing below works the same on a protocol requirement as on a concrete declaration. A purity or
ownership claim attached to a *requirement* obligates **every witness**, including ones in modules
that do not exist yet. And Swift has **no coherence check**: any module may retroactively conform
any type to any protocol (SE-0364 added only a warning and `@retroactive`), so a law verified
against the conformance visible here can be violated by a different witness downstream.

**Consequence, and it is larger than this plan:** laws about `Equatable`, `Comparable`, `Hashable`
are **module-scoped claims**, not global ones. SwiftPropertyLaws already generates tests about
conformances it does not own. This is a pre-existing border claim with no guard.

Three options, pick one explicitly:

| option | what it means |
|---|---|
| **out of scope** | claims attach to concrete declarations only; requirements are never annotated or inferred. Cheapest, and probably right for v1 |
| **module-scoped** | claims are made and verified within the module that owns the conformance, and say so in the output |
| **obligating** | a claim on a requirement generates an obligation on every visible witness. Highest value, largest blast radius, needs the coherence caveat documented at every consumer |

**Recommendation: out of scope for v1, with the module-scoping caveat written into
SwiftPropertyLaws' output regardless** — that half is already true today and unstated.

### 2.2 What Family B's output *is* — the gate applied evenly

The vocabulary gate below (§7) says no new grammar ships without a named consumer. Family B adds no
grammar, but its findings still need a home, and "feeds A" is not a mechanism.

**Item 28 already answered this shape.** `SwiftProjectLint@9a21f3c1` added an `effect` object to
`idempotency` seeds — `declared` / `resolved` / `provenance` / `depth` / `reason` — because a
linter running ahead of the pipeline can pay for a join `EffectResolver`'s one-hop pass cannot.
Family B findings are the same class of fact reaching the same boundary. **They belong on the seed,
not in a report.** A `final`-inference result that only reaches a human is a fifth instance of *the
consumer keeps asking the producer, in English*.

**And there is now a second precedent, closer to this plan than item 28's.** SwiftProjectLint #115
landed `knownImpurePackageFunctions`: a project-wide fact — the names this purity oracle refutes with
an establishable witness — resolved once in the pre-scan and handed to every per-file visitor
alongside `knownCleanInstanceMethods`. It gates `pure-function-candidate`, so the seed the pipeline
consumes is 12 rows cleaner on this repo. **That is the mechanism §2.2 is asking for, already built
and already carrying a Family-A-adjacent fact across the same boundary.** Family B findings should
arrive the same way rather than inventing a channel.

**Two cautions come with it, both measured rather than anticipated.**

- **Do not reach for cross-file dispatch to get a project-wide fact.** That was tried first in #115
  and reverted: the cross-file path does not forward the `known*` catalogs at all, so the rule lost
  the type knowledge its candidacy test depends on and **377 candidate symbols silently vanished**.
  The pre-scan is the supported route; the cross-file gap is still open for whoever hits it next.
- **A fact wired to one of two construction sites is inert, and silently so.** #115's join was
  correct, unit-tested and green while suppressing **0 rows on a real corpus**, because only one of
  the two per-file detector sites forwarded it. Any Family B fact reaching the seed needs an
  end-to-end assertion through `ProjectLinter`, not just a unit test — a unit test sets the very
  wiring under question.

---

## 3. Family B — the taxonomy

### B1 — over-claims (the body needs less than the declaration promises)

| claim | over-claim condition | ABI-sensitive | feeds A? |
|---|---|---|---|
| `mutating` | body never mutates `self` | yes, public | yes — `nonmutating` is purity evidence |
| `async` | body never suspends | yes | **yes — `async` refutes purity outright today** |
| `throws` → `throws(E)` | body throws exactly one error type | yes | **yes — characterises partiality** |
| `@escaping` | closure parameter never escapes | yes | yes — non-escape evidence |
| generic constraints | body uses fewer requirements than declared | yes | no |
| access level | no reference outside a narrower scope | yes | indirectly — item 13's inverse |
| `consuming` | body only borrows | **yes, explicitly** | yes |

### B2 — under-claims (the declaration could promise more, and something downstream gains)

| claim | under-claim condition | ABI-sensitive | feeds A? |
|---|---|---|---|
| `final` | no overrides in the module, not `open` | yes — adding to public API is breaking | **yes — the big one, §4** |
| `Sendable` | public type passes the structural check but doesn't declare it | yes | no |
| `nonisolated` | method touches no isolated state | yes | adjacent |
| `borrowing` | body neither stores, returns, mutates, nor forwards-as-consuming | yes | yes |

### B3 — not derivable (do not attempt)

`~Copyable`, `~Escapable`, `@frozen`, `@inlinable`, `open`, `@discardableResult`. Promises about the
**future** — that a layout won't change, that an enum won't gain cases. No body derives them; only
API diffing between versions bites, which is `swift-api-digester` territory and out of scope.

**Naming B3 explicitly is load-bearing.** `~Copyable` is in this plan's title and is the one item in
it that cannot be inferred at all.

---

## 4. Family C — the feedback edges

Each row's value is measured in *purity verdicts decided*, not findings emitted.

| edge | mechanism | measurement that would settle it |
|---|---|---|
| **`final` → resolvable call edge** | a `final` method has a statically known implementation, so a dynamic-dispatch blocker becomes a real call-graph edge | rows moved **out of the 133 ignorance-only refutations** — and see the tier warning below, which is the binding constraint |
| **unnecessary `async` → purity candidate** | `verdict(for:)` refutes on `asyncSpecifier` before walking the body; a function that never suspends is refuted for a reason that isn't real | count of `async`-refuted functions whose bodies never suspend **and** pass every other refuter. The census puts `asyncSignature` at **31 rows**, which is this edge's ceiling |
| **typed `throws` → characterised partiality** | the 37 `.pureButPartial` are unconsumed because partiality is unnamed; `throws(E)` names it | how many of the 37 throw exactly one error type |
| **`borrowing` → non-escape evidence** | a `borrowing` parameter cannot be mutated or stored — the fact `refuteIfCaptured` computes for captures | overlap between inferred-`borrowing` params and functions refuted on capture. **Check the population is non-zero first** — see below |
| **`consuming` → in-place mutation unobservable** | the callee owns the value outright; purity without escape analysis | **premise check before measurement** — see below |

> ### There is no `.undecided`, so this table had no scorer
>
> `PurityVerdict` is `pure` / `pureButPartial` / `refuted`. The `.undecided` this table and §10's
> phase-1 gate were scored against **does not exist**, and neither does the `.undecided` population
> §6.3's decision arm proposes to sandbox. The real quantity is the **133 ignorance-only
> refutations** — refuted with nothing in the source naming a construct — which is what item 29's
> census split out and what `final` would actually be trying to move.

> ### `final`'s leverage was already measured, and it lands in a tier nothing reads
>
> **This is the correction that most changes the plan.** `final`'s value here is *"shrinks the
> unknown-callee bucket (items 29/31)"* — and `docs/measurements/purity-blocking-callee-census.md`
> measured exactly that shrinking, then **declined it twice**:
>
> - leverage is **13–31 rows** against the 133-row population, taking **9 hops** to converge, well
>   past the one hop `EffectResolver` affords under §13's 2-second budget;
> - **every freed row `throws`**, structurally — `propagatedTry` is a `throws` clause *plus* a `try`,
>   and `verdict(for:)` returns `.pure` only with no `throws` clause. So the best a resolved callee
>   can do is `.pureButPartial`;
> - **`.pureButPartial` has zero non-comment references in `Sources/`.** Resolving every blocking
>   callee in the package moves **zero** advisory rows, by construction.
>
> **So item 34 — a `.pureButPartial` consumer — is `final`'s precondition, not its beneficiary.**
> Phase 1 as originally written could succeed at its mechanism and deliver nothing, which is §9's
> Daikon-trap warning arriving against this document's own highest-leverage claim. The population has
> moved three times (152 → 135 → 133) while the leverage has not moved once; **the number that
> decides this build is the one that has never changed.**
>
> `final` may still be worth building — a statically resolved call graph is worth more than one
> census — but it must be scored against *rows that reach a reader*, and today that means sequencing
> item 34 first or accepting a legibility-only gain and saying so.

> ### Two ownership rows may have a zero population, like item 33's premise did
>
> `CaptureMutationChecker` is constructed `init(closure: ClosureExprSyntax, …)` — it is
> **closure-only**. No refuter examines parameter mutation in a function declaration, and a Swift
> parameter is immutable unless `inout`. So *"count of `consuming`-parameter mutations currently
> refuting purity"* is plausibly **zero by construction**, and the `borrowing` row's overlap is with a
> capture refuter that never fires on the declarations these annotations attach to.
>
> **Measure the population before building either.** Three times in this line of work the documented
> error direction has been backwards, and item 33 was declined precisely because its premise —
> *chains terminate at a higher-order call* — measured **false**: nine of ten probe shapes reached
> `.pure`. A one-afternoon probe settles both rows.

### 4.1 These interact, so a sequential pass under-reports

Inferring `final` changes the call graph → changes purity verdicts → changes law candidacy →
changes which annotations are worth writing. That is a fixpoint **across** analyses, not within one.

**Requirement:** each Family B phase re-runs purity inference and reports its delta against the
*post-previous-phase* baseline, not against phase 0. A phase measured against a stale baseline
reports a number no later phase can be compared to — the same-binary/same-day rule from
`docs/measurements/swiftorg-property-test-study-findings.md` §10.3, applied across *analyses* instead
of across binaries. (That reference is to the findings doc, not to §10 of this plan, which has no
subsections; a reader looking for §10.3 here will not find it.) If the phases are cheap enough, run them to a joint fixpoint and report per-phase
attribution by ablation instead.

---

## 5. Family A — `@Pure`, and whether it needs a negation

### The gap is real

`@NonIdempotent` is not the negation of `@Pure`. A function reading `Date()` is **`observational`**
— retry-safe, near the bottom of the lattice — and not pure. `@EffectUnknown` says *"I cannot
determine the tier,"* a different claim. There is no spelling for *"this is not referentially
transparent, and I know it."*

### But the obvious version is inert — item 20's failure mode

`PurityInferrer` refutes on doubt. A marker saying *"not pure"* on a function already refuted agrees
with the default, and a vocabulary that agrees with the default is indistinguishable from an
unannotated codebase. `@EffectUnknown` earned its place by being distinguishable from the `nil`
returned for unannotated *and* misspelled declarations. This must clear the same bar.

### It earns its place in exactly one case

**As the override of a false `.pure`** — item 30's axiom gap, where an unrecognised callee refutes
nothing and the function stays `.pure` incorrectly. Dual of `@unchecked Sendable`.

**Its usage count is therefore a metric, not a feature.** Every instance is a false `.pure` the
inferrer produced. Ship it with the counter; read a rising count as a defect report.

### Design: mirror the verdict, don't invent a boolean

Purity is a conjunction — transparent ∧ deterministic ∧ total — and `PurityVerdict` already splits
the third clause out. Name the failing clause:

```
/// @lint.purity refuted(effects)          — a side effect
/// @lint.purity refuted(nondeterministic) — reads a clock, RNG, environment
/// @lint.purity refuted(partial)          — undefined on part of its domain
```

`refuted(partial)` **is** `.pureButPartial`, so the annotation and the verdict share a vocabulary
rather than approximating each other, and item 34's **37** rows gain an author-supplied path alongside
the inferred one.

### Namespace: not `@lint.effect`

`impure` is **not a lattice tier**. Putting a non-tier in the tier namespace re-opens the
incomparability problem `unknown` already lost. `@ClockDeterministic` solved exactly this with its
own `@lint.determinism` namespace and a bespoke predicate outside `AttributeRecognition`. Follow it:
`@lint.purity`, own predicate, no `Effect` case, no Hasse join.

Attribute form, if any, belongs in **SwiftIdempotency** — the toolchain's marker-macro home. Doc
comment first: it needs no dependency, which is what made the `@lint.effect` veto usable without
adopting the package.

### 5.1 The zero-annotation problem — this is why Family A is last

**Step 1 of the idempotency vocabulary shipped and affected 0 of the 13 measured false positives**,
because this repo carries zero effect annotations in its own sources. It was a *capability, not a
fix*. `@lint.purity` inherits that exactly, and so does every ownership finding that requires an
author to act.

Two consequences, both structural rather than schedule:

1. **Family A cannot be gated on adoption.** No corpus available here will show it working. Its gate
   must be *"the empirical arm (§6) discovered N false `.pure`"* — a number the tool produces about
   itself, not a number a user's codebase produces.
2. **Family B is the near-term value, and Family A is infrastructure for later.** Worth saying
   plainly now rather than discovering it after building the marker.

---

## 6. The empirical arm — over-claim inside the loop

The toolchain has a loop, so a claim can be made optimistically and refuted by execution. Purity
needs refutation rather than confirmation, and execution is the only thing that supplies it —
whereas a conservative `.refuted` verdict is **unfalsifiable by execution**, which means the current
inferrer produces claims nothing can score.

**The hazard is specific and it is the crux.** Item 13 mutates a copy and proposes a patch; being
wrong costs a suggestion. Here, SEI's own doc calls `.pure` the most dangerous place to land wrongly
because a generated property test runs the function in-process over random inputs. **Executing the
speculation is the side effect** — if the answer is "not pure," you have already inserted the rows.

> **Since SEI `3ea25f2`, the determinism refuter's population is smaller than this section assumes.**
> `hasRefutingMarker` now consults `NondeterminismSources` as a union with its token set, so the
> monotonic clocks, `SuspendingClock.now`, `Locale.current` and `TimeZone.current` are refuted
> *statically*, before any sandbox sees them. Seven such sources reached `.pure` before that bump. The
> empirical determinism arm therefore inherits a corpus already stripped of the obvious cases, which
> raises its cost per finding and should be priced in rather than discovered.

### 6.1 The sandbox is the detector, not safety wrapping

Run under deny-by-default: no network, no filesystem writes outside the workdir, no subprocess
spawn. A pure function completes; an impure one fails trying to do the thing. Better than an effect
recorder, which only observes effects you instrumented — denial fires on effects nobody enumerated,
which is item 30's axiom gap answered empirically instead of by curation.

**Two constraints, one of them already recorded here.** The denial must **report which policy
fired**, not kill the process: a trapping `precondition` in `#assertIdempotent` destroys the
counterexample and leaves *no* output, and a sandbox that refutes by SIGKILL reproduces that one
layer down. And **tier the policy** — `observational` is retry-safe but not pure, so a naive
deny-all produces a wall of `print` refutations. stdout is not a socket.

### 6.2 Three clauses, three refuters

| clause | empirical refuter |
|---|---|
| effects | sandbox denial, reported not fatal |
| determinism | invoke twice, compare — the `#assertIdempotent` shape minus the trap |
| totality | does it trap |

Same decomposition as `refuted(effects \| nondeterministic \| partial)`. The annotation, the verdict
type, and the empirical arm end up sharing one vocabulary rather than three approximations.

### 6.3 Three arms, and the order matters

| arm | population | what it measures | prediction to freeze? |
|---|---|---|---|
| **soundness** | the **2,396 `.pure`** | **is the inferrer wrong where it matters most** | **yes — a named trip list now exists, see below** |
| precision | the **307 `.refuted`** | the false-refutation rate | yes, per function, before the run |
| decision | the **133 ignorance-only** refutations | individual verdicts | yes |

**Take the soundness arm first.** It is the cheapest and it tests the assumption everything else
rests on. "Conservative by construction" is an argument, not a measurement, and any trip is a defect
report against the marker sets.

> ### The soundness arm has a prediction to freeze, and should freeze it
>
> This table originally said *"none — the claim already exists in the output."* That was true when
> nothing had been measured. It is not true now, and running the arm unstratified would waste the
> strongest asset the plan has.
>
> `docs/measurements/purity-unrecognised-callee-census.md` names **17 hand-checked `.pure` functions
> that call a package function this same analyzer refutes with a witness** — one hop, name-unique,
> every one read by hand. The sharpest is `DrainedProcess.standardOutputViaEnv`, which **spawns a
> subprocess, drains two pipes on a global queue, and is judged `.pure`.** SwiftProjectLint #115
> independently suppressed **12** candidates on this corpus, **eight of them the same rows**, reached
> by a different instrument.
>
> **So freeze this prediction before the run:** *these named functions trip the sandbox; the
> remainder of the 2,396 do not.* That converts the arm from a trip count over an unstratified
> population — a number with no denominator anyone can argue about — into a **precision and recall
> reading against a hand-verified answer key**, which is the standard every other measurement in this
> repo is held to.
>
> **It also settles falsifier #2 in advance.** *"Phase 0.5 finds zero trips over the `.pure`
> population"* is already known to be false: SEI `3ea25f2` fixed 7–8 functions that wrote to standard
> error and were judged `.pure`, including both of this package's own `writeDiagnostic(_:)`. A tool
> vouching for the purity of its own diagnostic writer is the existence proof the arm was designed to
> look for, and it has already been found statically. **The open question is not whether the inferrer
> is ever wrong — it is what the base rate is on the rows no static refuter reaches.**

### 6.4 Constructibility, not generatability

The verify arm is capped by carrier reach — 105 declines, 37% corpus-wide — because a law needs a
*generator*. A purity probe does not. One call that trips a denial refutes; no domain coverage
required, so a degenerate or default-initialised argument suffices. **This arm reaches a population
the law-running arm structurally cannot**, and its coverage must be estimated separately rather than
inherited from 139-of-281.

### 6.5 Reuse

`VerifierSubprocess` already runs each law as its own process with `DYLD_*` injection — process
isolation exists and the interposition hook is in place, which is what makes report-rather-than-kill
cheap. And *one package for the survey, not one per suggestion* applies with more force: a purity
probe needs no law, so it is one stub with N invocations, not N SwiftPM builds. Minutes, not the
survey's 7.7 CPU-hours.

---

## 7. The backtest arm — the oracle that cannot be contaminated

Everything in §4 and §6 measures against this corpus with this binary, which is the instrument
already ruled contaminable: *a tool may not grade itself while it is still changing.* Backtests are
a different instrument and were explicitly **not** deferred with road tests — the oracle is a public
fix commit predating the tools, cheap to re-run, and it survives churn.

**The purity backtest:** find fix commits where the bug *was* a purity failure — a memoising
accessor, a hidden `Date()` read, a cached value that went stale, a function that mutated shared
state through a captured reference — and ask whether the tool flags the pre-fix version and not the
post-fix one. `backtest-apple-libraries.md` and `kit-suite-backtest-plan.md` are the precedent.

**This is the only arm that produces a number defensible outside the repo**, and it belongs early,
because it is cheap and because it is the one measurement the phases below cannot invalidate.

---

## 8. Gates

~~**Nothing in Family A ships before phase 0's measurement.**~~ **DISCHARGED 2026-08-17.** The
question was: of the refuted verdicts, how many carry a witness and how many are ignorance? If
ignorance were a rounding error, item 30's axiom gap would not be real, `@lint.purity refuted` would
have no consumer, and Family A would close as *measured-not-worth-building*.

**Measured: 174 witness / 133 ignorance of 307.** Ignorance is 43%, all of it actionable, `noBody`
structurally 0 — so the gate is passed and Family A has a consumer. The surviving constraint on
Family A is not this gate but §5.1's: no corpus available here will show it working, so it is
infrastructure whose gate must be *"the empirical arm discovered N false `.pure`"*, and §6.3 now
names the first of those N.

**No new vocabulary ships without a named consumer that reads it in the same PR.** Four recorded
instances of shipping one without: items 4, 17, 20, 28. Well enough characterised now to be a
precondition rather than a lesson. §2.2 applies the same rule to Family B's output.

**Any new grammar needs the item-4 contract test on the day it lands.** Terms matched by name
against a package no manifest mentions are one rename from silent breakage, and the symptom is a
*missing* annotation — indistinguishable from an unannotated codebase.

---

## 9. Traps

- **`deinit` timing.** For a `~Copyable` type with a `deinit`, `borrowing` → `consuming` moves
  *where the value is destroyed* — the callee now runs the deinit. Observable behaviour, not a
  calling convention. A tool treating all four ownership cases uniformly is wrong exactly there.
- **Copyable vs noncopyable stakes differ.** For a copyable type the choice is performance, since
  the caller can always copy; for a noncopyable type it is semantic. Advice that doesn't split them
  buries the real findings under ARC micro-optimisations.
- **ABI scoping.** SE-0377: ownership "affects the ABI-level calling convention and cannot be
  changed without breaking ABI-stable libraries." Same for access, `final` on public classes, and
  `async`. Internal is free; `public` under library evolution is not. Every finding must carry which
  side of that line it is on.
- **The Daikon trap wearing a linter.** Family B findings are sound by construction and potentially
  numerous — a repo could yield 600 "could be `final`" rows, none wrong and none worth reading.
  **Score by purity verdicts decided, not findings emitted.** A `final` inference resolving no
  blocked callee is a style preference; the same inference deciding 40 verdicts is the highest-value
  row here, and the count alone cannot tell them apart.
- **`async_without_await` already exists in SwiftLint** (opt-in, autocorrectable) and answers a
  *different question*: **can you delete the keyword**, not **does this suspend**. Its documented
  non-triggering set — overrides of async parents, actor initialisers, `@concurrent`, async closure
  signatures — is exactly where the two diverge, since an override that never awaits still doesn't
  suspend and is still a purity candidate. Take its exclusion list as reference, not its predicate;
  and note its output reaches a human, not this pipeline.
- **Recognition ahead of grammar is the safe direction.** `@Pure` was in SEI's default set before the
  macro shipped, and that ordering was correct. The reverse fails silently.

---

## 10. Sequencing

| phase | work | gate to proceed |
|---|---|---|
| **0** | §2.1 scope decision (recommend: requirements out of scope). ~~split `.refuted`~~ — **done, 174/133 of 307** | a decision recorded. The measurement half is discharged |
| **0.5** | §6.3 **soundness arm** — sandbox the **2,396** `.pure`, against the **frozen 17-row trip list** | precision **and** recall against the answer key, not a bare trip count |
| **0.6** | §7 backtest arm — purity-failure fix commits | ≥1 pre-fix flagged, post-fix clean |
| **0.7** | **premise probe for the two ownership rows** (§4) — does any refuter fire on parameter mutation at all? | a population, or a recorded *measured-premise-false* like item 33's |
| **1a** | **item 34 — a `.pureButPartial` consumer**, or an explicit decision to accept a legibility-only gain from 1b | a reader exists for the tier `final` frees rows into, or the absence is recorded as the price |
| **1b** | **`final` inference**, module-scoped, feeding the call graph and the seed via the §2.2 pre-scan route | rows moved out of the **133**, re-baselined per §4.1 — **and rows that reach a reader**, which is what 1a buys |
| **2** | unnecessary-`async` **edge** (not detector — see §9) | purity candidates created, not findings emitted |
| **3** | `borrowing` / `consuming` over-claims, split by copyable and by ABI exposure | over-claims found in internal code |
| **4** | typed-`throws` narrowing, scored against the **37** `.pureButPartial` | how many gain a named error type |
| **5** | `@lint.purity refuted(_)` + counter — **infrastructure, per §5.1** | phases 0.5–4 leave a residue of false `.pure`; **not** gated on adoption |

Phases 0.5, 0.6 and 0.7 are independent of each other and of 1–4; **0.6 is still the cheapest thing
in the document and 0.7 is the second cheapest.** Phases 2–4 may run in any order — the ordering is by
*expected* feedback into Family A, which is a prediction and should be checked against 1b's actual
number before committing to phase 2.

**The 1a/1b split is the substantive change to this sequence.** `final` was phase 1 and unconditional.
It is now gated on a reader existing for the tier it frees rows into, because the blocking-callee
census measured that resolving *every* blocking callee in the package moves **zero** advisory rows —
`.pureButPartial` has no consumer, so the mechanism can succeed completely and deliver nothing. Either
build the consumer first or take the legibility gain deliberately; what is not available is assuming
the reach.

---

## 11. What would falsify this plan

**Two of these have already been settled, and saying so is the point of keeping the list.** A
falsifier that has fired is worth more than one still waiting.

1. ~~**Phase 0 says ignorance is a rounding error.**~~ **RESOLVED — it is not.** 133 of 307, 43%, all
   actionable. Items 30/31 are real and Family A has a consumer. What survives from this row is its
   *weaker* form, and it is still live: the ignorance share has fallen 54% → 45% → 43% across three
   SEI pins, because every refuter added anywhere moves rows out of it. **If it keeps falling, this
   falsifier fires late rather than never** — so re-take it before Family A ships, not before it
   starts.
2. ~~**Phase 0.5 finds zero trips.**~~ **RESOLVED — the inferrer is demonstrably wrong on this
   corpus.** SEI `3ea25f2` refuted 7–8 functions that wrote to standard error and were judged
   `.pure`, including both of this package's own `writeDiagnostic(_:)`, and 17 hand-checked `.pure`
   functions call a package function this same analyzer refutes with a witness — one of them spawns a
   subprocess. **The axiom gap is not theoretical and §5's consumer stands.** The open question is
   narrower and better: what is the base rate on rows *no static refuter reaches*, which is what the
   sandbox is uniquely able to answer.
3. **Phase 1b's `final` inference decides no verdicts.** Still live, and now the most likely of the
   four to fire — the blocking-callee census already measured 13–31 rows of leverage all landing in
   `.pureButPartial`, which nothing reads. If 1b moves no row that reaches a reader, Family C is a
   story rather than an architecture and this work belongs in SwiftProjectLint with no connection to
   inference. **Record it as *measured-not-a-pipeline* rather than quietly rescoping** — and note that
   phase 1a exists precisely so this outcome is a decision rather than a discovery.
4. **The over-claim findings are numerous and inert.** Still live. If phases 2–4 emit thousands of rows
   and move no verdict, the honest close is that Swift's declaration-level claims are already well
   maintained in this corpus — itself worth writing down.
5. **The two ownership rows have no population at all** (§4, phase 0.7). If no refuter fires on
   parameter mutation, `consuming` and `borrowing` are not purity evidence in this analyzer and the
   rows close as *measured-premise-false*, the way item 33 did. Cheap to check and it should be checked
   before either is built.
