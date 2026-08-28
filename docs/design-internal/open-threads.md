# Open threads

> **Status:** `reference` · **As of:** 2026-08-27


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

> **2026-08-27 — reviewed against `2ad04a33`, NOT re-measured, and three rows added.**
> `make docs-drift` flagged this file at 27 source commits, which is what prompted the pass. Twelve
> commits had landed since its last edit (`0c8c1d44`, 2026-08-23) and **not one of them had a row
> here** — criterion A being met, the true availability number, the 20-corpus census re-take, the
> leaf-spelling fix and two more rate attempts.
>
> **What was checked:** every still-open row (32, 36, 37, 38, 45, 48, 52, 53, 55, 56) against those
> twelve commits, for anything closed or overtaken. **None was.** That window is the survey and
> refutation line of work; it does not touch the purity cluster, which is why the table below moves
> only at its end.
>
> **What was added:** rows **64**, **65** and **66** — a decision left unasked, a piece of work left
> undone, and something noticed and deliberately not explained. None is a measurement.
>
> ⚠ **Row 64 was ASKED, ANSWERED and DELETED the same day.** The answer is **no** — criterion A's
> two halves do not have to be met on one subject — and it is written into
> `toolchain-exit-criteria.md` **§6.3**, per this file's rule that a closed row's answer moves to
> where it belongs. **The row lasting one afternoon is the whole of its value**: it existed because
> row 8 reads CLOSED and nothing anywhere tracked a decision that was pending, and the number is
> retired rather than reused, so the count and the highest number diverge by one more.
>
> **What was corrected:** the *wrong instruments* observation, which a seventh joined on 2026-08-23,
> and this file's own purity-line heading, which had been annexing rows that are not purity work.
>
> **No integer in any existing row was touched**, per the standing rule below that the rows are
> as-filed. Same meaning as every note above: the SHA says *this file was reviewed against that
> tree*, not *these numbers were re-measured there*.

<!-- doc-provenance date=2026-08-27 subject=SwiftInferProperties@8a49a65c observer=SwiftInferProperties@8a49a65c -->

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

> **2026-08-27.** The two items carried forward below are from 2026-08-03, are still true, and are
> **not what is live.** What is live is **row 65** — the refutation rate, which is still not a rate
> and has run out of local subjects to try. **Row 66 is residue, not a task.** Row **64** was filed
> and answered the same day (*no*, the composite is not required —
> `toolchain-exit-criteria.md` §6.3) and is deleted. Of the rest of the table, the two still
> genuinely open rather than declined-with-reasons are the purity cluster's consumer question
> (**55**, **56**) and row **38**'s call-graph decision, both unchanged since 2026-08-19.
>
> **So: criterion A is settled, and row 65 is the only piece of live WORK on this table.**
>
> ⚠ **UPDATED 2026-08-28.** Row 65 was screened, not closed: the pool exhaustion is now measured,
> a **third real defect** landed (`OpenAPI.XML`, tally 30/3), and the screen found two blind spots
> in itself. **Row 67 was filed on the way, and its one-line fix was then REFUTED** — extending the
> gate as filed would falsely decline **27 of 136** carriers (20%) to correct 6, because the shape
> merges same-file extensions only. Row 67 now carries the shape of the real fix. `swift-docc` is the richest unrun candidate.

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
| 8 | ~~**Exit criteria for "the toolchain is in shape"** are unwritten~~  ✅ **RATIFIED 2026-08-21 — A is the bar, B–E do not gate** | `docs/design-internal/toolchain-exit-criteria.md`. **They were not unwritten — they were written 2026-08-03 inside the *Road tests were misfiled* decision note and never looked at again.** That note named the trap and then fell into it: *"not ready to measure yet" is unfalsifiable — the confident zero of project planning*, plus the instruction **write them while inclined to be strict**. Seventeen days of silence is the prediction coming true, not an accident — row 46's *"do not carry this zero"* shape a second time. **Scored: (1) composer reach past 38% is ILL-POSED** — the figure is Arm 3, labelled *"diagnostic only … never a headline"*; **(2) the 5 dead templates is PARTLY met** — 5 → 4 and reframed as *unwitnessed on eight corpora*, while the manifest now resolves **seventeen**; **(3) instrument-error closed is UNFALSIFIABLE** — a claim of absence, satisfiable by not looking; **(4) `--sources` is NOT MET BY DESIGN** and should be restated as an outcome. **The finding: all four are CAPABILITY bars, none is an OUTCOME bar** — which is why five consecutive *no movement* results cannot be read either way. A–E proposed for ratification; **A is the only one that would say the toolchain is worth using.** **CLOSED 2026-08-21 by the maintainer's ratification**: **A alone is the bar** — *on a subject the toolchain has never met, ≥1 emitted law kills a mutant the subject's own tests miss* — and **B–E are supporting measurements that do NOT gate**. The reasoning is the cycle's own evidence: **A is the only OUTCOME bar**, and every capability bar can pass while the tool emits code that does not compile. Nine reach measurements were taken this cycle and none could have found the 89%; **one outcome attempt did, on its first subject**. **The item closes as a decision and opens as work**: A is NOT ANSWERED. Answering it needs a fresh unmet subject (`swift-http-types` is spent, `swift-algorithms` and GRDB were disqualified — **check the manifest, it recorded both**), a defect chosen to VIOLATE the law rather than for realism, and a re-run now that the three emitter defects are fixed **AMENDED 2026-08-22 — A SPLIT INTO A-reach AND A-quality by the maintainer.** The split is ratified; the thresholds are a proposal. **A-reach** — *≥1 emitted law runs to a PASSING verdict under a stressed trial budget* — is **MET for the first time** on `swift-system` (`isSeparator`, `isPrenormalSeparator`, holding at 5,000 trials). **A-quality** — *≥1 of those kills a mutant the subject's own tests miss* — is **ANSWERABLE at last and not yet answered**. **The reason for splitting is this row's own finding arriving one level up**: three subjects were attempted and A was evaluable on NONE, so every *A fails* was a sentence about the pipeline wearing a law-quality label — **A had quietly become a capability bar too**, which is exactly what this row convicted candidates 1–4 of. **A-reach's threshold is a PASSING law, not an executing one, and it is derived rather than chosen**: a trapped law yields no verdict and a refuted one is a false law on all evidence here (**17 of 17** hand-checked), so a passing law is the only kind a mutant can be aimed at. **The budget clause is load-bearing** — `removingLastComponent()` passed at 100 trials and FAILED at 2,000, so a pass without its budget is not a pass. **And the split immediately exposes a confound it did not create**: both surviving laws are totality predicates, so A-quality must not be expected to pass merely because A-reach did — a failure there would indict the CATALOGUE, not the pipeline. **Selection rule learned the expensive way (§6.1): unmet is necessary and not sufficient — select for SHORT-CHAIN too.** A-reach's length is a property of the subject, and swift-system was near worst-case (relocated target, C interop, invariants inside `#if DEBUG`); the cheap pre-check is rows-reaching-the-build-stage, whose first honest reading there was **0 of 41** **A-quality ANSWERED 2026-08-22 — NO at the shipped budget, YES at N ≥ 500.** `swift-system`, `isSeparator(_:)` totality vs a NUL-guard mutant: their **78 tests miss it**, the law misses it at N=100 and kills it at N=500. **The control is load-bearing and A-quality must not be reported without one** — a common-input mutant is killed at trial 9 AND caught by their own tests, which proves the law is under-budgeted rather than blind and shows its entire unique value sits on the rare input their suite cannot reach. **Second independent arrival at N=100 as the binding constraint**, the first being `removingLastComponent()` passing at 100 and failing at 2,000 — both failure modes a budget has, one subject, one day, same N. No new default proposed; the cost is unmeasured |
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
| 43 | ~~**The one-hop refuting join is measured-BUILD — and the LINTER built it while this side did not**~~  ✅ **CLOSED 2026-08-18** | **MEASURED 2026-08-17, and the first row in this cluster whose answer is *build it*.** `docs/measurements/purity-refuting-fixpoint-census.md`; harness `PurityFixpointCensusMeasuredTests`, `make batch2`. This is row 30's package-internal half asked in the **refuting** direction, and the direction is the whole finding: **18 rows retracted at one hop** over the 2,396 `.pure`, **29 at fixpoint** (6 hops, per-hop 18 · 6 · 2 · 1 · 1 · 1), **1.2%** of the population. The loop multiplier is **1.6×** against the promoting direction's 2.1×, so **one hop is 62% of the effect and the loop is phase 2, not the headline.** **Why this builds where row 31 declined**: a retraction lands on `.pure` → `isInferredPure`, which IS consumed; a promotion lands on `.pureButPartial`, which nothing reads. Same seam, opposite direction, opposite verdict — and it is the answer to *the purity vocabulary is consumed in neither direction*, which is that one direction already had a reader and nobody had asked in it. **A hand-check killed the first answer.** The harness first reported 75 at fixpoint with 57 from the cascade; **46 of the 75 were `classify`-style name-collision artifacts, 61% false.** Both readings are kept in the doc rather than the wrong one being replaced. The one-hop 18 never moved — the seed always obeyed the settledness rule — which is why 18 has two independent confirmations and 11 needed a hand-check. **Name collision is now the dominant defect at this seam in three measurements**, and it is why row 48's trip list is keyed by file *and* name. **SHIPPED UPSTREAM, NOT HERE — SwiftProjectLint `7704178` + `aba87fc`, 2026-08-17.** `PackagePurityJoin` resolves the join in the pre-scan, and `PureFunctionCandidateVisitor` gates on it, so **`DrainedProcess.standardOutputViaEnv` is no longer offered as a pure-function seed** — it was in that seed, and this repo consumes that seed, so a wrong seed was becoming a law nobody can hold. **That is item 28's asymmetry paying out exactly as priced**: the linter has no §13 ceiling, so it can afford the join `EffectResolver` cannot. **The linter's witness rule is deliberately NARROWER than the census's** — only evidence propagates, established from public API alone, because `PurityVerdict` carries no witness and SEI's reason is `private`; that is **row 31's complaint arriving as a constraint rather than a wish**. **§7 closes row 30's stdlib half from the other side**: Swift ships `@_effects`, readable from the SDK's 226 `.swiftinterface` files without building the stdlib — and its entire `readnone`/`readonly` surface is **20 underscored names, 0 of them called here**. The axiom list cannot be borrowed; it has to be asserted, exactly as row 30 said. **BUILT HERE 2026-08-18 — `PackagePurityJoin`, applied in `scanCorpus(directory:)` and deliberately NOT in `scanCorpus(source:file:)`**, because a single file is not a package and the unanimity rule would then be checked against a fraction of a name's declarations. **It retracts 16, not 18, and the gap is the finding.** The shipped rule is stricter than the census's: a census reads SEI's causes through a test-only replica, shipped code cannot, so the witness is established from public API alone — `propagatedTry` requires a `throws` clause by definition and `noBody` is structurally unreachable, therefore a `.refuted` **non-throwing** declaration cannot be ignorance-only. A throwing callee carrying a marker is a witness the rule cannot see, so it **under-retracts by two**, which is the safe direction and is now measured rather than assumed. **A/B against the merged per-file scan** — which cannot run the join and is therefore the honest baseline: `.pure` 2,583 → 2,567 here, 344 → 332 on OrderedCollections, 323 → 320 on SwiftPropertyLaws. `PackagePurityJoinMeasuredTests` pins `standardOutputViaEnv` as no longer `.pure`. **§13 green** — discover 0.754s against 2s, pipeline 3.541s against 6s — so the second body walk is affordable. **It moved row 49's population, exactly as predicted before building**: +5 suggestions and +6 refuted subjects under laws, and it broke that census's witness split for one run, since a joined retraction leaves no *local* cause and six rows were bucketed as ignorance — the inverse of the truth. Fixed with a `joined` category. **The loop remains unbuilt**, per the census's own verdict: one hop is 62% of the effect. |
| 44 | ~~**The purity oracle has never been scored against a real purity bug**~~ | **MEASURED 2026-08-17 — 0 HITS OF 3, 0 false alarms, and the GATE IS NOT MET.** `docs/measurements/purity-backtest.md`; harness `PurityBacktestMeasuredTests`; phase 0.6 of `docs/plans/declaration-claims-plan.md`, and the cheapest thing in that document. **The only number in this cluster an outside reader can check** — the subject is a public fix commit predating these tools, so the oracle cannot have been contaminated by it, which is what every other census here has to argue for itself. It sees neither bug class that history actually produced: **hash-order nondeterminism** (a `Set` rendered into a returned `String` — the class this repo already paid for in `orderedSources`) and **an instance `self` write on a `class`** (`ReducerPurityAnalyzer` covers `Self.`, not `self.`). **0 false alarms is not the consolation it reads as** — an oracle that flags nothing scores it too, which is why the pair of numbers is quoted and never the second alone. The two blind spots were **filed and priced rather than guessed at**, which is row 45. |
| 45 | **Blind spot 2 has a live instance — a smell, not a bug, and the oracle is still wrong** | **MEASURED 2026-08-17.** `docs/measurements/blindspot-base-rates.md`; harness `BlindSpotBaseRateCensusMeasuredTests`. Row 44's two gaps, priced against the 2,396 `.pure`. **Bucket 1 — instance `self` write on a `class` — is ZERO, and the reconciliation is the publishable part.** `grep` finds **1,226** `self.x =` lines in `Sources/`, so a detector reporting zero *anywhere* would be broken; of the first 400, **380 are inside an `init`**, and `InitializerDeclSyntax` is not a `FunctionDeclSyntax` — out of scope **by construction**, not by a filter that could drift. The rest are setters and closures, the latter already refuted by `refuteIfCaptured`. **The two zeros had to be separated by hand precisely because row 46's first detector published one that was blind.** **Bucket 2 — hash-order — is TWO, hand-checked, and one is live**: `PartitionAggregator.finalizeTwoClass` returns `winnerByPredicate.values.map(…)` — hash-seed order — and the oracle calls it `.pure`. **Measured NOT to escape** (`32b62f0`): `finalize()` sorts, and the comparator is total because `NClassPartitionKey` is `(predicateName, markerSetName)`. So the *program* is correct and the *verdict* is wrong, and only the second of those is this toolchain's business. **Bucket 2 is decidable from a parse only as a lower bound**, which is why it stays a row rather than closing. |
| 46 | ~~**A module-state mutation is judged pure, and this corpus has no exhibits**~~  ✅ **RE-TAKEN ACROSS 17 CORPORA 2026-08-19 — see row 63**  ⚠️ found by row 47's probe, not filed ahead of it | **MEASURED 2026-08-17 — the base rate is ZERO, and it is zero BECAUSE THE CORPUS DECLARES NO FILE-SCOPE `var` AT ALL**, corroborated by grep four ways. `docs/measurements/module-state-base-rate.md`; harness `ModuleStateCensusMeasuredTests`. **Row 40's shape exactly: a latent unsoundness — not a defect, and not a clean bill of health either.** The asymmetry is real; it has no victims here. **Do NOT carry this zero to another corpus** — it is a fact about the subject, not about the oracle, and a parser-heavy or CLI-heavy package would not inherit it. **And the first run reported the same 0 with a BLIND detector**, which is the reason this row is worth keeping past its own answer: `Parser.parse` yields `SequenceExprSyntax` for a top-level assignment, not `InfixOperatorExprSyntax`, so the instrument matched nothing and its zero was byte-identical to the real one. **Two zeros, one measured and one broken** — this repo's *confident zero* arriving in the census whose subject is a zero. **SUPERSEDED IN ITS REASONING, NOT ITS VERDICT:** the arm below measured the base rate at **5, not 0**, and refuted this row's prediction about which codebases exhibit the shape. |
| 47 | ~~**`consuming` / `borrowing` might carry purity evidence**~~ | **MEASURED 2026-08-17 and DECLINED twice over — the PREMISE IS FALSE *and* the population is ZERO.** `docs/measurements/ownership-premise-declined.md`; harness `OwnershipPremiseCensusMeasuredTests`; phase 0.7 of `docs/plans/declaration-claims-plan.md`. **No clause in `verdict(for:)` examines a parameter at all**, so the mechanism does not exist; and this corpus declares **0 `consuming` and 0 `borrowing`** against 52 `inout`, so there would be nothing to run it on. Closed as *measured-premise-false*, the way row 33 was. **Second Family C row declined for a premise that reads plausibly and measures false**, which makes it a pattern rather than an incident: **probe the premise before scoping the build.** It cost an afternoon against a phase, twice. **The probe's real find is row 46**: a function mutating a file-scope `var` is `.pure` while `static` mutation is refuted, and a closure doing the same write IS refuted — an asymmetry inside one type. **Fourth census in a row whose finding is not the thing it went looking for**, after rows 40, 41 and 42. |
| 48 | **The soundness arm can reach its own answer key, so phase 0.5 is not blocked on reach** | **MEASURED 2026-08-17 — 14 of the 17 frozen rows are callable, 9 of them with nothing to construct at all.** `docs/measurements/soundness-arm-reach.md`; harness `SoundnessArmReachCensusMeasuredTests`; phase 0.5 step 1 of `docs/plans/declaration-claims-plan.md`. The trip list is nearly all `static`, which **dodges the receiver problem that caps the verify arm at 139 of 281** — a purity probe needs a *call*, not a domain, so one degenerate argument suffices where a law needs a generator. §6.4 forbade inheriting the verify arm's reach and that estimate had never been taken; **a prediction the arm cannot execute is not a prediction.** Out: 2 `private`, 1 awkward type. Keyed by **file and name**, because `resolve` and `load` each match several declarations here — the collision hazard row 43's hand-check makes the standing one at this seam. **Reach is a precondition, not a result** — it says nothing about whether a probe would be *informative*, and the 9-with-nothing-to-construct are where an uninformative probe is cheapest to discover. **Build the 9 first.** |
| 49 | ~~**Would refactoring toward purity put more code within a law's reach?**~~ | **MEASURED 2026-08-18 — NO, at a ceiling, on three corpora; and the same fact read from the other side is a SOUNDNESS finding.** `docs/measurements/purity-refactoring-reach.md`; harness `PurityRefactoringReachMeasuredTests`, `make batch2`. **Arm 1**: force every `.refuted` / `.pureButPartial` verdict to `.pure` and re-run discovery — **710 → 710, 160 → 160, 51 → 51. Zero everywhere**, with an instrument deliberately more generous than any real refactor, since a real one changes the body and this changes only the verdict. **The zero is structural, not incidental**: `isInferredPure` has ONE consumer in shipped code (`EffectAnnotationAdvice+Build`, the advisory), `purityVerdict` has NONE, and **`UnverifiableCause` has eight cases of which purity is not one** — so no law is declined for an impure subject either. There is no wire for the refactor to travel down. **The control is item 34's `isThrows` mask on item 34's corpora, and it reproduces its +2 exactly** — which is what makes the zero readable rather than a blind instrument's, the failure `module-state-base-rate.md` published once. **Arm 2, the question checking arm 1 exposed**: because nothing gates on purity, **22 suggestions of 921 rest on a subject refuted with a WITNESS** — and the raw figure is 50, so **item 32's arithmetic lands a fourth time**: 23 of the 53 refuted subjects are `propagatedTry` only, ten of them `encode(to:)`, which throws because `Encoder` throws and is not impure. **The 22 are three findings, not one, split by refuter.** Self's 8 are all `marker` and all genuinely impure — seven filesystem reads offered under **`predicate`**, so *the law's truth depends on what is on disk and nothing in the output says so*. OrderedCollections' 11 are all `nonTotal` — a totality question, which is what `.pureButPartial` exists for and does not reach, since these are `.refuted` outright. SwiftPropertyLaws' 3 are async/marker. **Verdict: the purity signal's use is a VETO, not an annotation, and it must be scoped to witness-bearing refutations** — vetoing on `.refuted` outright would remove the ten `encode(to:)` rows under `codable-round-trip`, the one template measured at 100% yield. **Population measured, false-positive rate NOT**, which is the next thing anyone building the veto has to take. Denominators reconcile with row 29's census: 2,920 = 2,740 + 180 computed properties, and 2,576 `.pure` = 2,396 + 180 |
| 50 | ~~**`isReadOnlyGetter` accepts a `_modify` coroutine, so a MUTABLE property is offered as a law subject**~~  ✅ **CLOSED 2026-08-18, both halves** | **Measured 2026-08-18, hand-checked, NOT fixed and NOT A/B'd.** `docs/measurements/purity-refactoring-reach.md` §3. `OrderedSet.unordered` declares `get` and `_modify`; the guard accepts any accessor list containing `get` and not containing the literal **`"set"`**, and a `_modify` coroutine **is** a mutating accessor — `set.unordered.insert(x)` writes through it. So the property is summarised as a read-only computed property and carries **8 suggestions** (`inverse-pair` ×4, `round-trip` ×4). **A second defect masks the first, which is why it survived**: `SoundPurity.verdict(forGetter:)` is handed the whole `AccessorBlockSyntax`, so it reads the `_modify` body, sees `self = OrderedSet()`, and returns `.refuted` — the property is reported impure *correctly but for a reason that has nothing to do with its getter*, which is pure. Delete the `_modify` and the same misclassification returns a clean `.pure`. **Item 40's shape exactly — an oracle pointed at the wrong node** — and the second time a computed-property path has produced a verdict nobody computed for the thing being asked about. **CLOSED 2026-08-18 — `docs/measurements/modify-accessor-misclassification.md`; harness `ModifyAccessorCensusMeasuredTests` plus `ReadOnlyAccessorTests` in the fast path.** **Half one FIXED by an allowlist**, `["get", "_read", "unsafeAddress"]`, so an accessor Swift adds later makes a property writable by default; a denylist admits each new kind silently, which is the wrong direction for *when in doubt, fewer suggestions*. A/B on OrderedCollections with one instrument: 435 → **429** summaries, 103 → **97** computed properties, **6 → 0** admitted despite `_modify`, **8 → 0** suggestions resting on one. **Half two CLOSED as *measured-no-population*, not fixed**: across all three corpora and **325 admitted computed properties, ZERO declare more than one accessor**, so the whole-block read has nothing else to misread. It is still there — `theOracleSeesOneAccessor` reopens the day a `get` + `_read` pair is admitted, which is legal. **The urgency was the cancellation, and it is the transferable part**: the 8 rows were already vetoed by row 54, *because* `verdict(forGetter:)` read the `_modify` body — so narrowing the oracle first would have made `unordered` read `.pure`, stopped the veto, and re-admitted eight laws over a mutable property. **Fixing either half alone made things worse; the interlock only existed because the veto had shipped the day before.** **The census's own first detector over-matched** — a 20-line text window reported 8, two of them genuinely read-only `keys` declarations whose neighbour carried the `_modify`; re-parsing gives 6, and both arms were re-taken. The blind-detector failure inverted, and the same rule catches both: prefer a parse to a window. Original framing follows. **Both halves are separable and neither is scoped**: the guard is a one-line vocabulary question (`_modify`, `set`, `willSet`/`didSet`, `unsafeAddress`), the oracle half is the accessor-scoping question item 40 explicitly left open when it noted `verdict(forGetter:)` can never answer `.pureButPartial` because `isReadOnlyGetter` filters throwing accessors upstream. **Fifth census in a row whose finding is not the thing it went looking for**, after rows 40, 41, 42 and 47 |
| 51 | ~~**`withInferredEffect` dropped three fields, and one of them is `@EffectUnknown`**~~  ⚠️ found while building row 43, not filed ahead of it | **CLOSED 2026-08-18, same day it was found.** `FunctionSummary.init` has 23 parameters and **14 are defaulted**, so a copy-with builder that omits one compiles, runs, and silently substitutes the default. Three were omitted: **`qualifiedContainingTypeName`** (which falls back to `containingTypeName`, so a qualified `Outer.Inner` was *downgraded* to `Inner` rather than merely lost), **`declaresUnknownEffect`** (reset to `false`) and **`bodyFingerprint`** (reset to `nil`). **`FunctionSummary+Builders.swift`'s own header names this exact failure** — *"a builder that forgets a field compiles silently"* — and it had happened in the file that names it. **`declaresUnknownEffect` is the sharpest**: row 20's entire chain exists to carry `@EffectUnknown` from a sibling repo to a template, and this builder reset it on precisely the summaries `EffectResolver` had just resolved an effect for — two live call sites, `EffectResolver.swift:64` and `SeedEffectResolver.swift:103`. **A/B: 5,511 fast tests unchanged, and the zero is EXPLAINED rather than lucky** — `Sources/` carries zero effect annotations, which `declaration-claims-plan.md` §5.1 states and grep confirms (every hit is prose or a string literal). **Row 40's shape a third time: a latent unsoundness, not a defect, and not a clean bill of health either.** **The guard reflects rather than enumerates.** `BuilderFieldParityTests` walks `Mirror(reflecting:)` and compares every stored property, because a hand-written field list is *the same artefact as the builder with the same failure mode* — the next field is forgotten in both places and the test then certifies the bug. Watched failing against the unfixed builder on all three fields, including the `Outer.Inner → Inner` downgrade. **Found only because row 43 added a field**, which is the general lesson: a silent drop surfaces when someone touches the thing that drops, never on its own |
| 52 | **A witness-scoped purity veto is measured AFFORDABLE — 0 refutations, 2 passes, 4 unpriced** | **MEASURED 2026-08-18.** `docs/measurements/purity-veto-precision.md`; harness `PurityVetoPrecisionMeasuredTests`, `make batch2`. Row 49 measured the veto's *population* and said outright its precision was not measured; this is that measurement, scored the way this repo scores a candidate veto — **against the laws that HELD**. **"False positive" had to be DEFINED before it could be counted**, and that definition is most of the finding: `measured-bothPass` means *no counterexample in the generated domain*, not *the property holds*, and for an impure subject that is exactly the ambiguous case — a `predicate` law over `isDirectory(_:)` passes when the path happens to be there. Counting every pass as a good law would assume the answer. So a removal is priced four ways and only `refuted` is an unambiguous loss. **The result**: veto on `.refuted` outright removes **20 — 0 refuted, 10 passed, 3 inert, 7 unrecorded**; scoped to witness-bearing removes **8 — 0 refuted, 2 passed, 2 inert, 4 unrecorded**. **The headline is the ZERO**: no scope removes a law that found a counterexample. **The scoping recommendation row 49 made as an argument is now a number and it holds** — scoping spares 8 passing laws, *all* of them `encode(to:)` under `codable-round-trip`, the one template at 100% yield, refuted only by `propagatedTry`, which is the analyzer failing to see past a `try`. **Item 32's arithmetic a fifth time**: 20 raw against 8 actionable, so a veto sized from the raw population over-reports its reach by 2.5×. **The 2 passes the scoped veto still removes are `isDirectory(_:)` and `isStale(…)`, both filesystem reads — the cases the veto EXISTS for, not cases it gets wrong.** **Joined exactly, on `SuggestionIdentity.display` = the survey's `identityHash`**, never on a name — and the join survived a signature change (`isStale` gained a `diagnostic:` parameter since 2026-08-05 and still matched), which is what a stable cross-run identity is for. **Does NOT establish**: anything about the 7 unrecorded (4 of them in the scoped set), so the honest ceiling is *2 passes plus up to 4 unknowns*; anything about the other two corpora, which have no recorded survey; and it does not decide whether to ship — it removes the objection that the cost is unknown |
| 53 | **A control that fired was CORRECTED rather than relaxed, and the difference is worth keeping**  ⚠️ method, not a task | Row 52's coverage control first asserted that half of all **712** suggestions carry a row in the 2026-08-05 survey. **274 do, so it failed** — and the tempting move, lowering the threshold until it passed, would have been fitting the instrument to its result. **The gap was not drift.** The survey's own README says *"281 records, one per **index** entry"*: a filtered population that was never a map of every suggestion. The assertion compared a **discover** population against an **index** one and would have failed at any corpus size and any staleness — it was measuring the wrong two things, not measuring a real problem too strictly. **The threat a coverage control guards is single**: a join that resolves nothing reports a veto that costs nothing, which is the most flattering possible artefact of a broken instrument. The quantity that threat turns on is what fraction of the **removals** are priced — **13 of 20** — and that is what the control now asserts. **The transferable rule**: a threshold moved because the number came out wrong is fitting; a predicate replaced because it compared the wrong populations is a correction. Say which one happened, in the doc, every time — `docs/measurements/purity-veto-precision.md` does |
| 54 | ~~**Nothing withholds a law whose subject is known impure**~~  ✅ **SHIPPED 2026-08-18** | **`TemplateRegistry.applyImpureSubjectVeto`, witness-scoped — the scope row 52 priced, not a wider one.** A suggestion is a law to be **executed** as a property test, in-process, over random inputs, which is why SEI's own doc calls `.pure` the most dangerous place to land wrongly; `predicate :: directoryExists(_:)` is a law whose truth depends on what is on disk and nothing in the output said so. Suppresses **8** on this repo, and `theShippedVetoMatchesTheScope` pins that population to row 52's priced one so the doc and the code cannot drift into describing different vetoes. **A veto rather than a demotion** — unlike `KitEvidence`'s −45 the objection is not that the law is weakly evidenced but that *running it runs an impurity* — and **it still renders its reason**, since `Signal.formattedLine` writes `"… (veto)"` into `whyMightBeWrong`; a withheld law that cannot say why is item 20's failure in a new place. **The scope predicate is `PackagePurityJoin.refutingNames` REUSED, not restated**, so the veto's rule and row 43's join are one rule; a second copy is the drift relocating `PurityInferrer` into SEI ended. **The part worth reading is the gate, and it is row 40's finding arriving at a CONSUMER**: `.refuted` is `FunctionSummary.init`'s **default**, so on a summary nothing analysed it means *not computed*. The first shipped rule read that default as evidence and **suppressed six unrelated suites** whose fixtures build summaries by hand — monotonicity cross-validation, the counter-signal seam, `value-round-trip` end-to-end, associativity aggregation, `normalize(_:)` at Likely, the `encode/decode` pair. The gate is `bodyFingerprint != nil`, whose own doc already stated the semantics (*"`nil` for … one of the many hand-built summaries in tests"*), and it is a **no-op on any scanned corpus**, so row 52's numbers are unchanged. **A census over a real scan cannot see a defaulted verdict — the fast suite caught what the measurement structurally could not.** Adding the `Signal.Kind` case took `Signal+Kind.swift` past its 400-line cap, so `subjectNotVisibleToTests`' rationale moved to `docs/design/signal-kind-rationales.md`: the documented procedure, relocate and never trim |
| 55 | **Phase 0.5's soundness arm is BUILT, and its precondition is discharged — 4 of 9 trip, 0 of 3 controls** | **MEASURED 2026-08-18.** `docs/measurements/soundness-arm-probe.md`; harness `SoundnessArmProbeMeasuredTests`, probe `Sources/soundness-probe`, `make batch2`. §6.3's gate is *"if the sandbox cannot distinguish those nine from a control set of genuinely pure functions, it does not work and nothing else matters"* — **it distinguishes them.** Trips: `DrainedProcess.standardOutputViaEnv` (subprocess denied), `SpeculativeRefactorRunner.scanRestricted` (2 files → 0), `MetricsInteraction.loadDecisions` (1 warning → 0), and **`KitEvidenceStore.load`, which is the sharpest row: `outcomes=0` open, `outcomes=590` DENIED.** Denying reads of the fixture made it **walk up out of the directory it was given** and read this repo's own `.swiftinfer/kit-evidence.json` — so its result depends on ambient filesystem state *outside its argument*, and a law over it would pass or fail on where the test process was launched from. **The detector is differential because it must be**: these subjects swallow failure, so a denial is invisible in a return value, and `sandbox-detector-mechanism.md` had already measured that the errno often does not name the policy and no log channel carries it. **Reads are denied on the FIXTURE SUBPATH ONLY** — a global read denial stops `dyld` before the probe's first line and measures the runtime. **The five that did not trip are NOT thereby pure, and that is the finding worth carrying**: a degenerate argument reaches a function without exercising it — `macOSPlatformLine(userPackage: nil)` short-circuits, `resolve(summaries: [])` has no work — which is row 48's *reach is a precondition, not a result* arriving as a measurement rather than a caveat. **The first run made it vivid**: against an *empty* temp dir, **eight of nine** returned identical results and only the subprocess spawn tripped; a tiny fixture moved the count 1 → 4 without changing a line of subject code. Pointing the probe at the repo root instead was tried and **hung**, because the scanners walk `.build`. **Next, in order**: richer arguments for the five (two lines each, both `macOSPlatformLine` and `resolve` predicted to trip), then the `DiagnosticOutput` stub for 2 more, then the three cheap constructions to reach 14 of 17. **Do NOT widen to the full 2,396 `.pure` population** — the trip list is the only part with a hand-verified key, and a sandbox scored against it without one produces a number nobody can check |
| 56 | **The soundness arm's findings have NO consumer — and no victims** | **MEASURED 2026-08-18, same day the arm produced its first output.** `docs/measurements/soundness-arm-probe.md`; harness `SoundnessArmProbeMeasuredTests`. The *Decisions* stub generalises this cluster's recurring lesson — *"does this have a consumer?" must be asked of the OUTPUT VALUE, not only of the report that would carry it* — so it was asked immediately. **0 suggestions rest on any of the four confirmed-impure subjects.** **The veto structurally cannot catch them**: `applyImpureSubjectVeto` fires on *witness-refuted* subjects and these four are `.pure`, so nothing refutes them and the veto never sees them — if a law did rest on one, it would ship. **None does**, because the four are not template-shaped (`load(startingFrom:explicitPath:diagnostic:)` and `scanRestricted(under:diagnostic:)` match no template's signature). So the arm's first findings are real and currently **inert**: a false `.pure` with no downstream victim. **The zero has a non-vacuity control and needed one** — the same join pointed at `directoryExists` and `fileExists`, which row 52 measures as carrying laws, finds them; a dictionary built on the wrong key would have reported *"no law rests on the arm's findings"* just as convincingly as the truth. **What it costs Family A**: §5.1 gates `@lint.purity refuted(_)` on *"the empirical arm discovered N false `.pure`"*, so **N = 4 and the gate is discharged** — and the same measurement says those 4 annotations would move **0** suggestions. **Fifth time the reach half came back empty**, after rows 31, 32, 33 and 34. The pattern is not that the findings are wrong: a purity fact has no path to a law unless something gates on it, and the one thing that does gates on the *refuted* side — which is the side the arm is not about |
| 57 | ~~**The whole-corpus survey is re-taken, and the executing share FELL 49% → 33%**~~ **— CORRECTED: it ROSE, 50% → 65%** | **MEASURED 2026-08-19 at `15bb86c`.** `fixtures/whole-corpus-survey/2026-08-19-whole-corpus.jsonl`, 538 records, release binary, rebuilt index over all seven library targets. **CORRECTED 2026-08-19, same day, and the error is the finding.** The figure that means something is **178 of the 272 RUNNABLE-tier entries — 65%, UP from 50%** (139 of 279). This row first said the share *fell* 49% → 33%. **266 of the 538 rows are `Advisory`, which cannot execute a law by construction** — `Tier.advisory`'s own doc calls it an *informational tier for stand-alone advisory findings that don't carry a runnable property*, and all 266 decline `architectural-coverage-pending`. The 2026-08-05 index held **none** of them; this one holds 266, so dividing by the total manufactured a decline out of an increase. **The CLAUDE.md row carrying this figure says *read the tier cut, not the total* — and the total is what I quoted.** A rule stated in the index did not survive contact with the person writing the next number into it, which is a sharper instance of the same failure `stale-summary-guard-declined.md` measured four detectors against. **`.advisory` is not new** — it landed 2026-05-05, three months before the earlier survey — so this is a change in what gets INDEXED, not a new tier. Raw counts follow: 163 held, 15 refuted, 16 errored, 344 declined of 538. **The counts are NOT comparable and the README now says so**: the 2026-08-05 run recorded its *verify* command but not how its index was built, so that population cannot be reconstructed — the **ratio** is what carries across, not the numerator. **The 76-min / 7.7-CPU-hour estimate is retired**: the re-take took **11 minutes** over nearly twice the population; do not budget from the old figure. **The tier cut is starker than before**: `Strong` 9/5 run/0 refute · `Likely` 28/25/**3** · `Possible` 235/148/12 · **`Advisory` 266 entries and ZERO run, all 266 declined** — half the corpus sits in a tier that never executes, which no earlier reading surfaced. **And the dominant blocker has CHANGED**: *no test can name the subject: it is `private`* is **191** rows with the enclosing-type variant another **13**, against **47** for *no generator for carrier* and **17** for *no composer for template*. **Visibility, at 204 rows, now dwarfs both carrier and template reach** — which is `subjectNotVisibleToTests`' own population, the `Signal.Kind` whose rationale was relocated to the overflow doc the day before. **`round-trip` is 72 entries and 0 ran**, almost entirely *cross-type round-trip pair* declines: a whole template producing nothing on this corpus. **Still open**: whether the 15 refutations follow the old tier rule (all real bugs `Likely`, all `Possible` refutations false laws) — 3 are `Likely` and 12 `Possible`, and none has been hand-checked |
| 58 | ~~**Are the survey's 15 refutations real bugs, and does the TIER predict it?**~~ | **MEASURED 2026-08-19 — 15 of 15 are FALSE LAWS, zero real bugs, and the tier does NOT predict which is worth reading.** `docs/measurements/refutation-hand-check.md`. Hand-checked, not harnessed: reading a law against its subject is the judgement a harness cannot make. **The index has carried a 2026-08-05 rule** — *"all 4 real bugs are `Likely`; all 5 `Possible` refutations are false laws"* — whose useful inference is *a `Likely` refutation is worth reading first*. **Measured false: 3 `Likely` refutations, 0 real bugs.** **What is NOT refuted is the original statement**: *real bugs ⊆ `Likely`* is **untested** today because there are no real bugs to place — most likely 2026-08-05's were fixed and this is the false-law tail — and **a rule with an empty antecedent is neither confirmed nor broken**, so reporting it as *the rule is wrong* would claim more than the evidence carries. Beside `fixtures/planted-defect-arm/`, which measured that the **template** does not predict either: **neither tier nor template predicts whether a refutation is worth reading.** **The 12 `Possible` are idempotence over a DERIVATION rather than a projection** — `defaultPath(for:)` ×5 appends its suffix twice, `SubjectFingerprint.of` and `regressionFileHash` digest a digest, `seedString` derives a seed from a seed, `versionString` yields `"1.0 (abc) (abc)"`, plus two emitters. A normaliser is idempotent; a hash, a path-builder and a formatter share its **type** and none is. **The 3 `Likely` are operands with distinct ROLES** — `pairShrinkPhase(carrier:oracle:)` and `tripleShrinkPhase` interpolate `carrier` into a *type* position and `oracle` into an *expression* position, so a swap would not even compile, and `ternarySweep(functionCall:carrier _:)` **does not use its second parameter at all**. **`(T, T) -> T` is a type, not a semantics.** ⚠ **A stronger claim made here on 2026-08-19 was corrected the same day**: this was written as `same-name-differential-pairing.md`'s finding *"reached from the other end … one cause"*, and it is not. That census is about a shared **function name** naming a role across types, and its FP is *pairing two functions*; this is about two **parameters of one function**, and its FP is a *commutativity law over non-interchangeable operands*. **Analogous, not identical** — the identity would have licensed re-opening a recorded decline on evidence that is not about it. **Every refutation failed at `trial=0`** — a law false *by construction* fails on the first trial, and that signal is already in the stream as `outcomeDetail`. **Not proposed as a filter**: 15 rows all on one side is not a base rate, it is a hypothesis for the next survey. **Does NOT establish that the tool finds no real bugs** — it found four by this route on 2026-08-05, and a codebase whose bugs were fixed two weeks ago is the expected place to find none |
| 59 | **The lift caveat is measured REACHABLE — 260 of 373, and the blocker moved without anyone aiming at it** | **MEASURED 2026-08-19.** `docs/measurements/lift-caller-reach.md`; harness `LiftCallerReachMeasuredTests`, `make batch2`. `roadtest-self-dogfood-2026-08-08.md` §2 settled the design eleven days ago — *"a caveat that names the nearest reachable caller, turning 'you cannot test this' into 'state it on `lookupSuggestion`'"*, and explicitly **not a gate, not a demotion, not a veto**, which is why `subjectNotVisibleToTests` is weight 0. **It sat because callers were unresolvable (row 38: no IndexStore).** **`calledFreeFunctionNames` changed that on 2026-08-18** — added for row 43's join, and inverting it gives a caller index; the blocker moved as a side effect of an unrelated build. **934 restricted functions · 842 (90%) have a same-file caller · 561 have a VISIBLE one · 534 of those exactly one · 92 none. The number that matters: 373 suggestions decline for visibility and 260 (70%) could name a visible caller.** **Same-file is SOUND, not heuristic**: `private` and `fileprivate` are file-scoped in Swift, so a caller *must* be in the same file — which kills the reverse-name-collision hazard that has been the dominant defect at this seam in four measurements. **The estimate that nearly parked this was wrong and is recorded**: the scoping worry was that private helpers are reached through a receiver, invisible to a free-shape collector, with a stated *park it if it is 20* threshold. It is 260, because an unqualified call to a member of the enclosing type **is** free shape and that is how private helpers are normally called. **"Nearest" barely needs defining** — 534 of 561 have exactly one visible caller, so the tie-break rule this was blocked on applies to 27 rows. **It moves ZERO rows** and that is by construction: a caveat is explainability, not a law, and all 373 stay declined — reading 260 as *260 new laws* is the misreading to avoid. **Auto-lifting is DECLINED**: §2's worked example shows the lifted law is a *different* law — `idempotence(normalize)` became metamorphic spelling-insensitivity of `lookupSuggestion`, catching a mutant the helper-level law is structurally blind to — so it is judgement, not a transform, and naming the caller is where the tool's contribution stops. ~~**Open**: the 842 → 561 gap is chains of private helpers~~ — **BUILT the same day: the walk adds 267 subjects at depths 2:198, 3:62, 4:7, taking reach from 561 to 828 of 934**, and the rendered rows on `SwiftInferCLI` from **102 to 120** with 29 indirect. Shallow chains are why a bounded walk suffices and row 38's call-graph cap does not bind. **The chain stays in one file as a CONSEQUENCE, not a restriction**: each link is a call to a `private` declaration and `private` is file-scoped, so the walk cannot leave the file until it reaches something visible — which is exactly where it stops. Three properties pinned, each for a different failure: the caveat **states the hop count** when it is not 1 (a reader told to state the law on something that does not call the subject directly would look for the call, fail, and distrust the advice), the walk stops at the **nearest** visible caller rather than the outermost, and a **cycle terminates** rather than hanging — mutual recursion between two private helpers is rare and not impossible, and hanging inside `discover` is worse than declining to answer. §13 green at 3.683s against 6s |
| 60 | ~~**A survey stream cannot be read without its index, and the index can be overwritten**~~  ✅ **CLOSED 2026-08-19** | **`SurveyRecord` now carries `tier`.** `fixtures/whole-corpus-survey/README.md` named this gap **in its own tooling row** — *"the stream carries no tier, so it must be joined in from the index the run was taken against"* — which is why `tier_split.py` needed a second input. **That join is what made row 57's ratio easy to get wrong**: computing the honest denominator required the index the run was taken against, and that index had already been **overwritten twice the same day** (281 / 538 / 712, three populations of one corpus). **A stream carrying its own tier cannot be paired with the wrong index**, which is the whole point. **Both consumers land in the same change, per the vocabulary gate**: `tier_split.py` takes the index as *optional* and prints `RUNNABLE tiers` with an explicit line saying the total counts rows that cannot run; `analyse.py` prints the runnable ratio beside the headline. Verified on a fresh stream with no index at all, where the gap is stark — **84.5% runnable against 54% total on the same data**. **Optional on purpose**: streams frozen before today carry no tier and a consumer must tell *absent* from *`Advisory`*, so both tools say so out loud rather than reporting the total as if it were the ratio — checked against the 2026-08-05 stream, which now prints a *no `tier` in this stream* line instead of a misleading number. **The decline path is asserted separately because that is where it matters most**: every `Advisory` row declines, so a record dropping the tier there would lose it on exactly the population the denominator turns on. **Two alternatives measured and DISCARDED.** Skipping `Advisory` rows in `verify` saves nothing — they decline *pre-build* as `not-a-candidate` — and dropping rows makes streams incomparable across versions. Inferring *never runnable* from `outcomeDetail` is **unsound**: `not-a-candidate` covers 266 `Advisory` **plus 7 `Possible`** in the 538 survey and 385 plus **58** in the 712 arm — close enough to look like a proxy, wrong often enough to mislead, which is the same shape as the original error |
| 61 | ~~**Do commutativity and associativity fire on operands that cannot be swapped?**~~ | **DECLINED — verdict stands, EVERY REASON RE-TAKEN 2026-08-19.** ⚠ **The first version used 3 corpora when the manifest lists 22 and 17 resolve locally, and its signal was broken.** `isRoleDistinct` tested only that the two labels *differ* — true of nearly every named pair — while the doc's own prose listed `lhs`/`rhs` as symmetric; across the manifest it fired on the stdlib's `*(a:b:)` and Foundation's `+(lhs:rhs:)`, **36 rows of false positive on genuinely commutative arithmetic**. So the reported *precision 5/5* was an artifact: this repo does not write `+(lhs:rhs:)`, so the only corpus it was scored against could not exhibit its failure mode. **Corrected signal (positional labels excluded) over `CorpusManifest.available`: 118 binary-operator suggestions across 17 corpora, 2 role-distinct**, both `join(word:bit:)` in the standard library — so the decline is stronger than it was, on a universe 17 wide rather than 3. **Coverage caveat**: the manifest's `swift-infer-core` entry scans `Sources/SwiftInferCore` only, so this repo's own 5 rows in `SwiftInferCLI` are outside that run. Original framing follows. **MEASURED 2026-08-19 and DECLINED — the signal separates PERFECTLY and the population is 5 rows on one corpus.** `docs/measurements/parameter-role-declined.md`; harness `ParameterRoleCensusMeasuredTests`, `make batch2`. **Why it looked worth building**: row 58 hand-checked all 15 refutations and found **3 of 3 `Likely`** were laws over operands with distinct roles. **3 of 3 reads like a pattern; those 3 are 3 of the 5 rows that exist.** **The signal** — a `(T, T) -> T` whose two parameters carry different external labels, neither `_` — reads labels, not bodies: `carrier:oracle:` and `functionCall:carrier:` qualify, `merge(_:)` and `merge(_:_:)` do not. **Where it fires it is exact**: on self, 5 role-distinct rows are **0 held · 3 refuted · 2 declined**, against 8 symmetric rows at **7 held · 0 refuted** — so it removes every refutation in the family and no law that held. **And that is not enough.** 22 binary-operator suggestions across three corpora, **5 role-distinct, all of them this repo's own stub emitters** (`scalarShrinkPhase`, `pairShrinkPhase`, `tripleShrinkPhase`, `ternarySweep`). **OrderedCollections is the control that closes it: 9 binary-operator suggestions, ZERO role-distinct** — a collections library's binary ops are genuine and positional, and the role-distinct shape is what a **code generator** produces. **The finding worth keeping**: the evidence that made this look like a class *was* the class. A ratio over a denominator you have not counted reads as a pattern at any size — the same shape as rows 31 and 33, a real mechanism correctly identified with nothing behind it. **NOT a reopen of row 22's same-name decline**, whose *"undeclared role interfaces"* is a different mechanism — a shared function *name* across types, FP = pairing two functions — which was briefly conflated with this on the same day and corrected. **Reopens on** a corpus with a materially larger role-distinct population; the harness prints the count per corpus, so pointing it at a new subject answers it in one run |
| 62 | ~~**Is cross-type round-trip pairing worth acting on?**~~ | **NO ACTION — verdict unchanged, CONTROL RE-TAKEN 2026-08-19 and now decisive.** The first version called the control *uninformative* because OrderedCollections yielded **1** round-trip suggestion; that was true of the three corpora it looked at, and those three are the trio whose narrowness refuted both reasons of row 61 an hour earlier. **Re-taken over `CorpusManifest.available`: 529 round-trip suggestions across 16 other corpora, 6 cross-type — 1.1% — against 220 of 230 (96%) on this repo's `Sources/`.** swiftlang-swift 206/**0**, swift-collections 107/**0**, swift-foundation 82/4, swift-package-manager 73/**0**, swift-syntax 47/**0**. **The obvious explanation is wrong, and checking it is what makes this a control**: a multi-module scan might pair a forward in one module with a reverse in another, but swift-collections is scanned at `Sources/` across `Collections`/`OrderedCollections`/`DequeModule` and shows **0 of 107** — same breadth, opposite result. So it is not scanning breadth but this repo's density of `emit`/`render`/`compose`/`parse` names across many types, which is what the pairing keys on. **The verdict now rests on evidence rather than on an empty control.** Original framing follows. **MEASURED 2026-08-19 — NO ACTION, and the control cannot discriminate.** `docs/measurements/cross-type-roundtrip-census.md`; harness `CrossTypePairCensusMeasuredTests`, `make batch2`. Chased because row 57's survey made it the **largest single-cause population**: `round-trip` proposes 72 index entries, 0 run, **62** declining *"Cross-type round-trip pair … cannot type-check across distinct containing types"*. **The numbers are real and the framing was wrong.** At API level over all `Sources/`: **230 round-trip suggestions, 220 cross-type (96%)**, spread over **127 distinct type pairs**, every suggestion carrying exactly 2 evidence rows, and the top pairs plainly unrelated — `AssociativityStubEmitter → KitEvidenceRecorder` 9×, `StrategistDispatchEmitter → LiftedTestEmitter` 9×. **But that is not what a user sees**: `discover --target SwiftInferCLI` shows **7 round-trip rows of 86**, because target scope and the tier cut both narrow it. **I had framed this as a user-facing flood; it is not, and the correction is the first useful thing the census produced.** **The control is UNINFORMATIVE and saying so is the point.** The same control closed row 61 — OrderedCollections had 9 binary-operator suggestions and zero role-distinct, a real discrimination. Here OrderedCollections produces **1** round-trip suggestion and SwiftPropertyLaws **0**, so *zero of one tells you nothing*: **a control with no population is not a control**, and reporting "0 cross-type elsewhere, 220 here" would imply a discrimination never made. **That the other corpora produce ~0 round-trip suggestions is itself worth noticing** — the template needs a forward/reverse *name* pair and library code apparently does not spell one. **Verdict: no action.** The rows are `Advisory`, so `StructuralBlocker` already knows they cannot run, and nothing here shows the pairing rule is *wrong* rather than merely unproductive on one corpus. **Reopens on** a corpus producing round-trip suggestions in quantity *and* pairing them across types; the harness prints both numbers per corpus. **Left unasked**: 38 of 86 default rows on one target are `Advisory` — 44%, mostly the visibility class the lift caveat now explains — and whether that share is right is a different question |
| 63 | ~~**Does the module-state hole have exhibits anywhere, or only here?**~~ | **MEASURED 2026-08-19 — the base rate is 5 of 20,526 functions across 17 corpora, and 16 of 17 measure ZERO.** `docs/measurements/module-state-base-rate.md` (cross-corpus arm); harness `ModuleStateCorpusCensusMeasuredTests`. Row 46 closed with a standing instruction — *do not carry this zero to another corpus* — and then nobody carried it anywhere for two days, **which is the same thing as carrying it**: the zero sat as the only measured answer, in a repo whose own index says a census's zero cannot be read without its corpus list. **All 5 hits are in `swiftlang-swift`** — `@c` / `@_silgen_name` / embedded runtime / exclusivity TLS, the one place mutable process-global state is the entire point. **All 5 hand-checked true**, but only 3 for the reason the detector gives: `swift_allocEmptyBox` and `swift_allocError` fire on the `&x` rule while the real mutation is one hop away. A conservative rule landing right is **not** a validated detector. **The denominator was 87% wrong and only the hand-check found it** — 118 of 135 "file-scope vars" are COMPUTED constants (`internal var CLOCK_REALTIME: clockid_t { … }`, 86 of them swift-foundation's). Findings unaffected; the ratio would have been three orders out. Real figure: 5 against **17 stored** globals. Fixing it needed care in the flattering direction — `accessorBlock == nil` files `var x = 0 { didSet { … } }` as a constant, and that case is now asserted rather than assumed. **Row 46's verdict SURVIVES and its reasoning does not.** It predicted a global cache or `nonisolated(unsafe)` singleton would exhibit the shape *immediately*; measured, 2 stored globals exist across the 16 non-stdlib corpora and none produced a false `.pure`. Mutable file-scope state is near-absent from Swift libraries generally — so the hole is **latent everywhere**, not latent-here-and-live-elsewhere. Still no refuter: 0.024% does not buy one. **The lesson is row 53's, one step further along**: a measurement that names its own weakness has not discharged it, and "do not carry this zero" written *inside* the doc nobody re-opens is a guard's worth of evidence spent on prose. |
| 65 | **The refutation rate is still not a rate, and the local subject pool is EXHAUSTED** | **MEASURED 2026-08-24 and 2026-08-25 — four unmet subjects across two attempts, still no denominator.** `docs/measurements/refutation-rate-second-subject.md` (`swift-aws-lambda-events`, `MacPaw/OpenAI`) and `docs/measurements/refutation-rate-third-fourth-subject.md` §5 (`jwt-kit`, `swift-openapi-runtime`); the tally itself lives in `docs/measurements/refutation-hand-check.md`. **29 hand-checked, 2 real** — but nine of the eleven `codable-round-trip` checks are **one mechanism from one generated codebase**, so deduplicated by mechanism it is nearer **2 real of 4 distinct mechanisms**, which that doc says outright is far too small to quote as a precision. Beside it: **`idempotence` 0 real of 18** across two corpora, and **`predicate` / totality 0 refutations of 102**. **What is undone is the SOURCING, not the method.** After excluding the manifest and every subject named anywhere in `docs/`, the best remaining unmet candidates carry 3–6 hand-written `Codable` ∩ `Equatable` types each — so a denominator worth the word means **cloning subjects deliberately rather than screening what is already on disk**, and every subject spent costs the *zero mentions across `docs/`* check one more future candidate. ⚠ **The cheapest thing that would move this is not another real defect.** §5 names two: a `codable-round-trip` refutation that is false **for a NEW reason** weakens the hypothesis more than another real one strengthens it, and **a real `idempotence` refutation** would end the comparison outright. 18 for 18 is a strong prior and not a proof. ⚠ **SCREENED 2026-08-28 — the exhaustion is now MEASURED, and a THIRD real defect landed on the way.** `docs/measurements/candidate-screening-pass.md`; instrument `scripts/screen_candidates.py`, validated on three published controls before use. **63 subjects screened**; of the 47 on disk, exactly **one** zero-mention candidate had any hand-written intersection — `indexstore-db`, 3 types behind **275 C files**. **`OpenAPIKit` @ `651cc55` refutes on shipped code**: `OpenAPI.XML` round-trips `{"name":"x"}` back to a DIFFERENT value, their **2,147 tests pass**, and the mechanism is `ToolChoice`'s — two values, byte-identical JSON, `Equatable` finer than `Codable`, which has now produced **all three** real defects. **Tally 30 hand-checked, 3 real; `idempotence` still 0 of 18.** ⚠ **The screen found TWO blind spots in ITSELF inside one pass** — it required a root `Package.swift` (hiding `IceCubesApp`'s 13 nested packages, instrument #7's exact shape, four days after that was recorded) and it greps a DIRECTORY BASENAME (`swift-sdk` **is** `mcp-swift-sdk`, spent, top score in the sweep, caught only because one name is a substring of the other). ⚠ **SELECTION IS THE BOTTLENECK, MEASURED 2026-08-28.** Two theories about which repos to clone were tried and both came back near zero — *models a wire format* (`sourcekit-lsp` **4**, and it implements the whole LSP) and *polymorphic domain model* (0, 4, 0, 0). **What worked was querying the population**: GitHub code search reports **136,192** Swift files hand-writing `encode(to encoder:`, and ranking by density surfaced **`Euclid`** — 15 hand-written of 15, in 47 files — which produced **the largest reading the toolchain has taken: 293 rows, 84 verdicts, 31 refutations** (`docs/measurements/subject-euclid.md`). **The headline there is WHICH TEMPLATES RAN** — associativity, commutativity, monotonicity, involution and binary-idempotence all executed, so the algebraic half of the catalogue has a subject for the first time. ⚠ **The 31 refutations are ~0 real, and the FIRST attribution of them was WRONG and is corrected in place**: floating point accounts for **1 confirmed + 1 probable**, not the bulk. **NINE are algebraically FALSE laws** — idempotence for involutions (5), monotonicity for trig (3), commutativity for 3D rotation composition (1) — which is row **69**. **Eleven more are NOT ADJUDICABLE**: the round-trip rows carry no `secondaryFunctionName`, so the stream does not say what the getter was paired against. The floating-point limit is real and still converges with the OpenAPIKit maintainer's *equality checks don't need to be equivalency checks* — it is simply not the dominant mechanism. ⚠ **The tally is NOT moved** — those 31 were TRIAGED, not hand-checked. **`swift-docc` @ `f160765` was the richest candidate and has been RUN** — `docs/measurements/subject-swift-docc.md`: **267 rows, 49 verdicts, 13 refutations**, ten times any previous subject's verdict count. **A FOURTH real defect, and it BREAKS the one-mechanism claim**: `CatalogFeatureFlags`'s `encode` writes JSON `null` for a nil `Bool?` and its own `init(from:)` THROWS on it, so `==` is never reached — the first three were all *`Equatable` finer than `Codable`*. `codable-round-trip` detects **the encoder and decoder disagreeing**, and they can disagree by throwing. ⚠ **Latent, not live: nothing in `SwiftDocC` encodes the type**, and no test among their 1,644 + 452 names it. **Tally 40 hand-checked, 4 real; `idempotence` 0 of 23** — five more of it landed here and all five are already-named mechanisms. A **fifth false-law mechanism** is named (`PlatformName`: fields derived from a canonical table, so only canonical values are constructible; its two embedders are the same mechanism, not extra evidence). ⚠ **Three refutations UNRESOLVED and recorded as such** — resolving `replacingWhitespaceAndPunctuation` as real would end the `idempotence` comparison outright. |
| 66 | **A corpus went 0 → 996 evidence-rows with no cause, and the run that read 0 is gone** | **NOTICED 2026-08-23 and deliberately NOT explained.** `docs/measurements/availability-gate.md` §3.1. Re-taking the availability population across the manifest moved `swift-syntax` from **0 evidence-rows to 996** — same scan path, same flag, same resolution in both runs, and the A/B reads **996 in both arms**, so it is not a gate effect. That doc records it as *unexplained* rather than inventing a cause, which is the right call there and leaves the question open here: **a silent zero for one corpus is the exact shape the three silently-zero corpora had**, and those were caught only because `scripts/measurement.py` returns a denominator beside every population. **What is actually known is narrow** — that the current figure reproduces, and that the earlier one does not, because no artifact of that run survives. ⚠ **Re-running it cannot settle this**; 996 reproduces on demand and the zero is unrecoverable. **The practice that caught it is the one to keep**: the movement was visible only because the earlier per-corpus figures had been written down in a table, which is a cheaper guard than any instrument and is already this file's answer to *the cheap capture answered a different question*. |
| 67 | **`codable-round-trip` is missing from the equatable gate, so an UNSTATABLE law reports as a broken emitter** | **MEASURED 2026-08-28, NOT FIXED.** `docs/measurements/candidate-screening-pass.md` §6.1. `VerifyCommand+TemplateDispatch.swift:367` declares `equalityShapedTemplates = ["inverse-pair", "identity-element"]`, and **`codable-round-trip`'s emitted law is `decode(encode(x)) == x`** — it needs `==` and was never added. On `SymbolKit` five carriers conform to `public protocol Mixin: Codable`, **with no `Equatable` anywhere in the chain**, so the stub emits `!=` on a type that has none and the build fails. **6 rows.** The gate's own doc comment states the joining criterion — *a template joins when someone has looked at its emitted law and seen the `==`* — and this one meets it on sight; the screening instrument excluded all five carriers correctly, which is what makes it a defect rather than a disagreement. **Payoff stated as ROWS MOVED: 6 move from `measured-error: build-failed` to `carrier-not-equatable`, and ZERO laws are gained.** A reporting-correctness fix of the availability-gate kind — it stops a real static decline from **wearing a build failure's name**, which currently reads as *our emitter is broken* when the truth is *the law is unstatable on that carrier*. ⚠ **Population across the corpora is UNMEASURED**, and the ~5:1 decline-to-rows ratio does not apply, because nothing is being freed. ⚠ **The gate lives in VERIFY, so discovery still emits the suggestion** — whether it should gate there too is the availability precedent's question and is not asked here. ⚠ **THE ONE-LINE FIX THIS ROW NAMED IS REFUTED, MEASURED 2026-08-28, AND WAS NOT SHIPPED.** `TypeShapeBuilder.swift:170` merges **same-file extensions only**, so `extension Foo: Equatable` in a separate file never reaches `shape.inheritedTypes` — and the gate fires on *absence of a token*, which for those types is absence of evidence, not evidence of absence. Across the 20 manifest corpora plus both subjects, **27 of 136 hand-written `Codable` ∩ `Equatable` types (20%) get their equality ONLY cross-file** — `OrderedSet`, `Deque`, `BitSet`, `ByteBuffer`, `Either`, `PackageReference` among them. **A fix that costs 27 rows to correct 6 is not a fix**, and it would land on the prime carriers of the only template that has ever found a real defect. **The gate is SOUND where it fires today** — checked, not assumed: OpenAPIKit's two live declines are on `IndividualFailure: Swift.Error`, which has no equality anywhere. **This is a finding about EXTENDING the gate, not about the gate.** ⚠ **`EquatableResolver` is the cross-file component `TypeShapeBuilder`'s own docstring points at, it handles the separate-file extension explicitly, and it has ZERO consumers in `Sources/`** — row 28's shape again. **It still cannot carry this gate**: a plain struct with nothing declared classifies `.unknown`, not `.notEquatable`, so a `.notEquatable`-only gate leaves all 6 rows where they are. The negative half needs *corpus-local and nothing anywhere declares equality*, **plus transitive closure through corpus protocols** — had SymbolKit's `protocol Mixin: Codable` been `Mixin: Hashable`, every carrier would be Equatable with no token on the type. **Shape of the real fix, so the next attempt does not restart at one line**: a tri-state computed at INDEX time where all `TypeDecl`s are in hand, carried on `IndexedTypeShape` as an additive `decodeIfPresent` field the way `enumCases` was, consumed by the gate. **Not attempted.** |
| 68 | **The first finding to leave the repository is reported upstream and UNANSWERED** | **FILED 2026-08-28.** [mattpolzin/OpenAPIKit#509](https://github.com/mattpolzin/OpenAPIKit/issues/509), for the `OpenAPI.XML` round-trip defect in `docs/measurements/candidate-screening-pass.md` §5.4. **This is a claim submitted for adjudication, not a confirmation** — and it is the recorded FALSIFIER for that finding: §10 of that doc already names *`OpenAPI.XML` being intended behaviour* as what would refute it, and the maintainer is the only person who can answer. **Three outcomes, written down BEFORE the answer so the reading is not fitted to it**: a fix accepted is the strongest external evidence this line of work has produced; accepted-but-unfixed confirms the *latent* reading; *intended* fires §10 and takes the tally to **3 real of 30**. A branch with the fix and two regression tests — both watched failing against the unfixed source — is prepared and **NOT pushed**, because the issue asks the maintainer which of two directions they want and their `CONTRIBUTING.md` says to seek conversation before committing to a strategy. ⚠ **Their AI policy is a CONSTRAINT ON HOW THIS EVIDENCE CAN BE PURSUED, not just on how it was filed**: contributors must own the PR, hand-write descriptions, and handle review **human-to-human** — so the follow-up is the maintainer's to answer and ours to answer in person, and no part of that thread can be automated. ⚠ **ANSWERED THE SAME DAY, AND THE ANSWER WAS NOT ON THE LIST.** The maintainer replied that the round trip is *"a goal of OpenAPIKit but not a mandate"*, that he *"maybe vaguely"* recalls the decision being intentional, and that *"equality checks don't need to be equivalency checks"* — while **agreeing** that *"the best ergonomics are that a value is equal to itself after going through an encode and a decode"*. **He asked for the PR to be held** (*"let me take a look at the code before you move on this"*), so the branch stays unpushed. **STATUS: CONTESTED — neither confirmed nor refuted**, and the tally now reads **3 real + 1 contested of 40**. ⚠ **The three-outcome table filed above did NOT contain this outcome**, and the pre-writing still paid for itself by stopping the reply being read as whichever row suited us; the missing row is the common one — *undecided, property conceded as desirable, enforcement declined as a mandate*. ⚠ **The objection GENERALISES and is not answered by any measurement here**: `codable-round-trip` takes `==` as the equivalence and cannot know a type intends `==` to be FINER than wire-identity, and **all four real defects rest on that assumption**. ⚠ **The recalled rationale does not match the code** — decode *preserves* `.legacy` whenever either flag is set and promotes nothing to a `nodeType` — but that is **the reporter's to raise human-to-human**, per their AI policy, and is not for this table to settle. |
| 69 | **NOTHING LICENSES AN ALGEBRAIC PROPOSAL — the templates fire on SHAPE, with no evidence the operation has the property** | **MEASURED 2026-08-28 on `Euclid`, NOT FIXED.** `docs/measurements/subject-euclid.md` §2.1. ⚠ **RE-SCOPED the same day it was filed.** It was first written as two cheap gates worth 7 rows — *`idempotence` for involutions* and *`monotonicity` for trig*. Re-checking the refutations row by row made it **one defect asked three ways, worth 9 of 31**, and the third way is the one that shows the shape of it. **The three:** `idempotence` on an **involution** (**5** rows — `Angle.-(angle:)`, `Rotation.-(r:)`, `Vector.-(rhs:)`, `LineSegment.inverted()`, `Vertex.inverted()`; the first filing counted 4 and missed `Angle`), `monotonicity` on `sin`/`cos`/`tan` (**3**), and **`commutativity` on `Rotation.*` (**1**) — 3D rotation composition is non-commutative, which is as textbook as a false law gets**. In every case the refutation is CORRECT and the proposal is the defect. **The algebraic templates fire on shape — a binary operator, a self-returning unary function — and nothing asks whether the operation plausibly HAS the property.** ⚠ **The catalogue is not ignorant, which is why this is a gate and not a rewrite**: `Rotation.*` drew BOTH `commutativity` (false) and `associativity` (true in exact arithmetic), so the two templates split correctly on one operator. It gets the harder half right and nothing guards the half it gets wrong. ⚠ **`involution` is the sharpest exhibit**: the catalogue OWNS that template and ran it 3 times on this very subject, while proposing `idempotence` for five functions that are involutions. The discriminator it needs is `involution`'s own question — *does a SECOND application return the original* — asked before `idempotence` is emitted. ⚠ **Do NOT fix by dropping `idempotence` for self-returning unary functions**, which is most of that template's population. ⚠ **Population beyond one subject is UNMEASURED**, and the standing ~5:1 decline-to-rows ratio does not apply: this REMOVES laws rather than freeing them, and the gain is that the tool stops proposing laws its own catalogue contradicts. ✅ **THE INVOLUTION HALF IS BUILT AND A/B'd, 2026-08-28** — `TemplateRegistry.applyInvolutionIdempotenceExclusion`. **The rule needs NO new analysis**: when `involution` and `idempotence` are both proposed for one `(file, line)` the tool has contradicted itself, since the two hold together only where `f(x) == x`, and `involution` is the one that named the shape. **Keyed on LOCATION, not name** — a name key would join same-named declarations on different types, the `SymbolJoinKey` collision already paid for once. **REMOVES rather than marks**, unlike the purity veto beside it: that veto's law might still be true, while this one is false whenever its sibling is true, and the availability gate is the precedent for withdrawing a law that cannot hold. **SAME-BINARY A/B over `make batch8`, both arms green at 21 tests (~565s each): `idempotence` 794 → 789 and 580 → 575, EXACTLY −5; `involution` unchanged at 5; `binary-idempotence` unchanged at 8/14.** ⚠ **THE CO-OCCURRENCE IS 100%**: there are 5 `involution` rows across the 20 corpora and the gate removed 5 `idempotence` rows, so **every declaration where `involution` fires also carried the contradicting proposal** — 5 of 5 in the manifest, and 5 of 5 again on `Euclid`. The contradiction is not occasional, it is universal in the measured population. ⚠ **THE HOME CORPUS HAS ZERO `involution` ROWS**, so the gate can never fire there — which is why this survived: the template never fired on the corpus the catalogue was tuned against, *a census is only as wide as its corpus list* landing on a TEMPLATE rather than a corpus. **Stated as ROWS REMOVED — 5 in the manifest, 5 on Euclid, 0 laws gained**, since it withdraws laws rather than freeing them; the value is that one of the five withdrawn (`Mesh.inverted()`) was returning `measured-bothPass` on a false law, and a passing false law is believed. ⚠ **THE MONOTONICITY HALF WAS SIZED 2026-08-28 AND THE GATE IS DECLINED ON POPULATION — but the census repoints this row.** The proposed fix was to gate the definitionally non-monotonic families (trigonometric, and hash functions, which cannot preserve order without being broken hashes). **Sampled 109 of the 339 monotonicity rows across 10 of the 20 corpora: ZERO trig and ZERO hash-shaped.** The `sin`/`cos`/`tan` rows exist only on `Euclid`, which is not a manifest corpus, and the hash rows seen in passing came from a `swift-collections` target the census does not use. **A gate with no population is the `parameter-role` decline again** — an exact signal over five rows — and it would have been built on one non-manifest subject. ⚠ **WHAT THE CENSUS FOUND INSTEAD IS BIGGER THAN THE GATE WOULD HAVE BEEN.** The sampled population is dominated by functions with no order semantics at all: **`decode(_:)` 18**, `fetchCount(_:)` 7, `columnCount(_:)` 3, `deleteAll(_:)` 3, `summary(of:)` 3, `parse(_:)` 2, `copyBytes(to:)` 2 — against `index(after:)` 9 and `index(before:)` 7, which are the genuinely monotonic ones. **`monotonicity` fires on `Comparable -> Comparable` and almost nothing in that population is about order**, so this is not a blocklist problem, it is this row's own thesis at **339 rows** instead of 5. ⚠ **Do NOT act on the 109 as if it were the 339**: 10 corpora sampled of 20, ~32% of the rows, and the missing half includes `swiftlang-swift` and `swift-collections`. **The next step is the full census, not a filter.** ⚠ **STILL OPEN and untouched: `commutativity` on `Rotation.*`** (1 row), which has neither a sibling proposal nor a measured population. **This row only exists because the algebraic half finally ran** — it was invisible across twenty corpora that never witnessed those templates. |
| 70 | **`round-trip` pairs an "inverse" on TYPE SIGNATURE alone, with no evidence it inverts anything** | **MEASURED 2026-08-28 on `Euclid` by READING THE EMITTED STUBS, NOT FIXED.** `docs/measurements/subject-euclid.md` §2.2. Re-emitted with `verify --all-from-index --template round-trip`, which leaves the generated `main.swift` in `.swiftinfer/verify-workdir/shared-survey/Sources/V<identityHash>/`; all three `Rotation.angle()` rows reproduced, so these are the stubs that refuted. **The law emitted for `Rotation.angle()` is `Rotation.yaw(r.angle) == r`** — and `Rotation.yaw(_:)` is documented *"Creates a rotation around the Y axis"*, one of three axis-specific constructors beside `pitch` and `roll`. It does not invert `angle`; the generator draws rotations from four random doubles, so the axis is essentially never Y. **The other pairings show the mechanism plainly**: `leastParallelAxis` → `clampedToScaleLimit()`, `mostParallelAxis` → `clampedToScaleLimit()`, `clampedToScaleLimit()` → `_quantized()`. **Unrelated functions, paired because both are `Vector -> Vector`.** **8 rows.** ⚠ **THE DEGREES-OF-FREEDOM GATE THIS ROW PROPOSED IS DECLINED ON MEASUREMENT, 2026-08-28** (`subject-euclid.md` §2.3). The observation is true — `Rotation.angle` returns a SCALAR from three degrees of freedom, so no one-argument constructor can invert it — but the GATE built from it fails three ways. **(1) Not computable**: `Rotation` stores one opaque `simd_quatd`, so the shape records `storedMembers = 1` against `Angle`'s **0**, and the comparison fires the wrong way round. **(2) The computable proxy is unsound**: initializer arity is recorded (Rotation 4, Vector 3, Angle 1) but arity is not dimensionality, and the obvious casualty is the CANONICAL round trip `URL(string: u.absoluteString) == u`. **(3) It covers 3 of the 8** — the other five are `Vector -> Vector` on both sides, where degrees of freedom are equal by construction. ⚠ **AND THE DISTINCTION IT WAS RECONSTRUCTING IS ALREADY IN THE TIER.** `RoundTripTemplate+InverseNames.swift` ships a curated inverse-name vocabulary, and `FunctionPairing`'s own docstring states the design — *naming is a signal, not a pre-filter, so the scoring engine can still see Possible-tier pairs*. **All eight refuting rows are `Possible`**, while the legitimate round trips elsewhere are name-linked and `Strong` (`rawValue(rawValue:)` on OpenAPIKit, `identifier(identifier:)` on SymbolKit). **So the defect is not a missing gate: it is that `Possible`-tier cross-function pairs enter the INDEX by default** — 204 of Euclid's 293 entries, and 55 of its 60 round-trip rows — and the index is what `verify --all-from-index` and the whole-corpus survey consume. The tier is computed, recorded, then not consulted where it would help most. ⚠ **That change is NOT made here**: the survey's executing ratio is measured over an index that includes `Possible`, so changing what is indexed moves that denominator and the movement must be measured. ⚠ **AND THE SHORTCUT IS NOW REFUTED, 2026-08-28** — `refutation-hand-check.md`, third addendum of that date. The appealing story was *the distinction is already computed, `Possible` is where the unlicensed proposals land, so stop indexing that tier*. **Re-asking the tier question with DENOMINATORS over four unmet subjects kills it**: `Euclid`'s `Possible` rows refute at **44%** against `Likely`'s 17%, while `swift-docc`'s go the OTHER WAY — `Possible` **19%**, `Likely` **39%**. The only two subjects carrying enough of both tiers disagree in direction. ⚠ **Pooled it reads `Likely` 24% / `Possible` 35%, and pooling is what HIDES the disagreement** — Euclid is 84 of the 143 verdicts, so the pooled figure is Euclid wearing a four-subject label. **The finding in this row stands** — an inverse chosen on type signature alone is a real defect, read out of the emitted stub — **but excluding `Possible` would not have removed those eight pairings and would have removed rows that refute at 19% elsewhere.** The weaker claim that survives is that both real defects are `Likely` and no `Possible` refutation has proved real in 32 — **n = 2, and those 32 were TRIAGED, not hand-checked**. ⚠ **This is row 69's defect at a different site** — nothing licenses the PAIRING, exactly as nothing licenses the algebraic PROPERTY — and together they are **17 of that subject's 31 refutations, 55%**. They are filed separately because the gates differ. ⚠ **NOT every round-trip row is affected**: the three `codable-round-trip` rows on the same subject pair `JSONEncoder().encode` with `JSONDecoder().decode`, which IS a genuine inverse, and they fail for an unrelated reason (`simd_normalize` re-applied on decode under an exact `==`). **The defect is in how an inverse is CHOSEN, not in the template.** |
| 71 | **`scaffold-kit-suites` emits a LIVE suite for a `private` carrier, which `@testable` cannot reach** | **MEASURED 2026-08-28, NOT FIXED.** `docs/measurements/kit-scaffold-conversion.md` §3.1. `Euclid.IndexPair` is `private struct IndexPair` in `Polygon.swift`; the scaffold emits its `Hashable` suite live, and `@testable import` exposes `internal`, not `private`. **Worth all 40 of the remaining compile errors on that subject** — 20 `cannot find 'IndexPair' in scope` plus 20 downstream `cannot infer contextual base` on `.strict`/`.passed`, which are error-typed `results` and not defects of their own. **After the `__genMesh` and observed-property fixes this is the ONLY cause left**, so closing it plausibly takes that subject to a compiling suite — the first one. ⚠ **The scaffold's banner already warns the reader** (*a carrier may be `private` or nested past what `@testable` reaches — delete what does not fit*), which is the check being shifted onto the person pasting the file when **the emitter is the one that knows**. Same shape as the availability gate: do not propose what cannot be written. ⚠ **NOT a rule change — a SCHEMA change.** `TypeDecl` carries no access level and `FunctionScannerVisitor+TypeDecls` captures none, so this needs a field threaded through scanner → shape → emitter, which is why it is filed rather than done beside two one-rule fixes. ⚠ **Blocked-not-live is the right disposition, not omission**: the reader should see that the carrier owes laws and why it cannot have them, which is what the blocked section is for. ✅ **SHIPPED 2026-08-28, and it took the subject to ZERO compile errors.** `TypeDecl.isVisibleToTestableImport`, computed from the `access(of:)` **the scanner already had and dropped** — the third defect in this sequence whose fix was a render rather than a derivation. Threaded scanner → pipeline → emitter as a sidecar map beside `genericParametersByName`, and **an ABSENT key means unknown, not private**, so every caller predating it is unchanged (tested). **240 → 160 → 40 → 0: Euclid's is the first generated kit suite anyone has compiled** — 13 carriers, 76 laws. ⚠ **RUNNING IT IS A THIRD RESULT AND NOT A CLEAN ONE**: two violations, both `Codable.roundTripFidelity[JSON]` on `Rotation` and `Vertex`, which are **the same two our own pipeline found** and whose counterexample is a last-digit float difference under exact `==` — two independent law implementations reaching one finding. **And the run does not COMPLETE**: signal 5 at `Plane.swift:230`, where `init(unchecked:)` asserts `normal.isNormalized` and the derived generator supplied an unnormalized `Vector`. **Fifth instance of the generator building what the type's invariants forbid** — after `SystemString`'s NUL, `Bounds` min>max, `Color` out of range and `Mesh` reaching only fixed points. **Compiles yes, runs yes, completes no.** |
| 72 | **GENERATOR FIDELITY — the generator builds values the type's own invariants forbid, and it has now blocked FIVE results** | **FILED 2026-08-28**, because this has carried five findings and has had no home. **The five**: `SystemString`'s interior NUL, forbidden by a `_invariantCheck()` inside `#if DEBUG` (`criterion-a-swift-system.md` §8.4); `Bounds(min:max:)` accepting `min > max`, so `union` commutativity refuted on a value the type excludes; `Color` components at ±5e5 in a 0…1 type; `Mesh` reaching only FIXED POINTS, which made a false `idempotence` law **PASS** — worse than refuting, because `bothPass` is believed; and `Plane.init(unchecked:)`, whose `assert(normal.isNormalized)` **traps the first kit suite anyone has compiled** (`kit-scaffold-conversion.md` §3.2). ⚠ **They are NOT one problem — they differ by WHERE the invariant is written, and that is the whole tractability question.** `Bounds` and `Color` declare theirs **nowhere**, so no static analysis reaches them. `SystemString`'s is a debug-only helper call. `Plane`'s is an `assert` in the initializer — **and that kind is already detectable**: `InitializerPreconditionDetector` (SwiftPropertyLaws, `PropertyLawSyntaxSupport`) matches `assert` / `precondition` / `fatalError` in an init body and records `self.init` delegation. ⚠ **THE LIVE EXHIBIT POINTS AT A CHEAPER SIGNAL THAN §8.5's HOP.** The strategist picked `Plane(unchecked: $0.0, pointOnPlane: $0.1)` — **an initializer whose argument label is literally `unchecked`**, which is the author saying the precondition is the caller's problem. That is detectable from `InitializerParameter.label`, which the index already carries. **Disposition is precedented three times**: block the carrier with a reason, as the availability gate and row 71's private-carrier gate do — do not propose what will trap. ⚠ **Any fix here is PARTIAL by construction**: it reaches the asserting and the `unchecked`-labelled kinds and cannot reach `Bounds` or `Color`, which state nothing. Saying so up front is the difference between a scoped fix and one that looks broken later. ⚠ **CENSUS RUN 2026-08-28, AND THE `unchecked`-LABEL GATE IS DECLINED ON POPULATION.** Over 12 manifest corpora via the real parser (index `typeShapes`, never a regex): **1 type of 1,251 with initializers, and 1 initializer of 3,035 — 0.0%** carries an `unchecked` label. It is `Euclid`'s local convention, and `Euclid` is not a manifest corpus. **Third signal this session that was exact on one subject and had no population**, after the monotonicity blocklist and parameter-role. ✅ **BUT THE CENSUS FOUND THE ROOT CAUSE, AND IT IS NOT §8.5's METHOD HOP.** `Plane`'s picked initializer is `init(unchecked normal:pointOnPlane:)`, whose body is `self.init(unchecked: normal, w: normal.dot(pointOnPlane))` — **pure `self.init` DELEGATION to the sibling that asserts**, which is precisely the case `InitializerPreconditionDetector.delegatesToSelf` documents and pairs with *does any initializer on this type assert*, calling it conservative in the right direction. **The kit's `MemberBlockInspector` computes BOTH flags; ours computes only `assertsPrecondition`** (`Sources/SwiftInferCore/MemberBlockInspector.swift:167`), so the delegation pairing can never fire on our side. ⚠ **AND THERE IS A SECOND, LATENT COPY OF THE SAME DROP**: `TypeShapeBuilder.swift:236` carries `assertsPrecondition` through with a comment warning that *any field added to `InitializerSignature` has to be carried through this map* — and names `_DequeSlot`, `_HeapNode`, `_HashTable.Bucket` as the symptom of not doing so, *kept deriving and kept aborting*, **which is the Plane symptom verbatim**. The INDEX round-trip at `IndexedTypeShape.swift:264` builds `PropertyLawCore.InitializerSignature` from `parameters`/`isFailable`/`isThrowing` only, dropping both flags. **FOURTH 'computed upstream, dropped on our side' finding of the day**, after `__genMesh`'s declarations, `access(of:)`, and the observed-property rule. **The scoped fix**: compute `delegatesToSelf` in our inspector, add both flags to `IndexedTypeShape.InitializerSignature`, carry them both ways. **Not done here** — a schema change beside four fixes already shipped today. |

### The purity line of work, and how to read the integers in every measured row

Rows 29–42 were merged here 2026-08-18 from the staging doc they were drafted in, which held them unmerged for a
month of sessions (retired the same day; recover it with
`git show 484bf7e:docs/design-internal/openthreads-additions.md`). Those rows are verbatim. **Rows 43–48 are new** — six measurements landed after that file's last edit (`598412b`) and had no row anywhere, which is the same failure one level down.

⚠ **This heading used to carry a range, and the range was wrong** (corrected 2026-08-27). It read
*Rows 29–62*, and it had been bumped one row at a time as new rows landed — 61 on 2026-08-19, 62
an hour later at `42dc5274` — while the sentence above it went on saying *six measurements*, which
is rows 43–48 and always was. **The purity cluster is 29–56 and 63**; 50 arrived out of row 49's
measurement and is about accessor classification rather than purity. **57–62 are the survey and
refutation line of work** and were annexed by an endpoint nobody re-read against what it now
claimed.

That is this file's own [*doc that characterises a set by a property its newest member
lacks*](#a-doc-that-characterises-a-set-by-a-property-its-newest-member-lacks) — in its own
section heading, in the file that records the observation. The fix is that observation's own
advice: **name the members, do not count them.** The *read the integers as-filed* rule below is
not purity-specific and never was; it applies to every measured row in this table.

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

### The chain of blockers, and why a pre-flight check would NOT shorten it — DECLINED 2026-08-22

Reaching an executing law on `swift-system` took four fixes in sequence: **module resolution →
emitter shapes → generator domain → composition preconditions**, plus **availability** alongside.
Each was invisible until the one before it was fixed — before the module fix the trap bucket was
**zero**, not because the generators were fine but because nothing reached a runtime.

The obvious proposal is to stop the pipeline swallowing its own information: **report every
blocker a row has at once, rather than the first**. `resolveFunctionCalls` is a `switch` that
throws, so today a row gets exactly one cause, and several causes are independent —
`subjectNotVisible`, `carrierNotEquatable`, `unsupportedCarrier` and `unsupportedTemplate` can
each be decided without the others.

**Measured, and it would not have helped.** Take the one link where the counterfactual is
observable — the 21 rows the module fix freed:

| where the freed rows landed | rows |
|---|---:|
| runtime trap (**dynamic** — needs execution) | 9 |
| build failure (**a bug in our own emitter**) | 6 |
| ran to a verdict | 4 |
| **another static decline** | **2** |

**A pre-flight check can only report causes it computes statically.** Nineteen of twenty-one
rows went straight to something no static check can see: a trap that needs the code to run, or
a compile error in the emitter, which is a defect and not a decision. Reporting every static
cause at once would have shortened the chain for **2 of 21**.

**The deeper reason, which the table only hints at: pre-flight reports the checks you already
have.** Of the five blockers, exactly one — availability — was a static cause a pre-flight pass
could have surfaced early, and the reason it went unreported was not that a different cause won
the race. It was that **nothing computed availability at all**. A check that does not exist
cannot be reported earlier.

So the chain is serial for reasons that are mostly not fixable by better reporting:

| blocker | kind | could pre-flight have surfaced it? |
|---|---|---|
| module resolution | static decline | **it already did** — reported as `unsupported-carrier: … not a library product`, and misread |
| emitter shapes | our own bug | no — a build failure is not a decision |
| generator domain | dynamic | no — needs execution |
| composition preconditions | dynamic | no — needs execution |
| availability | static decline | no — the check did not exist |

**What is left of the idea.** Multi-cause reporting may still be worth having as *diagnostics* —
a reader told three reasons at once forms a better plan than one told them across three runs —
but that is a different claim from *it shortens the work*, it is unmeasured, and it must not be
sold as the second thing. The measured lever for chain length is not reporting; it is
**subject selection** (`toolchain-exit-criteria.md` §6.1).

**And one correction to how the chain was first described.** It looked like the blockers were
hardening — three of *our* defects, then a wall at composition preconditions, where the
constraint is not in reachable program text. **Availability refutes that ordering**: its
attribute sits in the syntax tree and nothing read it, and it came *after* the hard one. The
chain is ordered by **where the pipeline dies**, and difficulty is scattered along it
independently — so *the last blocker was hard* implies nothing about what is behind it.

### Wrong instruments in one cycle, and the guard that was finally written (2026-08-17 → 08-23)

Between 2026-08-17 and 2026-08-23, **seven measurement instruments returned a wrong number**, all
with the shape this file has recorded as a standing observation since 2026-08-05: *the cheap
capture answered a different question from the one being asked.*

⚠ **The heading carried the count until 2026-08-27 and the count moved.** #7 was found on
2026-08-23, four days after the guard was written and two days before a doc-hygiene batch renamed
`catalog-health-17-corpora.md` for the identical reason — *a count belongs in the body where it can
be dated and re-taken; a name cannot be.* Second payment for that rule in a week, so the number now
lives in the sentence above this one, where it is allowed to change.

| # | instrument | reported | true |
|---|---|---|---|
| 1 | `--target System` on swift-system | "36 unsupported-carrier" | 21 were a module bug |
| 2 | availability count over `localPath: "."` | 31,541 `deprecated` | **1,163** — the walk entered `.build` |
| 3 | availability join on `discover` default output | 4 rows | **24** — the question was the index |
| 4 | swift-system baseline via `swift test \| tail -6` | 8 tests | **78** |
| 5 | `make test \| tail -35` | exit code only | every per-stage count lost |
| 6 | custom-`Codable` detector, 40-line window | 7 of 14 | **14 of 14** |
| 7 | availability join over the manifest's scan paths | `swift-project-lint` **9** rows | **396** — the join read `sources[0]` and never saw `Packages` |

**The standing observation did not prevent any of them**, which this file already predicted of
itself: *restating a rule in a second prose location does not approximate a guard — it produces
the feeling of having one.* Seven recurrences is that sentence being paid for.

**So the response is code**: `scripts/measurement.py`, wired into `make test-fast` via
`make measurement-selftest`. It owns corpus-root resolution, applies `EXCLUDED_DIRS` by
construction, brace-matches declaration blocks across the whole tree rather than a line window,
and returns the **denominator alongside every population**. Its self-test arms are regression
tests for specific wrong numbers above — an arm not traceable to one does not belong in it.

**This breaks a convention deliberately.** `scripts/` was study tooling that `make test` did not
run, and that separation is precisely why nothing caught six of the seven. The self-test
costs ~0.3s.

#### It found three silently-zero corpora on its first run

| corpus | declared scan path | resolved to | actually |
|---|---|---|---|
| `maccloud-client-ios` | `Shared` | **no such directory** | 22 files at `MacCloud_client_iOS` |
| `grdb` | *(none)* → `Sources` | **0 .swift** | 167 files at `GRDB` |
| `swiftlint-rule-studio` | `SwiftLintRuleStudio` | **only `Info.plist`** | 171 files |

**360 Swift files that every manifest-iterating census has counted in its denominator and drawn
nothing from.** It also explains a loose end recorded a day earlier — *three corpora returned
zero evidence-rows entirely* — which was noted as *a scoping artifact I haven't chased*.

**GRDB is the sharpest of the three**: its own manifest declares `path: "GRDB"`, so
`Sources/GRDB` does not exist. That is the **same trap** `VerifyTargetInference.manifestModule`
was written for — *`Sources/<target>` is a convention, not a rule* — arriving in a second
subsystem that had not learned it. The fix follows the manifest's own documented rule, which
was there the whole time: **target says what to BUILD, sources says what to SCAN.**

#### What is NOT guarded, stated so it is not assumed

**#4 and #5 are `| tail -N` in an interactive shell.** Nothing inside a Swift package can see
them. `measurement.capture()` makes the safe capture shorter to write than the unsafe one, and
that is a convenience, not a guard. **The recurrence risk there is unchanged.**

#### One movement that was NOT given a cause

The same re-take moved `swift-syntax` from **0 evidence-rows to 996**, and
`availability-gate.md` §3.1 records it as **unexplained** rather than attributing it — same scan
path, same flag, same resolution, and the A/B reads 996 in both arms. **That is the correct entry
in a table of instrument faults with known causes**: it is not known to be one. It is row **66**,
and it is here rather than only there because the three silently-zero corpora above are what a
corpus reading zero for an unknown reason looks like from the outside.

**Affected numbers — and one that was wrongly listed as affected.**

`availability-gate.md`'s declaration counts **were** taken while these three corpora contributed
nothing, and are re-taken there. The manifest fix moved them by **6 and 18**; it also surfaced a
larger, unrelated error (`obsoleted: 49+` was really **106**, from a form-census truncated to its
top shapes). **Both original figures reproduce to the digit on their original population**, which
cross-validates the old and new instruments against each other.

⚠ **`template-refutation-rates.md` was NOT affected, and saying it was, was an error.** Its three
streams are the home-corpus survey — which indexed *this repo's six library targets* via
`--index-path`, not the manifest — plus `mcp-swift-sdk` and `swift-system`, each a single
subject. **No manifest iteration touches any of them.**

That mistake is worth keeping rather than quietly deleting: **over-claiming contamination is not
the safe direction it looks like.** A number wrongly marked tainted gets discarded, and the work
behind it is repeated for nothing. The scope of a defect has to be measured with the same care as
the defect.

### Four of the twenty corpora are THIS REPO, so corpus cleanup can be destructive (2026-08-28)

A census script that indexed each manifest corpus and then ran `rm -rf .swiftinfer` to leave the
subject clean **deleted two TRACKED files** — `fixtures/cycle27-surface/.swiftinfer/index.json`
and `verify-evidence.json` — and four fast-suite tests went red on the next run. Restored with
`git checkout HEAD --`; nothing was lost, because they were committed.

**The cleanup step is correct for a clone and destructive for an in-repo corpus, and the manifest
contains both.** Four of the twenty resolve inside this repository: `swift-infer-core` at `.`,
plus `planted-defect-arm`, `cycle27-surface` and `leaderboard-sort` under `fixtures/`. Two of
those have `.swiftinfer/` **committed on purpose** — `cycle27-surface`'s index is the fixture that
`V1_51EndToEndFromIndexTests` and `V1_58MethodologyGuardTests` read, and its
`verify-evidence.json` is what `PersistEvidenceOptOutTests` asserts is *tracked*.

**The habit that saved it was `git status` before committing, not the test failure** — the tests
named the symptom, but the deletion had already happened and would have been committed by a
`git add -A` in between.

⚠ **This is a different hazard from the wrong-instrument entry above.** Those returned a wrong
number; this one returned a right number and damaged the tree on the way. **A per-corpus
teardown must ask whether the corpus is a clone**, and `scripts/measurement.py` — which owns
corpus resolution — is where that belongs if this is ever built rather than scripted ad hoc.

### A decline bucket's NAME is not its cause (2026-08-21)

`verify --all-from-index` over swift-system reported **36 `unsupported-carrier`**, and
grouping them by the `carrier` field gave a clean-looking table topped by **`FilePath`, 15
rows**. That table produced a diagnosis (the tool cannot construct the subject's principal
type), a recommendation (build an `ExpressibleByStringLiteral` generator route), and a
committed document — `docs/measurements/criterion-a-swift-system.md` at `647fc7c0`.

**Twenty-one of the 36 were a module-resolution bug**, quarantined with this reason:

```
unsupported-carrier: System is not a library product of swift-system (vended: SystemPackage)
```

A product-resolution failure, reported under the carrier label, in rows whose `carrier`
field still said `FilePath` — because the carrier *is* `FilePath`; it simply had nothing to
do with why the row declined. `FilePath` turned out to be constructible all along: after the
fix, not one remaining `unsupported-carrier` row names it.

**The recommendation was then built and measured, and moved zero rows** — row-for-row
identical output across all 41 records, with and without it. So the cost of grouping by the
wrong key was not just a wrong document; it was a feature designed against a phantom, and
only the project's own *rows moved* rule caught it before it shipped.

**Group by the reason string, not the bucket label.** A bucket is a channel that several
causes share — the same point `The bucket is a channel, not a report` makes about
`PurityVerdict.refuted`, arrived at independently from the other end. Two occurrences now,
in unrelated subsystems, is enough to call it a shape rather than an incident.

The narrower lesson is worth stating too: **the label was accurate and still misleading.**
Nobody wrote anything false. `unsupported-carrier` is a defensible name for "the workdir
cannot obtain this carrier," and product resolution is one way that happens. The defect is
that the label describes the *consequence* and the reader needs the *cause*, and the cause
was sitting in the reason string the whole time, unread.

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
