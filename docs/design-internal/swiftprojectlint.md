# SwiftProjectLint — the entry point

**Repo:** `~/xcode_projects/SwiftProjectLint` (`github.com/Joseph-Cursio/SwiftProjectLint`) ·
**Book home:** Appendix C, Chapter 15, and the seed hand-off in Chapters 12 and 16.

> **Counts re-verified 2026-08-06 (third pass)** · subject `SwiftProjectLint@08a4b09` · observer
> `SwiftInferProperties@2c599c0`
>
> Counts and measurements here are **dated and will rot**. Diagnoses, design rationale, and the
> reasons a decision was made **do not expire** — they were true when recorded and stay checkable.
> If the subject repo has moved, re-verify the numbers; don't re-litigate the prose.
>
> **What the third pass changed.** The subject moved 10 commits past the second pass's pin, and two
> of them changed the seed contract: a **new optional `effect` object** on `idempotency` seeds
> (§ *The effect tier*), and a fix to the `line` field's determinism. `RuleIdentifier` held at 202.
> One trap was retired — the stale `PBTSeed.role` doc comment was fixed upstream by `0d56d982`.
>
> **What the first pass got wrong, and how it was caught.** This doc was written against
> `6c88715` — a local checkout that turned out to be **46 commits behind its origin**. Two counts
> were stale within hours (`RuleIdentifier` 197 → 202, the testability family 7 → 9), and
> `make docs-drift` reported `ok` throughout, because it compared against local `HEAD` rather than
> the project. Both the checker and these numbers are fixed; the episode is why the checker now
> resolves a project tip and reports a behind-by-N clone as its own fact.

<!-- doc-provenance date=2026-08-06 subject=SwiftProjectLint@08a4b099276eb46e0a8b39a8ab0ea2f3e1e876c1 observer=SwiftInferProperties@2c599c02fd5a070b97c582a610909f542bbc5cdc -->

---

```
SwiftProjectLint ──▶ SwiftInferProperties ──▶ SwiftPropertyLaws ──▶ SwiftIdempotency
  refactor + seeds       discover + stubs        run the laws         retry-safety
        ▲                        ▲
        └──── SwiftEffectInference (purity oracle; no CLI, runs inside both) ────┘
```

A SwiftSyntax static analyzer with a macOS app and a CI-friendly CLI. Most of it has nothing to do
with property inference — it is a SwiftUI architecture linter. **This doc covers only the part that
does**, which is two jobs and nothing else:

| | job | output channel | who consumes it |
|---|---|---|---|
| **1** | **Make property-testable code exist** — extract a pure function, give a primitive a domain type, remove a blocker | the human-readable report | a person, who edits code |
| **2** | **Say where to point the next tool** — `{file, line, symbol, rule, kind, role}` | `--format pbt-seeds` JSON | `swift-infer discover --seeds`, and **only** that |

The two jobs are not independent, and the direction is the interesting part: **job 1's output
becomes job 2's input on the next run.** A kernel you extract this week is a named, analysable
symbol next week. That loop is the whole reason the linter sits upstream rather than beside.

It never says whether a property *holds*. It says where to look and what to fix.

### In and out, precisely

| | what | shape |
|---|---|---|
| **consumes** | a directory of Swift source | files on disk, parsed with SwiftSyntax; no build, no run, no network |
| | `.swiftprojectlint.yml` (optional) | severity overrides, category and rule enable/disable |
| | **SwiftEffectInference**, in-process | the purity oracle — a library dependency, not a CLI hop |
| **produces (1)** | the human report | `text` (default, collapses candidates) · `json` · `csv` — for a person |
| **produces (2)** | the seed manifest | `--format pbt-seeds` → JSON v2 — for `swift-infer discover --seeds`, and nothing else |
| | dropped-seed tally | **stderr**, so stdout stays a clean manifest |
| | exit code | severity-gated — except under `pbt-seeds`, which always exits 0 |

The two output channels are computed from **one** `issues` array. That is why disabling a noisy rule
to tidy the report also empties the manifest, and why the candidate flood is fixed in presentation
rather than detection (§ *The census flood*).

---

## The rule catalogue, and how little of it is about properties

`RuleIdentifier` has **202** cases. The rules package registers **192** rules, each exactly once —
so **10 enum cases are declared but never registered**.

Both figures are worth carrying, and so is their disagreement: an identifier is not self-evidently a
live rule. **Nothing asserts the enum and the registry agree**, which is exactly why they do not.

> **Counting method, because the obvious one is wrong.** A raw grep for `category: \.` returns
> **195**, and for `name: \.` returns 198 across 193 distinct values. Both overcount: six
> `SyntaxPattern(name: .unknown, …)` placeholders live in **test-only convenience initializers**
> (`MagicNumberVisitor`, `HardcodedStringVisitor`, `MemoryManagementVisitor`), three of which also
> set a category. Dropping the `.unknown` blocks gives 192, all distinct. The naive count inflates
> `accessibility` by 1 and `memoryManagement` by 2.

| category | rules | anything for property inference? |
|---|---|---|
| `codeQuality` | 52 | incidental — `couldBePrivateMember` **fights** the pipeline (§ 1a) |
| `architecture` | 32 | **3 rules** — the domain-type family (§ 1b), none of which seed |
| `modernization` | 25 | no |
| `accessibility` | 19 | no |
| `performance` | 14 | no |
| `stateManagement` | 13 | `Missing Equatable on State Type` is a blocker (§ 1c) |
| `animation` | 10 | no |
| `testability` | 9 | **the family** — candidates, kernels, blockers (§ 1a, § 1c) |
| `uiPatterns` | 7 | no |
| `security` | 5 | no |
| `memoryManagement` | 3 | no |
| `networking` | 3 | no |
| **total** | **192** | **~11 rules, 4 of which seed** |

**The ratio is the point.** Roughly 5% of the catalogue is upstream of property inference, and only
**four** rules reach the manifest at all. Everything else is a SwiftUI architecture linter that
happens to ship in the same binary. A reader who assumes "202 rules feed `swift-infer`" will
mis-estimate both the coverage and the flood; the correct mental model is a large linter with a small
deliberate seam cut into it.

`--categories testability` selects the 9, which is **not** the same set as the 4 that seed — two of
the seeding rules are testability, and the flood-collapsing opt-in is keyed to the category, not to
the seeding set. Confusing the two is how a reader concludes the manifest is empty when it is not.

---

## Job 1 — refactorings that create a subject

### 1a. Extract a pure function (the kernel family)

Three rules find pure logic, and they differ by **whether the logic already has a name**:

| rule | the logic is… | seed kind | can a tool act on it? |
|---|---|---|---|
| `Pure Function Property-Test Candidate` | a `func` | `pure-function` | yes — index it, propose laws |
| `Pure Closure Property-Test Candidate` | a closure passed to `sorted`/`filter`/`map`/`reduce` | `extractable-kernel` | **no** — extract it first |
| `Extractable Pure Kernel` | statements in the middle of an impure method | `extractable-kernel` | **no** — extract it first |

The third is the valuable one and the reason this family exists. `Docs/rules/extractable-pure-kernel.md`
carries the motivating case verbatim: `uploadRemainingChunks` is `private async throws`, does network
I/O, and has chunk arithmetic inlined in it that is a function of `(data.count, chunkSize, index)`
and nothing else. Two real bugs lived there — an unclamped resume counter that completes a partial
upload, and an empty file that never reports progress — and **no test could reach either**, because
reaching the arithmetic means standing up a live session and a server.

> A closure at least *exists* as a syntactic object. A kernel does not. It is a handful of statements
> separated from the I/O around it by nothing at all.

So the refactoring is not a style preference. It is the act of **creating a callable subject where
there was none** — and the linter's advice ("name this arithmetic") is exactly the precondition
`swift-infer` needs before it can do anything at all.

`ExtractablePureKernelVisitor` and `PureClosureCandidateVisitor` both hold a
`SwiftEffectInference.PurityInferrer` directly; `PureFunctionCandidateVisitor` reaches it through
`PropertyTestCandidacy`. That is why the linter and `swift-infer` can never disagree about what is
pure — same oracle, one instance each.

**Two gates worth knowing, both loosened by a road test that measured what the tightness cost:**

- **`throws` is not disqualifying.** A throwing function is reported as *pure but partial*
  (`PropertyTestCandidate.isPartial`). `throws` refutes *totality*, not referential transparency, and
  the consumer already knew how to narrow a law to the success set — `(try? f(x)) == (try? f(x))`.
  The exclusion meant `serialize(_:) throws -> String` was never named, so nothing downstream could
  propose it.
- **Instance methods are included.** `PropertyTestShape` is two-valued — `.ofInputs` and
  `.ofSelfAndInputs` — so a method reading only immutable stored state is a candidate, it just needs
  a `self` built first.

`PropertyTestCandidacy` is shared rather than private for a specific reason stated in its own doc:
`couldBePrivateMember` tells you to narrow a declaration used only in its own file, which is sound
scope advice that — applied to a pure function — puts it beyond `@testable import`. **Two rules each
individually right, composing into advice that destroys what the other just found.** They consult one
predicate so the rule can say what narrowing would cost.

### 1b. Give a primitive a domain type

Three Architecture rules, all `Info`, all **opt-in**:

| rule | signal | design |
|---|---|---|
| `Primitive Bypassing Its Domain Type` | a `[String: V]` beside an existing `[IdempotencyKey: V]` — same value type | Variant A, structural |
| `Primitive Named For Its Domain Type` | `idempotencyKey: String` in a project that declares `struct IdempotencyKey` | Variant B, name-keyed |
| `Shared Domain-Enum Field` | ≥3 unrelated types carrying the same project enum under the same field name, sharing no protocol | extract a marker protocol |

The design note is the one to keep: **primitive obsession is not detectable by a linter.** Whether a
given `String` "is really a dedup key" is domain knowledge in the developer's head, not in the
syntax. So the rules do not detect the disease — they **police the cure**. Once a newtype `W` over
primitive `P` exists and is used to key a map, a same-shaped map still keyed by raw `P` is a decidable
cross-file inconsistency. Undecidable becomes a cross-file check.

The matching value type is the false-positive guard, and it only holds when `V` is itself
distinctive — a bare-primitive value type (`[…: String]`) makes it worthless, because those maps are
ubiquitous. A 32-project field sweep is cited in the rule doc for that calibration.

**Why this family matters for property inference at all:** a law is stated over a **carrier**, and a
newtype is a carrier with an invariant that a bare `String` does not have. `Percentage` can own
"always in `0...100`"; `String` cannot. The refactor turns a value with no laws into a type that owes
some.

**And here is the honest gap: none of these three rules seed.** `PBTSeedsFormatter.seedKinds` maps
exactly four rules, and all four are testability/idempotency (below). A reader who adopts a domain
type gets no manifest entry for it, and the linter's own history says why that is expensive — see
*"a finding the linter prints but does not seed is a finding the pipeline does not have"* under Job 2.
Whether these should seed is **open**, not decided; the carrier they create has no callable function
attached, so a `pure-function` kind would be a lie and a new kind would be a v3 schema event.

### 1c. Blockers — things to remove before anything works

`Global Mutable State` · `Non-Injected Nondeterminism` · `Missing Equatable on State Type` ·
`Impure Call in View Body`. Warnings about things that are broken; they do not seed and are not
collapsed from the report. `Missing Equatable` is the quiet one — a law needs `==` to state a
conclusion, so a state type without it cannot carry one.

**The family grew to 9 on 2026-08-03** (`View Hosting Before Inspection`,
`Observable Environment View Missing Inspection Hook`). Both are about **ViewInspector** — whether a
test can drive a SwiftUI view at all — which is testability in the harness sense rather than the
property sense. Neither seeds, and the seeding set is unchanged at four: this family is the category
`--categories testability` selects, not the set `PBTSeedsFormatter` reads.

---

## Job 2 — the seed manifest

`swiftprojectlint <path> --format pbt-seeds > .pbt/seeds.json`, consumed by
`swift-infer discover --seeds`. One hop, one consumer.

### Schema (v2)

```json
{ "version": 2,
  "seeds": [ { "file": "Sync.swift", "line": 41, "symbol": "chunkCount",
               "rule": "Pure Function Property-Test Candidate",
               "kind": "pure-function", "role": "partition" },
             { "file": "Sync.swift", "line": 88, "symbol": "offset",
               "rule": "Pure Function Property-Test Candidate",
               "kind": "restricted-function", "restriction": "enclosing-type" } ] }
```

Both sides pin **2** (`PBTSeedManifest.currentVersion`, `SeedManifest.supportedVersion`). Producer
and consumer each declare `file`/`line`/`symbol`/`kind` required and `role` optional, for the same
stated reason: an absent role is honestly unknown and nothing acts on it, whereas an absent `kind`
would have to be *guessed*, and the guess decides whether a consumer narrows discovery onto the seed.

**`restriction` (added 2026-08-03, optional, `restricted-function` only)** — `declaration` or
`enclosing-type`, from `TestRestriction`. `kind` says a test cannot reach the symbol; this says what
would have to move, and **the two remedies are not interchangeable**: widening a member nested
inside a `private` type compiles and changes nothing, so a consumer acting on `kind` alone can emit
a patch that unblocks nothing and then read the resulting verification failure as evidence against
the *law*. `enclosing-type` wins when both apply, because it names the binding constraint.

Measured when it shipped: **27 of 338** restricted seeds on SwiftProjectLint (8%) and **18 of 659**
on SwiftInferProperties (2.7%) are `enclosing-type` — small, non-zero, and silent in exactly the
direction that would have been misread. No version bump: absent means "producer does not classify",
and a seed without it is byte-identical to one written before.

### Every field, and who may rely on it

| field | required | values | consumer use |
|---|---|---|---|
| `file` | ✅ | path as walked | **focus key**, with `symbol` |
| `line` | ✅ | 1-based | reported to the reader; **not** matched on |
| `symbol` | ✅ | resolved name | **focus key**, with `file` |
| `rule` | — | rule display name | attribution in warnings |
| `kind` | ✅ | 4 cases, below | decides whether the seed may focus at all |
| `role` | — | 6 cases | decides what law is *owed* |
| `restriction` | — | `declaration` · `enclosing-type` | names what must move to verify |
| `effect` | — | object, below | **`idempotency` seeds only; unread today** |

**`line` is carried but never matched on**, and that is load-bearing rather than incidental. The
subject fixed a real nondeterminism in it on 2026-08-06 (`36df9996`): `getLineNumber` measured a
cross-file finding against whichever converter was installed last, so **476 of 3,844 findings moved
between two runs over an unchanged corpus**. Because `Discover+Seeds` keys the focus set on
`(file, symbol)`, that defect could not perturb which functions got focused — the consumer was immune
by construction, not by luck. 472 of the 476 came from the two "could be private" rules, which do not
seed. Worth knowing before anyone "optimises" the focus key to include `line`.

### The effect tier — a field this repo does not yet read

Shipped upstream 2026-08-06 (`9a21f3c1`), on `idempotency` seeds only:

```json
"effect": { "declared": "idempotent", "resolved": "non_idempotent",
            "provenance": "inferred-upward", "depth": 3 }
```

| sub-field | values |
|---|---|
| `declared` | `pure` · `idempotent` · `observational` · `externally_idempotent` · `non_idempotent` |
| `resolved` | same five — what the body actually reaches |
| `provenance` | `declared` · `inferred-upward` · `inferred-downward` |
| `depth` | 1 = every contributing callee was annotated; 4 = survived three unannotated hops |
| `reason` | the phrase a heuristic matched (`inferred-downward` only) |

Three things make this more than a convenience field:

- **The valuable half is `resolved`, not `declared`.** A consumer parsing the same source can read
  the annotation itself. What it cannot reproduce is a cross-file, multi-hop lattice join through
  the call graph — knowledge only the linter has, which died at the manifest boundary until now.
- **Provenance travels with the tier because the treatments differ** — a *declaration* vetoes a
  proposed law, an *inference* demotes it. A bare tier forces a guess and both guesses cost:
  inference-read-as-declaration suppresses laws that may be true; declaration-read-as-inference
  dilutes the strongest signal the author ever gave. *"A tier without its provenance is not a weaker
  version of this field; it is one the consumer cannot safely use."*
- **The tiers use the annotation grammar** (`non_idempotent`, not `nonIdempotent`) because that
  spelling is already shared by humans, this linter, and SwiftEffectInference. A second spelling
  would be a fourth dialect.

**Status on this side: READ, as of `f33dfd1` (2026-08-06).** `SeedManifest.Seed.effect` decodes it
(`decodeIfPresent`, so a seed without one is still valid), `SeedEffect` mirrors the producer's five
tiers and three provenances, and `SeedEffectResolver` consumes them. The hand-off is complete —
**this row was written the same day describing it as inert, and was true for about two hours.**

What it buys, in the committing change's own words: `EffectResolver`'s local pass runs
`applyBodyInference` **one hop**, against a budget that must fit inside §13's 2-second `discover`
ceiling. A linter running ahead of the pipeline has no such constraint, so *"a `@NonIdempotent`
several calls down, which the local pass structurally cannot see, arrives already resolved — for
free, since the linter already paid."* That is the argument for the field: not a shortcut, but a
tier the consumer **cannot compute** within its own budget.

### The four seeding rules

```swift
static let seedKinds: [RuleIdentifier: PBTSeedKind] = [
    .pureFunctionCandidate:  .pureFunction,
    .idempotencyViolation:   .idempotency,
    .extractablePureKernel:  .extractableKernel,
    .pureClosureCandidate:   .extractableKernel
]
```

`.pureClosureCandidate` was held back once as "a separate, deliberate step," and the source records
what that cost: the kernel visitor is arithmetic-shaped, so on the road-test fixture it seeded
`uploadRemainingChunks` and `collect` and **could not see** `fetchLocalFiles`, whose logic is a
predicate and a comparator. The closure rule fired on both halves and said the right thing — and the
finding died in the formatter. No reader was asked to extract it, no comparator law was proposed, and
the bug in the predicate was reached by 1 cold reader in 3, by ignoring the manifest and reading the
code.

> **A finding the linter prints but does not seed is a finding the pipeline does not have.**

### Three fields, three different questions

| field | question | authority |
|---|---|---|
| `symbol` | *where* to look | `LintIssue.symbol` |
| `kind` | *whether a tool can call it yet* | `PBTSeedKind.isAnalysable` |
| `role` | *what law it owes* | `PBTSeedRole.impliesEntailedLaw` |

**`kind` — analysable vs refactor-pending.** Four cases produced, five recognised:

| kind | produced by | `isAnalysable` | what it means |
|---|---|---|---|
| `pure-function` | `.pureFunctionCandidate` | ✅ | pure and total; index it, propose laws |
| `idempotency` | `.idempotencyViolation` | ✅ | arrives with a ready-made property to verify |
| `restricted-function` | *demotion* of `pure-function` | ✅ | named and analysable; `private`, so not *verifiable* cross-module |
| `extractable-kernel` | `.extractablePureKernel`, `.pureClosureCandidate` | ❌ | the logic has no name yet; `symbol` is the **enclosing** function |
| `unrecognised(_)` | — *consumer-side only* | ❌ | a spelling this consumer does not know; fails loudly, never silently |

`restricted-function` has no rule of its own — it is `pure-function` demoted in
`PBTSeedsFormatter.effectiveKind` once `TestReachability` says no test can call the symbol.
`pure-function`, `idempotency` and `restricted-function` are analysable; `extractable-kernel` is not. Feed a refactor-pending seed to a focus filter and you
get a **confident zero**: the tool narrows to a symbol it must then refuse (`private async throws`
refutes purity) and reports `kept 0` for a codebase full of property-testable logic.

**`restricted-function` is a label, not a gate**, and getting that wrong was measured. `@testable
import` reaches `internal` and no further, so a `private` pure function is analysable but not
verifiable from another module. The kind first shipped with `isAnalysable == false`, which conflated
two different obstacles:

| | symbol to analyse? | law proposable? | blocker |
|---|---|---|---|
| `extractableKernel` | no — the logic has no name | no | someone must draw a boundary |
| `restrictedFunction` | **yes** — name and signature | **yes** | one keyword, to *verify* it |

Answering the verification question with the analysis flag **suppressed 319 seeds on the linter's own
repository**, and silently switched off a `swift-infer` feature keyed to the analysable set. An app
has no public API; its pure logic lives in `private` helpers, so a private helper is often the *best*
property target.

The demotion happens in `PBTSeedsFormatter.effectiveKind`, driven by `TestReachability` — three-valued
(`reachable` / `unreachable` / `unknown`), because "the rule did not look" is a genuine third state
that must not be confused with "I looked and it is reachable."

**`role` — what the code is.** Six cases; three imply a law a *correct* implementation cannot fail:

| role | owes | entailed? |
|---|---|---|
| `comparator` | a strict weak ordering | ✅ |
| `predicate` | totality | ✅ |
| `partition` | a tiling — parts reassemble the whole, no gap, no overlap | ✅ |
| `transform` | only that it is a function | ❌ conjecture |
| `reducer` | *usually* associative, *often* has an identity | ❌ conjecture |
| `normalizer` | a round-trip and idempotence | ❌ conjecture |

`transform` and `reducer` are carried anyway and honestly: *"a consumer that wants only entailed roles
can filter; a consumer that never hears about a reducer cannot."*

**The entailment claim is what can rot**, not the spelling — `SeedRole.unrecognised` handles a
spelling mismatch loudly. If `swift-infer` ever demotes `comparator`/`predicate`/`partition` out of
`Refutability.roleEntailedTemplates`, the producer's `impliesEntailedLaw` becomes a lie in the exact
direction the whole project is designed against: proposing a law that correct code fails.
`SeedRoleContractTests` pins the correspondence from the consumer side.

The field exists because the consumer asked for it in its own output — `discover` was already warning
*"the manifest SHOULD have named it: this is a LINTER gap."*

### Two silences the formatter was taught to break

**Dropped seeds.** A seed-bearing finding with no resolved `symbol` is dropped, which is correct
behaviour and the wrong silence: the output is still valid JSON, still exits 0, and is simply shorter
than the run that produced it. `LintConfiguration.applyOverrides` rebuilt `LintIssue` without
carrying `symbol` across, so **configuring a severity on any seed-bearing rule silently emptied that
rule's contribution** — a confident zero at the entry point of the whole loop. The linter's own
`lossyStructRebuild` rule reported the responsible line and the finding went unread, which is the
argument for detecting the loss where it happens. `PBTSeedsFormatter.droppedSeeds` returns a
per-rule tally; the CLI prints it to **stderr** so stdout stays a clean manifest.

**The census flood.** On its own repository a default run produces **876 findings, 664 of them (76%)
from the two candidate rules** — 460 pure functions and 204 pure closures. That is not a bug in either
rule; the pipeline needs every one. It is a bug in what a human sees: the road test's sharpest result
was that the linter found a real defect in its own configuration code, reported it correctly, and
**the finding went unread**, buried among hundreds of "this function is pure" lines that require no
action and cannot be wrong. *Volume that large does not inform; it functions as silence.* This is the
Daikon trap arriving at the entry point.

`CandidateInventory` fixes it in **presentation, not detection** — and that distinction is
load-bearing. The CLI computes `issues` once and hands the same array to the report formatter and to
`PBTSeedsFormatter`; disabling the rules would empty the manifest and stop the linter feeding
`swift-infer` at all. So candidates are still found, counted, exported, and exit-code relevant; they
are just not printed one per line. Only `text` collapses — JSON/CSV stay complete, and `pbt-seeds`
exists precisely to carry them. `--categories testability` is itself the opt-in and turns collapsing
off.

**`.extractablePureKernel` stays listed**, and the rule is worth generalising: *a candidate rule
**nominates** ("this is pure, it could be property-tested") — there is nothing to do per item. A
kernel rule **diagnoses** ("pure logic is trapped here, and here is the refactor") — that is a claim
about a specific place, it can be wrong, and it is worth reading each time.*

`--format pbt-seeds` also bypasses the severity exit gate: it is an extraction format, not a lint
gate, and a redirect into `.pbt/seeds.json` must not abort under a threshold.

---

## The hand-off, read from the consumer side

Worth reading `Sources/SwiftInferCLI/Discover+Seeds.swift` in full; the short version:

- **A seed focuses, it does not extend.** Discovery scans the whole target and *then* narrows to
  seeded functions. An empty manifest focuses to **zero**, not to all. A missing or malformed file is
  an error, not a silent fallback.
- **Refactor-pending seeds never focus.** They are reported to the reader as work to do.
- **The focus never hides a law the code OWES.** `keepRoleEntailedLaws` overrides the focus for
  role-entailed laws, and the warning it prints names the **linter** as the culprit: *"the manifest
  SHOULD have named it: this is a LINTER gap … the usual cause is a shape the linter cannot see —
  methods on a value type it just told you to extract, a computed-property read, a call to `min`."*
- That rule was earned by a cold reader whose sentence is the specification: **"Doing what the tool
  asked *lost* coverage."** They performed the extraction the linter demanded; the linter then failed
  to seed the value type it had just told them to create; the focus found no match for the
  `partition` law discovery had produced and dropped it. The sharpest law in the run vanished
  *because the reader complied*.
- `guardFinalAnswer` is the backstop: a non-empty answer containing zero refutable laws, when the run
  found one, is a lie and the law comes back — with opposite warnings depending on whether the **tier
  cut** (a scoring bug) or the **focus** (a linter gap) ate it.

---

## Traps

- **Rule counts disagree across four places.** README says 160, Appendix C says 189,
  `RuleIdentifier.swift` has **202** `case`s, and the rules package registers **192**. **Read the
  enum** for "how many rules exist" (`RuleIdentifier.allCases.count` is the only figure anything
  tests against); read the category census for "how many are reachable by `--categories`". **The
  10-case gap is unexplained and untested**, and a declared-but-unregistered identifier is a rule
  that can be configured, named in a severity override, and never fire. Do not silently pick
  whichever number supports the sentence you are writing.
- **Counting registered rules by grepping `category:` or `name:` overcounts.** Six `.unknown`
  `SyntaxPattern` placeholders sit in test-only convenience inits and are not rules. This bit *this
  doc* — see the counting-method note in the catalogue section — and the naive numbers (195 / 193)
  are close enough to the right one to survive review.
- ~~**`PBTSeed.role`'s doc comment is stale.**~~ **Fixed upstream 2026-08-06** (`0d56d982`, *"Say how
  many rules classify a seed role, and name them"*). The standing fact it recorded still holds and is
  the thing to remember: **three of the four seeding rules classify a role** — the two candidate
  rules and `ExtractablePureKernelVisitor` — and `.idempotencyViolation` is the only one that does
  not. Kept struck-through rather than deleted because the *count* is what a reader needs and the
  trap is where they will look for it.
- **Only `PureFunctionCandidateVisitor` sets `testReachability`.** Everything else leaves it
  `.unknown`, which `effectiveKind` treats as reachable — deliberately, since demoting on "the rule
  did not look" would silently shrink the manifest. Consequence: the `restricted-function` demotion
  applies to pure-function seeds and to nothing else today.
- **The seed count is not a suggestion count.** Re-measured 2026-08-06: **2,096 seeds → 180
  default-tier picks** on SwiftInferProperties (was 1,657 → 21), of which only **3 `strong` + 27
  `likely`** — the other 150 are rescue and advisory rows. A **seeded** run prints **1,738**, *more*
  than an unseeded one, because 662 `restricted-function` seeds vouch for private functions a plain
  run never opens. Never report one count as evidence about the other, and say which reading of
  "default tier" you mean.
- **The repo's own README opens with "THIS IS AN EXPERIMENT IN VIBE-CODING"** and says outright that
  some rules are bad ideas, some are poorly implemented, and some are both. The testability and
  idempotency families are the road-tested ones; treat a rule outside them as unvetted until measured.

---

## Where to look

| question | file (in `SwiftProjectLint`) |
|---|---|
| the manifest schema, seed kinds, dropped-seed detection | `Sources/Core/Export/PBTSeedsFormatter.swift` |
| the effect tier, its provenance, and why both travel | `Packages/SwiftProjectLintModels/…/PBTSeedEffect.swift` |
| which rules exist at all, and the count nothing tests | `Packages/SwiftProjectLintModels/…/RuleIdentifier.swift` |
| what a role is and why these six | `Packages/SwiftProjectLintModels/…/PBTSeedRole.swift` |
| reachability's three values | `Packages/SwiftProjectLintModels/…/TestReachability.swift` |
| why the report collapses candidates but the manifest does not | `Sources/Core/Export/CandidateInventory.swift` |
| what counts as a pure-function candidate | `Packages/SwiftProjectLintVisitors/…/PropertyTestCandidacy.swift` |
| the kernel motivating case, with its two real bugs | `Docs/rules/extractable-pure-kernel.md` |
| policing the cure vs detecting the disease | `Docs/design/primitive-bypassing-domain-type-rule-design.md` |
| the format wiring and the exit-gate bypass | `Sources/CLI/OutputFormat.swift`, `SwiftProjectLintCLI.swift` |
| consumer side of the same hop | `SwiftInferProperties/Sources/SwiftInferCLI/Discover+Seeds.swift`, `SeedManifest.swift`, `SeedRole.swift` |
| the vocabulary, both sides | `docs/design-internal/glossary.md` — *Seed / seed manifest*, *Role-entailed*, *Confident zero* |
