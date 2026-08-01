# Glossary

Vocabulary used across this repo's source, docs, and CLI output. Terms are grouped by the
stage they belong to, because several of them mean different things at different stages —
**"template" in `discover` and "template" in `verify` are not the same set**, and conflating
them is how a reach estimate goes wrong (see [Reach](#reach)).

Every definition here is keyed to code. Where a term's authority is a specific type or file,
it is named — prefer reading that over trusting this file, which is a map and not the territory.

---

## The pipeline, in one pass

```
SwiftProjectLint ──▶ SwiftInferProperties ──▶ SwiftPropertyLaws ──▶ SwiftIdempotency
  seeds                discover → index         run the laws          retry-safety
                       → verify → promote
        ▲                      ▲
        └──── SwiftEffectInference (purity oracle; no CLI, runs inside both) ────┘
```

A function's trip: the linter **seeds** it → `discover` matches a **template** and assigns a
**score** → the score maps to a **tier** → `index` persists it as an **entry** → `verify`
resolves a **carrier**, derives a **generator recipe**, composes a **stub**, and runs two
**passes** → the **outcome** may **promote** the tier to `verified`.

---

## Discovery

### Template
A named law shape that discovery can recognize from code — `idempotence`, `commutativity`,
`round-trip`, `predicate`. A template decides *whether it fires* and *what score it assigns*,
and ships the "why suggested / why this might be wrong" pair with each firing.

The canonical name vocabulary is `TemplateName` (`Sources/SwiftInferCore/TemplateName.swift`),
which exists so the several curated subsets ("the verifiable ones", "the v1.46 hardcoded set")
can't drift apart as string literals.

**Trap:** `TemplateName` does *not* enumerate every template discovery can emit. It holds the
verifiable set plus four extras; names like `predicate`, `input-totality`, and `filter-subset`
are live in the index and absent from the enum. Counting templates by `TemplateName.allCases`
undercounts. There are ~89 `*Template*.swift` files against 17 enum cases.

### Catalog
The whole collection of templates, taken together. "A catalog gap" = no template names the
shape in question. Distinguish from a **reach** gap (a template exists and doesn't fire) and a
**statability** gap (the law is real but cannot be *written down* generically).

### Score
An integer assembled from weighted `Signal`s. Not calibrated in an absolute sense — the
thresholds are documented as "v0.3 defaults, not load-bearing constants."

**Known distribution problem:** scores land on a sparse lattice
`{20,25,30,35,40,45,50,65,70,75,80,85}` with **nothing between 50 and 65**, and on swift-syntax
**738 of 1,115 suggestions sit at exactly 20** — the `possible` floor. Moving that cut to 21
deletes two-thirds of the output. Ranking anything by row count without accounting for the
floor will mislead.

### Tier
Visibility band derived from score (`Sources/SwiftInferCore/Tier.swift`):

| tier | rule | shown by default |
|---|---|---|
| `verified` | `strong` **and** verify reached `measured-bothPass` | yes |
| `strong` | score ≥ 75 | yes |
| `likely` | 40 ≤ score < 75 | yes |
| `possible` | 20 ≤ score < 40 | **no** — needs `--include-possible` |
| `suppressed` | score < 20, or any veto fired | never |
| `advisory` | informational, carries no runnable property | yes |

`verified` and `advisory` are never returned by `Tier(score:)` — the surfacing pipeline sets
them explicitly, because score alone cannot know a verify outcome.

**"Default tier" / "default surface"** in the docs means *what a plain run prints*:
`likely` and above, plus whatever the refutability rescue pulls up.

### Veto
A rule that suppresses a firing the template would otherwise make. Vetoes have been the
highest-yield catalog work in this repo — the stream-consumption veto took 53 false `likely`
claims on `SwiftParser` down to 1; the result-builder veto took SwiftSyntaxBuilder 23 → 2.
Contrast with *additions*, which have moved single-digit row counts.

### Seed / seed manifest
`{file, line, symbol}` records emitted by SwiftProjectLint's `--format pbt-seeds`, naming
functions worth pointing `discover` at. Consumed via `discover --seeds`. Kinds include
`pure-function`, `extractable-kernel`, `restricted-function`.

**A seed is not a suggestion.** 1,657 seeds have produced 21 default-tier picks on this repo.

### Lifted
A `mutating` method on a carrier, or a method reachable only through one, re-expressed as the
value-semantic `(T) -> T` shape a template needs. `idempotence-lifted` is the template; the
`+Lifted.swift` extensions are where lifting happens.

### Corroboration
Independent evidence that a proposed law is real — a docstring asserting it
(`DocstringPropertyCorroborator`), or an existing test body doing so (`TestLifter`). It raises
score; it does not by itself propose.

**`TestLifter` only corroborates.** Its detectors are keyed to existing templates, so
hand-rolled random-input property tests and libFuzzer harnesses are invisible to it.

---

## Refutability

### Refutable
A law some type-correct, plausible implementation would be **rejected** by. The scoring unit
this repo uses instead of suggestion count, because `f(x) == f(x)` passes "did discovery return
> 0" and can never fail.

Authority: `Refutability.isRefutable` (`Sources/SwiftInferCore/Refutability.swift`).

**Caveat — it is declared, not measured.** The current implementation is set membership against
`tautologicalTemplates`, which contains exactly one name (`determinism`). Everything else is
classified refutable *by template name*, at proposal time. Whether a given law, against a given
generator, could actually have failed is a different question and is not what this API answers.

### Role-entailed
A law a **correct** implementation cannot fail — it is owed *by virtue of the role*, not
conjectured from a name. A comparator owes a strict weak ordering; a predicate owes totality.

Orthogonal to refutable: refutable = *a wrong implementation can fail it*; role-entailed = *a
right implementation cannot*. A law wants both. `monotonicity` and `idempotence` are
conjectures and can be false of perfectly correct code.

### Tautology
A law true of every implementation that compiles. `determinism` (`f(x) == f(x)`) is the only
one, and it is what discovery emits for a seeded pure function no template matched — "I have
nothing to offer here," dressed as a finding.

### Rescue
`Refutability.preservingLastRefutable` — the invariant that no filter may take a run to zero
refutable laws. Fires when the tier cut or the seed focus is about to leave a reader holding
nothing that could ever fail.

**A rescue is a bug report, not a feature.** Every firing means an upstream stage has a blind
spot, and callers are required to say so loudly.

---

## Verify

### Carrier
The type a law is stated over — the `T` in `(T) -> T`. `Int`, `String`, `Decisions`, a reducer's
`State`. `carrierTypeName` on a `SemanticIndexEntry`.

### Strategist / generator recipe
`DerivationStrategist` (in SwiftPropertyLaws, **not** this repo) synthesizes a
`Gen<YourType>` per carrier. The result is a `GeneratorRecipe`, whose `expression` is the
generator source as a **string**. This repo calls the strategist and never reimplements it.

`.todo` marks where synthesis stopped and a human takes over.

### Composer
A function that renders the stub source for one template —
`composeIdempotencePass`, `composeRoundTripPass`, etc., in
`StrategistDispatchEmitter+Templates.swift`. Composers are pure
`(Inputs, GeneratorRecipe) -> String` and read the generator solely from `recipe.expression`.

**This is the set that determines verify's template reach**, and it is much smaller than the
catalog — see [Reach](#reach).

### Composer-supported
Said of a template that has a composer, and so of an index **entry** whose template has one —
i.e. the law can be *executed*, whatever the result turns out to be. The complement is exactly
the `unsupported-template` decline.

The set is the `switch` in `StrategistDispatchEmitter.defaultPassSection`, plus the algebraic
laws that dispatch through `algebraicLawPass` — thirteen templates, spelled once as
`TemplateName.verifiable`:

```
round-trip · codable-round-trip · idempotence · commutativity · associativity
idempotence-lifted · dual-style-consistency · monotonicity · involution
binary-idempotence · homomorphism · multiplicative-homomorphism · measure-non-negativity
```

Three things it is **not**:

- **Not a claim about the carrier.** A composer-supported template can still decline on
  `unsupported-carrier`, fail to compile, or trap. Composer support is necessary, not sufficient.
- **Not the same as "in the catalog."** Discovery emits template names that have no composer at
  all (`predicate`, `input-totality`, `inverse-pair`, …). Those are proposed, scored, tiered, and
  rendered to a reader exactly like any other suggestion — and then cannot be run. Measured on
  this repo's index: **95 of 251 entries composer-supported (38%)**.
- **Not a quality signal.** It says a stub can be composed. Whether the law could have *failed*
  is [refutation reach](#reach), a different and later question.

The term exists because "supported" alone is ambiguous across three gates — `supportedCarriers`
(Route 1 only), the composer switch, and the strategist's ability to derive a generator — and
attributing a decline to the wrong one is a documented way to build the wrong plan.

### Stub
The generated, compilable Swift package that actually runs a law. Built per suggestion in
`.swiftinfer/verify-workdir/`. One full SwiftPM workdir *each* — a 85-entry survey left 3.4 GB
behind, gitignored, accumulating silently. `make clean-temp` sweeps it.

### Pass 1 / Pass 2 (the edge pass)
Two runs of the same composed law. **Pass 1** uses the strategist's default generator and
**produces the verdict**. **Pass 2** uses a boundary-only recipe and is **advisory** — it
reports separately and cannot retract Pass 1.

The asymmetry is deliberate and load-bearing: boundary values cannot go in the verdict pass,
because `x + 1` traps at `Int.max` and the repo's existing tests depend on that being
unreachable at ~2⁻⁵⁸ per trial. Mixing them in turned three integration tests into
`signal 5` crashes. See `docs/verify-edge-pass.md`.

**Historical trap:** before 2026-07-31 Pass 2 was a hardcoded `print("VERIFY_EDGE_RESULT: PASS")`
with zero trials for every strategist-routed carrier. Any `measured-bothPass` recorded before
that date means *Pass 1 passed and Pass 2 was free*.

### Outcome
`VerifyEvidenceOutcome` (`Sources/SwiftInferCore/VerifyEvidence.swift`):

| outcome | meaning |
|---|---|
| `measured-bothPass` | no counterexample found in the generated domain |
| `measured-defaultFails` | Pass 1 found a counterexample — a **refutation** |
| `measured-edgeCaseAdvisory` | Pass 1 passed, the advisory boundary pass did not |
| `measured-error` | ran, but produced no verdict (build failed, timed out, crashed) |

**`measured-bothPass` does not mean "the property holds."** A derived generator is tuned for
coverage of the *type* and is silently mistuned for coverage of the *law*. Any law whose failure
needs two generated values to **collide** — merge tie-breaks, cache-key collisions, dedup, key
injectivity — is invisible to a generator drawing from a realistic domain.

### Decline
Verify returning no verdict because it could not build the attempt at all — as distinct from
running and passing. The `VerifyError` cases (`Sources/SwiftInferCLI/VerifyCommand.swift`):

| decline | meaning |
|---|---|
| `unsupported-template` | **no composer exists for this template.** The law was proposed, scored, and shown; nothing can run it |
| `unsupported-carrier` | the carrier type can't be resolved to a generator |
| `unsupported-pair` | a two-function template's pairing didn't resolve |
| `build-failed` | the stub was composed and did not compile |
| `runner-crashed` | the stub built and trapped |
| `monotonicity-domain-not-comparable` | pre-flight: `a ≤ b ⟹ f(a) ≤ f(b)` needs an ordered domain |

**`unsupported-carrier` is nearly always the wrong suspect.** It reads like the obvious
bottleneck and measures at ~4%. `supportedCarriers` — the constant that looks like the gate —
governs only the v1.46 hardcoded Route 1; everything else derives from `RawType` or an indexed
`TypeShape`. Reading that constant and believing it produced a wrong plan once already.

### Promotion
`strong` + `measured-bothPass` → `verified`. The only path to the top tier; score alone never
gets there.

---

## Reach

Three different numbers, routinely conflated. This is the distinction most worth keeping
straight.

**Discovery reach** — of the code scanned, how much gets a law proposed. Bounded by the
catalog. Measured badly by row counts, given the score floor.

**Verify reach** — of the laws proposed, how many can be *executed*. Bounded by the **composer**
set, not the catalog.

**Refutation reach** — of the laws executed, how many could actually have failed. Bounded by the
**generator**, and the newest of the three to be measurable.

Measured on this repo's own 251-entry index (2026-08-01):

| | entries | share |
|---|---:|---:|
| composer-supported | 95 | 38% |
| `unsupported-template` | **156** | **62%** |

and the 156 are not spread evenly:

| template | n | note |
|---|---:|---|
| `predicate` | **120** | 77% of the whole bucket — and a declined totality claim is arguably not a reach gap |
| `inverse-pair` | 14 | |
| `input-totality` | 11 | |
| `value-round-trip` | 3 | |
| `filter-subset` | 3 | |
| `differential-equivalence` | 2 | |
| `comparator` / `override-precedence` / `invariant-preservation` | 1 each | |

Net of `predicate`: **36 entries across 8 templates**, of which `inverse-pair` + `input-totality`
are 25 — **69% of the actionable gap in two composers**.

---

## Method

### Road test
Point the tools at a subject and score them. Requires a **frozen fixture** (the code before any
property work, pinned to a commit, never merged back into) and a **frozen answer key** (written
by hand, in advance, without consulting the tools).

**A tool may not grade its own homework.** Anything the tools find that the key missed is
recorded **unscored**, never folded in. A key edited in response to tool output stops being
independent the instant it is edited.

### Backtest
Point the *finished* tools at real, already-fixed defects in mature public libraries and ask
whether the loop would have caught each one **before** its fix. Stronger than a road test: a
public fix commit predates the tools and was written by someone who never heard of them, so it
removes the last degree of freedom a self-built answer key leaves open.

### Mutation corpus
Hand-authored mutants (reversible patches) kept **standing** and re-run whenever the toolchain
changes, to check the tests still catch the bug shapes they were written for. Distinct from the
frozen answer key: corpora are living tooling, deliberately sharpened over time.

The unit a generator should be scored in — `fixtures/integer-division-generator` reports
**2/8 → 8/8 mutants killed** alongside its coverage table, because coverage says boundary values
are *present* and only the mutant table says the test *catches* things it could not before.

### Latent
A shipped change verified on synthetic shapes that produces **zero delta on every measured
corpus**. Not a failure — a genuine absence, recorded as such so nobody mistakes "no effect
observed" for "not implemented."

### Statability gap
A law that is real, has population, and still cannot be written down generically — a fourth
failure mode beside not-scanned, not-paired, not-templated, and suppressed.

The worked example is the metamorphic family: ~599 carriers across five repos, so population is
not the blocker. The blockers are that type text is a *source spelling*, that locations are
*coordinates reformatting moves* — **"a template cannot tell a coordinate from a fact"** — and
that trivia is semantic inside `"""…"""`.

### Confident zero
The tool reporting "nothing here" when there was something. The failure mode this project
treats as worst, because a zero is believed and generates no follow-up. The first five-repo road
test returned **0 of 3** planted bugs this way, and each defect behind it was pinned in place by
a **passing test that asserted the buggy behavior**.

---

## Neighbours

Terms owned by sibling packages, listed because they appear in this repo's output.

**Effect lattice** — `pure < observational < idempotent < externallyIdempotent < nonIdempotent`,
with a `lub` join. Defined in SwiftEffectInference.

**Purity oracle** — `PurityInferrer`, the single authority both SwiftProjectLint's flagship rule
and this repo's veto consult, so the two can never disagree about what is pure. Refutes
`Date()`, `UUID()`, RNG reads.

**Purity gates must not relax to reach a target.** Removing the `throws` gate once re-admitted
`Process`/`Pipe`/`FileHandle`/SQLite at a stroke, with a subprocess-spawning function judged pure.

**Interaction family** — the five reducer/MVVM invariant families (idempotence, cardinality,
biconditional, referential-integrity, conservation). A separate vocabulary from `TemplateName`;
see `InteractionInvariantFamily`.

**`@ClockDeterministic`** — the claim that admits async code to verification. Bare `async` is
rejected, with a message saying how to make the claim.
