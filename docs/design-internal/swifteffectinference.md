# SwiftEffectInference — the shared leaf

> **Status:** `reference` · **As of:** 2026-08-17


**Repo:** `~/xcode_projects/SwiftEffectInference` (`github.com/Joseph-Cursio/SwiftEffectInference`) ·
**Book home:** Appendix C; Chapter 26 §26.3 (the lattice), Chapter 22 §22.6 (clock-determinism).

> **Counts verified 2026-08-06** against subject `SwiftEffectInference@6f45139` · observer
> `SwiftInferProperties@2c599c0`
>
> Counts and measurements here are **dated and will rot**. Diagnoses, design rationale, and the
> reasons a decision was made **do not expire** — they were true when recorded and stay checkable.
> If the subject repo has moved, re-verify the numbers; don't re-litigate the prose.
>
> **What the 2026-08-06 pass changed.** The pin divergence **reversed direction and is no longer
> blocked**: SEI#1's regression was fixed (`6470222`), this repo bumped from `1f2265a0` to HEAD, and
> the §13 budgets were re-measured green. SwiftProjectLint was then the laggard, by two commits, with
> a named consequence. Size held at 13 files / ~3,800 lines.
>
> **2026-08-07 — pin only, counts NOT re-verified.** SEI moved two commits to `bc084fb` (`01bcdf7`
> *Track what an inferred effect rests on*) and this repo's pin was bumped to match, closing the
> divergence — see § *The pin divergence*. That section and the **§13 perf table** are current (all
> 8 budgets re-measured green at `bc084fb`); **the file/line counts and every other number still
> describe `6f45139`** and have not been retaken. The bump was source-compatible (additive, defaulted
> argument), so the diagnoses are unaffected.

> **2026-08-16 — three claims went stale, and one of them was a Trap.** SEI's README was fixed
> (`94610c0`), so *Traps* item 1 no longer describes it — corrected in place, because a trap is a live
> warning rather than a diagnosis and a false one costs a reader a wasted lookup. Item 4 and the
> anchor's "open end" are both **further along than this doc says**: `verdict(for:)` is adopted at the
> scan boundary and `anchor` is read by `SeedEffectResolver`. Both corrected below with what remains
> genuinely open. Size re-counted: **13 files / 3,975 lines**.
>
> **Later the same day the pins moved for real.** SEI grew a shared nondeterminism classifier and a
> clock-determinism refuter (SEI #10, #11); both consumers now pin `22342ca`, and the **§13 table has
> a fresh column measured at that pin** — the first re-measurement since `bc084fb`. Every other
> number still describes `bc084fb`/`6f45139` and was not retaken. Size after those two: **15 files /
> 4,362 lines**.
>
> **And the dead subsystem stopped being dead.** SwiftProjectLint's `HeuristicEffectInferrer` was
> migrated onto `CallSiteEffectInferrer` (SwiftProjectLint #105), so **every engine in the table now
> has a consumer** and the 37% figure recorded earlier that day is obsolete. See § *The engines*.

> **2026-08-17 — pins and prose only; no count was retaken.** The § *pin divergence* table had gone
> **two bumps stale** while claiming both consumers were `at HEAD`, which is the one error that
> section is about. Corrected to `c66fceb` — where both consumers actually agree — and the
> currency claim replaced with the distance from SEI's tip (`3ea25f2`, 1 source commit ahead). The
> §13 table gains the `8127f26` column that was measured but never landed, and deliberately stops
> there. The guard's first live catch is recorded in that section.
>
> **Nothing else here was re-verified.** File/line counts, engine figures and every census number
> still describe the revision each of them names — most `bc084fb`/`6f45139`, some `22342ca`. Read a
> number together with the pin beside it, never together with this date.

> **2026-08-17, later — both consumers bumped to `3ea25f2`, and this is the first bump that MOVES
> VERDICTS.** Every previous one in this record was additive: a defaulted field, a split kind, a
> refuter this repo's corpus did not reach. `50125f8` is not. It closes the non-throwing half of the
> I/O hole — `FileHandle.standardError.write(_:)` does not throw, so the `throwsOnlyItsOwnErrors` gate
> never covered it, and SEI measured **7 non-refuted functions writing to standard error and judged
> pure, including both of this package's own `writeDiagnostic(_:)`** — and it makes
> `hasRefutingMarker` consult `NondeterminismSources` as a **union** with the existing token set
> rather than a replacement, which matters because the classifier is AST-precise and therefore
> *narrower* in places; swapping would have relaxed a gate whose over-refutation is deliberate.
>
> §13 was re-measured first, per protocol: **all 8 budgets green, every row within noise** of
> `8127f26` — see the new column. So the extra refutation is free at the perf scale. **What it costs
> in verdicts is a different question and is not answered here** — the census counts in
> `docs/measurements/` were taken at `c66fceb` and earlier, and a refuter that withholds `.pure`
> moves them by construction. Each census doc names its own pin; that is the number to trust.

<!-- doc-provenance date=2026-08-17 subject=SwiftEffectInference@c66fceb pinned=c66fceb825eebf77477631388e1ba4326a7aa4e6 observer=SwiftInferProperties@58e1b65 -->


```
SwiftProjectLint ──▶ SwiftInferProperties ──▶ SwiftPropertyLaws ──▶ SwiftIdempotency
        ▲                        ▲
        └──── SwiftEffectInference (purity oracle; no CLI, runs inside both) ────┘
```

The smallest package in the toolchain and the only one with **no CLI and no dependents below it** —
15 source files, ~4,362 lines (re-counted 2026-08-16, after SEI #10/#11), depends on nothing in the
set. It is a library two other tools *embed*, which is the entire architectural point: **the linter and the inference engine consult one
purity oracle, so they cannot disagree about what is pure.**

### In and out, precisely

The only member of the toolchain with **no process boundary** — so its "output" is return values, not
files, and there is no format to version.

| | what | shape |
|---|---|---|
| **consumes** | SwiftSyntax nodes, in memory | `FunctionDeclSyntax` · `ClosureExprSyntax` · `AccessorBlockSyntax` — never a path, never source text |
| | doc-comment and attribute annotations | the `@lint.effect` grammar + `@Idempotent`-family attribute names, matched **by name** |
| | *(nothing else)* | no config, no disk, no network, no build |
| **produces** | `Effect?` | the five-tier lattice position, or `nil` for "no opinion" |
| | `PurityVerdict` | `pure` · `pureButPartial` · `refuted` — separates transparency from totality |
| | `Bool` | the `isPure` overloads, for the three node kinds |

**`nil` is a real answer and is not the same as `.pure`.** It means the oracle declines, which is why
`@EffectUnknown` needed its own predicate (`declaresUnknownEffect`) rather than a sixth tier: before
it, an author's explicit *"I cannot determine this"* returned the same `nil` as an unannotated
declaration **and** as a misspelled tier — three different situations collapsed into one.

That claim is the thing to check when reading this doc, because for most of this document's history
**the two consumers did not compile against the same revision** — and between 2026-08-03 and
2026-08-06 they deliberately could not, the gap costing a measured ~2× regression on this repo's hot
path, filed as
[SwiftEffectInference#1](https://github.com/Joseph-Cursio/SwiftEffectInference/issues/1). As of
2026-08-16 both pin `22342ca` and the claim holds; it is a state that has broken repeatedly, so read
the pin rather than this sentence. See [The pin divergence](#the-pin-divergence).

---

## The lattice

```
pure < observational < idempotent < externallyIdempotent < nonIdempotent
```

`Effect` (`Effect.swift`, 115 lines) is a five-case enum with a `rank` (0…4) and a `lub` that is
**rank-only**: `rank >= other.rank ? self : other`, with left-bias on ties. `lub(of:)` is the
collection form, returning `nil` for empty input.

**Two axes are stacked in one chain, and the doc comment is explicit about it.** The upper four
tiers classify *retry-safety* — the original axis, and SwiftIdempotency's concern. `pure` was
**inserted at the bottom later** to add the *referential-transparency* axis, which is the one a
property-based test needs. Every pure function is retry-safe; an observational function that logs or
reads a clock is retry-safe and not pure. So the chain reads in one direction and is used in two.

**What is deliberately omitted, and why.** SwiftIdempotency's reference lattice is a genuine
*non-linear partial order* with two elements SEI does not model:

- `transactional_idempotent` sits **parallel** to `externallyIdempotent` — incomparable, since one
  relies on a transaction boundary and the other on a caller-supplied dedup key.
- `unknown` is incomparable to `non_idempotent`.

Modelling either forces a Hasse-diagram join in place of the rank comparison — a substantial change
to the core algebra **for tiers no current consumer reads**. `transactional_idempotent` is, by
SwiftIdempotency's own design, a doc-comment-only tier needing transaction-boundary verification
neither a macro nor SEI performs. So the chain stays linear, and `EffectAnnotationParser` still
*recognizes* the spelling and projects it conservatively onto `.nonIdempotent` — the sound bound
absent verification, rather than a silent drop.

`Effect.rank`'s own doc warns the values are **relative ordinals, not a wire format** — they shifted
once already when `pure` was inserted at the bottom.

---

## The engines

| type | what it answers | swift-infer uses it? |
|---|---|---|
| `PurityInferrer` | is this function referentially transparent? | **yes** — via `SoundPurity` |
| `EffectAnnotationParser` | what did the author *declare*? | **yes** — 3 sites |
| `CallSiteEffectInferrer` | what does this call expression do? | **no** — SwiftProjectLint's, since `a9a242c` |
| `BodyEffectInferrer` | what does this body do, from its callees? | **no** |
| `EffectSymbolTable` | cross-file declared+inferred lookup | **no** |
| `NondeterminismSources` | is this expression determined by its inputs? | **no** — added 2026-08-16 |
| `ClockDeterminismRefuter` | does this body contradict its own `@ClockDeterministic`? | **no** — added 2026-08-16 |

> **2026-08-16 — the heading said "four" and the table listed five; it now lists seven.** The two
> additions are the shared nondeterminism classifier and the clock-determinism refuter (SEI #10,
> #11). Both are **refuters**, which is the pattern to notice rather than the count: like
> `PurityInferrer`, each answers *contradicted* or *no opinion* and neither will confirm a claim.
> `NondeterminismSources` is the one place the marker sets live, after the same argument-aware scan
> was found written twice — here and in SwiftProjectLint's `NonInjectedNondeterminismVisitor`, which
> now consumes it.

Measured by grep over `Sources/` on 2026-08-03: `PurityInferrer` 4 references,
`EffectAnnotationParser` 5, and **zero** for `EffectSymbolTable`, `BodyEffectInferrer`,
`CallSiteEffectInferrer`, `FunctionSignature`. That asymmetry is worth stating plainly: the
cross-file grading machinery — call-graph lub with depth tracking, framework-gated call-site
classification, collision-withdrawal — is **SwiftProjectLint's half of the library**. This repo uses
the two leaf primitives and none of the graph.

> **2026-08-16 — "SwiftProjectLint's half of the library" is half right, and the wrong half is
> load-bearing.** A grep over *both* consumers, run when asking what the linter was missing, found
> `EffectSymbolTable` heavily used there (and `BodyInference.anchor` with it) — but
> **`CallSiteEffectInferrer` has zero references in either repository.** SwiftProjectLint rolled its
> own `HeuristicEffectInferrer` instead.
>
> That leaves `CallSiteEffectInferrer` (536 lines) plus the three internals only it reaches —
> `FrameworkGates` (505), `ReceiverShapes` (339), `StdlibIdempotentMutations` (83) — at **1,463 of
> SEI's 3,975 lines, 37% of the package, consumed by nobody.** It is tested and maintained and no
> caller exists. Recorded, not acted on: the choice is to migrate SwiftProjectLint's inferrer onto
> it or to drop it, and that is a decision rather than a cleanup.
>
> **Resolved the same day — migrated, not dropped** (SwiftProjectLint
> [#105](https://github.com/Joseph-Cursio/SwiftProjectLint/pull/105), `a9a242c`). **Every engine in
> the table above now has a consumer** — all seven, counting the two added the same day — and the
> 37% figure is obsolete.
>
> The comparison is the part worth keeping, because it changes what the duplication *was*. These were
> not parallel implementations that happened to agree: SEI's inferrer was **lifted from an earlier
> revision of SwiftProjectLint's** and then maintained separately, and they had barely moved apart.
> `FrameworkGates` and SwiftProjectLint's `FrameworkAllowlist` were **byte-identical** once the type
> name was normalised — all 505 lines. `StdlibIdempotentMutations` differed only in access modifiers.
> `ReceiverShapes` differed only by helpers SEI had extracted from the other's inline forms. The four
> name allowlists were identical and the decision trees matched rule for rule, orderings included.
>
> So the linter carried **1,471 lines that are now 242** — forwarders onto the leaf, keeping the
> local API so the 260 existing assertions (212 `infer`, 29 `resolve`, 19 `isExcluded`) stay pointed
> at it and serve as the migration's regression suite. They pass unchanged, which is the evidence
> that no verdict moved.
>
> **The migration also fixed a defect the line count hides.** SwiftProjectLint's copy computed the
> effect and its reason in *two parallel decision trees*, each with its own `*Reason` helpers; SEI
> resolves both from one walk. Two trees over one rule set can disagree about which rule fired, and
> a violation crediting the wrong heuristic is exactly where that surfaces. Duplication is not only
> a maintenance cost — one of the copies had already grown a way to be wrong that the other could
> not.
>
> The framing above survives for `EffectSymbolTable` and `BodyEffectInferrer`. It was never checked
> against the linter for `CallSiteEffectInferrer` — the 2026-08-03 grep it cites was over **this**
> repo's `Sources/` only, and "this repo doesn't use it" was read as "the other one must."

### `PurityInferrer` — the one that matters here

> This is the **canonical** purity oracle for the ecosystem.

The soundness argument is the load-bearing part, and it is stated as an asymmetry:

> Purity is a *conjunctive* property — a function is `.pure` only when **none** of the refuters fire
> — so a single narrow analyzer can never *establish* it soundly; it can only **refute** it.

`.pure` is the lattice bottom and the most dangerous place to land wrongly, because every downstream
consumer *trusts* it: a generated property test runs a `.pure` function in-process and asserts a law
over random inputs. So the inferrer over-approximates by construction — **any doubt refutes purity**,
and a missed refuter would be unsound.

Two marker sets do the refuting, both matched by **bare identifier token**:

- **side effects** — `print`, `NSLog`, `FileManager`, `URLSession`, `UserDefaults`,
  `NotificationCenter`, `DispatchQueue`
- **nondeterminism** — `arc4random`, `arc4random_uniform`, `drand48`, `CFAbsoluteTimeGetCurrent`,
  `random`, `randomElement`, `shuffled`, `Date`, `UUID`

The token scan is **deliberately** crude and says so: it refutes `Date()` *and* the perfectly
deterministic `Date(timeIntervalSince1970:)` alike, and refutes injected `random(in:using:)` as well
as the system-RNG form. Over-refutation is the sound direction. The AST-precise forms live in
SwiftProjectLint's `NonInjectedNondeterminismVisitor`; **this token set is the leaf-level
over-approximation of that rule**, not a rival to it.

Plus signature gates: `async` refutes, a body-less declaration (a protocol requirement) refutes —
there is nothing to inspect — and the body must be total (no traps, no force-unwraps).

### `EffectAnnotationParser` — two grammars, plus one orthogonal marker

Reads declared effects in **both spellings**, so a project can annotate either way:

- doc comment — `/// @lint.effect pure`
- attribute — `@Pure`, `@Idempotent`, `@NonIdempotent`, `@Observational`,
  `@ExternallyIdempotent(by:)`

Recognized attribute names are configurable (`AttributeRecognition`), with a `.default` set. Parses
`FunctionDeclSyntax` and `VariableDeclSyntax`, in both static and instance form.

**`@ClockDeterministic` is not on the lattice, and that is the design.** It is an *orthogonal* marker
— `/// @lint.determinism clock_deterministic` or `@ClockDeterministic` — surfaced only via
`isClockDeterministic(declaration:)` and never via `Effect`. The reason is stated in the source:
`.pure` implies *synchronous*, so an async function can never be `.pure` no matter what the author
claims. The marker exists so downstream consumers can relax an **async veto** exactly where the claim
is present, without pretending the lattice moved.

That is the mechanism behind this repo's async story. `ViewModelDiscoveryVisitor:154` and
`ReducerDiscoverer` call it; `FunctionSummary.isClockDeterministic` and
`ReducerCandidate.isClockDeterministic` carry it forward. Bare `async` keeps a clean rejection that
says how to make the claim; the claim, once made, is what admits the code to verification.

### The two swift-infer does not use

`CallSiteEffectInferrer` (498 lines) classifies call expressions by callee name plus **the file's
imports** — framework-gated for FluentKit, Hummingbird, Vapor, AWSLambdaRuntime, TCA, swift-metrics,
swift-log. The gate exists because of a real false positive: a user-defined `class Counter` in a
module with no `import Metrics` was classifying as observational purely on the name match
(`FrameworkGates`, 505 lines — the largest file in the package).

`StdlibIdempotentMutations` is the companion suppressor: `append`/`insert`/`remove` are correctly
non-idempotent for a user-defined persistent queue and **wrong** for `Array.append` or `Set.insert`,
so `(typeName, methodName)` pairs suppress the bare-name inference back to "no heuristic applied."
`Set.insert` is idempotent by set semantics; `Dictionary.updateValue` is key-addressed and
replay-safe.

`EffectSymbolTable` resolves cross-file with **collision-withdrawal**: unannotated declarations do
not participate in collisions (an annotation expresses intent; an unannotated sibling is noise, not
ambiguity), and two annotated declarations with conflicting effects **withdraw the entry** rather
than pick one. Precedence is `declared > collision-withdraw (silent) > upward-inferred >
heuristic-downward > silent`, of which the table covers the first three.

---

## How this repo consumes it: `SoundPurity`

`SwiftInferProperties/Sources/SwiftInferCore/SoundPurity.swift` — 45 lines, and the reason the conjunctive framing above
matters. It takes the **meet of two independent refutations**:

```swift
guard ReducerPurityAnalyzer.analyze(function) == .pure else { return nil }
return PurityInferrer().inferredEffect(for: function)
```

- `ReducerPurityAnalyzer` refutes on TCA/concurrency effects (`Effect`, `Task`, `await`, `.run`,
  `.send`) and hidden mutation (static / `Self` writes).
- `PurityInferrer` refutes on I/O, logging, nondeterminism, and totality.

`.pure` is claimed **only when neither refutes**, and each analyzer is blind to the other's refuters.
Mapping `ReducerPurity.pure` onto `Effect.pure` alone would be **unsound**: a reducer can be
`ReducerPurity.pure` while calling `print()` or `Date()` or force-unwrapping.

Consumers of the result: `FunctionScannerVisitor+Summary.swift:38` sets
`FunctionSummary.isInferredPure` at scan time, where the syntax node is live; `EffectAnnotationAdvice`
renders it as a *"consider adding `/// @lint.effect pure`"* row on its own advisory channel
(`DiscoverArtifacts.effectAnnotations`) — deliberately **not** a property-test `Suggestion`, since
that would need a fabricated `Score` and `GeneratorMetadata` and would dead-end in the
templateName-driven accept/verify switches. `SoundPurity` only ever yields `.pure`, so the
recommended annotation is always that tier.

**This is the veto CLAUDE.md means** by *"Purity gates must not relax to reach a target."* Removing
the `throws` gate once re-admitted `Process`/`Pipe`/`FileHandle`/SQLite at a stroke, with a
subprocess-spawning function judged pure.

---

## The pin divergence — RE-OPENED and re-closed 2026-08-08

SEI carries **no version tags**, so both consumers pin by revision. As of 2026-08-07 they pin **the
same revision** for the first time, and the section title is kept rather than renamed because the
divergence is the thing worth remembering: it ran for weeks, and it had a named consequence each time.

> **2026-08-08 — it did not stay closed for a day, and the shape is worth more than the fix.**
> SEI moved two source commits; SwiftProjectLint bumped to `fc82ec4` and this repo did not, so the
> divergence re-opened **with this repo as the laggard** while the section above said CLOSED. A
> heading that records a state rather than a rule goes stale the moment the state changes — the
> rule is *read the pin from `Package.swift`*, which is the standing instruction in CLAUDE.md and
> the reason this table names the manifest line.
>
> Now at `50c5d3a`, which is `fc82ec4` **plus a docs-only commit**, so the two consumers are
> source-identical again.
>
> **A/B measured before bumping, because one of the two commits relaxes a purity gate.**
> `a7acb22` counts a nested closure's parameters as locals, which its own message says makes
> `isPure` *"strictly more permissive"* — and CLAUDE.md's standing rule is that purity gates must
> not relax to reach a target. This is an upstream bug fix rather than a relaxation, but that is
> an argument, not a measurement. Two release binaries, same afternoon, `discover
> --include-possible` over **seven corpora** — this repo's three targets plus `OrderedCollections`,
> `DequeModule`, `ArgumentParser` and `NIOCore`: **byte-identical output on all seven, zero rows
> moved.** The other commit, `20b6e5a`, is additive API (it publishes the capture-write clause on
> its own for SwiftProjectLint's `unreachable-effect-closure` rule) and cannot move a verdict here.

| package | manifest | revision | vs SEI `HEAD` |
|---|---|---|---|
| SwiftInferProperties | `Package.swift:122` | `3ea25f2` | equal to the linter's; **verify against SEI's tip, do not trust this cell** |
| SwiftProjectLint | root + `SwiftProjectLintVisitors` + `SwiftProjectLintIdempotencyRules`, all three | `3ea25f2` | equal to this repo's; **same** |

> **The `at HEAD` this table used to claim was the failure mode it exists to catch.** Both rows read
> `22342ca` / **at HEAD** (2026-08-16) while `Package.swift` said `c66fceb` — the manifest had moved
> twice underneath the prose (`fec2bf0`, then `7dad9f5`) and the table tracked neither. It is the
> exact error CLAUDE.md's standing instruction names: *read the pin from `Package.swift`, never from
> prose*. The rule was written because prose copies go stale; this table then went stale in the
> section whose entire subject is pin staleness.
>
> **The fourth column no longer states currency, and that is deliberate.** It used to hold `at HEAD`,
> which is a claim about a *third* repository's tip — the one fact this doc cannot keep true, because
> nothing in either consumer changes when SEI gains a commit. What the two consumers can be held to
> is **equality with each other**, which is the property the shared leaf exists to give and which
> `SEICrossRepoPinTests` and `SEIPinAgreementTests` actually enforce across all four manifests. So
> the column states equality and sends you to `make docs-drift` for the distance. A cell that cannot
> be guarded should not read like a measurement.

> **2026-08-16, later still — the guard's first live catch, and it was not a drill.** SEI split its
> `.clock` kind into five (SEI #12, `8127f26`) so SwiftProjectLint could hold its nondeterminism rule
> at the scope it had before consuming the shared classifier; the linter bumped, this repo had not
> yet, and `SEICrossRepoPinTests` failed **unprompted** — naming all four manifests and both
> revisions. Every earlier divergence in this section was found by a human re-reading a manifest.
> This one was found by the mechanism, hours after the mechanism was written, which is the entire
> argument for having written it on a day when it passed.
>
> Closed by `fec2bf0` to `8127f26`, then carried forward by `7dad9f5` to `c66fceb` when SEI #13 added
> the default-argument purity refuter — a bump SwiftProjectLint made in the same act
> ([SwiftProjectLint #113](https://github.com/Joseph-Cursio/SwiftProjectLint/pull/113)), which is the
> shape a shared-leaf bump is supposed to have. Both closures were additive here: this repo
> constructs no `NondeterminismSource` and calls neither new type, so no verdict moved.
>
> **The guard caught the divergence; it did not catch this doc.** `SEICrossRepoPinTests` reads the
> manifests, so the table above stayed wrong through both bumps without failing anything. A pin guard
> and a prose guard are different instruments — `make docs-drift` is the second one, and it reports
> against the `doc-provenance` trailer, which is why that trailer moves with this edit.

> **2026-08-16 — a divergence opened across real source for the first time in this record, and was
> closed the same day.** Every previous gap this section tracks was inert; this one was not. SEI
> gained `NondeterminismSources` and `ClockDeterminismRefuter` (SEI #10, #11), SwiftProjectLint
> bumped to consume them, and for the length of that work the two consumers compiled against
> different oracles. It was still *additive* — nothing this repo calls changed, so behaviour here
> was identical throughout — but "additive" is a weaker guarantee than the one the shared leaf
> exists to give, and the invariant is equality, not compatibility.
>
> Closed by bumping this repo to `22342ca`. `make perf` first and `make test` second, in that order,
> per the protocol below — the ordering exists because a bump that costs wall-clock should fail at
> the budget rather than 20 minutes later. All 8 budgets green; see the §13 table.
>
> Note also that `Package.resolved` is **not tracked** in this repo, so the manifest line is the
> whole of the pin here. The row above used to name both.

> **2026-08-12 — the roles reversed, and the pin is the thing to read, not the prose below it.**
> This repo is now **at** SEI's tip (`50c5d3a`, verified against `origin/main` after a fetch) while
> SwiftProjectLint sits 2 commits back in all three of its manifests. The paragraph following this
> table says the linter got there first; that was true on 2026-08-06 and is not now.
>
> The gap is inert: both intervening commits are a PRD citation repair and its merge
> (`07d9711`, `50c5d3a`), so no inference behaviour differs between the two pins. Recorded because
> the pin divergence is what this section exists to track, and because "docs only" is a claim that
> has to be re-checked each time rather than inherited.

**Both consumers now agree, and the linter got there first.** SwiftProjectLint was already at
`bc084fb` in all three of its manifests when this repo bumped from `6f45139` to match — so the
two-commit gap this section used to describe closed from the *other* side, which is the reverse of
how the previous two closures went. The convergence is the state the shared leaf exists to produce:
one purity oracle, one revision, no way for the two tools to disagree about what is pure.

The history of the gap, kept because each phase had a distinct cause:

| date | this repo | the linter | why the gap existed |
|---|---|---|---|
| 2026-08-03 | `1f2265a0` | `097181aa` | this repo held **two public methods against five** and the bump was blocked by the SEI#1 regression (§ *The bump was blocked*) |
| 2026-08-06 | `6f45139` | `bfcf0e3` | direction reversed; the linter's oracle could not read `@EffectUnknown` (`7a70b3b`), so `@lint.effect unknown` parsed to `nil` — **indistinguishable from an unannotated declaration and from a misspelled tier**, and the two tools could disagree about an author's own stated uncertainty |
| 2026-08-07 | `bc084fb` | `bc084fb` | — |

Both consumers compile against the full five-method `PurityInferrer` — `inferredEffect(for:)`,
`isPure(_: FunctionDeclSyntax)`, `verdict(for:)`, `isPure(_: ClosureExprSyntax)`,
`isPure(_: AccessorBlockSyntax)` — and both are past the regression that once blocked the bump
(`6470222` is an ancestor of both pins).

**What the 2026-08-07 bump adds here.** `01bcdf7` *Track what an inferred effect rests on* gives
`BodyInference` an `Anchor` (`.declared` / `.heuristic`), so a consumer can tell an author's
annotation from a name-or-framework guess. It is **additive with a default argument**, and this repo
constructs no `BodyInference` — it only calls `applyBodyInference` — so the bump is source-compatible.

> **2026-08-16 — "nothing here reads the anchor yet… declining is not wired up" is no longer true.**
> `SeedEffect` carries its own `Anchor`, and `SeedEffectResolver` withholds on it: seeds are filtered
> to `$0.anchor == .heuristic` and to upward chains with **no anchor stated** (`provenance ==
> .inferredUpward && anchor == nil`), both excluded, with the counts named in the withholding
> message. So declining a name guess is exactly what it does. An upward chain anchored on
> `.declaration` is a multi-hop cross-file walk and is admitted; a `.heuristic` one is a guess and is
> not — *"this tool does not veto on names."*

### The bump was blocked 2026-08-03, and is UNBLOCKED as of 2026-08-06

**Resolved in SEI, exactly where this doc predicted it belonged.** `6470222` — *"Stop the whole-domain
purity path paying for verdict's body walk"* — is the fix for
[SwiftEffectInference#1](https://github.com/Joseph-Cursio/SwiftEffectInference/issues/1), and it
implements the remedy proposed below verbatim: `inferredEffect(for:)` stops delegating to
`verdict(for:)`. Both consumers' pins now contain it.

**Re-measured on this repo, 2026-08-06, at pin `6f45139`** — a full `make test` run, the §13 perf
target in its own isolated step:

| §13 perf test | budget | at `1f2265a0` | at `097181aa` (regressed) | at `6f45139` | at `bc084fb` | at `22342ca` | at `8127f26` | at `3ea25f2` |
|---|---|---|---|---|---|---|---|---|
| Discover pipeline, 100 test files | 6.0s | 3.389s | **6.777s** ❌ | 4.219s ✅ | 4.310s ✅ | 3.573s ✅ | 3.535s ✅ | **3.551s** ✅ |
| TestLifter.discover, 100 files | 4.0s | 0.502s | 1.036s | 0.669s ✅ | 0.690s ✅ | 0.560s ✅ | 0.566s ✅ | **0.566s** ✅ |
| Discover, 50-file corpus | 2.0s | 0.671s | 1.356s | 0.916s ✅ | 0.960s ✅ | 0.752s ✅ | 0.746s ✅ | **0.746s** ✅ |
| …with decisions-load active | — | 1.660s | 3.652s | 2.238s ✅ | 2.406s ✅ | 1.827s ✅ | 1.812s ✅ | **1.814s** ✅ |
| 500-file corpus, peak RSS delta | 800 MB | — | — | 234.1 MB ✅ | 245.6 MB ✅ | 256.0 MB ✅ | 257.7 MB ✅ | **257.8 MB** ✅ |

The `bc084fb` column was taken 2026-08-07 by `make perf` (serial, alone, 22.1s, 8 tests). Every row
is within noise of `6f45139` — the anchor work adds a field to `BodyInference` and does not change
the walk, so a flat reading is the expected shape rather than a reassuring one.

The `8127f26` column was taken by `make perf` before `make test`, per the protocol above — all 8
budgets green, every row within noise of the `22342ca` column, which is the expected shape for a
split this repo does not call. **There is deliberately no `c66fceb` column.** The pin moved there in
`7dad9f5` without a perf run at that revision, and an unmeasured column inferred from the one beside
it is the precise thing the `097181aa` row exists to warn against — the regression that produced it
was *reasoned* to be free. The table stops where the measurements stop.

The `3ea25f2` column was taken the same way, `make perf` alone before `make test`, and all 8 budgets
are green with every row inside noise of `8127f26` (largest move: 16 ms on the 100-file pipeline,
0.1 MB on peak RSS). **A flat reading here is worth more than the previous flat ones**, because this
bump is the first that is *not* additive: `50125f8` adds a non-throwing-I/O refuter and makes
`hasRefutingMarker` consult `NondeterminismSources`, so unlike the anchor and clock-split bumps it
does move verdicts in this repo. The budgets say the extra refutation is free at the §13 scale; what
it costs in *verdicts* is a separate measurement and is recorded in the census docs, not here.

Slightly slower than `1f2265a0` and comfortably inside every budget, which is the expected shape: the
cheap path is restored, and the extra three methods are real work that path no longer pays for.

**The record below is kept as the diagnosis, not as current state.** It is the argument that a
reasoned claim is not a measured one, and that argument is why the regression was caught at all.

---

**Historical — the blocking measurement (2026-08-03).**
`097181aa` cost a **~2× wall-clock regression on the whole-domain purity path**, which is the path
this repo's every command runs. Five of the PRD §13 budgets failed, one hard.

Controlled A/B, same machine, same isolated `make perf`, one variable — the revision:

| §13 perf test | `1f2265a0` ×2 | `097181aa` | ratio |
|---|---|---|---|
| Discover pipeline, 100 test files (budget 6.0s) | 3.389s / 3.455s ✅ | **6.777s** ❌ | 2.0× |
| TestLifter.discover, 100 files | 0.502s / 0.511s | 1.036s | 2.1× |
| Discover on 500-file corpus | 10.369s / 10.582s | 21.833s | 2.1× |
| Discover, 50-file corpus | 0.671s / 0.700s | 1.356s | 2.0× |
| …with decisions-load active | 1.660s / 1.703s | 3.652s | 2.2× |
| whole perf run | 16.682s / 17.038s | 28.474s | 1.7× |

The control replicates to **~2%**, one arm after a clean build and one after an incremental one, so
the effect is ~50× the measurement noise. Matched on the same harness too: full `make test` passes end
to end at `1f2265a0` and fails at the `perf` step at `097181aa`.

**Diagnostic detail worth keeping:** the treatment got *worse* in isolation (6.777s) than under
full-suite load (6.263s). That is backwards for a contention flake, and it is what moved the
investigation off `MemoryCeilingPerformanceTests`' "rerun before blaming your edit" note and onto a
controlled A/B.

Two candidate mechanisms, **neither measured** — in a chain of costs the first one found hides the
rest, so this is left open rather than guessed:

1. **`throws` no longer short-circuits before the body walks.** At `1f2265a0`,
   `isSynchronousAndNonThrowing(function.signature)` rejected throwing functions on a *signature*
   check. At HEAD only `async` short-circuits, so every throwing function pays two full traversals —
   and Swift corpora, test code especially, are dense with `throws`.
2. **The body-walk helpers were generalized to erased `Syntax`** (`hasRefutingMarker(in: Syntax(body))`,
   `isTotal(Syntax(body))`). Necessary — it is what lets HEAD answer purity for closures and computed
   properties — but it is on the hot path.

The proposed fix lives in SEI, not here: `inferredEffect(for:)` should stop delegating to
`verdict(for:)`. `verdict` genuinely needs the body walk to tell `.pureButPartial` from `.refuted`;
the whole-domain question does not, because `throws` disqualifies outright.

### What this cost, and the lesson it carries

**The paragraph that used to sit here said the drift was latent and nothing observable was broken.**
It reasoned — correctly — that `SoundPurity` calls only `inferredEffect(for:)`, that the method exists
at both revisions, and that its *answer* is unchanged. All true. The *cost* doubled, and reading the
code could not see it.

That is the identical shape as SwiftIdempotency's shrinker-composition entry, which sat labelled
*"not experimentally verified — the claim rests on reading the source"* until somebody wrote the
failing property in five minutes and found the reasoning had been optimistic. Same failure, recorded
in a document arguing that this failure keeps happening. **A reasoned claim about behaviour is not a
measured one, and "I read the call site" is not a measurement.**

### The invariant still stands, and is now reachable

**Keep this pin equal to SwiftProjectLint's**, not current with SEI's HEAD. The claim the shared leaf
exists to support — *the linter and the inference engine can never disagree about what is pure* — is
about the **oracle they compile against**, not the repository. The blocking reason is gone, so the
inequality is no longer *on purpose*; it is now just unfinished.

**The guard situation improved by half on 2026-08-04.** SwiftProjectLint's `SEIPinAgreementTests`
asserts its own **three** manifests name one revision — the duplication that a comment saying "keep
this aligned" was previously all that coordinated. Its doc comment is careful about what it cannot
reach: *"This test cannot see that cross-repo gap; nothing in a single repository can. What it can do
is make sure that when this repository's pin moves, it moves in all three places at once."*

So of four manifests across two repos, three are now guarded as a group and **the cross-repo equality
is still unchecked** — the same failure shape CLAUDE.md has a rule for on the other dependency
(*"The verifier's kit pin must equal this package's own,"* guarded by `VerifierWorkdirKitPinTests`,
written after that pin drifted a full major version unnoticed).

Progress against the ordered list this section used to carry:

| | item | state |
|---|---|---|
| 1 | **SEI#1** — restore the cheap path | ✅ **done** (`6470222`) |
| 2 | bump, re-running `make perf` before `make test` | ✅ **done** — budgets green (this repo reached HEAD 2026-08-07; 2 docs-only commits behind as of 2026-08-16) |
| 3 | pin-equality guard, phrased as *equality with the sibling consumer* | ⚠️ **half** — intra-repo guarded there, cross-repo unguarded |
| 4 | adopt `verdict(for:)` for `.pureButPartial` | ⚠️ **half — corrected 2026-08-16.** Adopted at the scan boundary; **no consumer reads the third state**, deliberately |
| 5 | SwiftProjectLint may be paying the regression unmeasured | ✅ **moot** — its pin is past the fix |

Item 4 is the one with value left in it: a `.pureButPartial` function is a real candidate whose law
narrows to the success set, and it is the surface the seed manifest's own `isPartial` field was built
to carry.

> **2026-08-16 — the sentence that used to end this paragraph said this repo "does not call it," and
> that was wrong.** `SoundPurity.verdict(for:)` calls `PurityInferrer().verdict(for:)`, and
> `FunctionScannerVisitor+Summary.swift:71` computes it at scan time and carries it on
> `FunctionSummary.purityVerdict`. What is *actually* open is one step further in: **nothing reads
> `.pureButPartial`.** That is a measured decision, not an oversight — of 2,500 functions on this
> repo, 2,206 are `.pure`, **35 are `.pureButPartial`**, 259 refuted, and the only consumer of the
> purity signal is the `/// @lint.effect pure` advisory, which those 35 cannot honestly take: SEI
> defines the tier as deterministic **and total**, and the lattice has no tier for
> deterministic-but-partial. So the adoption exists to stop the distinction being destroyed at the
> scan boundary, where `isPure` collapsed three states into two irrecoverably. The open work is a
> consumer that narrows a law's domain to the success set — not the plumbing.
>
> Note the shape, because it is the same one this document keeps recording: the item was tracked as
> *"open"* on the strength of a reading, and stayed that way through two dated revisions after the
> code had moved. **A status line is a claim about behaviour, and re-reading the source is how it
> gets checked.**

Item 3 has a **new** motivating symptom rather than a hypothetical one — see the `@EffectUnknown` row
above. A guard phrased as *equality with the sibling consumer* would currently fail, correctly.

> **2026-08-16 — it would now pass, and that is the weakest moment to leave it unwritten.** Both
> consumers pin `22342ca`, so the guard has nothing to catch today. But the divergence it exists to
> catch opened *and* closed within this one day, and for the first time across real source rather
> than docs — the window in which the linter and the inference engine consulted different oracles
> was hours, and nothing would have reported it. A guard is worth writing while the failure is
> fresh; every previous closure of this section was followed by a re-opening nobody predicted.

---

## Traps

- ~~**The README is stale in a way that inverts its meaning.**~~ **Fixed 2026-08-16 (`94610c0`).**
  It used to say *"Status: Pre-extraction skeleton"* and *"The current skeleton has no behavior; the
  test target only asserts the namespaces compile"* — while `Sources/` held ~3,975 lines of working
  engines. It now describes the shipped library, and the primitives list finally includes
  `PurityInferrer`, which it had **omitted entirely** despite that being the canonical oracle both
  consumers embed. Kept struck through rather than deleted: this was the toolchain's longest-lived
  documentation defect, and the failure mode it illustrates — a README that *inverts* rather than
  merely lags, so a reader concludes there is nothing to consult and leaves — is worth recognizing
  again elsewhere.
- **`Effect.rank` values are not stable.** They shifted when `pure` was inserted at the bottom. Never
  serialize them.
- **The marker sets are token-matched, not AST-matched.** `Date(timeIntervalSince1970:)` refutes
  purity. That is intended over-approximation, not a bug — but it means a false refutation is the
  expected failure mode and a false `.pure` is the alarming one.
- **`lub` is left-biased on ties**, which is only observable for two `externallyIdempotent` values
  with different `keyParameter`s. `[a, b].reduce(initial) { $0.lub($1) }` therefore matches
  SwiftProjectLint's collection-form lub — first in iteration order wins.
- **Purity is refuted, never established.** Any consumer that wants to *claim* `.pure` must take the
  meet with its own domain-specific refuter, the way `SoundPurity` does. A single narrow analyzer
  answering "pure" on its own is unsound by construction.
- **`@ClockDeterministic` is a user claim, not an inference.** SEI recognizes it; it never derives
  it. Everything downstream that relaxes an async veto is trusting an author.

---

## Where to look

| question | file |
|---|---|
| the lattice, `lub`, and what was deliberately left out | `SwiftEffectInference/Sources/SwiftEffectInference/Effect.swift` |
| the purity refuters and the soundness argument | `SwiftEffectInference/Sources/SwiftEffectInference/PurityInferrer.swift` |
| both annotation grammars + the clock-determinism marker | `SwiftEffectInference/Sources/SwiftEffectInference/EffectAnnotationParser.swift` |
| collision-withdrawal and lookup precedence | `SwiftEffectInference/Sources/SwiftEffectInference/EffectSymbolTable.swift` |
| why a name match needs an `import` to count | `SwiftEffectInference/Sources/…/Internal/FrameworkGates.swift` |
| why `Set.insert` is not a non-idempotent `insert` | `SwiftEffectInference/Sources/…/Internal/StdlibIdempotentMutations.swift` |
| the full design, including the migration plan §10 | `SwiftEffectInference/docs/SwiftEffectInference Design v0.2.md` |
| **the meet this repo actually takes** | `SwiftInferProperties/Sources/SwiftInferCore/SoundPurity.swift` |
| where the verdict is recorded at scan time | `…/FunctionScannerVisitor+Summary.swift:38`, `FunctionSummary.swift` |
| the advisory channel it renders on | `…/EffectAnnotationAdvice.swift` |
| the linter's side of the same oracle | `docs/design-internal/swiftprojectlint.md` |
| vocabulary — *Purity oracle*, *Effect lattice*, `@ClockDeterministic` | `docs/design-internal/glossary.md` § Neighbours |
