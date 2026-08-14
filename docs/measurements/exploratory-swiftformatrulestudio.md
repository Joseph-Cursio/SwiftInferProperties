# Exploratory run — SwiftFormatRuleStudio

> **Status:** `measured` · **As of:** 2026-08-13

**Not a road test.** No frozen fixture, no frozen answer key, nothing scored. The question
was *how many property-based tests can this toolchain actually land on a fresh subject*, and
*where does the process leak*. Numbers here are of their date and their commits; the
diagnoses are the durable half.

**Subject:** `SwiftFormatRuleStudio@2799291` — `SwiftFormatRuleStudioCore` (a SwiftPM library,
3,400 lines of source / 2,553 lines of tests over 24 files, zero property tests today) plus
`App/` (an Xcode SwiftUI target, reached with `--sources`).
**Instrument:** `SwiftInferProperties@95bf915`, release binary.
**Kit:** SwiftPropertyLaws `from: "3.28.0"`.

A hand list of the laws the package owes was written **before** any tool run
(`§6`), so a silence is legible as a silence.

---

## 1. The answer: how many tests

| surface | proposed | **executable today** |
|---|---:|---:|
| `scaffold-kit-suites` (conformance laws) | 21 carriers / **64 laws**, 100% live, 0 commented | **0** — see §2 |
| `discover` (algebraic), Core | 19 indexed (16 on the default surface) | **1** — and it refuted, see §3 |
| `discover-interaction`, Core | 4 (over 5 `@Observable` view models) | 0 — all `.possible`, hidden by default |
| `discover` / `discover-interaction`, App via `--sources` | 14 + 4 | not attempted (verify declines `--sources` by design) |

**Bankable today: one property test, and it is a banked *refutation*.** The 64 kit laws are
one build-setting away from being the bulk of the value, and that setting is the finding.

Tier distribution on the algebraic surface: **0 Strong, 2 Likely, 11 Possible, 6 Advisory.**
Nothing reached `Verified`.

---

## 2. The headline hole — `scaffold-kit-suites` over-claims by 64 laws

> **FIXED 2026-08-13 — `TargetIsolation` + `KitSuiteEmitter.isolationBlocked`. Measured A/B,
> two release binaries, same subject, same command, only the emitter changed:**
>
> | | before | after |
> |---|---|---|
> | reported | `21 carriers / 64 laws live`, `0 commented out` | `0 live`, **`21 carriers / 64 laws commented out`** |
> | compile errors | **132** | **0** |
>
> The gate reads `defaultIsolation` for the **scanned target** from `swift package
> dump-package` and, when set, blocks every carrier with the reason and the remedy. It runs
> **first** among the four gates, because it is the binding constraint — the same argument the
> instantiation gate already made one level down.
>
> **Control: `SwiftInferCore` is byte-identical across the change** — `122 carriers / 447 laws
> live, 8 / 26 commented out`, no isolation note. A gate that blocks everything must be inert
> where it does not apply, and every can't-answer arm (no manifest, `dump-package` failure,
> JSON drift, unknown target, `--sources`) returns `nil` and emits exactly as before. That
> asymmetry is the opposite of `TestTargetScope`'s and is chosen deliberately: a broken read
> that answered `"MainActor"` would empty the emitted file for every package in the world.
>
> **Two honest limits.** The gate is a sound **over-approximation** — a type declared
> `nonisolated` escapes default isolation and would compile, and the scanner records no
> isolation modifiers, so it is blocked anyway (0 of 43 public value types on this subject, so
> the cost is nil here; falsifier: `IndexedTypeShape.isNonisolated`). And because it runs
> first, the per-carrier gaps behind it are not reported while it fires — the reason says so
> and tells the reader to re-run.
>
> **It also fixed a misattribution the finding did not name.** The banner said *"commented
> out: the generator could not be derived"*, the stderr note said *"pending a hand-written
> `gen()`"*, and each block was headed *"BLOCKED on a generator"* — all three for **four**
> gates, only one of which is about a generator. A reader following that advice writes a
> `gen()` that changes nothing. All three are now cause-neutral, with the cause on the block.
> Guarded by `TargetIsolationGateTests` (12 laws).
>
> The finding as originally measured follows.

The emitter reports:

> `21 carrier(s) / 64 law(s) emitted live; 0 carrier(s) / 0 law(s) commented out pending a
> hand-written gen()`

100% derivation, nothing withheld — a better rate than any corpus in
`kit-suite-backtest-arms-2-3.md`. **It does not compile: 132 errors, 0 of 64 laws.**

One root cause. The package is built with `.defaultIsolation(MainActor.self)`, so every
type's conformances are MainActor-isolated, and `check<Protocol>PropertyLaws` requires
`Value: Sendable`:

```
error: main actor-isolated conformance of 'FormatOption' to 'Equatable' cannot satisfy
       conformance requirement for a 'Sendable' type parameter  [#IsolatedConformances]
```

**The cascade is proved, not assumed.** Of the 132, 52 are `#IsolatedConformances` and 80 are
`cannot infer contextual base in reference to member 'strict' / 'passed'` — which look like a
second defect in the emitted `#expect(results.allSatisfy { $0.tier != .strict || $0.outcome
== .passed })`. They are not. A minimal package (`scratchpad/cascade/`) with the *identical*
emitted shape — same `checkEquatablePropertyLaws(for:using:)` call, same `zip(...).map`
generator, same `#expect` line — against a plain non-isolated `Sendable` struct builds with
**0 errors and the law passes in 0.065s**. The emitted code is correct Swift; `results` simply
fails to type-check once the call errors, and every `.strict`/`.passed` reference falls over
behind it.

**Why this is the tool's problem and not the subject's.** The gate applied is *can I derive a
generator*, and the question that decides whether the file is usable is *will this compile*.
The deciding fact is one line of `Package.swift`, a file this repo **already parses** —
`TestTargetScope` shells out to `swift package dump-package` to scope test lifting. The
emitted header does warn, in prose, that the file is "NOT GUARANTEED TO COMPILE" because
`check<Protocol>PropertyLaws` requires `Sendable` — but the *count* on the line above says
`0 commented out`, and the count is what a reader takes. This is the
`docs/measurements/roadtest-self-dogfood-2026-08-08.md` §10.9 rule again in a new place: a
number and its own caveat, disagreeing, with the number winning.

**No remedy is offered, because the obvious one was tried and failed.** Marking the twenty
model types `nonisolated` (the one-keyword reading) left 115 errors — 64 `duplicate modifier`
where the declaration already said `nonisolated`, then `rawValue` isolation and a
`RawRepresentable` conformance failure underneath. Making these conformances non-isolated is
a real refactor of the subject with its own ripple, not a keyword. Recording it as *measured
and unsolved* rather than recommending an untested fix.

**Suggested shape of a fix, unbuilt:** read `defaultIsolation` from `dump-package` and, when
it is `MainActor`, emit the affected carriers **commented out** with the reason — which is
exactly the machinery the emitter already has for underivable generators, pointed at a second
gate. That converts a 64-law over-claim into a disclosed gap, which is the posture the
emitter already argues for in its own header.

---

## 3. One law ran, and it found a real defect

`round-trip` on `SwiftFormatConfig.parse(_:)` / `serialized()` — the only pick of 19 that
executed — returned `measured-defaultFails` at **trial 27**, counterexample `"  "`.

Reproduced by hand, independent of the harness:

| input | `parse(_:).serialized()` | |
|---|---|---|
| `"  "` | `""` | **FAIL** |
| `"\t"` | `""` | **FAIL** |
| `"--indent 2\n  \n"` | `"--indent 2\n\n"` | **FAIL** |
| `"  # c\n"` | `"  # c\n"` | ok |

`SwiftFormatConfig.Line.blank` is the **only** case that does not keep its `raw` text; every
other case does. So a whitespace-only line loses its whitespace on save. Against the type's
own docstring — *"preserves the original line order, comments, blanks, and unknown lines …
so unedited lines serialize byte-for-byte"* — that is a contract violation, and it defeats
the stated design goal (minimal diffs) for any config containing a `  \n`.

The existing hand-written suite has **two** round-trip tests, one of them
`roundTripEdges` covering `"--indent 2\n  # indented comment\n\n"` — an indented *comment*,
never an indented *blank*. Four example inputs, and the property found it at trial 27. That
is the case for property tests made on the subject's own code.

**Severity is cosmetic; the class is not.** This is the one place the loop delivered end to
end: proposed from shape + docstring, executed, refuted, reproduced.

---

## 4. …and then the finding became invisible

> **FIXED 2026-08-13 — `RefutationRenderer`.** A refuted law is now shown in its own
> `REFUTED BY MEASUREMENT` block on **stdout**, carrying the subject, its `file:line`, the
> counterexample detail and the identity. On this run's own evidence:
>
> ```
> REFUTED BY MEASUREMENT — 1 law was executed and a counterexample was found.
> These are NOT suggestions and are not proposed again: each was run and failed. …
>
>   ✗ round-trip  parse(_:)  (String) -> Self
>     …/Config/SwiftFormatConfig.swift:61
>     Verify: defaultFails — trial=27
>     Identity: 0x0809244D12C83111
> ```
>
> **The veto is unchanged** — a refuted pick still never re-enters the suggestion list, because
> it has been measured false. What changed is that the suppression stopped being silent.
>
> **stdout, not the neighbouring stderr channel, and that is measured rather than preferred.**
> `Discover+EvidenceDiagnostics` exists for this same class of problem and writes to stderr;
> its own header records that its coverage `note:` went unseen through an entire eight-corpus
> census, because every invocation ran with `2>/dev/null` — *including the runs whose numbers
> were written into the findings doc*. Putting the strongest evidence the tool produces on a
> channel already measured to be discarded would repeat a mistake this repo has paid for once.
>
> **It survives `--stats-only`**, which is what CI reads, and it survives a run with **zero
> suggestions** — the exact shape measured here, where everything else declined and the one
> law that ran refuted. Both are guarded arms, not incidental.
>
> `report` names the row too: `Disproven — executed and refuted: ✗ round-trip 0809244D12C83111
> — trial=27`, in place of the bare `Disproven 1`.
>
> **The selection filter is on the `verifyDisproven` SIGNAL, never on the `.suppressed`
> tier** — several vetoes land a pick in that tier, and only this one means *executed*.
> Reporting a coverage-vetoed pick as a refutation would present inference as measurement,
> which is worse than the silence being fixed. `RefutationVisibilityTests` (9 laws) pins that,
> plus a control asserting output is byte-identical when nothing was refuted.
>
> **Two existing tests were asserting the silence** and are now precise instead of loose:
> `DiscoverCLIVerifySuppressionTests` checked the identity was absent from the *whole* output.
> The invariant was never "the string is absent" but "the pick is not offered as a
> suggestion", so they now assert absence from the suggestion region **and** presence in the
> refutation block — strictly stronger than before.
>
> The finding as originally measured follows.

After `verify` recorded the refutation, `discover` **stops printing the row entirely** — the
`verifyDisproven` veto, working as designed. But the veto is silent: no note, no
counterexample, no "this was refuted on <date>". The row simply is not there.

`report` is the only surface that mentions it, as a bare count:

```
Measured verify — 19 record(s)
  Proven 0 · Disproven 1 · Unverifiable 18 · Inconclusive 0
```

**One digit.** To learn *which* law, on which function, with what counterexample, you read
`.swiftinfer/verify-evidence.json` by hand. The single most valuable thing this run produced
is, on the default surface, indistinguishable from having found nothing — a `Confident zero`
manufactured by the tool's own success. `roadtest-self-dogfood-2026-08-08.md` §7.4's *a row a
human cannot audit*, one step further along: a row a human cannot **see**.

> **Method note — I got this wrong first.** The vanishing row was initially diagnosed as a
> `--test-dir` effect, because a probe passing `--test-dir` reproduced it. The control that
> settled it was moving `.swiftinfer/verify-evidence.json` aside: `--test-dir Tests` and the
> bare default *both* print the row with the store gone, and *neither* does with it present.
> The probe and the cause were simply concurrent. **A/B the artifact, not the flag** — the
> flag was the thing I had changed, which is exactly why it read as the cause.

---

## 5. Seven smaller holes

1. **`report`'s Unverifiable tip misattributes 17 of 18.** It reads: *"an Unverifiable pick
   means the strategist has no generator for its carrier. Add `static func gen()`…"*. The
   actual split of the 18: **9** `unsupported-template` (no composer), **6** subject is
   `private`, **2** `instance-method-shape-not-supported`, **1** `unsupported-carrier`. The
   advice addresses the one cause responsible for a single row, and the fix it prescribes
   would move nothing else. This is the glossary's own *"`unsupported-carrier` is nearly
   always the wrong suspect … reading that constant and believing it produced a wrong plan
   once already"* — shipped verbatim as user-facing guidance.

   > **FIXED 2026-08-13 — `UnverifiableCause`.** The tip is replaced by a cause breakdown with
   > a remedy per cause present, largest first. On this exact population it now renders
   > *"Unverifiable by cause: no composer for the template 9, subject not visible to tests 6,
   > instance-method shape 2, no generator for the carrier 1"*, and the `gen()` advice is
   > attached to the line that says it covers **1**.
   >
   > **Every cause present gets a line, not just the dominant one** — picking the biggest
   > bucket is the same mistake with better arithmetic, and would have prescribed against 9 of
   > 18 while still implying it covered the rest. **Two causes now say the reader cannot fix
   > them** (`unsupported-template`, `instance-method-shape`): naming a tool gap as a tool gap
   > beats prescribing work that cannot move the number.
   >
   > **An unrecognised detail is a reported case, never folded into a known bucket** — that
   > silent folding is exactly how the original tip read as true.
   >
   > **Two existing tests were pinning the defect and both are corrected.**
   > `ReportRendererTests` asserted the `gen()` tip appeared for a record with `detail: nil`,
   > and `ProveThenShowInteractionRenderTests` asserted it for a row declining with
   > `(non-Identifiable element)` — a shape problem a generator cannot fix. Both now assert
   > the tip is **absent** for those causes. Same shape as the road test's own *"each defect
   > pinned in place by a passing test that asserted the buggy behavior"*.
   >
   > Guarded by `UnverifiableCauseTests` (9 laws), including one that reads the **producer
   > sources** and fails if a `detail` prefix is renamed out from under the classifier — the
   > stated cost of parsing a human-readable string instead of adding a field to a persisted
   > format.

2. **TestLifter: zero cross-validation signals across 19 picks.**

   > **FIXED 2026-08-14 — two independent causes, either alone enough to hide it.** Both were
   > in the round-trip detector, and both made it blind to house style rather than to the law.
   >
   > **(a) The value reaches the second call through the RECEIVER.** `parse(x).serialized()`
   > is a method chain whose outer call takes **no arguments**, and the detector read
   > `arguments.first`. `FunctionCallExprSyntax.consumedValueExpression` falls back to the
   > member-access base *only when the argument list is empty*, so no existing match changes.
   > **(b) The input is `Self.sample`, a member access**, where both sides were required to be
   > `DeclReferenceExprSyntax`. Comparison is now over `stableValueReferenceText`.
   >
   > **A four-arm probe is what separated them** — one law, one body, four spellings — and it
   > is why the first fix alone would have read as a failure: after (a), `localLet` and
   > `propertyCheck` lifted while `staticMember` and `literal` still did not.
   >
   > | spelling | before | after (a) | after (a)+(b) |
   > |---|---|---|---|
   > | `let sample = …` | ✗ | ✓ | ✓ |
   > | `propertyCheck { }` | ✗ | ✓ | ✓ |
   > | `Self.sample` (**the witness**) | ✗ | ✗ | ✓ |
   > | `"literal"` | ✗ | ✗ | ✓ |
   >
   > **A/B against a same-day baseline built from `main` with only these files stashed**, so
   > the arms differ in nothing else: `SwiftFormatRuleStudioCore` **cross-validated 0 → 1**,
   > `round-trip` **50 → 70**, rows unchanged at 20. Controls: `SwiftInferCore` **8 → 8**
   > (no existing lift lost — the regression that mattered), `SwiftInferTemplates` and
   > `SwiftInferCLI` unchanged.
   >
   > **The precision mechanism is that a CALL is not a value reference.** Comparing raw
   > expression text would match `f(makeValue()).g() == makeValue()`, which states a law only
   > if `makeValue` is deterministic — and reporting that as corroboration would have the
   > lifter claim a codebase asserts a law it never wrote. References, literals and pure member
   > chains qualify; anything rooted in a call does not. Guarded by `RoundTripSpellingTests`,
   > whose rejection arms are the load-bearing half.
   >
   > **The §7.2 caveat still stands and is now sharper**: this repo's own road test drove that
   > test's creation, so a `+20` can mean *this codebase took our advice* rather than *this
   > codebase independently states this law*. `Artifacts.crossValidationOrigins` renders which
   > test corroborated, so a reader can discount it — the fix widens reach, it does not settle
   > what the signal means. `SwiftFormatConfigTests`
   states the top-scoring law byte-exactly —
   `#expect(SwiftFormatConfig.parse(Self.sample).serialized() == Self.sample)` — and the
   `round-trip` pick scores 50 from type-symmetry (+30), docstring (+15) and value-semantics
   (+5), with no `+20`. 24 test files, 2,553 lines, nothing lifted. (Measured on the runs
   taken *before* any verify evidence existed, so this is not the §4 veto.) The known blind
   spot is `propertyCheck`-shaped bodies; this subject shows the same silence on a plain
   `#expect` with a static-property input, which is the ordinary way a human writes it.

3. **A generator recipe from the wrong domain.** `rulesAlreadyPresent(_ name: String, kind:
   RuleDirectiveKind)` — a rule-name lookup — is issued a **path** collision generator:
   a four-symbol alphabet including `/`, the rationale *"any path contains its own
   ancestors"*, `Gen.element(of: ["a","b","c","/"])…map { "/" + $0.joined() }`, and the
   instruction to build the carrier with `.map { SwiftFormatConfig(currentPath: $0) }` **for a
   stored property that does not exist on that type**. The collision *advice* is sound and the
   `predicate` template is right that the carrier's own state must be drawn from the same
   alphabet; the recipe attached to it is canned for a different subject. A reader following
   it writes code that does not compile, against a law that is fine.

4. **Totality is name-gated, and the gate costs the best law in the package.**

   > **HALF FIXED 2026-08-13 — `HostileInputEntryPoints.resultNouns`. Read which half.**
   > The **totality** gate now admits `tokens(inLine:)`; the **conservation** law is untouched
   > and remains a catalog gap.
   >
   > Isolated first: a probe with four spellings of one body showed `tokenize(line:)` and
   > `parse(_:)` admit while `tokens(inLine:)` and `tokens(inSource:)` do not — same type,
   > same docstring, same body, only the leading name token differing.
   >
   > **The obvious fix was measured and rejected.** Adding `tokens` to `interpretationVerbs`
   > scores **50%**: across eight corpora there are exactly four `func tokens(`, two take a
   > text carrier, and one of those is Harmonize's `tokens(startingWith: String) -> [Token]`,
   > whose `String` is a **filter prefix, not a payload** — the *"a bare `String` is far more
   > often a name than a payload"* case the type's own header warns about. 50% is the bar
   > `same-name-differential-pairing.md` froze and then rejected a rule at 40% under.
   >
   > So the noun route is **stricter than the verb route**: a verb asserts interpretation and
   > needs only the absence of a location label, while a noun only describes the return value
   > and additionally requires a **positive content label**. That separates the two witnesses
   > cleanly — `inLine` is content, `startingWith` is a predicate — and needed one supporting
   > change, stripping a leading preposition so `inLine` and `line` classify alike.
   >
   > **Agent-nouns are excluded and that is the rule, not an omission**: `tokens` names what
   > comes *out*; `parser`/`decoder`/`lexer` name a thing that *does* the work, so a function
   > called `parser(...)` is a factory that interprets nothing.
   >
   > **A/B, two binaries, same afternoon, four corpora:** SwiftFormatRuleStudioCore
   > **19 → 20 rows** (totality 6 → 7, the witness); `SwiftInferCore` 156/3,
   > `SwiftInferTemplates` 136/0, `SwiftInferCLI` 198/11 — **all unchanged, and 0 score lines
   > differ** on any control, which is the check that matters since the label change touches
   > the verb route too.
   >
   > **Honest bound: population is 1.** This is a correctness fix for a shape the catalog
   > already intends to cover, **not a recall win** — it moves exactly one row across eight
   > corpora, and a rule fitted to a single witness is what `maximumZipNesting`'s comment warns
   > about. What justifies it is that the rejected-alternative measurement is real and the
   > rejection arms are guarded (`ResultNounAdmissionTests`, 11 laws, most of them asserting
   > NON-admission).
   >
   > **One defect shipped and was caught in the A/B**: the new row first rendered *"`tokens`
   > leads with the interpretation verb `tokens`"* — false, it is a noun. The two routes now
   > render different reasons, which is the same misattribution class as §5.1 and the
   > kit-suite banner.
   `input-totality` fires on all four `parse(_:)` functions and **not** on
   `SwiftCodeTokenizer.tokens(inLine: String) -> [Token]` — same `String -> structure` shape,
   different verb. The tokenizer also owes a conservation law,
   `tokens(inLine: l).map(\.text).joined() == l`, which catches any dropped or duplicated
   character and which nothing else in the suite checks. It is proposed by no template and
   does not even reach the docstring-fallback list. Same shape as the `commutativity`
   name gate in `fixtures/planted-defect-arm`.

5. **The mutating editors are invisible.** `setOption`, `removeOption`, `disableRule`,
   `enableRule`, `clearRuleOverride` — five textbook `idempotence-lifted` subjects on a
   value-semantic carrier, with `enable`/`disable`/`clear` forming an obvious inverse triple —
   produce **zero rows** and appear nowhere, not in the suggestions and not in the fallback
   list. `addRule`/`removeOption(key:)` draw a `state-machine` row each, both Advisory, and
   both then decline as `private`.

6. **6 of 19 picks decline because the subject is `private`.** The tool proposes, scores,
   renders and indexes a law, then reports at verify time that no test can call it. The
   message is good (it names the one-keyword remedy); the ordering wastes a sixth of the run,
   and visibility is knowable at discovery.

7. **The interaction default surface is empty.** 4 candidates found on 5 `@Observable` view
   models; `discover-interaction` prints *"0 interaction-invariant suggestions shown (4 at
   .possible tier hidden)"*. For an app developer — the audience of that surface — the first
   run of the command aimed at their code shows nothing.

**Operational:** `verify --all-from-index` left **549 MB** in
`SwiftFormatRuleStudioCore/.swiftinfer/verify-workdir/` for 19 entries of which 1 ran, and
`.swiftinfer/` is **not** in that project's `.gitignore`, so it lands in `git status` as an
untracked directory. Removed after the run; the repo is as found.

---

## 6. The hand list, scored

Written before any tool run. Not an answer key — a check on silence.

| # | law | outcome |
|---|---|---|
| 1 | `parse(serialized(c)) == c` | **hit**, `round-trip` 50 |
| 2 | `serialized(parse(t)) == t` | **hit** — and this is the one that **refuted** (§3) |
| 3–8 | `setOption`/`removeOption`/`disableRule`/`enableRule`/`clearRuleOverride` idempotence + inverses | **miss** (§5.5) |
| 9 | `commandLineArguments` structural invariant | miss |
| 10–13 | `filteredRules` subset / case-insensitivity / trim / monotone in `includeDeprecated` | **no template**, but named by the docstring fallback |
| 14–16 | `groupedRules` conservation / no empty group / sorted | **no template**, named by the docstring fallback |
| 17 | tokenizer conservation | **miss**, and it is the strongest law here (§5.4) |
| 18 | `parse(_:)` totality ×4 | **hit** ×4 |
| 19 | `category(for:)` totality | miss |
| 20 | `OptionRuleUsage` inverse relation | **withdrawn by me before running** — `optionKeysByRule` is derived from `rulesByOptionKey` in a static initializer, so it is true by construction and unrefutable. Recorded because predicting it from the signature and withdrawing it on reading the body is the same error the tool is scored against |

**The best output on this corpus is the part that admits defeat.** The docstring-fallback
section — *"the templates could offer only a determinism tautology here; your docstring is the
one refutable contract"* — caught 19 subjects including `filteredRules` and `groupedRules`,
and quoted back the sentences (*"case-insensitively"*, *"each group's rules sorted by name …
empty groups are omitted"*) that are precisely hand-list items 10–16. It reached the right
laws by declining to name them. Both predicted instrument problems (§6 of the pre-run list)
held: the MainActor collision, and the metamorphic statability gap.
