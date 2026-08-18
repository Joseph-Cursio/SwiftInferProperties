# Open threads

> **Status:** `reference` · **As of:** 2026-08-12


Things decided, noticed, or left undone that have **no other home**. Deliberately terse — an
index, not an essay. Anything with a real home lives there instead; this file exists so a
conversation's residue does not evaporate.

> **As of 2026-08-06** · `SwiftInferProperties@2c599c0`. Entries here are *not* dated claims
> about code — they are open questions and standing reads. Close them by deleting the row and
> putting the answer where it belongs. Measurements *inside* an entry carry their own date and
> SHA.
>
> **The suite run is re-taken.** It sat at `1e0218e` and unrepeated; a full `swift package clean`
> + `make test` at `2c599c0` on 2026-08-06 passed end to end — **4,932 fast-suite tests, 8 perf,
> 66 across the eight subprocess batches, zero failures**, with the §13 budgets green in isolation
> (peak RSS 234.1 MB against 800 MB; discover-pipeline 4.219s against 6s). Two lint violations that
> arrived with the pull were fixed in the same session, so `swiftlint --strict` is back at zero.
>
> **Item 28 added 2026-08-06** — the linter now emits an effect tier that nothing here reads.

> **2026-08-18 — rows 29–42 merged in from the staging doc, which is retired.** They were drafted
> as a separate file and never merged, so the highest row here read 28 while fourteen measured rows
> sat beside it unreachable from this table. The provenance SHA below moves to `484bf7e` and means
> *this file was reviewed against that tree* — **not** that any figure in it was re-measured there.
> Same rule as the 2026-08-12 note above, for the same reason.

<!-- doc-provenance date=2026-08-18 subject=SwiftInferProperties@484bf7e observer=SwiftInferProperties@484bf7e -->

> **2026-08-12 — re-dated, NOT re-measured, and the distinction is the whole point of this note.**
> 99 commits landed since the last pass. Every figure in this file comes from a survey stream or a
> scored experiment, each already carrying its own date inline; none was re-run here, because
> re-running one of them is hours and re-running some but not others would produce a table whose
> rows are no longer comparable to each other.
>
> So the provenance SHA below means *this file was reviewed against a tree at `21bc279`*, not
> *these numbers were re-measured there*. Read every count as of the date printed beside it.
>
> **Four threads did close in that window** and are the ones most likely to be stale here: the
> round-trip domain anchor and the inverse call shape (#236), the TestLifter type-qualifier misread
> (#242), the seed focus keeping a lifted law (#244), and lifted evidence gaining a real source
> location (#245). Anything below that describes lifted rows as unlocatable, or a round-trip stub as
> mis-anchored, has been overtaken.

---

## Next session starts here

The 2026-08-03 list that lived here is **spent** — items 0/1/3/4/5 all closed, and the reasoning
that outlived them is in *Open items* and *Decisions*. Two things from it are worth carrying
forward, and only two:

- **The `predicate` composer stops at 83%, and the number is the argument.** The remaining 22 are
  not composer failures: both compile buckets are ZERO, and what is left is 17 carrier declines
  (14 SwiftSyntax nodes and optionals), 4 traps the gate correctly refuses to call refutations, and
  1 `build-failed` that turned out to be the `Gen<URL>` defect. Nothing on that list improves by changing the
  composer. **The next gain is breadth, not depth** — and the whole-corpus survey agrees from the
  other side: `codable-round-trip`, the one template that never has to guess, is the only one at
  100% yield.
- **Generators for syntax-node carriers** — now item 27, because it is the largest single bucket
  left anywhere in this survey and it is a scope-and-file question rather than a build one.


## Open items

| # | item | where it stands |
|---|---|---|
| 4 | ~~**The attribute-grammar join has no contract test**~~ | **CLOSED 2026-08-05** — the cross-repo half now has a manifest and a test that was watched failing. `fixtures/effect-vocabulary/` records SwiftIdempotency's **`@attached(peer)` public macros** with a provenance SHA, and `EffectVocabularyCrossRepoTests` asserts swift-infer's recognised set **equals** that minus two named exclusions. **Equality, not subset, because the directions fail differently**: a name disappearing is the rename that disarms the veto; a name appearing is a vocabulary nobody reads — **which is item 20 having already happened**, and this shape would have said so the day `@EffectUnknown` landed. The rule is derivable rather than curated (`@attached(peer)` separates the 7 annotations from `IdempotencyTests` and `assertIdempotent` structurally). Three mutants watched firing: rename, addition, stale exclusion. **The honest limit is in the fixture README** — freshness re-derives from `../SwiftIdempotency` only when that checkout exists, so CI alone would not catch an upstream rename; `make docs-drift` is the standing detector. Earlier half: **The names this repo's behaviour is keyed to are now pinned** ([#79](https://github.com/Joseph-Cursio/SwiftInferProperties/pull/79), `EffectVocabularyContractTests`): contents, behaviour (every spelling round-trips through the real scanner), and **the rename simulated** — a near-miss spelling yields `nil`, not a wrong effect. It became urgent when [#78](https://github.com/Joseph-Cursio/SwiftInferProperties/pull/78) made `IdempotenceTemplate` **veto** on these names, so a rename stops suppressing a false law instead of failing loudly. **Still open: the cross-repo half.** swift-infer deliberately does not depend on SwiftIdempotency — the doc-comment spelling needs no dependency and the attribute is matched by NAME — so asserting these equal its *shipped macro names* needs a fixture or a checked-in manifest |
| 7 | ~~**No end-to-end number for the LOOP**~~ | **CLOSED 2026-08-05 — the loop verifies its own output.** `index --seeds` filters the index to what the linter pointed at, reusing `Discover.focus` so it cannot disagree with `discover --seeds` about what a seed selects, and writes **`.swiftinfer/seed-index.json` — never the conventional path**. Sharing one would let a `verify --all-from-index` run silently answer about whichever was written last, which is exactly how the loop came to verify a population its own earlier stage never produced. `toolchain.sh` stage 3 now runs `index --seeds` → `verify --index-path`, and **`--index-path` never auto-rebuilds**, so a stale seed index stays visibly stale. **Proven on a fixture rather than asserted**: `seed-index.json` holds exactly stage 2's 3 suggestions, `index.json` is *absent*, and `verify.stderr` contains **zero** reindex lines. Verify half remains 139 of 281 (`fixtures/whole-corpus-survey/`). **Still open, and smaller**: the loop number has only been taken on a two-function fixture — a real corpus run is now possible and has not been done |
| 8 | **Exit criteria for "the toolchain is in shape"** are unwritten | see *Decisions* → *Road tests were misfiled* |
| 9 | ~~**Driver stages 3–4** (`verify`, kit conformance suites) are declared and unimplemented~~ | **STAGE 3 BUILT, STAGE 4 HALF BUILT, 2026-08-05 — the loop executes a law for the first time.** `toolchain.sh --verify` runs `verify --all-from-index` after the seed hop and reports **laws that RAN**, not entries surveyed: a run where everything declined executed nothing, and reporting the survey size would hide exactly that. Measured end to end on a two-function fixture: *1 law executed — 0 held, 1 refuted*, and the refutation is correct. **Stage 4 emits and does not execute, and says so in the same breath** — `scaffold-kit-suites --output` writes into the run dir, never the target tree, because a driver that generated files into a repo it was pointed at would break the standing never-modifies line; running them needs a synthesized test target that does not exist. **New `skipped` status**, distinct from `not-implemented`: once a stage is built, reporting it as *not built* understates the gap in the other direction. **The closing line is now DERIVED** — it said *"stages 3-5 did NOT"* as a fixed string and would have kept saying it after stage 3 shipped. Original note: `scripts/toolchain.sh`. Until they exist, **no run of the loop executes a law** — the driver says so every run rather than implying otherwise |
| 10 | ~~**The two ends of the lint→infer hop take different inputs**~~ | **CLOSED 2026-08-05 — the fix belongs in `discover`, and the open question is answered.** `discover` with neither flag now infers scope and **says what it inferred**, so the documented hop no longer fails on a reader's first attempt. **The no-confident-zero rule is kept, not traded**: inference fires only where the layout is unambiguous. One module under `Sources/` → that target; **several → the whole tree, never a pick**, because naming one would silently scan a fraction of the package while scanning everything cannot be a *narrower* wrong answer; **no `Sources/` at all → still a loud error** naming `--sources`, which is the Xcode case where guessing produces exactly the confident zero. **Scoped to `discover` deliberately** — the other five scanning commands keep the strict resolver, because none of them is the second half of a documented two-tool pipeline. **A test caught a real bug in the fix**: the single-module path called `resolve(_:)`, which applies `Sources/<target>` to the PROCESS working directory, so an injected root was ignored — it worked in production only because cwd and package root coincide |
| 12 | ~~**Neither binary can state its own build identity**~~ | **CLOSED 2026-08-05 for swift-infer.** `BuildIdentity.commit` ships as **`unattributable`**, and the refusal is the design: a plain `swift build` cannot know its own commit — dirty tree, detached checkout, not a git repo — so reporting anything else would be a **confident zero wearing provenance**. `scripts/stamp_build_identity.sh` is the deliberate act that earns it (writes the SHA, builds, restores), and a dirty tree stamps `sha+dirty` rather than pretending. **A SwiftPM prebuild plugin was rejected**: sandboxed, `git` from one is unreliable across toolchains, and a mechanism that silently fails would reintroduce exactly the false attribution this prevents. **The driver now CROSS-CHECKS** tree SHA against `--version` and fails stage 0 when they disagree — its own border claim, closed. **One defect found by running it**: the first restore used `git checkout -- <file> || true`, which cannot restore an *untracked* file and swallowed the failure, so the first stamped build left the constant baked into the tree while reporting success — a `|| true` on a restore is how a guard fires never. Now restores from a copy. **Still open: SwiftProjectLint and the other three packages**, which have the same gap; this is the pattern for them |
| 13 | ~~**Speculative refactoring** — mutate a copy, verify, propose a patch only when the law ran~~ | **TIER 1 BUILT 2026-08-05.** `suggest-refactors --speculative` snapshots the package, widens one `private`/`fileprivate` declaration, diffs the discovered identities, verifies what was gained, and emits **a diff, a law and a verdict** — never prose, because a verdict about an edit the reader did not make does not transfer. Gated and `--max-candidates`-capped: one snapshot plus one verify workdir per candidate. Only `.notVisibleToTests` is a candidate. **The trap this doc named two paragraphs down was NOT `.nestedLocal`** — it is a member of a `private` TYPE, and this summary said `.nestedLocal` while the design note below said *"for a nested member, widening the member is a no-op"*, correctly. The same conflation shipped in `SpeculativeWidening`'s own doc and in the test that asserted the exclusion, so **nothing ever produced the case being described** and the trap was live: `FunctionScanner` returned `.notVisibleToTests` — the one widenable answer — for 15 such members in this repo's `Sources/`. Fixed 2026-08-06 (`c14dc7e`) by an ordering change and a new `.enclosingTypeNotVisibleToTests`, which `isWidenable` excludes. `SpeculativeVerdict` is its own vocabulary rather than `measured-defaultFails`, which would dishonestly mean *the property is false of your program*; the copy carries a source digest, since it is a border claim. **Non-recommendations are reported, not hidden** — 14 of 20 widenings gained nothing in the 2026-08-04 sample, and suppressing that would flatter the command. **One defect only an end-to-end run could find**: the first version matched `runPipeline`'s prose for `"bothPass"`, a word it never emits, so the headline verdict was unreachable and every candidate read `not-runnable` — now routed through `SurveyOutcome`, and the seam is filed as [#116](https://github.com/Joseph-Cursio/SwiftInferProperties/issues/116). **Tiers 2–4 remain**: closure extraction, kernel extraction (needs differential testing before *"we know it would work"* is earned), and primitive→domain type, which is out. Design: designed 2026-08-03, **unbuilt**, and **re-measured 2026-08-04 with laws that RUN**. The 2026-08-03 funnel (20 → 8 proposed → 2 composer-supported) was a ceiling nobody had executed. Executed: **0 of 6 ran on the pre-composer binary, 3 of 6 on HEAD** — 1 holds, **2 refute**, and both refutations are false laws rather than bugs. The blocker was never the composer; it was the cross-module import (item 16). See *Decisions* → *Access widening, re-measured* |
| 17 | ~~**The idempotency vocabulary is split across two packages, and this one reads neither half it owns**~~ | **CLOSED 2026-08-05 — all three steps done, in the order the trap required.** Step 1 (#78) made swift-infer read the vocabulary; step 3 is item 4's contract test; step 2 lands here: `CheckPropertyKind.idempotent` is **deprecated, not deleted**. Deleting would take a working test generator from users and point them at a package they may not depend on — and **the replacement is not a relabel**: swift-infer *reading* `@Idempotent` corroborates a law, it does not generate a test, so migrating means `@Idempotent` **with** `@IdempotencyTests`. `.roundTrip` and `.preservesInvariant` stay; SwiftIdempotency has no equivalent. **Watching it fire found a live defect the deprecation created**: `roundTripRequiresDistinctTypes` told users *"For T -> T use @CheckProperty(.idempotent)"* — the tool steering people onto the API it had just deprecated. Both diagnostics now name the owner. Original survey: surveyed 2026-08-04, **undecided by choice** — see *Decisions* → *Idempotency vocabulary*. Not a naming clash: two packages independently **generate idempotency tests from an annotation**, and swift-infer uses `EffectAnnotationParser` at exactly **three call sites, all `isClockDeterministic`**. Ordering matters — retiring `.idempotent` before swift-infer *reads* `@Idempotent` reproduces item 4's failure mode by hand. **Step 1 SHIPPED** ([#78](https://github.com/Joseph-Cursio/SwiftInferProperties/pull/78)): swift-infer reads the effect vocabulary — `@Idempotent` corroborates, `@NonIdempotent`/`@ExternallyIdempotent` veto. **Dogfooding it found two defects** ([#81](https://github.com/Joseph-Cursio/SwiftInferProperties/pull/81)): the annotation was paid for **twice** (the `@lint.effect` line is a doc comment, so `DocstringPropertyCorroborator` also credited it), and **+40 was keyed to the wrong definition** — the owner defines `@Idempotent` as re-invocation stability, not composition, so it is now +15. **Steps 2 and 3 remain**: retire `.idempotent` from `CheckPropertyKind`, and the cross-repo contract test (item 4). **Folded in**: whether `@ClockDeterministic` belongs in SwiftIdempotency — it does **not** belong to the effect lattice (four pre-existing fences say so) but probably does belong to the package; the actionable part is that it is the one annotation neither configurable nor contract-tested, which is item 4 |
| 20 | ~~**Nothing reads `@EffectUnknown`.**~~ | **CLOSED 2026-08-05 — the chain is complete.** Link 1 shipped in [SEI#3](https://github.com/Joseph-Cursio/SwiftEffectInference/pull/3): `declaresUnknownEffect` reads both grammars with its own predicate, since `unknown` is incomparable to `non_idempotent` and admitting it to a linear five-tier `Effect` would force a Hasse-diagram join. **The gap it closed is precise**: `parseEffect` returned `nil` for `@lint.effect unknown` — the same answer as for an unannotated declaration *and* for a misspelled tier. Links 2 and 3 followed here: pin bumped to `6f45139`, and `IdempotenceTemplate` emits a **caveat, not a signal**. **Score-neutral by design and pinned as such** — `@NonIdempotent` vetoes because it *denies this law*; `unknown` denies nothing, so vetoing would suppress possibly-true laws on the strength of an author's uncertainty, and corroborating would treat uncertainty as evidence. It earns a line, not points — the `StdlibAnchor` / kit-passed posture. Measured end to end: two identical functions, one annotated, **both score 35, only one carries the caveat**. Original framing: SwiftIdempotency ships the marker as of [#3](https://github.com/Joseph-Cursio/SwiftIdempotency/pull/3) (2026-08-04); no tool distinguishes it from an unannotated declaration | **Unblocked 2026-08-04.** Item 1 is fixed and the pin now sits at `bfcf0e3`, so links 2 and 3 of the chain are clear. What remains is **link 1: SEI must learn to read the marker** — and it belongs there, not here, because swift-infer re-implementing the `@lint.effect` grammar is exactly what SEI exists to prevent. See *Decisions* → *The `@EffectUnknown` dependency chain* |
| 28 | ~~**The linter now ships an effect tier and nothing reads it**~~ | **CLOSED 2026-08-06 by `f33dfd1`, about two hours after being filed** — `SeedManifest.Seed.effect` decodes it, `SeedEffect` mirrors the producer's five tiers and three provenances, `SeedEffectResolver` consumes them. **The argument that closed it is better than the one that filed it:** this row said the valuable half is `resolved` because a consumer can read a declaration itself. The real reason is a *budget* asymmetry — `EffectResolver`'s local pass runs `applyBodyInference` **one hop** to stay inside §13's 2-second `discover` ceiling, while a linter running ahead of the pipeline has no such constraint, so a `@NonIdempotent` several calls down "arrives already resolved — for free, since the linter already paid." That is a tier the consumer **structurally cannot compute**, not merely one it would rather not recompute. **A second half CLOSED 2026-08-06 by `38368c3`:** the producer shipped `anchor` (`a5795819`), so a declaration-anchored multi-hop chain is now distinguishable from a name-guessed one and `carriesEnoughEvidenceToDemote` admits it — 3 seeds on this repo, two at `depth: 5`. Building it exposed a **false demotion** the widening made reachable: the resolver joined on the bare symbol, so 3 seeds applied 5 effects, two of them to functions merely *named* `record` in other files. Now keyed `(file, symbol)`. **Still open, and smaller:** whether an *inferred* tier should veto or only demote — the filing note flagged this against `@EffectUnknown`'s score-neutral precedent, and closing the decode does not answer it. Original framing follows. **OPEN, filed 2026-08-06.** `SwiftProjectLint@9a21f3c1` added an optional **`effect` object** to `idempotency` seeds — `declared` / `resolved` / `provenance` / `depth` / `reason` — and this repo's `SeedManifest.Seed` declares no such property, so it decodes leniently and the field is **inert**. This is item 20's shape *with the roles reversed*: there, a vocabulary was shipped and unread; here, a whole resolved lattice position is. **The valuable half is `resolved`, not `declared`** — we already read the author's annotation off the declaration (`IdempotenceTemplate+DeclaredEffect`, which *names this exact gap in its own doc comment*); what we cannot reproduce is the linter's cross-file, multi-hop upward join through the call graph. **`provenance` is what makes it safe to act on**, and the producer says so explicitly: a `declared` tier should **veto** a proposed law, an `inferred-*` tier should only **demote** it — so consuming the tier without branching on provenance would either suppress possibly-true laws or dilute the strongest signal an author ever gave. Note the alignment already present: those tiers use the same annotation grammar (`non_idempotent`) that `EffectAnnotationParser` and the item-4 vocabulary fixture pin, so this is a wiring job, not a vocabulary negotiation. **Undecided: whether it should veto at all**, given `@EffectUnknown`'s score-neutral precedent (item 20) — an *inferred* non-idempotence is weaker evidence than an author's `@NonIdempotent`, and the existing veto is keyed to the latter |
| 27 | ~~**Generators for syntax-node carriers**~~ | **SCOPED AND FILED 2026-08-05, and the measurement inverted the priority.** This row called syntax nodes *"the largest single decline bucket in the whole-corpus survey"*. **They are 11 of 105 (10%)**, across 9 carriers. The largest is **`FunctionSummary` at 32 (30%)** — nearly 3× the whole syntax bucket. The old figure was true *within `predicate`*; it was carried over to corpus scope without recounting. **`FunctionSummary` declines for two STACKED reasons**, which is why *"record cross-module shapes"* is not the fix: its `Effect?` and `PurityVerdict` parameters are declared in SwiftEffectInference and **zero of the index's 745 recorded types come from outside this package**; and even given a shape, `Effect` is **not `CaseIterable`** and cannot be, since `externallyIdempotent(keyParameter:)` carries an associated value — so the strategist's `allCases` route does not apply. Fixing only the first moves the failure. Filed as [#118](https://github.com/Joseph-Cursio/SwiftInferProperties/issues/118) (this repo — shapes are the index's job) and [SwiftPropertyLaws#7](https://github.com/Joseph-Cursio/SwiftPropertyLaws/issues/7) (the strategist question, both halves). **The syntax-node half is filed expecting a documented NO** — a syntax node is a parse of source text, not a value with a domain, and a decline with a reason stops downstream counting these as a reach gap. Original framing: **Scope-and-file, not build.** 14 of `predicate`'s 22 non-running rows, and the largest single decline bucket in the whole-corpus survey (`no generator for carrier` is 105 of 281 corpus-wide). The design decision *"generator inference delegates to SwiftPropertyLaws"* says the answer is probably **not here** — so the deliverable is a scoped question for `DerivationStrategist`, not a generator in this repo |
| 29 | ~~**`PurityVerdict.refuted` collapses evidence and ignorance**~~ | **MEASURED 2026-08-17 — and RE-MEASURED the same day, when row 41's fix reversed the headline.** On SEI pin `c66fceb` the split is **135 ignorance / 164 witness of 299**: witnesses are now the majority, the rankable ceiling is **135, not 152**, and the surviving claim is the weaker *ignorance is not a rounding error* (45%, all actionable, `noBody` still 0) rather than *most of the bucket is unread*. 17 rows moved out of rankable ignorance because they carry an impure default argument as well as a propagated `try` — nothing could ever have freed them. `ignoranceIsNotARoundingError` carries the surviving claim, re-argued in its doc rather than quietly relaxed. **What this costs 31–33 is the sentence they were sold on, not their population.** The pre-fix reading, on pin `22342ca`, follows. **MEASURED 2026-08-17, and the answer permits 30–33 rather than closing them.** `docs/measurements/purity-refuted-bucket-census.md`; the harness is `PurityRefutationCensusMeasuredTests`, taxonomy frozen at `20e134c1` **before** the run. On `Sources/` at tree `d6285dff`: 2,739 functions → 2,416 `.pure`, 39 `.pureButPartial`, **284 `.refuted`, of which 132 carry a witness and 152 name nothing at all**. Ignorance is the majority, so there is a bucket. **Three things the split shows that the undivided number could not.** (1) **`noBody` is 0, structurally** — `FunctionScannerVisitor` skips protocol bodies, so the *"could not be inspected at all"* half of the doc is unreachable through this consumer; every ignorance row has a callee to name and the half needs no triage step. (2) **A decline-reason tally over-reports the ceiling by 44%** — `propagatedTry` holds of 219 rows and *blocks* 152, the other 67 carrying a witness too. That is *rows moved, never laws gained* in a new place, and it is exactly the arithmetic item 32 warns about. (3) **180 entries are an initialiser default, not a verdict** — see the new item 40, which is the finding this measurement was not looking for. Original framing follows. Its own doc says it means *"an impurity or nondeterminism refuter fired, **or** the shape could not be inspected at all."* Those are different facts and only the first is a finding. **This is item 2's shape one level down** — `isPure` answered `false` for all 294 non-pure functions alike, and widening it to `verdict(for:)` was worth doing; `.refuted` is still a Bool wearing three cases. **The measurement comes first and is not a build**: of the **259 `.refuted`** counted over 2,500 functions on 2026-08-04, how many carry a witness and how many are ignorance? One query against the same corpus. If ignorance is a rounding error the rest of items 31–33 are unwarranted; if it is most of them, the bucket is the largest unread population in the toolchain. **Do not re-use the 259** — §10.3, same binary, same day |
| 30 | ~~**An unrecognised callee is silently innocent, against the stated posture**~~ | **MEASURED 2026-08-17. The premise is CONFIRMED and the build is DECLINED AS FILED, because the item is two items.** `docs/measurements/purity-unrecognised-callee-census.md`; the harness is `PurityAllowlistCensusMeasuredTests`, corpus and verdicts reused from item 29's statics so the denominators cannot drift. On `Sources/` at tree `abbc0edb`. **(1) The under-refutation is REAL — this is not item 40.** 18 `.pure` verdicts call a package function this same analyzer refutes with a witness, one hop, name-unique, every one hand-checked. The sharpest is `DrainedProcess.standardOutputViaEnv`, which **spawns a subprocess** and is judged `.pure` — the exact disaster `throwsOnlyItsOwnErrors`' own doc was written about, with the `try` route closed and the plain-call route left open. So unlike item 40, the base rate is not zero and the finding is not narrower than the filing. **(2) The proposed fix costs 1,579 of 2,417 `.pure` verdicts (65%)**, restored only by axioms — that is the bill for flipping the default. **(3) The price is finite, and that is the surprise**: 508 distinct unrecognised callees hold the *whole* corpus, greedy-with-recompute reaching half the blocked rows on 24 axioms and 80% on 131. Hand-curatable, not open-ended. **(4) Item 32's arithmetic, in a second place and larger**: the top 10 names *touch* 992 subjects and *free* 463, because a subject with three unrecognised callees is freed by none of them individually. **Score a seed set by subjects fully covered, never by name frequency.** **The split, which is the actual verdict.** The *package-internal* half is measured-defective and cheap — all 18 rows are one hop into a function this package already computed a verdict for, closable by a within-package callee join at **zero** cost to any `.pure` verdict resting on stdlib, and `EffectSymbolTable.applyBodyInference` already does upward inference over un-annotated callees; what does not happen is `verdict(for:)` consulting it. That is item 31's *wiring, not analysis* about the same seam. The *stdlib* half is expensive and **unmeasured** — this census can exhibit no defect in it and **cannot**, having no oracle for those callees; absence of evidence, which is why it stays open rather than closing. Building item 30 as filed pays the second half's price to fix the first half's problem. Original framing follows. `PurityInferrer` documents *"any doubt refutes"* and the marker sets *"err toward flagging"* — true of the tokens they recognise. There is no allowlist, so a call to something unlisted refutes nothing and the function stays `.pure`. **The error direction is opposite to the documented one**: `Date(timeIntervalSince1970:)` over-refutes *deliberately*, and that trade stands; this one under-refutes accidentally. Needs a seed set of known-pure stdlib operations, with unrecognised ⇒ the item-29 ignorance case rather than a pass. **The seed set is asserted, not proven** — separate file, counted separately, every downstream claim reads *pure given these axioms* |
| 31 | ~~**Nothing can name the callee that blocked a verdict**~~ | **MEASURED 2026-08-17 and DECLINED, on two independent grounds either of which would be enough.** `docs/measurements/purity-blocking-callee-census.md`; the harness is `PurityBlockingCalleeCensusMeasuredTests`, which builds the inverse index the item asks for so it could be measured before being shipped. **(1) The leverage is 13–31 rows, not 135.** A within-package join frees 13 at one hop and 27 at fixpoint reading the blockers conservatively, 17 and 31 optimistically — 9 hops to converge, well past the one hop `EffectResolver` can afford under §13, which prices item 28's asymmetry at 27 rows. **Quoting the 135 is this row's own instance of the error item 32 warns about, a fifth time and now inside the corrected number.** Of the other 104, only 36 depend on a foreign callee; the rest **resolve fine, to package callees that are themselves correctly refuted** — `write`, `encode`, `emit`, `discover`, `resolve` all genuinely do I/O. **Most of this ignorance is accurate**, so naming the blocker buys legibility and no reach. **(2) Every row in the population `throws`** — `propagatedTry` is defined as `throwsClause` plus a `try` — so the best a resolved callee can do is `.pureButPartial`, and **nothing consumes `.pureButPartial`**: it appears in `Sources/` only inside doc comments, and `isInferredPure` is `== .pure` by definition. **Resolving every blocking callee in the package moves ZERO advisory rows, by construction.** So **item 34 is item 31's precondition, not item 29** — the chain was drawn to the *population* question and nobody drew it to the *tier* question. **(3) What makes this a decline rather than a defer: the index's head is unmovable.** The most-blocking callee is `String` at 14 rows, and every `try String(…)` here is `String(contentsOf:)`, a file read; `Data` at 6 is `Data(contentsOf:)`. A leverage report ranks *resolve `String`* first and nothing can resolve it. The first entry annotation could legitimately move is `makeSeedHex`, at 4 rows, **eleventh**. A report whose top recommendations are all wrong is worse than none — item 20's *vocabulary nobody reads* with the added failure mode that this one would be acted on. **Worth keeping**: the extraction itself, ~40 lines, now in the harness. Naming the blocking callee on `PurityVerdict.refuted` delivers the legibility gain with no ranking, channel or report. **Reopens on**: a `.pureButPartial` consumer (guarded by `thePartialTierHasNoConsumer`), the freed count reaching a third of the population (`theLeverageIsAFractionOfThePopulation`), or the index's head changing character. Original framing follows. **Unblocked 2026-08-17 by item 29's census, and it sized the population — then row 41's fix shrank it the same day: 135 rows, all of them rankable** (`noBody` is 0, so no row is hopeless). **The ceiling is 135, not the 219 a `propagatedTry` tally would report** — 84 of those carry a witness as well and stay refuted however many callees resolve. **Quote the 135, and re-take it before building**: it was 152 for a few hours, and the 17 it lost went to a refuter added somewhere else entirely. A ceiling over this bucket is only valid against the SEI pin it was measured on. Original framing follows. **Fourth instance of *the consumer keeps asking the producer, in English*.** Item 28 established the budget asymmetry and closed the tier half: `EffectResolver` runs `applyBodyInference` **one hop** against §13's 2s `discover` ceiling, and a linter running ahead has no such constraint, so it *"arrives already resolved — for free."* Same asymmetry, unexploited fact: at the point SEI gives up, it knows **which** callee it gave up on, and that never leaves the inferrer. Inverse-index it — key by blocking callee, list the functions whose verdict rests on it. **Wiring, not analysis**: `BodyInference.anchor` already distinguishes `.declared` from `.heuristic` (shipped `a5795819`, consumed by `carriesEnoughEvidenceToDemote`). Depends on 29 |
| 32 | **Leverage over the bucket is not additive, and the obvious implementation is wrong**  ⚠️ **blocked: item 31 declined 2026-08-17** | **The census measured the first half of this and it is worse than "not additive" — it is not even *attributable*.** 84 of the 219 `propagatedTry` rows carry an independent witness, so they are unmovable by any annotation whatsoever; a naive report promises 219 against a ceiling of **135** — a 62% over-report — before greedy-with-recompute is even reached. **The number moved once already**: it was 67-against-152 until row 41's default-argument refuter landed, which is this row's own warning arriving from outside the ranking. Item 30's census then hit the identical arithmetic a third time, on axioms rather than annotations: the top 10 unrecognised callee names *touch* 992 subjects and *free* 463. **And a fifth, inside this row's own dependency**: item 31's census measured the ranking it would sort and found 13–31 rows of leverage behind a 135-row population. **There is nothing left for this row to rank** — greedy-with-recompute over an index whose head is `String(contentsOf:)` sorts unmovable entries more carefully. Reopens with 31. **Any ranking must also exclude the 180 computed properties (item 40)**, which are `.refuted` by an initialiser default and would otherwise be ranked as blocked. Original framing follows. Two blockers can jointly block one function, so a single-pass sort recommends five annotations that together unblock far less than the report promised — plausible-looking, and the report is the only thing anyone would check. Needs greedy-with-recompute. **Score it against the laws that HELD, not the class it targets** — item 22's transferable practice. An annotation that decides 40 functions is only a win if their laws are refutable; 40 new unrefutable greens is the [Daikon trap](glossary.md#daikon-trap) reached through a new door. Depends on 31 |
| 33 | ~~**Purity does not propagate through a higher-order call**~~ | **MEASURED 2026-08-17 — the PREMISE IS FALSE, and the real gap runs the opposite way.** `docs/measurements/purity-higher-order-census.md`; harness `PurityHigherOrderCensusMeasuredTests`. **Chains do not terminate — they sail straight through.** `map`/`reduce`/`filter` are in neither marker set, so a ten-shape probe reaches `.pure` **nine times**; the only refutation is the one with `print` written inside the literal, which is the refuter that was always there. So there is no under-claim to fix. **There is an over-claim**: `func f(_ xs: [Int], _ t: (Int) -> Int) { xs.map(t) }` is judged `.pure`, and it is pure iff `t` is. That IS the `rethrows`-for-purity gap this row names, but knowing the direction changes the fix — a conditional verdict would stop the over-claiming and would unblock no chain, because no chain is blocked. **Third time in this line of work that the documented error direction was backwards** (item 30 was the first): *a posture stated in a doc comment is a claim about intent, and intent is not measurable from the same doc.* **DECLINED as the next build, on three grounds.** (1) **Population is 27 rows, 1.1%** of the non-refuted corpus — item 22 closed at measured-not-buildable against more than this. (2) **The base rate is unmeasurable today, and that is the finding.** 1,329 closure literals are passed in `Sources/`, 8 are refuted, **0** reach one of the 27 — and that zero is an artifact: `diagnostic: { diagnostics.writeDiagnostic($0) }` writes to standard error and the oracle calls it pure, because an unrecognised callee is silently innocent. **A zero measured with a blind instrument is not a zero.** Item 30's package-internal half is the precondition, exactly as item 34 turned out to be for item 31. (3) **Item 42 is cheaper and certain.** **On item 22's reopen**: parameterised purity may still be the dataflow proposal it asked for, but 27 rows of *over*-claim is not the 47 rows of *under*-reach — not the same scorer. **Reopens on**: the population growing past a few percent on a more functional corpus, the base rate becoming measurable and non-zero, or a consumer acting on the `.pure` claim for a closure-taking function. Original framing follows. Closure *literals* are handled (`isPure(closure:)`, `refuteIfCaptured`, locally-bound-name tracking). What is missing is the conditional form — `map` is not pure or impure, it is pure-if-its-argument-is, which is `rethrows` semantics for purity. Without it every chain terminates at the first `map`/`reduce`/`filter`, which is where the laws are; leaf arithmetic is not where the value is. **Note the adjacency to item 22**: that closed *measured-not-buildable* with the reopen condition *"a dataflow proposal, scored against the same 47 rows"* — parameterised purity is a dataflow analysis, so building this may be the reopen, and the 47 rows are the scorer that already exists |
| 34 | ~~**The 37 `.pureButPartial` are still unconsumed**~~ | **MEASURED 2026-08-17 and DECLINED — the ceiling is 2 suggestions across 3 corpora and 363 throwing functions.** `docs/measurements/partial-purity-consumer-declined.md`; harness `PartialPurityConsumerMeasuredTests`. **The item was better than filed, right up until it was measured.** `isInferredPure` is read in **one** place in shipped code (the outbound advisory) and `purityVerdict` in **none** — no template consults either. But **`isThrows` is a hard gate in eight places** (`InvolutionTemplate`, `HomomorphismTemplate`, `EquivalenceRelationTemplate`, `CaseIterableMappingTemplate`, `SetRelationModelPairing`, `OverridePrecedenceTemplate`, and two TestLifter detectors naming `.producerThrows`/`.predicateThrows`). So the real item is *`.pureButPartial` is the licence to relax a throws gate eight templates apply unconditionally* — leverage landing in **law emission** rather than an advisory nobody reads. **Then the A/B**, with `isThrows` masked (a deliberately GENEROUS instrument — a real build emits `try?` and compares optionals, masking emits a bare call that would not compile, so this is a ceiling): self **710 → 711 partial / 712 all-throwing**; OrderedCollections **163 → 163 → 163**; SwiftPropertyLaws **51 → 51 → 51**. **+2 total, +1 attributable**, and both are `subset` laws on one *private* CLI helper (refutable, so not the `f(x) == f(x)` trap — just one function's worth of reach). **The most informative number is a zero**: OrderedCollections has 36 throwing functions and **0 `.pureButPartial`** — every one is `.refuted` for a propagated `try`, so on a third-party corpus the tier is not merely unconsumed but **empty**. **This closes 31–33 as well**, since item 31 made this their precondition. **Corpus trap worth keeping**: `fixtures/cycle27-surface/Sources` is an empty stub, not the v1 corpus — the corpus is the resolved checkouts, and scanning the stub returns a 0 that reads exactly like a measured zero. The harness now fails any arm scanning 0 summaries. **Reopens on**: a template gating on `purityVerdict`, the gate reaching a tenth of the throwing population (`theGateHoldsBackAlmostNothing`, today 2 in 363), or a parser/codec-heavy corpus with a real partial population. **The shrink-and-replay consumer is untouched by this** — it gates test *behaviour*, not law emission, and needs its own measurement. Original framing follows. | Filed 2026-08-04 as waiting on *"a consumer that can narrow a law's domain to the non-throwing inputs."* Still true. The second, unnamed one: a `.pureButPartial` function is safe to **shrink and replay**, which is the property PBT actually needs, and is weaker than what the advisory refuses to say. Worth deciding whether the shrink-safety consumer is the same build or a different one. **Reprioritised 2026-08-17**: item 31's whole population `throws`, so every row it could free lands here, and `.pureButPartial` occurs in `Sources/` **only inside doc comments** — no code branches on it. That makes this row the thing standing between items 31–33 and any output at all, which nothing in the chain recorded: they were all filed as depending on item 29, the *population* question. **Count is 37, not 35** — re-take it, the tier moved twice on 2026-08-17 (39 after item 40, 37 after item 41) |
| 35 | ~~**The `pure` advisory is outbound-only**~~ | **MEASURED 2026-08-17 — the premise is WRONG about the mechanism and RIGHT about the consequence.** `docs/measurements/pure-advisory-round-trip.md`; harness `PureAdvisoryRoundTripMeasuredTests`. **The channel is not outbound-only.** `FunctionScannerVisitor` calls `EffectAnnotationParser.parseEffect(declaration:)` on every declaration and stores it as `declaredEffect`, and templates genuinely consume it — `IdempotenceTemplate` scores `.idempotent` **+15** and **vetoes** `.nonIdempotent` and `.externallyIdempotent`, `ReplayIdempotenceTemplate` dispatches on two tiers, `EffectResolver` gates inference on its presence. Write `@lint.effect non_idempotent` and the tool reads it, believes it, and withdraws a law. **What is inert is `pure` specifically, and deliberately**: `declaredEffectSignal` carries `case .observational, .pure: return nil` and argues it — *"`pure` is orthogonal (`x + 1` is pure and not idempotent). Staying silent is the claim."* **That reasoning is correct for idempotence; the trouble is no OTHER template consumes it either**, so one template's deliberate silence is indistinguishable from the catalog's total silence. **So the sharp claim is not *nothing reads it back* but *acting on the advice changes nothing*** — measured: **3,250 functions annotated across three corpora, ZERO suggestions moved** (self 710 → 710 over 2,571 annotations; OrderedCollections 163 → 163 over 356; SwiftPropertyLaws 51 → 51 over 323). **The control is what makes that zero readable**: substituting `.nonIdempotent` on the same population moves −107 / −3 / −12, so the channel is live and the harness reaches the consumers. **This is item 34's finding at the other end of the round trip** — 34 measured that no template gates on `purityVerdict` (the *inferred* signal), this measures the same for the *declared* one. Stated once: **the purity vocabulary is complete in both directions and consumed in neither**, which is the root cause items 31–34 kept meeting from different sides. **A fix is not a read-back — that exists — but a CONSUMER.** Two unscoped shapes: a tier bump (declared purity as a `Signal` on laws already proposed — cheap, but score it against the laws that HELD or it is the Daikon trap through a new door), or a veto's mirror (`.pure` ADMITTING a law shape alone would decline — more valuable, more dangerous, since it trusts a claim the tool cannot check). **Reopens on** `takingTheAdviceChangesNothing` going red, or the advisory learning to emit a tier something consumes — today it emits only `pure`, and the tiers with consumers are never recommended. Original framing follows. | `discover --effect-annotations` recommends `/// @lint.effect pure` lines (`EffectAnnotationAdvice` / `EffectAnnotationRenderer`) and nothing reads them back — *one tool talking to itself in English*, noted in *Decisions → Idempotency vocabulary* but never filed. Item 20's shape a third time, with both ends inside one repo. The read-back is what makes item 31's ranking actionable: without it a leverage report names annotations that, once written, still change nothing |
| 36 | **SwiftProjectLint has no indeterminate verdict, so the bucket flattens at the reporting boundary** | Findings are Error / Warning / Info. An undecided purity verdict is neither a violation nor a style note, and reporting it as a warning is the specific way this information normally gets discarded. `CrossFileAnalysisEngine` and the pre-scan → per-file → cross-file pipeline are already the right shape to carry it; the gap is the severity vocabulary, not the analysis |
| 37 | **The runtime tier can refute purity and cannot confirm it — unlike the idempotency one** | `#assertIdempotent` works because idempotence has a witness: invoke twice, compare via `Equatable`. Purity has none — a second invocation proves determinism on that input, and the impurities that matter (logging, cache fill, metric emission, a global write) are invisible to a return-value comparison. Generalising `IdempotentEffectRecorder` gives a *single-invocation* "were there any effects" check, which is the cheaper question. **Consequence for reporting**: these numbers are not comparable to SwiftIdempotency's and must not share a column — same rule as the tier cut in *The whole-corpus number* |
| 38 | **SwiftSyntax cannot resolve the call graph, and that caps 31–33**  ⚠️ decision, not a task | No IndexStore in any of the five packages (`swift-syntax` exact `602.0.0` throughout). Overloads, generics and protocol witnesses are unresolvable, so cross-module purity is out of reach and every leverage figure carries that as unmeasured attrition. Options are IndexStoreDB (real edges, and the build already happens) or SIL, where the optimiser's own effect analysis already lives. **Do not start here** — 29–33 are worth doing at current precision, and a build dependency in a parse-only toolchain is a larger change than anything above it |
| 39 | ~~**`PBT_EFFECT_VOCABULARY_SURVEY.md` argues against the code, and `make docs-drift` did not say so**~~ | **MEASURED 2026-08-17 — the answer is NEITHER of the two branches the row offered.** `docs/measurements/docs-drift-coverage-boundary.md`. **Staleness verified first**: the survey says SEI *"has no `pure`"* and lists adding it as next-step work, while `Effect.swift:67` ships `case pure` at **rank 0**; it records SwiftInferProperties as **"No (parallel)"** on consuming SEI, while `Package.swift` declares the dependency and `SoundPurity` composes `PurityInferrer`. Both stale. **But the detector answer is the finding**: the survey lives in the **workspace parent, outside every git repository** — `xcode_projects` is not a repo — so no per-repo check could reach it whatever trailer it carried. Underneath that, `docs_drift.sh` reads `DOCS_DIR=docs/design-internal` and globs `"$DOCS_DIR"/*.md`: **one directory, non-recursive, one repo.** **The blind region, measured: 91 `.md` under `docs/`, 9 in scope, and 49 of the 82 out-of-scope docs name a sibling repo** — exactly the class of claim the check exists to verify. Plus 6 orphan workspace-parent docs making cross-repo claims, checked by nothing. **Why it was invisible**: the summary printed `9 doc(s) checked · 6 drifted` — **a count with no denominator**, reading as a coverage report and tallying one directory. This project's own rule forbids exactly that (*a census's zero cannot be read without its corpus list*), and the tool reporting on docs was the one breaking it — the same shape as the standing `docs/**/*.md` not `docs/*.md` warning in CLAUDE.md, which did not prevent its recurrence in a different check. **FIXED by stating the gap, not closing it**: the script now prints its own scope and the out-of-scope cross-repo count. **Deliberately NOT widened** — all 82 lack a trailer, so a recursive glob prints 82 `?` rows and the signal drowns, which is the *check nobody reads* failure mode two other rows already record. **Left as a decision**: the survey cannot be maintained where it is (no history, no review path, no detector) — archive it here with a superseded header, delete it, or leave it now that the staleness is recorded. Same question for the other five orphans | The survey lists *"Add `.pure` to SEI's `Effect`"* as Idea-#4 next-step work; `Effect.swift` ships `.pure` at rank 0 with the full lattice rationale. It also records SwiftInferProperties as **not** importing SEI; `Package.swift:133` imports it. **The interesting half is not the staleness** — it is that this is the *doc that characterises a set by a property its newest member lacks* pattern, and the standing detector did not fire. Either the survey carries no provenance trailer, or it does and the drift check does not cover cross-repo claims. Worth knowing which before trusting the detector elsewhere |
| 40 | ~~**A computed property's purity verdict is an initialiser default, and its `isInferredPure` is an unchecked `true`**~~ ⚠️ found by item 29's census, not filed ahead of it | **CLOSED 2026-08-17, same day it was filed.** `SoundPurity.verdict(forGetter:)` takes the same meet the function path takes — `ReducerPurityAnalyzer` for the TCA surface and static writes, `PurityInferrer.isPure(_ accessor:)` for markers and totality — and `isInferredPure` is now **derived** from the verdict rather than asserted beside it. **A/B with the tree otherwise byte-identical: 2,597 → 2,597 advisory rows, 180 → 180 of them computed properties.** Zero rows moved, which is the point: the constant had been accidentally correct here all along, and the `.refuted` bucket a consumer reads drops 464 → 284 with no output change at all. **The guard that could not reach the failing path now can** — `boolIsTheCollapse` gains a case per polarity, and `clockReadingGetterIsRefuted` pins `var now: Date { Date() }`, watched failing against the pre-fix code. The witness is synthetic on purpose: the failing shape is one this corpus does not contain, and waiting for a real one was the alternative. **One thing deliberately not built**: `verdict(forGetter:)` can never answer `.pureButPartial`, because `isReadOnlyGetter` filters throwing accessors out upstream and SEI's accessor oracle is a `Bool`. That is a *filter*, not a property — if the filter widens, this method is what has to learn the distinction. Original framing follows. `makeSummary(fromComputedProperty:)` passes **no** `purityVerdict`, so all **180** read-only computed properties under `Sources/` take `FunctionSummary.init`'s `.refuted` default — while being handed `isInferredPure: true` unconditionally. The field's own doc says *"`isInferredPure` is `purityVerdict == .pure`"*, so those two facts cannot both be right, and today neither is computed. **It survived because the invariant's guard cannot reach the violating path** — `PurityVerdictAdoptionTests.boolIsTheCollapse` asserts exactly that equality over six cases, **all six of them `func` declarations**, and the computed-property route is the only one that breaks it. *Verify a suppression by removing it*, in new clothes: six green cases and a live contradiction. **Consequence for everything above: the bucket a consumer reads is 464, not 284, and 39% of it is a question nobody asked.** A ranking built over `purityVerdict` without excluding computed properties ranks a default. **The unchecked `true` has cost NOTHING measured** — `PurityInferrer.isPure(_ accessor:)` is the right oracle, exists, is not called, and refutes **0 of the 180**, so no false `/// @lint.effect pure` has been emitted here. Filing it as *"the advisory is unsound"* would be [manufacturing a defect that is not there](open-threads.md); what is true is narrower — the claim is unchecked and its base rate is zero, and `computedPropertyAdviceIsAccidentallyCorrect` fails the day that changes. **The fix is small and its A/B is predictable**: call the accessor oracle, derive `isInferredPure` from the verdict rather than asserting it, and expect **0 advisory rows to move** while 180 leave the refuted bucket. Do it before item 31, not after — otherwise the first leverage report is computed over a population 39% of which is noise |
| 41 | ~~**A marker in a DEFAULT ARGUMENT is invisible, because the scan stops one node short**~~  ⚠️ found by item 30's census, not filed ahead of it | **CLOSED 2026-08-17, same day it was filed, by the honest fix rather than the local one.** `PurityInferrer.hasRefutingDefaultArgument` — SwiftEffectInference [#13](https://github.com/Joseph-Cursio/SwiftEffectInference/pull/13), merged at `c66fceb`, pinned here at `Package.swift:122` and in SwiftProjectLint's three manifests on the same SHA. **The A/B has victims, unlike item 40's**: `.pure` 2,417 → 2,404, `.pureButPartial` 39 → 37, and **advisory rows 2,597 → 2,584 — 13 false `/// @lint.effect pure` recommendations retracted** (13 and not 15 because two were `.pureButPartial`, which never entered the advisory). Item 40 was an unchecked claim that was accidentally correct; this one was telling thirteen functions something false on every defaulted call. **Both controls were watched failing, in both directions** — refuter disabled, the five hole tests fail; refuter replaced by the naive whole-signature scan, both type controls fail. That second one is the whole design: `func f(_ d: Date)` mentions the marker in a parameter *type* and is the shape dependency injection produces, so a signature-wide scan would refute exactly the code the inferrer should reward. **It cost item 29 its headline, which is the part worth reading.** `markerInDefault` holds of **32** rows: 15 newly refuted, and **17 that were already refuted and already counted as rankable ignorance** — `propagatedTry` plus an impure default, so no annotation on any blocked callee could ever have freed them. The bucket goes 284 → 299 while the *rankable* population goes **152 → 135**, and the split flips 152/132-ignorance-majority to 135/**164-witness-majority**. Item 32's warning a fourth time and the sharpest yet: the correction came from closing an *unrelated* hole, and nothing inside a ranking would have revealed it. **Also cleared the standing known-red** `SEICrossRepoPinTests` — the two consumers had disagreed since 2026-08-16 and the joint bump is what a joint act is for. `markersInDefaultArgumentsAreRefuted` was inverted rather than deleted, because a revision pin can move backwards; `theDefaultArgumentPathIsStillExercised` is its non-vacuity control. Original framing follows. **Measured 2026-08-17, 15 subjects, all hand-checked.** `bodyHasRefutingMarker` is handed `function.body`; a default value lives in the *signature*. So `public static func bridges(…, now: Date = Date())` reads the clock on every call that omits the argument and is judged `.pure`, and `TargetDirectory.resolve(_:relativeTo:)` defaults to the process's current working directory — global mutable state — the same way. Fourteen are `Date()`, one pair is `FileManager`. **Separable from item 30 and much smaller than either of its halves**: no allowlist, no axioms, no population cost beyond the 15 — it is a scan that stops one node too early |
| 42 | ~~**The I/O the `throws` gate used to mask is STILL invisible without `throws`**~~  ✅ **CLOSED 2026-08-17** | **FIXED upstream at SEI `3ea25f2` (SwiftEffectInference #14), by the fix this row proposed verbatim** — `sideEffectMarkers ∪ {FileHandle, Process, Pipe}` plus a joint pin bump across all four manifests. `unmaskedIO` is now **0**; every probe below reads `.refuted`. It was **8** subjects by the time the fix landed, not 7 (`VerifyCommand+CorpusDisclosure.discloseSupersededDependencies` joined the corpus in between), and the eight were surfaced independently by `verdictAgreesWithSoundPurity` failing with eight `real=refuted replicated=pure` mismatches on the bump — the same population found by a different instrument. `maskedIOIsStillInvisible` fired as designed and is **inverted, not deleted**, into `maskedIOIsRefuted`: the marker set lives in a pinned dependency, so it can regress without a line of this repo changing, and a falsifier's job ends where a regression guard's begins. **What it did NOT fix**: item 33's base rate is still 0 and still unmeasurable — the closure oracle does not consult a callee's verdict, so `{ diagnostics.writeDiagnostic($0) }` stays `.pure` even now that `writeDiagnostic` is refuted. That is item 30's package-internal half, stated as precisely as it has been. Original framing follows. **Measured 2026-08-17, 7 subjects, all hand-checked.** `throwsOnlyItsOwnErrors`' **own doc** names the impurities that gate exists to stop masking — *"`Process`, `Pipe`, `FileHandle`, `String(contentsOf:)`, `Data(contentsOf:)`, the SQLite surface"* — and **not one of them is in either marker set**. The gate re-closed the hole for **throwing** functions only. `FileHandle.standardError.write(_:)` does not throw, and it is the commonest non-throwing I/O call in a Swift CLI. Probe: `FileHandle.standardError.write`, `h.write(d)`, `Process()`, `Pipe()`, `h.readDataToEndOfFile()` **all reach `.pure`**, against `print` and `FileManager` controls that refute. **7 non-refuted functions in this package do it**, including *both* `writeDiagnostic(_:)` — the tool judges its own stderr writer pure. **Item 41's shape again**: a small unambiguous marker-set gap with real instances, needing no new verdict state, no dataflow analysis and no design decision. **How it was found is the argument for fixing it first**: item 33's base rate measured 0 *because of this hole*, so it blocks measurement and not just reach. The fix is `sideEffectMarkers ∪ {FileHandle, Process, Pipe}` in SEI plus a joint pin bump; A/B expected to move ≥7 rows out of `.pure`, which unlike item 41's is a *withdrawal of advice the tool currently gives about itself*. `maskedIOIsStillInvisible` pins it as open and fails the day the marker set grows |
| 43 | **The one-hop refuting join is measured-BUILD — and the LINTER built it while this side did not** | **MEASURED 2026-08-17, and the first row in this cluster whose answer is *build it*.** `docs/measurements/purity-refuting-fixpoint-census.md`; harness `PurityFixpointCensusMeasuredTests`, `make batch2`. This is row 30's package-internal half asked in the **refuting** direction, and the direction is the whole finding: **18 rows retracted at one hop** over the 2,396 `.pure`, **29 at fixpoint** (6 hops, per-hop 18 · 6 · 2 · 1 · 1 · 1), **1.2%** of the population. The loop multiplier is **1.6×** against the promoting direction's 2.1×, so **one hop is 62% of the effect and the loop is phase 2, not the headline.** **Why this builds where row 31 declined**: a retraction lands on `.pure` → `isInferredPure`, which IS consumed; a promotion lands on `.pureButPartial`, which nothing reads. Same seam, opposite direction, opposite verdict — and it is the answer to *the purity vocabulary is consumed in neither direction*, which is that one direction already had a reader and nobody had asked in it. **A hand-check killed the first answer.** The harness first reported 75 at fixpoint with 57 from the cascade; **46 of the 75 were `classify`-style name-collision artifacts, 61% false.** Both readings are kept in the doc rather than the wrong one being replaced. The one-hop 18 never moved — the seed always obeyed the settledness rule — which is why 18 has two independent confirmations and 11 needed a hand-check. **Name collision is now the dominant defect at this seam in three measurements**, and it is why row 48's trip list is keyed by file *and* name. **SHIPPED UPSTREAM, NOT HERE — SwiftProjectLint `7704178` + `aba87fc`, 2026-08-17.** `PackagePurityJoin` resolves the join in the pre-scan, and `PureFunctionCandidateVisitor` gates on it, so **`DrainedProcess.standardOutputViaEnv` is no longer offered as a pure-function seed** — it was in that seed, and this repo consumes that seed, so a wrong seed was becoming a law nobody can hold. **That is item 28's asymmetry paying out exactly as priced**: the linter has no §13 ceiling, so it can afford the join `EffectResolver` cannot. **The linter's witness rule is deliberately NARROWER than the census's** — only evidence propagates, established from public API alone, because `PurityVerdict` carries no witness and SEI's reason is `private`; that is **row 31's complaint arriving as a constraint rather than a wish**. **§7 closes row 30's stdlib half from the other side**: Swift ships `@_effects`, readable from the SDK's 226 `.swiftinterface` files without building the stdlib — and its entire `readnone`/`readonly` surface is **20 underscored names, 0 of them called here**. The axiom list cannot be borrowed; it has to be asserted, exactly as row 30 said. **What is still open, and it is this row**: `verdict(for:)` in *this* repo does not consult the join, so those 18 remain `.pure` in `swift-infer`'s own advisory. The measurement was taken here and the fix shipped there. |
| 44 | ~~**The purity oracle has never been scored against a real purity bug**~~ | **MEASURED 2026-08-17 — 0 HITS OF 3, 0 false alarms, and the GATE IS NOT MET.** `docs/measurements/purity-backtest.md`; harness `PurityBacktestMeasuredTests`; phase 0.6 of `docs/plans/declaration-claims-plan.md`, and the cheapest thing in that document. **The only number in this cluster an outside reader can check** — the subject is a public fix commit predating these tools, so the oracle cannot have been contaminated by it, which is what every other census here has to argue for itself. It sees neither bug class that history actually produced: **hash-order nondeterminism** (a `Set` rendered into a returned `String` — the class this repo already paid for in `orderedSources`) and **an instance `self` write on a `class`** (`ReducerPurityAnalyzer` covers `Self.`, not `self.`). **0 false alarms is not the consolation it reads as** — an oracle that flags nothing scores it too, which is why the pair of numbers is quoted and never the second alone. The two blind spots were **filed and priced rather than guessed at**, which is row 45. |
| 45 | **Blind spot 2 has a live instance — a smell, not a bug, and the oracle is still wrong** | **MEASURED 2026-08-17.** `docs/measurements/blindspot-base-rates.md`; harness `BlindSpotBaseRateCensusMeasuredTests`. Row 44's two gaps, priced against the 2,396 `.pure`. **Bucket 1 — instance `self` write on a `class` — is ZERO, and the reconciliation is the publishable part.** `grep` finds **1,226** `self.x =` lines in `Sources/`, so a detector reporting zero *anywhere* would be broken; of the first 400, **380 are inside an `init`**, and `InitializerDeclSyntax` is not a `FunctionDeclSyntax` — out of scope **by construction**, not by a filter that could drift. The rest are setters and closures, the latter already refuted by `refuteIfCaptured`. **The two zeros had to be separated by hand precisely because row 46's first detector published one that was blind.** **Bucket 2 — hash-order — is TWO, hand-checked, and one is live**: `PartitionAggregator.finalizeTwoClass` returns `winnerByPredicate.values.map(…)` — hash-seed order — and the oracle calls it `.pure`. **Measured NOT to escape** (`32b62f0`): `finalize()` sorts, and the comparator is total because `NClassPartitionKey` is `(predicateName, markerSetName)`. So the *program* is correct and the *verdict* is wrong, and only the second of those is this toolchain's business. **Bucket 2 is decidable from a parse only as a lower bound**, which is why it stays a row rather than closing. |
| 46 | **A module-state mutation is judged pure, and this corpus has no exhibits**  ⚠️ found by row 47's probe, not filed ahead of it | **MEASURED 2026-08-17 — the base rate is ZERO, and it is zero BECAUSE THE CORPUS DECLARES NO FILE-SCOPE `var` AT ALL**, corroborated by grep four ways. `docs/measurements/module-state-base-rate.md`; harness `ModuleStateCensusMeasuredTests`. **Row 40's shape exactly: a latent unsoundness — not a defect, and not a clean bill of health either.** The asymmetry is real; it has no victims here. **Do NOT carry this zero to another corpus** — it is a fact about the subject, not about the oracle, and a parser-heavy or CLI-heavy package would not inherit it. **And the first run reported the same 0 with a BLIND detector**, which is the reason this row is worth keeping past its own answer: `Parser.parse` yields `SequenceExprSyntax` for a top-level assignment, not `InfixOperatorExprSyntax`, so the instrument matched nothing and its zero was byte-identical to the real one. **Two zeros, one measured and one broken** — this repo's *confident zero* arriving in the census whose subject is a zero. |
| 47 | ~~**`consuming` / `borrowing` might carry purity evidence**~~ | **MEASURED 2026-08-17 and DECLINED twice over — the PREMISE IS FALSE *and* the population is ZERO.** `docs/measurements/ownership-premise-declined.md`; harness `OwnershipPremiseCensusMeasuredTests`; phase 0.7 of `docs/plans/declaration-claims-plan.md`. **No clause in `verdict(for:)` examines a parameter at all**, so the mechanism does not exist; and this corpus declares **0 `consuming` and 0 `borrowing`** against 52 `inout`, so there would be nothing to run it on. Closed as *measured-premise-false*, the way row 33 was. **Second Family C row declined for a premise that reads plausibly and measures false**, which makes it a pattern rather than an incident: **probe the premise before scoping the build.** It cost an afternoon against a phase, twice. **The probe's real find is row 46**: a function mutating a file-scope `var` is `.pure` while `static` mutation is refuted, and a closure doing the same write IS refuted — an asymmetry inside one type. **Fourth census in a row whose finding is not the thing it went looking for**, after rows 40, 41 and 42. |
| 48 | **The soundness arm can reach its own answer key, so phase 0.5 is not blocked on reach** | **MEASURED 2026-08-17 — 14 of the 17 frozen rows are callable, 9 of them with nothing to construct at all.** `docs/measurements/soundness-arm-reach.md`; harness `SoundnessArmReachCensusMeasuredTests`; phase 0.5 step 1 of `docs/plans/declaration-claims-plan.md`. The trip list is nearly all `static`, which **dodges the receiver problem that caps the verify arm at 139 of 281** — a purity probe needs a *call*, not a domain, so one degenerate argument suffices where a law needs a generator. §6.4 forbade inheriting the verify arm's reach and that estimate had never been taken; **a prediction the arm cannot execute is not a prediction.** Out: 2 `private`, 1 awkward type. Keyed by **file and name**, because `resolve` and `load` each match several declarations here — the collision hazard row 43's hand-check makes the standing one at this seam. **Reach is a precondition, not a result** — it says nothing about whether a probe would be *informative*, and the 9-with-nothing-to-construct are where an uninformative probe is cheapest to discover. **Build the 9 first.** |

### Rows 29–48 — the purity line of work, and how to read their integers

Rows 29–42 were merged here 2026-08-18 from the staging doc they were drafted in, which held them unmerged for a
month of sessions (retired the same day; recover it with
`git show 484bf7e:docs/design-internal/openthreads-additions.md`). Those rows are verbatim. **Rows 43–48 are new** — six measurements landed after that file's last edit (`598412b`) and had no row anywhere, which is the same failure one level down.

> **The integers inside these rows are as-filed and are NOT re-edited in place** — the rows are the
> argument, and rewriting the numbers inside them would erase the record of what each verdict was
> actually decided on. **The census docs in `docs/measurements/` are the authority for any current
> figure**, and each carries the SEI pin its columns belong to. Read every count below as *"as
> measured at the pin named in that row"*.

**Every count moved once from outside, and none of them moved a verdict.** SEI `3ea25f2`
(SwiftEffectInference #14, pinned here 2026-08-17) closed the non-throwing I/O hole and made
`hasRefutingMarker` consult `NondeterminismSources` as a **union** with the token set. The
movements: rankable ceiling **135 → 133**, refuted bucket 299 → **307**, witness 164 → **174**,
row 30's base rate 18 → **17**, row 33's population 27 → **26**. Rows 30, 31 and 33 remain declined
on the same grounds, and the grounds got *stronger* rather than weaker — row 31's population has
now moved three times while its leverage (13–31) has not moved once, and row 30's price curve (24
axioms for half the corpus, ~128 for 80%) is identical to the digit across two oracles. **A decline
that survives a change of oracle without any of its deciding numbers moving is a firmer decline
than the one first recorded.**

**What the line of work bought, stated once.** Rows 29 and 30 were measurements that found real
defects, and three fixes shipped from them: **40** (computed-property verdicts, 0 rows moved, a
latent unsoundness closed), **41** (default arguments, 13 false advisories retracted), **42**
(masked I/O and the unconsulted shared classifier, 8 rows). Rows **31–34** are the *reach* half,
and the reach half came back empty every time. The root cause is one sentence: **no template gates
on `purityVerdict`**, so the signal has no path to a law, and every proposal to enrich it was
proposing to enrich something nothing reads.

---

## Decisions taken in conversation

Recorded because the reasoning is the useful part and it exists nowhere else.

### One package for the survey, not one per suggestion (2026-08-05, built)

`verify --all-from-index` built a complete SwiftPM package **per suggestion** — resolve,
fetch, compile four dependencies, link — around a stub that is a ~113-line `main.swift`.
Measured on `fixtures/cycle27-surface` (53 entries): **13m 30s, 24 GB, 464 MB per
workdir**. The shared form is **100s / 1.6 GB cold and 45s warm**, verdicts **53/53
identical** against the frozen v1.134.0 answer key — reconfirmed 2026-08-05 at
v1.148.0, 0 mismatches over an intersection of 53.

**Cold vs warm is not a footnote — omitting it manufactured a contradiction.** This
entry said `103s`; the source comments said `54s`; both were true and neither named
its cache state, so for a day they read as two irreconcilable measurements of one
run. Re-measured back to back on one binary: **cold** (no `verify-workdir`) 100s /
1596 MB, **warm** (reusing that `.build`) 45s / 1596 MB. Same shape as the
denominator lesson below — **a number is evidence only with the conditions it was
taken under**, and wall-clock's condition is the cache.

**The rationale was real and was read too widely.** `VerifierWorkdir`'s doc says one
directory per hash *"so concurrent verify calls against different suggestions don't stomp
on each other's `.build/`"* — a claim about two **concurrent** runs. It was taken to
license 53 **sequential** entries each owning a dependency graph. Three properties were
conflated under it, and only the third needed a separate package:

| property | still required | how it survives |
|---|---|---|
| a trapping law takes one law, not the batch | yes — `predicate` fails by trap | each target is its own executable, run as its own process |
| `build-failed` lands on one entry | yes | `swift build --product <target>` |
| two concurrent runs don't share a `.build/` | only for single-entry callers | they keep their hash-keyed root |

**`--product` is load-bearing and was measured, not assumed.** With one deliberately
broken stub among 53: a whole-package `swift build` exits 1 and produces **zero**
binaries — one bad emission would blank an entire survey — while `--product` builds 52
and fails exactly the broken one. **`--target` is the wrong flag and lies**: exit 0, no
binary, only an entitlement plist, so a caller keying on its exit code reports "built"
for something that does not exist.

**`--max-parallel` now schedules nothing.** The concurrency existed to overlap dependency
builds that no longer happen; serial-over-one-`.build` is **8.1× faster cold** (810s →
100s) and 18× warm than 4-way-over-53.
Whether per-product builds are safe *in parallel* against one `.build` is **not
established** — arm C and the shipped run were both serial. Left unmeasured on purpose:
the flag is kept because it is a documented interface and because the *run* phase could
still use it.

**The comparison nearly reported a false green.** The frozen key writes `identityHash`
without the `0x` prefix the JSONL stream carries, so the first diff found 53 rows on each
side, an **empty intersection**, and "0 mismatches" — a loop over nothing. Printing the
size of the compared set, not just the mismatch count, is what caught it. Same shape as
the cycle27 rerun that compared against a file it had itself overwritten
([#129](https://github.com/Joseph-Cursio/SwiftInferProperties/issues/129)); the general
form is that **a zero is only evidence when the denominator is printed beside it.**

### Road tests were misfiled, not mistimed (2026-08-03)

They were premature **as scorecards** and exactly on time **as development instruments**. The
distinction matters because the conclusion "stop road-testing" does not follow.

- The 0-of-3 run is what *found* five confident zeros. You cannot find a confident zero by reading
  code — by definition it looks like success.
- `roadtest-self-dogfood.md` has every measurement withdrawn and **19 live source sites still cite
  its diagnoses**. That is a high yield for a "premature" exercise.
- **What went wrong was publishing scores from a tool that was still changing.** The repo already
  has *"a tool may not grade its own homework"* (about answer-key contamination). The missing
  sibling: **a tool may not grade itself while it is still changing** — every score taken during
  active development is a score of a binary that no longer exists. That is §10.3's A/B rule
  (two binaries, same day, same corpora) generalised past templates.

**Backtests are not the same instrument and should not be deferred with road tests.** Their oracle
is a public fix commit that predates the tools and cannot be contaminated; they are cheap to re-run
and survive tool churn. In-repo record agrees: road-test scorecards withdrawn twice, backtests
standing (`backtest-apple-libraries.md`, and `kit-suite-backtest-plan.md` Arm 1 a clean hit).

**The trap in the position:** *"not ready to measure yet"* is unfalsifiable — the confident zero of
project planning, always defensible, forever. Write the exit criteria while inclined to be strict.
Candidates: composer reach past 38%, the 5 dead templates diagnosed, the instrument-error class
closed (Pass 2 was the big one, fixed), `--sources` no longer gating app code out of measured
verify.

### Speculative refactoring — shape and build order (2026-08-03, designed not built)

**The idea.** `swift-infer` copies the target, applies a refactor the linter suggested, derives a
law from the *refactored* shape, verifies it, and surfaces the refactor **only if the law ran**.
Output stops being advice and becomes a **patch + a law + a verdict**.

This is `prove-then-show`'s inversion — *"the test-then-surface inversion of the hide-Possible
default"* — applied to `suggest-refactors`' domain. Both commands already exist; what is missing is
the copy, the mutation, and the join between them.

**Why it is worth doing at all.** Today the linter says *"extract this kernel"* and the reader takes
it on faith; `extractable-kernel` seeds explicitly do not focus discovery, and `swift-infer` reports
"work a human must do before any tool can help" and stops. This lets it say instead: *extract this,
and here are the laws you get.* The value is **refactors that actually get done**, not more
suggestions.

**Emit a diff, not advice.** If the output is prose, the verdict does not transfer — you verified
*your* extraction and they will write a different one, and choosing the parameters is where the
design work lives. If the output is the exact code that was compiled, the claim is precise and
checkable: *paste this, and this law held over 100 trials.*

**"A patch we know would work" means two different things.** Conflating them is how the kernel tier
would over-claim:

| tier | what makes the **patch** safe | what the property test proves |
|---|---|---|
| access widening | the compiler — a visibility change cannot alter behaviour | that the **law** holds |
| kernel extraction | **nothing yet** — the extraction may not preserve behaviour | that the law holds **of that extraction** |

A passing law on an extracted function says nothing about whether the extraction preserved the
original. You can extract wrongly, get a clean law, and propose a patch that changes the program.

**Build order, by how much the PATCH needs proving** — not by how valuable the law is:

1. **Access widening.** Patch free, law proven, and **extraction ambiguity is zero**: same symbol,
   same body, one keyword. A verdict on the copy is a verdict on their code. `restricted-function`
   is 316 of 468 analysable seeds on SwiftProjectLint's own repo. **Start here** — it also builds the
   copy-mutate-verify machinery the later tiers reuse.
2. **Extract closure to a named function.** Nearly mechanical; the risk is captures and the signature.
3. **Kernel extraction.** Needs a *second* property — that the original method and the refactored one
   **agree**. That is differential/oracle testing, already in this repo's vocabulary
   (`parsing-catalog-gap.md`, holes 8/9/12). Without it, "we know it would work" is not earned.
4. **Primitive → domain type.** A redesign. No property makes that patch safe. Out.

**The linter side needs one thing, and it is not a new seed kind.** `PBTSeedsFormatter.effectiveKind`
already demotes to `restricted-function` on `TestReachability.unreachable`, so the seed ships today.
What it collapses is *why*: that case covers `private`/`fileprivate` **and** "nested inside a type
that is", and the remedies differ — for a nested member, widening the member is a **no-op**, and a
generator that got it wrong would emit a patch that unblocks nothing and then fail verification for
a reason unrelated to the law. Add a `reason`, not a kind.

**Three costs to price first.** Build cost multiplies (every candidate is its own SwiftPM workdir;
an 85-entry survey already leaves 3.4 GB) so it must be hard-gated and opt-in. A **disproven**
speculative law is ambiguous in a way a real one is not — it indicts either the code or the
extraction, and reusing `measured-defaultFails` would be dishonest, since that name means *the
property is false of your program*. And the copy is a [border claim](glossary.md#border-claim):
verify against a snapshot and report on the original, and a moved source silently invalidates the
verdict — record the source hash the way `run.json` records tool SHAs.

**The safety line survives, and reads better.** `swift-infer` still never modifies your tree; it
mutates a copy and proposes a patch, which is what every refactoring tool does.

#### Measured before building — and it changed the plan (2026-08-03)

The prerequisite shipped first (SwiftProjectLint#64: `TestRestriction`, so a patch generator can
tell "widen this declaration" from "widening it is a no-op"). Then a probe, because the population
figure answers the wrong question.

**Sampling.** 20 of the 641 `declaration`-restricted seeds on this repo — every 32nd, sorted by
`file:line`, **frozen before any was read**. Widened by line number in a throwaway worktree, then
the same `swift-infer` binary run over four targets, before and after.

| stage | count |
|---|---:|
| widened | **20** |
| gained a proposed law | **8** (256 → 264 suggestions) |
| law is **composer-supported**, i.e. `verify` can attempt it | **2** |

The two runnable are both `idempotence`. The other six are `predicate` ×3, `filter-subset`,
`comparator` — none of which has a composer, so they would be proposed, scored, rendered, and then
decline `unsupported-template`. Six of the seven distinct laws are `Possible`, hidden by default.

**Access is not the binding constraint.** Widening it moves a function from *invisible* to
*proposed-but-unrunnable*; the binding constraint is the composer set. The probe's contribution is
showing the access population lands in **the same bucket** the decline census already described.

**The first reading of this was wrong, and the error is the instructive part.** Extrapolating 10%
over 641 seeds gives ~60 runnable laws, which was written up as a disappointment — by comparing 60
against **641 seeds**, the denominator this repo explicitly warns against (*"a seed is not a
suggestion"*, glossary). Nobody had measured what 60 would be added *to*. Measured, over the same
four targets:

| | suggestions | **runnable** |
|---|---:|---:|
| default tier | 180 | 28 |
| with `--include-possible` | 256 | **100** |

So +60 is a **60% increase in the executable population**, not a rounding error. Anchoring on the
seed count made a substantial gain read as a small one.

**What each lever might be worth — CEILINGS, not predictions.** Same corpus, same binary. 156 laws
are non-runnable today and **126 of them are `predicate`**:

| lever | attemptable after | change | needs |
|---|---:|---|---|
| today | 100 | — | — |
| `predicate` composer | ≤226 | **≤+126** | no new machinery |
| access widening (item 13) | ≤160 | **≤+60** | copy-mutate-verify |

Both are **composer-supported counts**, obtained by grouping declines by template name. That makes
them comparable *to each other* and to nothing else. Composer support is **necessary, not
sufficient** — the glossary says so — so every row still has to resolve a generator for its carrier,
compile, and not trap. That attrition is unmeasured. Neither number is a count of laws that would
run, still less of laws that would *hold*.

**The ordering claim is NOT established, and the reason is worth more than the claim.** These levers
were ranked by **count**, in a repo whose standing rule is *score refutability, not suggestion
count*. A totality law over a function that never traps passes every time, and 126 new green results
that cannot fail is the [Daikon trap](glossary.md#daikon-trap) wearing a composer — *"a wall of
green unrefutable passes is the Daikon trap in a new costume."*

The counter-argument is real and also unmeasured: `predicate`/totality is **role-entailed**, a law a
*correct* implementation cannot fail, which is the combination a law wants. A green pass there is a
guard against future change rather than noise. Both readings are available and nothing here decides
between them.

**What is actually known:** `predicate` is the largest blocked population, and `predicate` +
access widening compose — after a composer the probe's own 8 proposals go from 2 attemptable to 5,
so the composer makes item 13 better rather than redundant. **What is not known:** whether unblocking
`predicate` yields refutable laws or a wall of green. That is cheap to settle — take a handful of
the 126, hand-write the totality law, and ask whether any plausible wrong implementation traps.
Do that before committing to the order.

The probe cost about twenty minutes. Recorded because the habit is worth more than the result, and
the record now has **two** corrections stacked on one measurement: the extrapolation was first read
against the wrong denominator, and then the corrected reading was used to rank two options by a unit
this project explicitly rejects. Neither error was in the measuring.

#### Are `predicate` laws refutable, or a wall of green? — answered (2026-08-03)

**Not a wall of green.** Two independent readings of the same 126:

- **Measured, all 126:** **35 (27%)** already contain an explicit totality-shaped guard — 17 count
  bounds, 12 `isEmpty` checks, 8 optional-`first` guards, 2 index-domain aware. An author had to
  think about emptiness or bounds in a quarter of these functions.
- **Judged, a 20-sample** (every 6th, sorted by `file:line`, frozen before reading): roughly **half**
  operate on domains where a plausible implementation traps — string index walking, positional
  collection access, force-unwrapped `first`. `looksLikeMobiusNext` is the clean case: total as
  written, and `returnType.firstIndex(of: ",")!` is an entirely natural way to write it.

**The concrete framing.** For those 35, the totality law is a **regression test on a guard that has
none**. `isOptional`'s `type.count > 1` does no classifying work — it is there so the function is
total — and deleting it turns nothing red today.

**Limits, because both numbers are soft in different directions.** 27% is a *lower-bound proxy*: a
guard proves the author hit the issue, its absence does not prove safety, since totality is often
implicit in the operations chosen. The ~50% is judgement over 20 functions, not a measurement.
Neither says the law would *fail* on shipped code — it will not; refutability asks whether a **wrong**
implementation would be caught.

**A method note worth more than the result.** The first pass classified by regex — force unwraps,
subscripts, division — and returned **1 of 20**, with that one a false positive (`/` inside a
comment). The regex asked *"does this implementation trap?"* when refutability asks *"would a
plausible implementation be rejected?"* Different questions; the cheap proxy answered the wrong one,
which is the fourth instance today of measuring through a proxy that does not cover the claim.

**What it settles:** the wall-of-green objection to the `predicate` composer is gone. **What it does not:** the
precise ranking of 14 against 13 — refutability was measured for `predicate` and not for access
widening's output, though that output's 2 runnable rows were both `idempotence`, a conjecture
template a wrong implementation can fail by construction.

### Signature, not carrier — the largest measured blocker to running laws (2026-08-03, scoped not built)

**The finding.** `verify --all-from-index --template predicate` over this repo, after the
`--target` derivation fix, resolves 126 entries into:

| outcome | count |
|---|---:|
| ran and held | **54** |
| compile: type not in scope (cross-module) | 37 |
| compile: n-ary predicate | 19 |
| no generator for carrier (SwiftSyntax nodes) | 11 |
| trapped — declined as domain evidence, correctly | 4 |
| other | 1 |

Two error buckets dominate, and they are **not two defects**. `SemanticIndexEntry` records
`carrierTypeName` — **singular** — and `primaryFunctionName` carries argument *labels* only
(`matches(typeName:inheritedTypeNames:)`). So:

- a predicate taking `(A, B)` cannot be composed, because nothing says what `B` is — **19 rows**;
- a predicate over a type declared in another module cannot be imported, because nothing records
  which module any type lives in — **37 rows**, of which **31 are `FunctionSummary` alone**.

One missing fact, two symptoms, **56 of the 72 non-running rows (78%)**.

**The data already exists and is dropped.** `FunctionSummary.parameters[].typeText` carries every
parameter type at scan time, and `FunctionSummary.location.file` carries the file;
`TypeShapeBuilder` reads `decl.location.file` too. Neither survives projection into the index.

**Where it must NOT go.** `Discover.PipelineResult.typeShapesByName` is
`[String: PropertyLawCore.TypeShape]` — the **kit's** type, owned by SwiftPropertyLaws. Putting a
module or source path on it is a cross-repo change plus a pin bump, for a fact the kit has no use
for. The established alternative is a **sidecar map keyed by type name**, and this would be the
third: `inheritedTypesByName` exists because the shape merges same-file extensions only, and
`genericParametersByName` exists because — in its own words — *"`TypeShape` does not carry them …
which is why `scaffold-kit-suites` wrote `Deque.self`"*. Same shape of gap, same remedy.

**The change, in five pieces.**

| # | what | where |
|---|---|---|
| 1 | `sourceFileByTypeName: [String: String]` | `Discover.PipelineResult` — third sidecar map, no kit change |
| 2 | `parameterTypeNames: [String]?` on the entry | `SemanticIndexEntry` + the projection; straight pass-through from the summary |
| 3 | persist the sidecar beside `typeShapes` | `IndexStore` / `IndexCommand` |
| 4 | import set = union of modules over every type the recipe touches | the stub emitter, via **`VerifyTargetInference.module(forLocation:)` — already shipped**, so no new concept |
| 5 | draw one value per parameter, not one per law | `composePredicatePass` |

**Rollout is graceful and needs no schema bump.** `SemanticIndexEntry` has a hand-written
`init(from decoder:)` using `decodeIfPresent`, so an added optional decodes as `nil` from an
existing index and verify falls back to today's behaviour. `reindexIfNeeded` then repopulates it on
the next stale read, which shipping the code itself triggers.

**≤+56 is a CEILING, not a prediction** — the same discipline items 13/14 are held to. Composer
support is necessary, not sufficient: an n-ary predicate still needs a resolvable generator for
*each* parameter carrier, and the 11 SwiftSyntax declines are evidence that some will land exactly
there. The honest claim is *up to* 110 of 126 (87%), with the attrition inside that unmeasured.

**Two known limitations, stated rather than discovered later.** The sidecar is keyed by **bare type
name**, so two modules declaring the same type name collide — an existing limitation of
`typeShapesByName` that this inherits rather than introduces. And a stub importing N modules builds
more than one importing one; this survey already costs ~35 min and ~72 GB for 126 entries.

**How to measure it.** Re-run the identical command — `verify --all-from-index --template predicate
--max-parallel 4` — per §10.3: two binaries, same day, same corpus, never against a remembered
count. **The run above IS the before-binary measurement**, taken 2026-08-03 at `1d39745` plus the
`--target` derivation. Do not substitute a recollection of it.

### Signature, not carrier — the measured close (2026-08-03)

Three binaries, same 126 entries, same afternoon — the §10.3 shape, and the reason the numbers are
comparable at all.

| bucket | A: `--target` | B: `+signature` | C: `+fixes` |
|---|---:|---:|---:|
| **ran and held** | 54 | 94 | **104** |
| compile: type not in scope | 37 | 0 | **0** |
| compile: arity | 19 | 7 | **0** |
| no generator for carrier | 11 | 20 | 17 |
| trapped — domain evidence | 4 | 4 | 4 |
| other | 1 | 1 | 1 |

**Both compile buckets closed. `≤+56` realised as +50**, and the 6 it fell short by are visible
rather than unexplained: carrier declines rose 11 → 17. Those entries did not get worse — they
stopped failing at compile and started failing earlier, at generator resolution, which is where
they were always going to fail. `DefaultFileSystemReader` was never generatable; saying so beats
reporting a missing argument count.

**Three defects sat between "written" and "runs" for the `predicate` composer** — it was
unreachable at gate 2, then never-composing because a compile-time value escaped as a
runtime one — and every one was invisible to the unit tests that call the composer
directly. That is the general shape: a composer's unit tests exercise the composer, and
these defects were all in what reaches it.

**Two further defects that only running it could find**, both invisible to those tests:

1. **The receiver is an implicit parameter.** `receiverCallExpression` renders `{ $0.method($1) }`,
   so an instance method's closure takes `parameters + 1` values. Exactly 7 entries, and all 7 had
   been failing on a missing type first — *a refuter that fires first hides every refuter behind
   it*, which is a design decision in this repo and turned out to describe its own measurement.
2. **The n-ary path dropped the resolver.** `emit` builds a `GeneratorResolver` from `allShapes`;
   the totality composer re-resolved per parameter without it, so nested custom types could not
   derive. Five `FunctionSummary` laws declined for a type that derives fine on the unary path —
   which never noticed, because it is handed an already-resolved recipe. **Anything that
   re-resolves must re-resolve with the same resolver.**

**What remains is a different kind of problem.** Of 22 non-passing, **17 are carrier declines** and
14 of those are SwiftSyntax nodes or optionals — nothing derives generators for those, and it is
not more plumbing. Plus `[String: TypeShape]` ×2 and `[TypeDecl]` (containers of custom types),
4 traps the carrier gate correctly refuses to call refutations, and 1 undiagnosed build failure.

**And 104 laws holding is not 104 findings.** Zero refutations across all three runs. These are
executable regression guards on code that is currently correct — the refutability prediction, and what
*score refutability, not suggestion count* requires be said out loud.

### Access widening, re-measured — the read was right about the cause and wrong about the lever (2026-08-04)

Item 3 asked for a **pre-check**: do the widened functions' parameter types land in the same
carrier-decline bucket the residual 17 do? Then it asked for the re-measurement. Both were run,
in that order, and the pre-check turned out to answer a *narrower* question than it was asked.

**Apparatus, stated first because one detail invalidated the first attempt.** 641
`declaration`-restricted seeds (the identical figure to 2026-08-03), sorted by `file:line`, every
32nd — indices 31, 63, … 639, exactly 20 — **frozen to a file before any body was read**. Two
worktrees at `1e0218e`, pristine and widened. Two binaries, **same day, same trees**, per §10.3:
**A** = `7e7a633` (the last commit before the `predicate` composer) and **B** = `1e0218e`. The
index — not `discover`'s prose — is the instrument, because it is JSON, it defaults to
`--include-possible`, and it is the artifact `verify --all-from-index` actually consumes.

> ⚠ **These are not the same 20 functions as 2026-08-03.** That list was never recorded — only
> the aggregate was. The sampling *rule* is reproduced exactly and the seed population is
> identical (641), but function-level comparison to the old run is not available. Read the old
> `20 → 8 → 2` as context, never as this table's before-column; the before-column is binary A.

**The funnel, executed.**

| stage | A (`7e7a633`) | B (`1e0218e`) |
|---|---:|---:|
| widened | 20 | 20 |
| index entries, pristine → widened | 249 → 255 | 249 → 255 |
| **gained a proposed law** | 6 | 6 |
| composer-supported | 4 | 6 |
| **ran a law** | **0** | **3** |
| held | 0 | 1 |
| refuted | 0 | 2 |

**The recorded read is refuted, and not by the lever it was filed under.** *"Widening moves a
function from invisible to proposed-but-unrunnable"* was true of binary A and is false of HEAD.
But the `predicate` composer is **not** what changed it — the composer moved 2 rows from
`unsupported-template: predicate` to `unsupported-carrier: FunctionDeclSyntax` /
`InheritanceClauseSyntax?`, which is a **more honest decline and still zero laws run**. What made
laws run was the signature-not-carrier cross-module import fix: all three `idempotence` rows failed under A with
`build-failed: cannot find 'LiftedTestEmitter' in scope` (and `IdempotenceStubEmitter`,
`Suggestion`) and execute under B. **The two levers were ranked against each other; the one that
mattered here was neither.**

**The pre-check was right, and it was answering a smaller question than it was asked.** It
predicted 3 of 20 SwiftSyntax carriers against 14 of 17 in the residual list, i.e. *not the same
bucket*. Measured: the two rows that reach a carrier decline are **exactly** rows 10 and 20 of
the pre-check, declining on `FunctionDeclSyntax` and `InheritanceClauseSyntax?` — the residual
bucket named verbatim. So the bucket prediction held **per row**. What it could not predict is
**which functions gain a law at all**: 6 of 20 did, and two of the five all-primitive rows
(`source`, `manifest`) gained nothing, because the template gate — not the carrier — decides
whether a law is proposed. Parameter types predict whether a proposed law can *run*; they say
nothing about whether one is *proposed*. The pre-check conflated the two, cheaply and recoverably.

**3 ran is not 3 wins, and this is the first time that was visible.** One is a real regression
guard (`sanitizeKeyPathForIdentifier` — strips a leading `\.`, then `.`→`_`; genuinely
idempotent, `measured-bothPass` at 100 + 100 trials). **Two are false laws refuted at trial 0**:
`complexDoubleEdgePass` is a source-*template* emitter, so applying it twice embeds the block
twice, and `rebuildWithCounterSignal` **appends** a signal and a caveat per call, so `f(f(s))`
carries the counter-signal twice and scores −50 instead of −25. Neither is a bug; both are
`idempotence` firing on a `T -> T` shape that is not idempotent. Both sit at `Possible` (score
35), hidden without `--include-possible`. **The 2026-08-03 funnel could not see this at all** —
nothing ran, so precision was unmeasurable, and *"2 composer-supported"* silently read as
2 prospective wins. Against *score refutability, not suggestion count*: the honest yield of
this sample is **1 guard, 2 false proposals, 3 declines**.

**A trap that cost a full run, and it is the one item 13's design already warned about from a
different direction.** The first widening rewrote `private ` → `internal `, which is the obvious
spelling of "widen access". It gained **exactly nothing**: 249 → 249, *identical* identityHash
set. `FunctionScanner` skips explicit `internal` too (cycle 148, Lever A) — it reads the token as
deliberate SPI, and Swift's default access carries **no token**, which is the shape the scanner
accepts. So a patch generator that emits `internal` produces a patch that compiles, changes
nothing, and then fails verification for a reason unrelated to the law — the exact failure item
13 anticipated for members nested inside a `private` type, arriving from a second, unrelated
cause. **The patch must delete the modifier, not replace it.** Measured, not argued.

**What this does to the ordering.** Item 13 no longer produces unrunnable output, so the reason
to defer it is gone. But the case *for* it is now smaller and better-founded than the ceiling
suggested: 20 widenings → 6 laws → 3 executions → **1 correct law**. Extrapolated over 641 seeds
that is roughly 32 correct laws and 64 false proposals — a real gain and a real precision cost,
where before there was only a count. The widened tree **compiles clean**, so the access tier's
"the compiler makes the patch safe" claim is confirmed rather than assumed.

### Idempotency vocabulary — surveyed, not yet decided (2026-08-04)

Raised while scoping speculative *annotation* (item 13's cousin: add an annotation to a copy,
verify, propose it only when the law ran). Recorded as a survey because the decision is the
user's and the facts were not written down anywhere.

**The first read of this was WRONG and the correction is the useful part.** I claimed the
SwiftIdempotency and swift-infer vocabularies "don't meet, with nothing asserting they match."
The second half is item 4 and is true. The first half is false: **`EffectAnnotationParser` in
SwiftEffectInference already parses the entire SwiftIdempotency family**, bilingually — attribute
form (`@Idempotent`, `@NonIdempotent`, `@Observational`, `@ExternallyIdempotent(by:)`, `@Pure`)
*and* doc-comment form (`/// @lint.effect …`, `@lint.determinism clock_deterministic`) — with the
names configurable through `AttributeRecognition`. swift-infer already depends on it. The join
exists; it is simply almost unused.

**Three vocabularies, three genuinely different jobs. That part is healthy.**

| package | ships | job |
|---|---|---|
| SwiftIdempotency | `@Idempotent` `@NonIdempotent` `@Observational` `@ExternallyIdempotent(by:)` `@Pure` `@ClockDeterministic` | *what this function does* |
| SwiftPropertyLaws | `@Discoverable(group:)` `@PropertyLawSuite` `@ValueSemanticTests` … | *what to discover / generate suites for* |
| **this repo** | `@CheckProperty(.idempotent / .roundTrip(pairedWith:) / .preservesInvariant(_:))` | *which law to check* |

**The real inconsistency is one row of overlap, and it is duplicated FUNCTION, not spelling.**
`@CheckProperty(.idempotent)` expands into a peer `@Test func` (`CheckPropertyMacro`, M5.2);
SwiftIdempotency's `@Idempotent` + `@IdempotencyTests` does the same job. Two packages generating
idempotency tests from an annotation.

**And this repo reads neither half it owns.** `AttributeScanner` reads only the
`.preservesInvariant` arm — its own comment says `.idempotent` and `.roundTrip` "are ignored
here." `EffectAnnotationParser` is called at exactly **three sites, all `isClockDeterministic`**
(`FunctionScannerVisitor+Summary`, `ViewModelDiscoveryVisitor`, `ReducerDiscoverer`). Everything
else in the effect vocabulary is parsed by a linked dependency and consumed by nothing.

**Two defects found while checking, both small and both real:**

- `AttributeScanner`'s doc comment says it recognises `@CheckProperty` and that "SwiftInferProperties
  does not take a runtime dependency on **`PropertyLawMacro`**'s definitions". But `@CheckProperty`
  is **this repo's own macro** (`SwiftInferProperties/Sources/SwiftInferMacro/CheckProperty.swift`) — the comment
  attributes a local macro to another package. House failure mode, again.
- **`@ClockDeterministic` is deliberately OUTSIDE `AttributeRecognition`** and hardcoded — SEI's own
  comment says so in as many words. So the one annotation swift-infer depends on for admitting
  `async` is the single name that is neither configurable nor contract-tested. That is item 4's
  precise bite, now with a named target instead of a general worry.

**The order that was proposed, and the trap in reversing it.**

1. **Make swift-infer READ the effect vocabulary.** No cross-repo change — the parser is already a
   dependency. `@Idempotent` as corroboration; **`@NonIdempotent` / `@Observational` as vetoes**.
   This lands on the same afternoon's false-positive work: an author-declared `@NonIdempotent` is
   exactly the signal that kills a shape-only score-35 candidate, and SwiftIdempotency has
   spellings for the negative and conditional cases (`@ExternallyIdempotent(by:)`) that this repo
   cannot express at all. It also gives SwiftIdempotency its first stage in the toolchain.
2. **Then** converge authoring — retire `.idempotent` from `CheckPropertyKind`, keep `.roundTrip`
   and `.preservesInvariant` (no SwiftIdempotency equivalent).
3. **Then** the item-4 contract test, against the hardcoded `@ClockDeterministic` name.

**Doing 2 before 1 is the worst order**: it removes a working test generator and replaces it with
an annotation the tool cannot see — a rename that fails as a *missing* annotation, which is item
4's failure mode reproduced by hand. Same shape as the `private` → explicit `internal` no-op
measured the same day.

**Step 1 shipped the same day** ([#78](https://github.com/Joseph-Cursio/SwiftInferProperties/pull/78)), with one caveat against the framing that sold it — and dogfooding it then corrected the weight from +40 to +15 (see below). This
repo carries **zero** effect annotations in its own sources — the `@lint.effect` hits are all code
*about* the annotation — and SwiftIdempotency is not a dependency here. So a `@NonIdempotent` veto
would affect **0 of the 13 false positives measured the same day** (the `idempotence` survey). It is a
**capability, not a fix**: it gives an author a way to kill a false law, it does not kill one.
The shape-based work and the annotation-reading work attack the same class from opposite ends,
and only one of them helps a codebase that has annotated nothing — they should not be scored
against each other. What does hold up is the dependency-free part: the doc-comment spelling
`/// @lint.effect idempotent` needs no package dependency, so the veto is usable without adopting
SwiftIdempotency. And the tool **already speaks this vocabulary outbound** —
`discover --effect-annotations` recommends `/// @lint.effect pure` lines
(`EffectAnnotationAdvice` / `EffectAnnotationRenderer`) — and reads none back. One tool talking to
itself in English, which is the *consumer keeps asking the producer* observation with both ends in
the same repo.

#### Does `@ClockDeterministic` belong in SwiftIdempotency? (folded in 2026-08-04)

Raised as *"I think it was bolted on later for the infer-properties work"*. **The timing claim is
exactly right** — `@Idempotent` dates from 2026-05-19; `@ClockDeterministic` and `@Pure` both
landed 2026-07-10, the latter committed as *"closing the recognizer-first gap"*: the recognizer
existed first and the macro was shipped afterwards so the attribute spelling would compile.

**Two questions, and merging them is the trap.**

**Does it belong to the idempotency LATTICE? No — and four fences already say so**, none of them
added by this conversation:

1. Its own doc header: *"Not an effect tier … attaching it grants no lattice trust — it makes a
   **determinism** claim."*
2. A different doc-comment namespace — `@lint.determinism`, where every other marker is
   `@lint.effect <tier>`.
3. SEI **excludes it from `AttributeRecognition`**; the configurable set is
   pure / idempotent / nonIdempotent / observational / externallyIdempotent, and this one gets a
   bespoke `isClockDeterministic(declaration:)`.
4. `Effect` has five ordered tiers. `@lint.determinism` has **exactly one legal value**
   (`clock_deterministic`) — a singleton namespace beside an ordered lattice.

**Does it belong in the PACKAGE? Probably yes, and the two arguments that look decisive both
fail.** *"SwiftIdempotency does not consume it"* is true — and true of **all five markers**, which
are `EmptyPeerMacro {}` and expand to nothing; the whole family is vocabulary, so this does not
separate it. *"It landed late"* fails too: `@Pure` shipped the **same day** for the **same**
recognizer-first reason and is uncontroversially the lattice bottom. And every alternative home is
worse — moving it to swift-infer would have **SEI (upstream, shared with SwiftProjectLint)
recognising a name owned by a downstream package**; SwiftPropertyLaws is a real candidate since it
ships the law that falsifies the claim (`TimedAsyncSequence.debounceIsDeterministicUnderTestClock`),
but its macro vocabulary is suite generation, not claims; a package for one marker is overkill.

**So the problem is not location — it is that the package silently plays two roles** (the
retry-safety lattice, and the toolchain's marker-macro home) and only the first is named.
`@ClockDeterministic` is a tenant of the second, defended by four fences and stated as a structure
nowhere.

**The concrete cost, which is the part worth acting on.** Because it sits outside
`AttributeRecognition`, it is the one annotation in the toolchain that is **neither configurable
nor contract-tested** — and it is the one swift-infer depends on to admit `async` at all. That is
open item 4's target. Either give it a `determinism` field in `AttributeRecognition` (a **separate**
field, not an effect tier — the orthogonality is real and worth keeping) or write the contract
test. Doing neither leaves a rename failing as a *missing* annotation, indistinguishable from
unannotated code.

### The `@EffectUnknown` dependency chain (2026-08-04)

Recorded because the chain is four links long, crosses three repositories, and
its **first** link is an open performance issue — which is not a connection
anyone would guess from either end.

**Where it started.** Item 17's step 1 made swift-infer read the effect
vocabulary, and dogfooding it surfaced a gap: an author who means *"I cannot
guarantee idempotency here"* had no way to say so. `@NonIdempotent` claims
something strictly stronger — SwiftIdempotency defines it as **unconditionally**
non-idempotent, *"re-invocation produces additional observable effects (sending
email, inserting rows, publishing events)"*. The tier that does mean "cannot
determine" is `unknown`, which had been in the reference lattice from the start
and was **inference-only**: no spelling, so no way to write it down.

**Link 0 — shipped.** `@EffectUnknown`
([SwiftIdempotency#3](https://github.com/Joseph-Cursio/SwiftIdempotency/pull/3)),
marker-only, plus `/// @lint.effect unknown`. Also corrected two stale
`REFERENCE.md` claims found while checking — the table gave `pure` no macro and
the prose called `pure`/`unknown` "tiers that need no marker", but `@Pure`
shipped 2026-07-10.

| # | link | state |
|---|---|---|
| 0 | SwiftIdempotency ships the marker | **done** |
| 1 | SEI learns to *read* it | **now the only blocker** |
| 2 | swift-infer bumps the SEI pin | **done 2026-08-04** — `bfcf0e3` |
| 3 | swift-infer suppresses on it | waiting on link 1 |

**Links 2 and 3 came unblocked the same day**, by fixing [SEI#1](https://github.com/Joseph-Cursio/SwiftEffectInference/issues/1) rather than
working around it — the `~2×` regression that made the pin unbumpable is gone, and
the bump landed past it. What is left is the one link that was never about
performance.

**Why the reader must live in SEI.** swift-infer could parse `@lint.effect`
itself, and that is precisely what `EffectAnnotationParser` exists to prevent —
one grammar, shared by SwiftProjectLint and swift-infer, is the reason the
vocabulary has not already drifted. Re-implementing it downstream would buy
speed now and a second dialect later.

**Why that blocks on a performance issue.** swift-infer pins SEI at
`1f2265a0`; SEI's HEAD is `097181a`, the commit [SEI#1](https://github.com/Joseph-Cursio/SwiftEffectInference/issues/1) records as a
`~2×` regression on the whole-domain purity path and names as blocking the pin
bump. So the reader cannot ship without either moving past that commit or
branching SEI from the old pin — and a divergent branch is worse than waiting.

**Deliberately NOT in the chain: an `Effect` case.** `unknown` is *incomparable*
to `non_idempotent`, so admitting it to SEI's `Effect` enum would force its
linear five-tier chain into a genuine partial order and replace the rank-only
`lub(_:)` with a Hasse-diagram join — a change SEI declined for exactly this
tier. Link 1 should therefore read it the way `@ClockDeterministic` is read: its
own predicate, outside `AttributeRecognition`, answering its own question. That
keeps the chain to a reader rather than a re-derivation of the core algebra.

**The honest state until then: the marker documents intent and nothing acts on
it.** Which is the very condition it was built to end — a declaration that is
indistinguishable from an unannotated one. Worth saying plainly rather than
letting "shipped" imply "working".

### The `Gen<URL>` defect — fixed, after a wrong diagnosis worth keeping (2026-08-04)

Item 19, closed. Two lines in this repo, no kit change, no version bump. **The first
diagnosis of it, published earlier the same day, was wrong**, and the way it was wrong
is the more useful half.

**What it actually was.** `Gen<T>` comes from `PropertyBased`; the Foundation
generators — `Gen<URL>.url()`, `.uuid()`, `.data()`, `.decimal()` — are **extensions in
`PropertyLawKit`**. The algebraic verify workdir declared `PropertyLawComplex` and not
`PropertyLawKit`, and the strategist stub imported `PropertyBased` alone, so the
expression the kit handed us referenced an extension the file could not see.

**Why the kit is not at fault.** `CompositeMemberParser` omits `PropertyLawKit` from
`requiredImports` **deliberately**, saying these are *"the generators every derivation
consumer already imports"* and naming `GeneratedFileEmitter` / `ScaffoldFileEmitter`.
True of the kit's own emitters. False of a verify stub — which is a
[border claim](glossary.md#border-claim) about a consumer in another repository, and we
were the consumer violating it. `.interaction` and `.valueSemantics` already declared
the product; `.algebraic` was the outlier.

**The wrong turn, recorded because it cost a cross-repo refactor.** The first pass added
the product and the import by hand, ran the binary **directly**, and hit
`dyld: Library not loaded: @rpath/libTesting.dylib`. That was written up as *"the obvious
fix builds and then does not run"*, and a `PropertyLawFoundation` carve-out was built in
SwiftPropertyLaws to move the generators out of a Testing-bound module.

Three things falsified it, in order:

1. A probe importing **only** the new Testing-free target still failed to launch — so
   `PropertyLawKit` was never the source.
2. **`swift-property-based` itself imports `Testing`** (four files). Every verify stub
   ever emitted links it.
3. `VerifierSubprocess` **already injects `DYLD_LIBRARY_PATH` / `DYLD_FRAMEWORK_PATH`**
   for exactly this, and says so — V1.53.A, tracing cycle-49's 12 parse-error picks to
   this same `dyld` message.

So the launch failure was an artefact of running the binary outside the harness that
exists to run it. **The lesson is not "check the harness" but something narrower: a
reproduction that skips the caller is not a reproduction.** The carve-out was reverted
unpushed.

**Measured after the fix**, every `URL`-carrier row on this repo:

| | before | after |
|---|---:|---:|
| execute | 0 | **11 of 13** |
| held | 0 | 2 |
| **refuted** | 0 | **9** |

The 9 refutations are the `defaultPath(for:)` family, and they are **not new bugs** —
they are `appendingPathComponent`, which the `idempotence` frozen classifier flagged as
`extension` (the output extends its input, so it cannot be idempotent). Nine blind
predictions, nine confirmations, on rows that could not run when the prediction was made.
That is the strongest evidence the classifier has, and it arrived from a defect fixed for
an unrelated reason. The 2 remaining non-executing rows are a different class
(`cannot find 'Scaffold' in scope` — the cross-module import fix's residual, not this).

### Adopting `verdict(for:)` — the measurement argued against the obvious version (2026-08-04)

Item 2's last piece, and the A/B ran **before** the build rather than after it.

**The population, measured on 2,500 functions in this repo:** 2,206 `.pure`, **35
`.pureButPartial`** (1.4%), 259 `.refuted`. Those 35 are everything adoption could
newly admit.

**Why the literal reading of "adopt `verdict(for:)`" is wrong.** `isInferredPure` has
exactly **one** consumer — the `/// @lint.effect pure` advisory. It gates no law, no
score, no template. So adopting the verdict *there* would mean advising 35 partial
functions `pure`, and that is false: SEI defines the tier as *"no side effects,
deterministic, **and total**"*, and the lattice has **no tier** for
deterministic-but-partial. There is nothing honest to tell them, so the advisory is
deliberately unchanged.

**What was adopted instead** is the half that is not a lie: `SoundPurity.verdict(for:)`
and `FunctionSummary.purityVerdict`, carrying the state the Bool collapse destroyed.
Before this, `isPure` answered `false` for all **294** non-pure functions alike —
nothing downstream could distinguish *"reads the clock"* from *"raises its own error"*.
The information was being discarded at the scan boundary, which is the same shape as
every other producer→consumer loss in this toolchain.

**The soundness worry is real and does not apply.** Admitting `throws` resembles the
relaxation this project warns about — *"removing the `throws` gate once re-admitted
`Process`/`Pipe`/`FileHandle`/SQLite at once"*. It is not: `.pureButPartial` requires
the body contain **no `try` at all**, so a throw propagated from a dependency still
refutes. Only a function raising its own errors qualifies. Pinned by a test, because
the resemblance is close enough to be worth guarding rather than explaining.

**A/B: 251 → 251 suggestions, and the only 12 differing lines are self-referential** —
the docstring advisory went 139 → 140 because the new `verdict(for:)` is itself a
documented function in the scanned corpus, plus two line-number shifts. The tool
noticed the function just added to it.

**The 35 stay unconsumed on purpose.** They are waiting on a consumer that can narrow a
law's domain to the non-throwing inputs, which is what `PurityVerdict`'s own doc says
the method is for. Filing them as available beats inventing an annotation tier to
justify reading them.

**The regression that made this adoption possible is fully closed, with no second fix to
chase.** [SEI#1](https://github.com/Joseph-Cursio/SwiftEffectInference/issues/1) was a `~2×` cost on the whole-domain purity path;
[SEI#2](https://github.com/Joseph-Cursio/SwiftEffectInference/pull/2) removed it by
stopping `inferredEffect(for:)` delegating to `verdict(for:)`, which cannot check
`throws` until *after* the body walk. That delegation was the **entire** cost — the
erased-`Syntax` generalisation the issue also suspected contributes nothing measurable —
so SEI performance is not a live thread here.

### Was SwiftProjectLint paying the purity regression? No (2026-08-04)

The suspicion was reasonable: SPL calls `PurityInferrer` from two visitors over every
function *and closure* in a project, so it has more calls into that path than anything
else. It was still wrong, and the way it was wrong is the useful part.

**Measured, §10.3 shape.** Two *release* binaries from one commit differing only in the
three SEI manifest lines, alternating runs over a 564-file corpus:

| run | `097181aa` (regressed) | `bfcf0e3` (fixed) |
|---|---:|---:|
| 1 | 8.15s | 8.16s |
| 2 | 8.23s | 8.40s |
| 3 | 8.42s | 8.42s |

Indistinguishable.

**The mechanism, which matters more than the number.** SPL calls
`PurityInferrer().verdict(for:)` and `PurityInferrer().isPure(accessor:)`. It **never
calls `inferredEffect(for:)`** — and that was the only method [SEI#1](https://github.com/Joseph-Cursio/SwiftEffectInference/issues/1) regressed, by
delegating to `verdict` and inheriting a body walk before the `throws` check. SPL was
already asking the question that legitimately costs the walk, so there was nothing to
inherit. The fix helps swift-infer, which asks the whole-domain question, and is a
genuine no-op here.

**A null result is only worth recording with a mechanism**, otherwise it is
indistinguishable from a measurement too coarse to see the effect. This one has both.

**Incidental, and larger than the thing being measured**: while checking that both arms
produced identical findings, they did not — and neither did the same binary run twice.
**476 of 3,844 findings (12.4%) report a different LINE between identical runs**, 472
of them the two cross-file *could be private* rules. Filed as
[SPL#67](https://github.com/Joseph-Cursio/SwiftProjectLint/issues/67). The `pbt-seeds`
manifest is stable across three runs, so the lint→infer hop does not carry it.

**One method note, because it nearly became a false finding.** A first pass compared
seeds keyed on `(file, symbol)` and reported 238 "moved" seeds. Overloads share that key
— two `merge` functions in one file — so the dictionary collapsed them and the
comparison was meaningless. The multiset comparison on `(file, line, symbol, kind)` is
the correct one, and it says stable. Same shape as the day's other near-misses: the
cheap key answered a different question from the one being asked.

**SPL#67 is fixed, and verified here rather than read off its state (2026-08-05).**
[SPL#68](https://github.com/Joseph-Cursio/SwiftProjectLint/pull/68) measures a cross-file
finding against its own file instead of the last one walked, and walks the cache in path
order. Re-measured from a binary built at that merge, three runs over this repo: **752
findings each, `(file:line, rule)` multiset identical**, including all 159
`Could Be Private Member` rows — 472 of the original 476. The residual is **order, not
content** (624 of 752 findings change position), filed as
[SPL#69](https://github.com/Joseph-Cursio/SwiftProjectLint/issues/69) and irrelevant to
the hop, since `pbt-seeds` is stable.

### The `idempotence` false-positive rate, and the veto it earned (2026-08-04)

Item 18, closed. Survey of all 72 `idempotence` entries via `--all-from-index` at `1e0218e`:
**55 executed, 13 refuted — a 24% false-law rate**, and **every refutation sits at score 35**, the
shape-only floor (+30 type symmetry, +5 value semantics, no name signal); 0 of 4 at score 55. Read
beside `leaderboard-sort`'s finding that the score is *inverted* inside the 30–45 band — different
corpora, different bands, both measurements stand.

**A classifier frozen before any verdict existed.** Hypothesis: an idempotent function *projects*
onto a normal form, so its result is a **sub-part** of its input; a result that **extends** its
input cannot be idempotent. Recorded to `classification-FROZEN.json` at 0 verdicts, then scored:
**precision 5/6, recall 5/13**, 83% false-law rate in the `extension` class against 9% in
`reduction`.

**The decision turned on where those rows surface, not how many there were.** Score 35 is
`Possible`, **hidden from default output**, so PRD §3.5's *raise thresholds, don't add filters* — an
argument about reader-facing volume — never applied. What false laws actually cost is **index and
verify hygiene**: the index defaults to `--include-possible` by design, and each row burns a full
SwiftPM build in `--all-from-index`. That reframing is what made a tenth veto defensible where a
tenth *filter* would not have been. The precedent is exact: `orderSensitiveCarrier` vetoes because
*"the suggestion is genuinely wrong, not merely low-confidence"*, and a result built **around** its
input applies the construction twice. Falsity, not doubt.

| | before | after |
|---|---:|---:|
| `idempotence` rows | 72 | **54** |
| measured refutations removed | — | **8 of 13**, plus the 9 `defaultPath` rows |
| laws that HELD and were vetoed | — | **none** |

**Read the RETURN expression and nothing else** — the finding, not an implementation detail. A
body-wide scan calls `quoted(_:)` a normalizer (it runs `replacingOccurrences` and *then* wraps) and
calls a dedup an extender (`.append` appears while it filters). Both readings are wrong and both
come from looking in the wrong place. The frozen prototype's single false alarm came from its
body-wide fallback; dropping it cost no recall. *Where* you look beats *what* you look for.

**Three things the measurement forced that reasoning did not.**

1. **SwiftSyntax does not fold operators.** `text + "."` parses as `SequenceExprSyntax`, not
   `InfixOperatorExprSyntax`. The first concatenation check keyed on the folded node, looked
   correct, and fired **never** — the exact failure this classifier exists to catch in others.
2. **A bare `+` rule vetoed two laws that HELD.** `prioritised` is
   `kernels.filter{…} + kernels.filter{…}`; `unwrappingRepetition` is `Array(leading) + loopBody`.
   Both operands derive from the input, so `+` there is a **reordering**, not growth. The rule now
   requires a **literal** operand; both are pinned as regression tests.
3. **`IndexStore.upsert` keeps historical entries**, so the first re-measurement showed the veto
   firing on nothing. Delete the index before an A/B or it reports the union of every run.

**An apparatus bug caught before it became a finding.** Six rows first failed
`cannot find type … in scope`, which reads exactly like a residual of the signature-not-carrier cross-module import
fix. It was mine — the filtered index's `sourceFileByTypeName` pointed into a deleted worktree.
**Third instance in one day of the same shape**, and the standing lesson: *the harness fails in ways
that look precisely like the tool failing.*

**Domain transfer stays unclaimed** — `T -> T` where the output is a different *kind* of thing (a
hash, a rendered name, a seed string), so `f(f(x))` is meaningless though it type-checks. That is
the residual, and what the `_description` and capacity-from-scale vetoes have chased **by name** for
cycles. Not characterised well enough to veto on, and a veto that fires on a guess suppresses true
laws — the failure that cannot be seen from the outside. **Re-measured 2026-08-05** on the
whole-corpus survey: 24% → **10.6%** with the `extendsInput` class producing ZERO refutations, and
all survivors domain transfer. Now [#93](https://github.com/Joseph-Cursio/SwiftInferProperties/issues/93).


### The whole-corpus number, and the "regression" that was not one (2026-08-05)

Item 4, closed. `verify --all-from-index` with **no `--template` filter**, release binary at
`1ef7128`, `--max-parallel 4`. **139 of 281 entries execute a law: 130 hold, 9 refute.**
76 min wall, 7.7 CPU-hours, 107 GB of workdirs, 2.45 GB peak RSS.

| template | n | ran | held | ref | why the rest did not run |
|---|---:|---:|---:|---:|---|
| `predicate` | 129 | 76 | 76 | 0 | 49 no generator · 4 trap |
| `idempotence` | 54 | 47 | 42 | **5** | 4 trap · 1 build-failed · 1 no generator · 1 instance-method shape |
| `round-trip` | 46 | **0** | 0 | 0 | **45 no generator** · 1 build-failed |
| `input-totality` | 11 | 0 | 0 | 0 | 11 no composer |
| `codable-round-trip` | 8 | **8** | 8 | 0 | — |
| `associativity` | 6 | 4 | 4 | 0 | 2 no generator |
| `commutativity` | 5 | 4 | **0** | **4** | 1 no generator |
| `monotonicity` | 4 | 0 | 0 | 0 | 3 no generator · 1 domain not `Comparable` |
| `measure-non-negativity` | 4 | 0 | 0 | 0 | 3 no generator · 1 trap |
| 8 others (≤3 each) | 14 | 0 | 0 | 0 | 13 no composer · 1 no generator |

Corpus-wide: **105 carrier declines (37%)**, 24 no-composer (9%), 11 errors, 2 misc.

**The tier cut is the honest headline, and 139-of-281 is not.** The table above averages a 249-row
recall floor with 27 high-confidence rows, which are different populations asked different questions.

| tier | n | ran | held | ref | no generator | other | err |
|---|---:|---:|---:|---:|---:|---:|---:|
| **Strong** | 3 | **0** | 0 | 0 | 0 | 3 | 0 |
| **Likely** | 27 | 23 (85%) | 19 | **4** | 4 | 0 | 0 |
| **Possible** | 249 | 116 (47%) | 111 | 5 | 101 | 21 | 11 |

**All 4 real bugs are `Likely`. All 5 `Possible` refutations are false laws.** That is a stronger
result for the scoring than any aggregate — the tier predicts whether a refutation is worth reading.
And the **3 `Strong` entries, score 80, are the only tier where NOTHING runs**: all three decline
`unsupported-template` (`differential-equivalence` ×2, `invariant-preservation`). Verify cannot
attempt the suggestions discovery is most confident in.

**Two things `--template predicate` could not have said.**

1. **Refutations concentrate, and `predicate` contributes none.** 0 of 76 `predicate`, 5 of 47
   `idempotence`, **4 of 4 `commutativity`**. The wall-of-green question, answered from the other
   side: `predicate` really is regression-guard work, and the refutable population lives elsewhere.
   Every executed `commutativity` law on this repo is one of the four merges, and every one is false.
2. **`codable-round-trip` is the only template at 100% yield** — 8/8 ran, 8 held. It is also the
   only round-trip family that never has to GUESS an inverse: the inverse is the carrier's own
   `Codable` conformance. That is the comparison the row below turns on.

#### `round-trip`'s zero is NOT carrier reach — that reading was wrong (corrected 2026-08-05)

The first version of this entry called `round-trip` *"the biggest single loss — 46 entries, ZERO
laws, and the binding constraint is carrier reach, not composer support."* The decline census says
45 want a generator, so the census reads that way. It is wrong, and the correction matters more than
the claim.

| scan | round-trip suggestions | same-file | cross-file | cross-type counter fired |
|---|---:|---:|---:|---:|
| `--target <each of 7>` | **1** | 1 | 0 | — |
| `--sources Sources` (what the INDEX does) | **46** | 1 | 45 | **45 of 46** |

The index is built by a whole-`Sources/` scan, which pools functions across module boundaries and
forms 45 cross-module pairs a per-target `discover` never produces. `crossTypeRoundTripCounterSignal`
detects every one and demotes them to `Possible`/score 25, so **nothing false reaches default
output** — discovery is behaving correctly. But they are still written to the index, and
`--all-from-index` then spends a full SwiftPM build on each, rediscovering by compilation what the
counter's own detail line already says: *"property cannot type-check across distinct containing
types."* ~16% of a 76-minute run.

So the real shape of the zero is **45 non-candidates plus exactly one real law**
(`SamplingSeed.derive(fromIdentityHash:)` ↔ `renderHex(_:)`, same file, score 35), and that one is
blocked on a missing `SamplingSeed` generator. Filed as **#97**.

**How the wrong reading happened, because it is the reusable part.** The evidence was a `grep` for
`func <name>(` across `Sources/`, used as a proxy for *where does the paired inverse live*. It
answered a different question. `discover`'s own output was one command away and settles it exactly.
Same failure as the §8.9 regex that returned 1 of 20, and the fourth instance this project has
recorded of a cheap proxy not covering the claim.

Five defects filed. **#92** (merge fold non-commutative ×4) and **#95** (unqualified nested
carriers) are FIXED in [#98](https://github.com/Joseph-Cursio/SwiftInferProperties/pull/98).
**#93** (domain-transfer class), **#94** (round-trip receiver slot), **#97** (the survey builds
entries the counter already flagged) stay open, plus **#99**, which #95's fix uncovered. Items 21–26.

**Three of the five were re-reports of things this repo already knew**, and each was corrected in
place rather than quietly closed: #92 was pinned by `MergeAlgebraPropertyTests` over an injected
clock (all four logs, the associativity split, the stale docstrings, and a mutation test on
`>=` vs `>`); #93's class is named verbatim in `IdempotenceReturnShapeClassifier`'s doc, which
declines to veto it *on purpose*; #97's counter exists and fires. The tool's OUTPUT was new every
time; the diagnosis was not. **Search `Tests/` and the type's own doc before filing** — all three
would have been caught by one grep of the repo rather than of the corpus.

#### The 106 does not reproduce — and the flag raised over it is WITHDRAWN

The survey's first write-up flagged a top follow-up: `predicate` ran **76** where the stored
evidence recorded **106**, with carrier declines at 49 against 17. That was reported as a
discrepancy needing an A/B rather than as a regression, which was the right call, because the
A/B says **there was no regression and HEAD is better by 2**.

Two binaries, same day, same machine, **same 129 entries from the same index file** — the §10.3
shape, with the corpus held at HEAD so only the binary moves:

| bucket | BEFORE `2f65f92` | HEAD `1ef7128` | delta |
|---|---:|---:|---:|
| ran and held | 74 | **76** | **+2** |
| no generator for carrier | 49 | 49 | 0 |
| error: trap/parse | 4 | 4 | 0 |
| error: build-failed | 2 | **0** | **−2** |

**2 disagreements in 129, both the same direction**: `isDirectory(_:)` and
`isStale(indexPath:packageRoot:)` go `build-failed → ran and held`. That is the `Gen<URL>`
fix landing on exactly the row that motivated it. The carrier bucket is **49 in both arms**, so
the "17" was never a property of any binary in this range.

**The cheap half of the A/B was worth more than the expensive half.** Before running either
verify arm, both binaries built an index over the same sources: the predicate index is
**identical** — 129 entries, all 129 identities shared, 814 type shapes and 745 source-file
entries matching exactly. That is a five-second check and it eliminated the discover side
outright, including the two leading hypotheses (the purity-verdict change, the SEI pin bump).
The only index delta anywhere is `idempotence` 72 → 54, which is #78 doing its job.

**What the 106 was cannot be recovered, and that is itself the finding.** The survey's own
`persistSurveyBatch` overwrote `.swiftinfer/verify-evidence.json`, so the figure now exists only
as a reading taken mid-session. The evidence log upserts by identity and **keeps historical
entries** — the `idempotence` veto A/B already recorded that trap in the other direction — so the likeliest reading
is an accumulation across runs rather than one survey's output. Which is exactly why §10.3 says
never to compare against a stored count. **Third instance of a "measured drift" that was an
artefact of the comparison**, after the census's `SwiftInferCore` 96-vs-80 (`--include-possible`)
and this one's own two halves.

**A measurement whose artifact its own run destroys is not re-checkable.** Nothing was designed
to prevent that; the survey persists over the file it is being compared against. Worth fixing
before the next survey, or worth copying the evidence file first and saying so.

### The veto that was never asked, and the surface that would have hidden it (2026-08-05)

Item 26, closed ([#102](https://github.com/Joseph-Cursio/SwiftInferProperties/pull/102)).
`isUnaryEndomorphism` gated `idempotenceReturnShape` on exact
`parameter.type == returnType`; `IdempotenceTemplate+OptionalNarrowing` admits `T? -> T` as well.
The two gates disagreed and **nothing could notice**, because `returnShapeVeto` returns `nil` both
when the shape was never computed and when it was computed and cleared. Same shape as
`CuratedEntryRole` guarding the wrong join: a guard checking something narrower than the thing it
protects looks green while the hole stays open.

`Scaffold.defaultOutputURL(packageRoot: URL?) -> URL` returns
`(packageRoot ?? …).appendingPathComponent(…)`, and `appendingPathComponent` is the **first entry**
in the classifier's own `extensionCalls`. It would have returned `.extendsInput` unmodified. It was
never asked, so the law was proposed, ran, and refuted at trial 0.

**A/B, two binaries the same afternoon, index deleted between arms** (`IndexStore.upsert` keeps
historical entries — the `idempotence` veto A/B learned that the hard way):

| | before | after |
|---|---:|---:|
| index entries | 283 | **282** |
| `idempotence` | 54 | **53** |
| removed | — | **the witness, and only the witness** |
| added | — | **0** |

**Three things worth keeping.**

1. **The surface decided the answer.** Per-target `discover` and whole-`Sources/` `discover` both
   showed **zero** delta — the witness exists only in the **index**, which is built by a different
   pipeline. Measuring the convenient surface would have reported "no change" and proved nothing.
   Third time in two days that picking the wrong surface would have produced a confident wrong
   number.
2. **Three defects were stacked on one entry, each hiding the next**: a scope error (#95) hid a
   false law, which hid this veto gap. Only fixing the first made the second visible, and only
   running the second exposed the third. *A refuter that fires first hides every refuter behind it*
   — at the level of a single index row.
3. **A false law in the wrong bucket flatters the bucket.** This witness was briefly filed under
   #93's domain-transfer class, which it is not. Domain transfer stays at **5** witnesses; a class
   that absorbs anything unexplained stops being a characterisation.

**Unexplained and NOT chased**: the absolute index count moved from 281 earlier the same day to 283
in both arms. It cannot affect a same-day two-binary comparison, but **do not cite 281 as current**
until someone works out why.

### The census that pointed at the wrong constraint (2026-08-05)

Item 25, closed. All 45 cross-module `round-trip` pairs were filed as
`unsupported-carrier: <Carrier>` — *no generator derives this carrier*. They are not that. The
inverse half lives on a different type in a different module, so **even a perfect generator would
not make the call resolve**; `crossTypeRoundTripCounterSignal` had already said so at discovery
time, in a detail string that states the conclusion outright.

**The cost is demonstrated, not hypothetical: that label is what produced the claim "round-trip's
zero is carrier reach" in the survey write-up, and a proposal to spend effort on generators.** A
census that misattributes 45 rows to reach points work at the wrong constraint — the same failure
`verify-carrier-reach-census.md` records for a different cause (*"a census that forgets to thread
`allShapes` invents a carrier problem two-thirds of which is the harness"*), reached by a second
route.

| `round-trip` census | before | after |
|---|---|---|
| | 45 blocked-on-carrier + 1 error | **45 not-a-candidate + 1 blocked-on-carrier** |

The remaining 1 is `SamplingSeed.derive(fromIdentityHash:)` — the repo's **one** real round-trip
pair, genuinely waiting on a generator. That is the honest denominator.

**This issue was wrong three times, and the pattern is the lesson.** Wrong about the mechanism (the
counter does fire — 45 of 46, no misses); wrong about the population (discovery is correct, it is
the whole-`Sources/` *index scan* that pools modules); wrong about the cost (**nothing builds** —
`buildStubBundle` throws before `runSwiftBuild`, so the 45 already declined for free). Each error was
**claiming without measuring something one command would settle**, and each was caught only by
finally running it.

**The one true cost claim is smaller and more specific than the one I invented.** A single
cross-type entry *did* have a derivable carrier, reached the compiler and failed there — **46.0s of
the round-trip arm's 46.5s**. So the saving is real and comes from exactly one row. That row was
also [#94](https://github.com/Joseph-Cursio/SwiftInferProperties/issues/94)'s only
witness, which is why closing it followed immediately — as **real-but-unwitnessed**, since
the `composeRoundTripPass` receiver defect is a correct code reading with nothing left to
exercise it. Its reopen condition is checkable from the index without running anything:
a `round-trip` entry that is an instance method, non-mutating, non-nullary, and carries no
structural blocker. **Zero matches today**, verified rather than assumed.

**`StructuralBlocker`'s bar, stated because it will be tempting to widen**: the signal must make the
law *unstatable as paired*, not merely improbable. A counter meaning "probably wrong" belongs in the
score, where a reader can overrule it. One member today, and it carries the counter's own `detail`
rather than a re-spelling, so the two cannot drift.

### Domain transfer, scored — a rule that cannot be built is a finding (2026-08-05)

Item 22 closed. `IdempotenceReturnShapeClassifier` declines to veto its documented miss class on the
grounds that it is *"not characterised well enough, and a veto that fires on a guess suppresses true
laws"*. This is the number behind that sentence.

**Method, fixed before the answer existed.** The candidate rule and its *predicted failure* were
committed in `5a6cff0`, before the scorer was written — git order is the proof, the same posture as
`q2-answer-key.json`. Scored against the 47 `idempotence` rows that EXECUTED in the whole-corpus
survey: 5 refuted, **42 held**.

Rule: **the parameter does not appear in the returned expression.**

| | count | |
|---|---:|---|
| flagged, genuinely the class | **4** | `markovSynthesized`, `regressionFileHash`, `seedString`, `seedTuple` |
| flagged, but a law that **HELD** | **8** | incl. `dedupedByStateAndAction`, `unwrappingRepetition` |
| the class, missed | **1** | `codableRoundTripGenerator` |

**Recall 80%, precision 33%** — two true laws suppressed for every false one removed.

**Why it fails, and the reason generalises.** *"The parameter is absent from the return expression"*
is true of **every function that binds a local and returns it** — a coding style, not a semantic
property. `seedString` hashes its input and returns a rendering of the digest, so the input is gone;
`normalisedTypeName` binds a trimmed copy and returns it, so the input is right there. **Those are
the same shape.** No return-expression rule separates them, so the signal is **dataflow** — whether
the parameter's value survives into the result or merely seeds something that replaces it. That is
strictly more expensive than anything this classifier performs.

**The prediction was right on both halves**, which is what makes it a test of the idea rather than a
description of an outcome: recall 4 of 5 *naming the miss*, precision below 50% *naming the suspect*.

**The transferable practice — score a veto against the laws that HELD, not against the class it
targets.** Recall on the target class is easy and says almost nothing; the 42 held rows are where a
veto's cost lives, and they are the only reason this failure was visible. It is also why
`unwrappingRepetition` appears here after the `idempotence` veto's first bare-`+` rule had already mis-vetoed it: **a
handful of functions keep tripping every cheap heuristic aimed at this template**, and that set is
worth naming before the next one is proposed.

Closed as **measured-not-buildable**, not *no signal exists*. A dataflow proposal would likely work;
reopen with one and score it against the same 47 rows. Artifacts:
`fixtures/domain-transfer-signal/` and `DomainTransferSignalExperimentTests`, whose numbers are
**asserted rather than described** so they cannot drift.

### The measurement artifacts are frozen now, because the run destroyed its own (2026-08-05)

`fixtures/whole-corpus-survey/` holds the raw `verify --all-from-index` streams behind every number
in *The whole-corpus number* — 281 records, plus the 129-record `predicate` A/B before-arm and the
bucketing script. 132 KB.

**The reason is not tidiness.** That survey's own `persistSurveyBatch` overwrote
`.swiftinfer/verify-evidence.json`, which is gitignored, so the figure it was being compared against
**no longer existed anywhere** by the time the comparison was questioned. The SHAs and commands were
recorded and both binaries rebuild from git, so the *method* was always reproducible — but the raw
evidence lived in a session temp directory and would have gone with the session.

Two caveats live in that directory's README rather than here, because that is where someone re-running
will look: delete the index before an A/B, and **do not diff a fresh run against these files** — §10.3
wants both arms taken the same day, so these are evidence of what was measured, not a baseline.

### Doc staleness: automate the trigger, not the habit (2026-08-03)

The rejected alternative was *"check the design-internal docs whenever we merge."* Two problems:
the **trigger is wrong** (a merge here does not correlate with a sibling moving — the gap between
sessions does), and **"check the docs" has no pass/fail**, so a skipped check looks exactly like a
passed one. Shipped instead: provenance trailers + `make docs-drift` + a `SessionStart` hook, with
claims split by perishability — counts and measurements rot, diagnoses do not. See PRs #55/#56 and
`scripts/docs_drift.sh`'s header.

---

### The bucket is a channel, not a report (2026-08-17, `146d986`; amended at `8599bd5`)

Items 31/32 look like reporting work and are not. The standing observation *the consumer keeps
asking the producer for things, in English* has three recorded instances (`role` on a seed,
`KitEvidence`, the rescue warnings) and this is the fourth, with the same signature: the
producer already computed the fact, the consumer structurally cannot recompute it, and the
current carrier is prose.

What is different here is that item 28 **already priced it**. The `effect` object on
`idempotency` seeds closed because a linter with no §13 ceiling can pay for a multi-hop join
that `EffectResolver`'s one-hop pass cannot. The blocking-callee identity is the same class of
fact reaching the same boundary, and it needs no new channel — the seed `effect` object is
already there.

**The trap to avoid**: shipping the bucket as a rendered report first. Item 20's lesson is that
a vocabulary nobody reads is indistinguishable from one that does not exist, and item 28 is the
same with roles reversed. If the ranking has no consumer, it is a third instance rather than a
fix.

**The trap was real and it sprang somewhere else — recorded 2026-08-17.** This stub expected it via
item 35: the `pure` advisory is outbound-only, so a *recommended annotation* would have no reader.
What item 31's census found instead is that the **verdict** has no reader — the whole population
throws, so it can only ever reach `.pureButPartial`, and nothing branches on that tier. The trap was
one level further down than the stub was watching, and it was reachable by measurement rather than
by argument. **Generalising: "does this have a consumer?" has to be asked of the OUTPUT VALUE, not
only of the report that would carry it.**

### Purity's tiers are asymmetric in what they can be proven by (2026-08-17, `146d986`; the axiom row sized at `0882bcf`)

Three tiers, three different strengths of evidence, and putting their numbers in one column
would repeat exactly the error the tier cut in *The whole-corpus number* corrected:

| tier | can confirm | can refute | denominator |
|---|---|---|---|
| axioms (item 30) | — | — | asserted; not a measurement. **Sized 2026-08-17: 508 names hold this corpus, 24 hold half of it** |
| static inference | yes, given the axioms | yes | functions analysed |
| runtime recorder (item 37) | **no** | yes | invocations observed |

The static tier's confirmations are conditional on a hand-curated list. The runtime tier cannot
confirm at all. So a headline "N% pure" averages three populations asked three different
questions — the 139-of-281 mistake, in a new place. Report the tiers separately or not at all.

### What would falsify the whole line of work — TAKEN 2026-08-17, and it did not falsify

Item 29's measurement. The condition was: if most of the `.refuted` carry a real witness, there
is no bucket, 31–33 have nothing to rank, and the honest close is *measured-not-worth-building*
with the number attached — the same posture as item 22.

**It came back the other way.** 152 of 284 refutations named nothing in the source, so ignorance
was the majority and the bucket exists. `docs/measurements/purity-refuted-bucket-census.md`.

**And then it came back partway again, hours later, on the same day.** Row 41's fix put the split
at 135 of 299 — a 45% minority. The bucket still exists and is still entirely actionable, which is
what the falsifier was actually testing; what did not survive is the stronger *most of the bucket
is unread*. **A falsifier that passes is not thereby settled** — this one was overturned in part by
a fix to something else, and the lesson is that the answer is a function of the oracle's pin, not
of the corpus alone.

Three things to carry forward, because the measurement changed the shape of 30–33 rather than
merely licensing them:

- **The rankable population is 135, and the number a naive report would print is 219.** The gap
  is 84 rows that carry an independent witness. Item 32's warning was about *joint* blockers; the
  census found a blunter version underneath it, which is rows that no annotation can move at all.
  **It read 152 / 67 for a few hours** — row 41's default-argument refuter moved 17 more rows into
  the unmovable set on the day it landed, from outside the ranking entirely.
- **`noBody` is 0, so the ignorance half needs no triage.** Every row has a callee to name.
- **A new precondition sits in front of item 31**: the 180 computed properties in item 40 are
  `.refuted` by an initialiser default and must be excluded before anything is ranked. Rank
  first and 39% of the input is a question nobody asked.

**What the census deliberately does NOT discharge** is item 35 — the `pure` advisory is
outbound-only, so a leverage report may still have no consumer, and the trap named two
paragraphs up (shipping the bucket as a rendered report first) is untouched by this number.

---

## Standing observations

Toolchain-level reads with no single owning package. Not tasks; not measurements.

### The documented error direction has been backwards three times, always permissively

Row 30 — `PurityInferrer` documents *"any doubt refutes"* and the marker sets *"err toward
flagging"*; measured, an unrecognised callee refutes nothing and a subprocess spawn reads `.pure`.
Row 33 — chains were documented as terminating at the first `map`/`reduce`/`filter`; measured, nine
of ten probe shapes sail straight through and the real defect is an **over**-claim. Row 35 — the
`pure` advisory was filed as outbound-only; measured, it is read back and believed, and what is
inert is every *consumer*.

Three for three, and every one of them errs toward claiming **more** purity than the evidence
supports — the opposite of the conservative posture each doc comment states.

**A posture stated in a doc comment is a claim about intent, and intent is not measurable from the
doc that states it.** The transferable practice is row 47's, which paid for itself twice: **probe
the premise before scoping the build.** An afternoon against a phase, and the premise probe is the
cheaper half every time — rows 33, 47 and 46 were each closed or re-aimed by one.

### The consumer keeps asking the producer for things, in English

Three times the downstream tool discovered it needed something upstream already knew, and each was
bolted on differently:

- `role` on a seed — added **because `discover` was already printing** *"the manifest SHOULD have
  named it: this is a LINTER gap."*
- `KitEvidence` — the kit's verdicts were the only *executed* evidence anywhere and fed nothing back.
- The rescue warnings — `swift-infer` prints prose **addressed at the linter**, to a human, hoping
  they act.

Not three coincidences. The pipeline is one-way by design and has needed backflow three times.
Worth deciding deliberately: is one-way load-bearing, or just how it started? **When a tool's best
diagnostic output is a sentence addressed to another tool, that is a missing channel.**

### The middle is thin where it should be thick

Volume and value point opposite directions at the lint → infer boundary: ~664 candidate findings →
1,657 seeds → **21 default-tier picks**. Meanwhile the *refactoring* half — extract this kernel,
make this domain type — **does not seed at all** (`PBTSeedsFormatter.seedKinds` maps four rules,
all testability/idempotency). The highest-value handoff is human-only; the highest-volume one is
nearly all noise. `CandidateInventory` fixed the reader-facing symptom by collapsing the census;
the manifest still carries the flood and not the insight.

### "Toolchain" claims more than the code backs — *now half-addressed*

**Was:** two of five packages had no automated relationship to anything, and no command ran the
loop, so every claim about "the loop" described a sequence nobody had automated.

**Now:** `scripts/toolchain.sh` runs **stages 0–2** (locate → lint → `discover --seeds`) and
declares 3–5 as not-implemented on every run. What that changes and what it does not:

- **Closed:** the sequence is executable and attributable. `run.json` records tool SHAs, so two
  runs are comparable — the precondition for any end-to-end number.
- **Still open:** stages 3–4 do not exist, so **no run executes a law** (item 9). Stage 5 never
  will — hardening is a human's job, and the driver says `not-a-command` rather than pretend.
- **SwiftIdempotency is still attached by one word** (`@ClockDeterministic`, via SEI) and appears
  in no stage. That half of the observation is untouched.

**Two facts that only surfaced by writing it**, and they say more than the observation did:

1. **`.pbt/seeds.json` had never existed anywhere on this machine.** Both repos document that
   path — the formatter writes it, `discover --seeds` reads it — and the hop had no instance until
   2026-08-03. A documented handoff with zero instances is not a handoff.
2. **The loop's entry point could not be invoked** — SwiftProjectLint ships no installed binary
   and is not on `PATH`, so "run the linter" meant knowing to type `swift run CLI` from the right
   directory. **Fixed 2026-08-03** by `scripts/bin/swiftprojectlint` (add `scripts/bin` to `PATH`).

   The reason it stayed broken is worth keeping, because it was a *good* instinct producing a bad
   outcome: binaries were never installed because the code was always changing, and recompiling
   was the safe choice. That is correct — **an installed binary is a remembered build**, the same
   hazard the A/B rule exists to prevent. The wrappers keep that property (they build through
   SwiftPM every invocation, so the binary is always the working tree) while removing the friction,
   which was never the compile — it was the missing command.

### The measurements are all withdrawn; the diagnoses survive

`roadtest-self-dogfood.md` voided, `leaderboard-sort`'s scorecards voided,
`PBT_TOOLCHAIN_FIX_PLAN.md` scored against a frozen fixture. **There is no current number for
"does a reader following the loop reach the bugs?"** — the one row the road test says should be
the only row that matters. That is open item 7, and it is downstream of *"toolchain claims more
than the code backs"*: you cannot cheaply re-measure a loop you cannot cheaply run.

**Partly unblocked as of 2026-08-03.** `scripts/toolchain.sh` makes stages 0–2 re-runnable and
writes a comparable `run.json`, so a *seed-and-suggestion* number is now cheap. A **refutation**
number still is not, because that needs stage 3, which does not exist (item 9). Worth being exact
about which number is back: the loop's own headline row — *would a reader reach the bugs?* —
remains unmeasured.

### Two ways to manufacture a defect that is not there

Both nearly produced a filed bug on 2026-08-05, verifying someone else's fix.

**An unsorted `diff` of two runs conflates ORDER with CONTENT.** Comparing two lint runs
reported ~541 differing lines and read as *the fix did not work*. Sorting first showed the
findings and their line numbers were identical and only the sequence moved — a different,
lesser defect. Separate the two before concluding anything about determinism.

**Capturing with `2>&1` merges two unsynchronised streams.** A trailing banner written to
stderr spliced into the middle of a stdout finding line, at a different byte offset each
run, in every run. That looks exactly like a real output defect and is purely the
redirection; re-running with the streams separated showed one clean line. It was one
command from being filed.

Same family as the `(file, symbol)` seed key and the §8.9 regex: **the cheap capture
answered a different question from the one being asked.**

### A doc that characterises a set by a property its newest member lacks

It does not go out of date — it **argues against the code**. `PBTSeed.role`'s comment said *"every
rule but the two **candidate** rules"*, and `extractablePureKernel` is a kernel rule, so a reader
checking the sentence against the classifier would have read the correct behaviour they found there
as a bug. The count was stale *and* the wording ruled the third out by name, which is why it was not
a one-line fix ([SPL#65](https://github.com/Joseph-Cursio/SwiftProjectLint/pull/65)). Name the
members individually rather than counting them.

### Every guard here was a retrofit

`VerifierWorkdirKitPinTests`, `SeedRoleContractTests`, `KitCoverageLawLevelTests`,
`SubprocessBatchCoverageTests` — all added *after* the incident. Not one
[border claim](glossary.md#border-claim) was guarded when written.

The 2026-08-05 addition sharpens the diagnosis, because its claim was written **twice**
and enforced neither time: the Makefile says *"Keep every regex-matched suite in exactly
one batch"* and CLAUDE.md restates it as a standing instruction. Nine suites drifted
through both. So restating a rule in a second prose location does not approximate a
guard — **it produces the feeling of having one**, which is worse than a single
unenforced comment, since the reader now finds agreement wherever they check.

Worse still, that Makefile comment is not a general warning but a **tally**: it names
BATCH5, BATCH6 and BATCH7 as batches added *because* suites had already been orphaned
this way. The rule was therefore written at the site of the mistake, by someone who had
just made it, three times, and it did not prevent the fourth. **A comment that records
its own recurrences is a guard's worth of evidence being spent on prose.**
The question is not "which guard is missing" but **what makes writing one feel like it needs no
test** — and the answer looks like: it is expressed where prose is normally decorative, its failure
is an absence, and the author is the only person who ever held both repos at once.
