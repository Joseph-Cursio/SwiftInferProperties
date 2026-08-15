# SwiftProjectLint — the entry point

> **Status:** `reference` · **As of:** 2026-08-15


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
> **Fourth pass, same day — and it was the consumer that had moved, not the subject.** Subject
> unchanged at `08a4b09`; observer is an uncommitted working tree on `b41a3bd`. Reading this doc
> end to end surfaced three consumer-side defects, all in the same class — **fields the producer
> sends that this repo does not act on** — and all three are now closed. `restriction` was not
> decoded at all (§ *Every field*), `rule` was decoded and read by nothing, and the access question
> `restriction` answers was being answered *wrongly* by this repo's own scanner.
>
> **Fifth pass, also the same day, and this one corrected the doc rather than the code.** Filing the
> residue upstream meant re-verifying it first, and **two of the four claims did not survive
> contact**. The catalogue section's *"10 enum cases are declared but never registered"* is an
> artifact of scanning one package of three — the residue is **zero** — and the category table was
> missing an entire category (`idempotency`, 7 rules) that contains one of the four **seeding** rules.
> Both are corrected in place with the wrong figure kept visible, because the wrong figure is what
> the obvious arithmetic gives. The two claims that held are filed as
> [#74](https://github.com/Joseph-Cursio/SwiftProjectLint/issues/74) and
> [#75](https://github.com/Joseph-Cursio/SwiftProjectLint/issues/75); the retraction became
> [#73](https://github.com/Joseph-Cursio/SwiftProjectLint/issues/73) and the §1b argument
> [#76](https://github.com/Joseph-Cursio/SwiftProjectLint/issues/76).
>
> The moral is narrower than "check your numbers": **a count is a claim about a scope, and this doc
> kept stating the count without the scope.** 192 was always true *of `SwiftProjectLintRules`*. It
> was the subtraction that was fiction.
>
> **Sixth pass — `anchor` (§ *The effect tier*), which landed upstream mid-edit and is now read.**
> It discharges a request `SeedEffect`'s own doc had written down (*"the fix is on the producer:
> track anchor purity …"*), and building it exposed two defects here, both found by running rather
> than reading: the parity guard did not open nested objects, and widening the rule made a latent
> bare-symbol join reachable, which applied 5 effects for 3 seeds. Subject now `db4be6b6`.
>
> **Seventh pass, 2026-08-15 — counts re-verified against `e06e39fc`, and the headline is that the
> subject closed all four filed issues and the doc did not notice.** #73/#74/#75/#76 are CLOSED.
> Two of them landed *guards*, which changes how this section should be read: the catalogue's
> residue arithmetic is no longer this doc's job, because `RuleRegistrationResidualTests` now
> asserts it against the **live registry** and `READMERuleCountTests` asserts the README against
> `RuleIdentifier.selectableRules`. Both are green at `e06e39fc`. **Prefer them to any count
> written here** — a grep answers *is this identifier mentioned somewhere*, which was never the
> question.
>
> **Three claims did not survive contact, and only one of them is drift.**
>
> *(a) Not drift — wrong when written.* The counting-method note said **six** `.unknown`
> placeholders in three files. There were **eight, in six files**, at `d59cd782` as well, and one
> of them (`BasePatternVisitor.placeholderPattern`) is **production**, not a test-only convenience
> init — it is the placeholder cross-file visitors hold before their pattern is set. The 192 did
> not depend on it (that figure came from *distinct* values, not occurrences), which is why the
> error survived three passes.
>
> *(b) `onTapGestureMissingAccessibility` was a REAL DEFECT and this doc recorded it as an
> arrangement.* The residue note said it *"**is** emitted — at `OnTapGestureInsteadOfButtonVisitor.swift:97`,
> via `ruleName:`"*, and treated that as the third special case that made the arithmetic come out
> to zero. It was emitted and then **filtered out of its own visitor's output** by
> `SourcePatternDetector.runVisitors`, because a rule with no registered pattern never survives
> that filter — so it never fired on a default run. Upstream found it by writing the reason down:
> it was the single entry in `unregisteredByDesign`, and the *"no exception is stale"* arm forced
> it to be fixed rather than excused. It now has a pattern and the exception list is **empty**.
> **The lesson is the one this doc keeps paying for: a plausible sentence about why a count works
> out is not a check.** Three passes tuned the arithmetic; none asked whether the rule ran.
>
> *(c) The effect-tier demotion has silently stopped firing here.* The sixth pass measured **3
> idempotency seeds carrying `anchor: declaration`**, two at `depth: 5`, and called it *"the first
> time anything in this repository has been demoted on linter-resolved evidence."* Re-measured
> against `e06e39fc`: the same three seeds, same symbols, same depths — and all three now carry
> **`anchor: heuristic`**. `carriesEnoughEvidenceToDemote` excludes `.heuristic` by design, so the
> demotion is correctly not applied and the capability is now **unexercised on this corpus**.
> Nothing is broken on either side; the producer reclassified. Worth knowing because a feature
> that stops firing looks exactly like a feature that was never wired.
>
> **And the biggest change is a decline this doc argued against, which then shipped.** §1b's
> *"none of these three rules seed"* is false: the domain-type family seeds as a new
> `carrier` kind, and **both sides already handle it**. See §1b.
>
> **What the first pass got wrong, and how it was caught.** This doc was written against
> `6c88715` — a local checkout that turned out to be **46 commits behind its origin**. Two counts
> were stale within hours (`RuleIdentifier` 197 → 202, the testability family 7 → 9), and
> `make docs-drift` reported `ok` throughout, because it compared against local `HEAD` rather than
> the project. Both the checker and these numbers are fixed; the episode is why the checker now
> resolves a project tip and reports a behind-by-N clone as its own fact.

<!-- doc-provenance date=2026-08-15 subject=SwiftProjectLint@e06e39fc observer=SwiftInferProperties@392fb2a -->

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
| **2** | **Say where to point the next tool** — `{file, line, symbol, rule, kind}` required, `{role, restriction, effect}` optional | `--format pbt-seeds` JSON | `swift-infer discover --seeds`, and **only** that |

The two jobs are not independent, and the direction is the interesting part: **job 1's output
becomes job 2's input on the next run.** A kernel you extract this week is a named, analysable
symbol next week. That loop is the whole reason the linter sits upstream rather than beside.

It never says whether a property *holds*. It says where to look and what to fix.

### In and out, precisely

| | what | shape |
|---|---|---|
| **consumes** | a directory of Swift source | files on disk, parsed with SwiftSyntax; no build, no run, no network |
| | `.swiftprojectlint.yml` (optional) | severity overrides, category and rule enable/disable |
| | `--target-type auto\|app\|library` | **new 2026-08-14** — the caller states what auto-detection cannot |
| | `--include-nested-packages` | off by default; a nested first-party package is **skipped and said so on stderr** |
| | **SwiftEffectInference**, in-process | the purity oracle — a library dependency, not a CLI hop |
| **produces (1)** | the human report | `text` (default, collapses candidates) · `json` · `csv` — for a person |
| **produces (2)** | the seed manifest | `--format pbt-seeds` → JSON v2 — for `swift-infer discover --seeds`, and nothing else |
| | dropped-seed tally | **stderr**, so stdout stays a clean manifest |
| | exit code | severity-gated — except under `pbt-seeds`, which always exits 0 |

The two output channels are computed from **one** `issues` array. That is why disabling a noisy rule
to tidy the report also empties the manifest, and why the candidate flood is fixed in presentation
rather than detection (§ *The census flood*).

> **Two input knobs added 2026-08-14, and both change what a manifest means.**
>
> **`--target-type auto|app|library`.** A few rules assume the single-target app model —
> `publicInAppTarget` most clearly, where *"in an app a `public` declaration is over-exposure …
> in a library `public` IS the API."* The old sniff looked for a `Package.swift` beside the
> analysed path and answered "app" for everything else, including a framework target in an Xcode
> project (no manifest at all) and a package linted from a subdirectory (manifest further up).
> Both are libraries that do not look like one from the path handed in. **This matters here
> because access level is what the `restricted-function` demotion turns on**, and a subject linted
> as the wrong target type gets a different `public` story.
>
> **`--include-nested-packages`, off by default.** A nested first-party package is skipped, and
> the CLI says so on **stderr**: *"Cross-file rules (e.g. architecture and protocol checks) cannot
> span the package boundary."* Quote the flag with any seed count taken from a repo that has
> nested packages — the default is a **narrower** scan than a reader will assume, and every seed
> figure in this doc was taken with it off.

---

## The rule catalogue, and how little of it is about properties

`RuleIdentifier` has **204** cases, and **every one is accounted for**: **202** live rules and 2
deliberate sentinels.

> **2026-08-15 — and the count is no longer this doc's to keep.** +1 since the last pass:
> `.navigationButtonShouldBeLink`, which lands in `accessibility` (taking that family to 21).
> Upstream now vends the distinction as API — **`RuleIdentifier.selectableRules`** (`allCases`
> minus `RuleIdentifier.sentinels`), written because the definition of "a rule" was being
> re-derived by an inline `subtracting` at each site, *"which meant … the count in the README
> could disagree with the code without anything noticing — it did, by roughly a quarter."*
>
> **Read `selectableRules.count`. Do not count anything by hand.** Two suites assert it against
> the tree and both are green at `e06e39fc` (run 2026-08-15, 7 tests, 2 suites):
> `RuleRegistrationResidualTests` — every selectable rule is registered *exactly once* in the
> registry `PatternRegistryFactory.createConfiguredSystem()` builds, no sentinel is registered,
> and the documented-exception list is **empty and asserted non-stale** — and
> `READMERuleCountTests`, which scans the README for the *pattern* rather than fixed lines so a
> fifth mention is covered without editing the test.
>
> **2026-08-12 (superseded, kept for the reasoning):** +1 for `.unreachableEffectClosure`
> (`testability` → 10). The distinct-`name:` figures below were left at their 2026-08-06 values
> deliberately, on the argument that re-running a grep with a different pattern replaces a
> measured number with an incomparable one. That argument was sound and is now moot: the
> registry test answers the question the greps were approximating, and answers a *stricter*
> version of it (see the residue note).

> **This section said "10 enum cases are declared but never registered" until 2026-08-06, and that
> was wrong.** It compared 202 against the **192** registered in `SwiftProjectLintRules` and read the
> difference as a residue. The difference is two other places the count never looked:
> `SwiftProjectLintIdempotencyRules` registers 7 more (including `.idempotencyViolation`, one of the
> four **seeding** rules), and `Sources/` supplies the rest, some identifiers appearing in more than
> one package. Distinct total referenced as `name:` across every package: **199**.
>
> The remaining three are not a gap either. `unknown` and `fileParsingError` are sentinels the config
> layer subtracts by name (`LintConfiguration.swift:164`, and again in `ContentViewModel.swift:178`),
> so they are deliberately not rules. `onTapGestureMissingAccessibility` **is** emitted — at
> `OnTapGestureInsteadOfButtonVisitor.swift:97`, via `ruleName:` rather than `name:`, because one
> visitor raises two findings. So: 199 + 1 + 2 = 202, residue **zero**.
>
> Measured across all packages at `d59cd782`. The lesson is the one this doc keeps relearning about
> the subject's counts — **a census that scans one package reports the other packages as a defect**,
> which is the same shape as the road test that invented a carrier problem two-thirds of which was
> the harness. Filed upstream as
> [#73](https://github.com/Joseph-Cursio/SwiftProjectLint/issues/73), *with the false alarm as the
> argument for the test*: nothing records this result, so the obvious arithmetic reproduces it.

> **2026-08-15 — #73 is CLOSED, the residue is asserted rather than argued, and the third special
> case above was a DEFECT.** `RuleRegistrationResidualTests` checks every selectable rule against
> the registry `PatternRegistryFactory.createConfiguredSystem()` builds, which is the registry the
> CLI runs. That is strictly stronger than the arithmetic this section reached for, and its own
> header says why: *"an identifier can be mentioned in a registrar that is never wired into a
> category, and would then pass a textual check while reaching no analysis."*
>
> **Which is exactly what `onTapGestureMissingAccessibility` was doing.** The paragraph above
> reports it as emitted-via-`ruleName:`, one of three special cases that made the residue come out
> to zero. It was emitted and then **dropped**: `SourcePatternDetector.runVisitors` filters a
> visitor's findings against the registered patterns, and this rule had none, so it **never fired
> on a default run**. It was the sole entry in the new test's `unregisteredByDesign` map, and the
> *"no exception is stale"* arm is what forced it to be fixed rather than left as a written excuse.
> It now has its own pattern; the map is **empty**. Re-verified at `e06e39fc`: `ruleName:` is used
> by 175 identifiers and **none of them is reachable only that way**.
>
> So the current arithmetic is 204 = 202 registered + 2 sentinels — but **quote the test, not the
> sum.** The sum was right three times while a rule sat dead behind it.

What has changed since: **the enum and the registry are now asserted to agree** (2026-08-15). This
section previously closed on *"nothing asserts the enum and the registry agree — the catalogue
happens to be healthy; no test says so."* Something says so now, and it found a dead rule on its
first run.

> **Counting method — superseded 2026-08-15, and kept because a reader will still reach for a
> grep.** Re-measured at `e06e39fc` over **git-tracked files only**: `category: \.` returns
> **222**, `name: \.` returns 218 occurrences across **204** distinct values, 203 after dropping
> `.unknown`. (The 2026-08-06 figures were 195 / 198 / 193 / 192.) All four still overcount or
> mislead, for the same reason, and none of them is the registry.
>
> **First trap: `.build`.** The obvious `grep -r … Packages Sources` sweeps vendored
> **swift-syntax checkouts**, which contribute **786 of 1,112** `name: \.` hits and answer a
> question about somebody else's parser. Use `git ls-files`.
>
> **Second trap, and this doc fell into it: the placeholder count was wrong when written.** The
> note said **six** `SyntaxPattern(name: .unknown, …)` placeholders in **test-only convenience
> initializers** (`MagicNumberVisitor`, `HardcodedStringVisitor`, `MemoryManagementVisitor`).
> There are **eight, in six files** — add `AccessibilityVisitor`, `DocumentationVisitor` and
> **two** in `BasePatternVisitor` — and it was eight at `d59cd782` too, so this is an error, not
> drift. **One of them is not test-only:** `BasePatternVisitor.placeholderPattern` is a production
> `static let`, *"used for cross-file visitors that set their pattern after initialization."*
>
> The 192 was nevertheless right, because it came from *distinct values* and every one of the
> eight spells `.unknown`. **That is why the error survived three passes** — an occurrence count
> stated beside a distinct count, where only the distinct count was load-bearing.

| category | rules | anything for property inference? |
|---|---|---|
| `codeQuality` | 52 | incidental — `couldBePrivateMember` **fights** the pipeline (§ 1a) |
| `architecture` | 32 | **3 rules** — the domain-type family (§ 1b), **all three of which now SEED** |
| `modernization` | 25 | no |
| `accessibility` | **21** | no |
| `performance` | 14 | no |
| `stateManagement` | 13 | `Missing Equatable on State Type` is a blocker (§ 1c) |
| `animation` | 10 | no |
| `testability` | **10** | **the family** — candidates, kernels, blockers (§ 1a, § 1c) |
| `uiPatterns` | 7 | no |
| **`idempotency`** | **7** | **1 rule — `.idempotencyViolation`, and it SEEDS** |
| `security` | 5 | no |
| `memoryManagement` | 3 | no |
| `networking` | 3 | no |
| `other` | 2 | the two sentinels — not rules |
| **total** | **204** | **~12 rules, 7 of which seed** |

> **2026-08-15:** re-derived over all 204 cases at `e06e39fc` by parsing the `category` switch, so
> it still partitions by construction — **204 distinct, no case classified twice, none missing**.
> Only two cells moved: `accessibility` 20 → **21** (`.navigationButtonShouldBeLink`) and the
> total. The seeding figure moved for a different reason and is the bigger change: **4 → 7**, the
> domain-type family having shipped as `carrier` seeds (§ 1b). Upstream's own
> `READMERuleCountTests` asserts this same table against the README, so a third copy of it now
> exists that cannot silently disagree.

> **This table was 12 rows totalling 192 until 2026-08-06, and the missing row held a seeding
> rule.** `idempotency` is a whole category the census never had, because the census scanned
> `SwiftProjectLintRules` and that package does not contain it — so a table whose stated job is *how
> little of this catalogue is about properties* omitted one of the four rules that actually reach the
> manifest. `accessibility` moved 19 → 20 for the `ruleName:`-emitted rule above. Read off
> `RuleIdentifier+Category.swift` over all 202 cases at `d59cd782`, so it partitions by construction
> rather than by summing what a grep found.

**The ratio is the point, and correcting the table did not move it.** Roughly 6% of the catalogue is
upstream of property inference, and only **seven** rules reach the manifest at all (four until
2026-08-12). Everything else is a SwiftUI architecture linter that happens to ship in the same
binary. A reader who assumes "202 rules feed `swift-infer`" will mis-estimate both the coverage and
the flood; the correct mental model is a large linter with a small deliberate seam cut into it.

`--categories testability` selects the 10, which is **not** the same set as the 4 that seed — two of
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

The third is the valuable one and the reason this family exists. `SwiftProjectLint/Docs/rules/extractable-pure-kernel.md`
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

> **From the consumer side, 2026-08-06: the stated blocker does not hold.** *"No callable function
> attached"* assumes this tool's subject is always a function. It is not — `CodableRoundTripTemplate`,
> `FunctorIdentityTemplate`, `ModelLawTemplate`, `SequenceViewModelLawTemplate` and the whole of
> `verify-value-semantics` state laws over a **carrier**, and a newtype is a carrier that owes some.
> That is the argument §1b already makes in its own last paragraph (*"the refactor turns a value with
> no laws into a type that owes some"*), which the decline then contradicts.
>
> The real blocker is narrower and is on this side: **`SeedFocus` joins on function evidence**
> (`Evidence.displayName`, a function name with parameter labels), so a `carrier` kind would decode
> and then match nothing. That is a join change here, not a schema problem there — and it is worth
> saying which of the two repos the work actually lands in before the decision is re-litigated.
> Filed as [#76](https://github.com/Joseph-Cursio/SwiftProjectLint/issues/76).

> **SHIPPED — #76 is CLOSED, on both sides, and the paragraph above is now wrong in its
> conclusion while right in its analysis.** Verified 2026-08-15.
>
> Producer: `PBTSeedsFormatter.seedKinds` maps **seven** rules, the three new ones being the
> domain-type family, all to a fifth kind `PBTSeedKind.carrier` (`9dbc335d`, *"Seed the domain-type
> rules as carrier seeds"*). **Their `symbol` is a type name, not a function name** — which is
> precisely the join problem the consumer-side note predicted, addressed rather than dodged.
>
> Consumer: `SeedManifest.SeedKind` has `case carrier` with `isAnalysable == true`, and `SeedFocus`
> resolves it — *"a `carrier` seed joins on the type name alone, deliberately unscoped by file"* —
> with `SeedFocusCarrierTests` covering it. So the join change landed here, in the repo the note
> correctly said owned it.
>
> **No schema bump, and the producer's reasoning names this consumer by symbol.** Its docstring:
> *"a consumer built before this case decodes it as unrecognised and skips it loudly —
> `SwiftInferProperties.SeedKind` has an explicit `case unrecognised(String)` with
> `isAnalysable == false`, chosen because guessing 'analysable' for an unknown kind is"* the wrong
> default. That is the v1 → v2 argument reused for an additive change: an old consumer degrades to
> exactly its pre-`carrier` behaviour, which is all a version bump would have bought.
>
> **What this doc got right and wrong.** Right: the stated blocker (*"no callable function
> attached"*) did not hold, the templates state laws over carriers, and the real work was a join on
> this side. Wrong: the framing *"whether these should seed is **open**, not decided"* outlived the
> decision by three days, and the seed count in the catalogue table went stale with it — the
> summary-drift shape again, in the section that argued for the change.

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
and a seed without it is byte-identical to one written before. Re-measured 2026-08-06 at `08a4b09`:
**15 of 662** on SwiftInferProperties, the same shape.

> **Re-measured 2026-08-15 at `e06e39fc`, and the shape is stable across a year's worth of rule
> churn:** **27 of 349** restricted seeds on SwiftProjectLint (7.7% — the numerator is unchanged
> and the denominator grew by 11) and **17 of 701** on SwiftInferProperties (2.4%). Both runs are
> the shipped CLI against the repo root, default flags. The stable numerator on the subject is
> worth noting: `enclosing-type` tracks how many `private` *types* hold pure helpers, which does
> not move when rules are added.

**That paragraph turned out to be a prediction, and it was right about this repo.** *"A consumer
acting on the kind alone can emit a patch that unblocks nothing"* is not hypothetical —
`SpeculativeWidening` was doing exactly that, for a reason the field would have named. See below.

### Every field, and who may rely on it

| field | required | values | consumer use |
|---|---|---|---|
| `file` | ✅ | path as walked | **focus key**, with `symbol` |
| `line` | ✅ | 1-based | reported to the reader; **not** matched on |
| `symbol` | ✅ | resolved name | **focus key**, with `file` |
| `rule` | ✅ | rule display name | names the rule in the unrecognised-`kind` warning |
| `kind` | ✅ | 4 cases, below | decides whether the seed may focus at all |
| `role` | — | 6 cases | decides what law is *owed* |
| `restriction` | — | `declaration` · `enclosing-type` | names what must move to verify — **corrects the remedy this repo renders** |
| `effect` | — | object, below | `idempotency` seeds only; read since `f33dfd1` |

**Two of those "consumer use" cells were aspirational until 2026-08-06** — they described what the
field was *for*, and this repo did neither. `rule` was optional here, decoded, stored, and read by
nothing; `restriction` was **not decoded at all**. Both are fixed, and the second one had already
cost something. See § *The three fields this consumer was not reading*.

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

> **`anchor` (upstream `a5795819`, merged `db4be6b6`, 2026-08-06) — landed mid-edit and is now
> READ.** A fourth sub-field on `effect`, `declaration` | `heuristic`, present only for
> `inferred-upward`. Its own doc names this repo as the reason it exists — *"a consumer reading
> provenance alone had to withhold every upward tier, which SwiftInferProperties did, keeping only
> the direct-callee case. This field separates the two"* — and `SeedEffect`'s doc had already asked
> for it in as many words: *"The fix is on the producer: track anchor purity … Until then the honest
> reading of an upward tier is a caveat, not a score."* That "until then" expired the same day.
>
> `carriesEnoughEvidenceToDemote` now admits `inferredUpward` **when `anchor == .declaration`**.
> `.heuristic` stays excluded (the `save` failure, by the producer's own admission) and so does a
> **nil** anchor on an upward tier — a producer that did not say is not a producer that said
> `declaration`, and absent-means-guess is the one default that turns a missing field into a score.
>
> Measured on this repo: **3 idempotency seeds carry `anchor: declaration`**, two of them at
> `depth: 5` — five hops, which `EffectResolver`'s one-hop local pass structurally cannot see inside
> §13's 2-second ceiling. That is the case the field was built for, and it is the first time
> anything in this repository has been demoted on linter-resolved evidence.
>
> > **Re-measured 2026-08-15 at `e06e39fc`: the anchor flipped, and the demotion has stopped
> > firing here.** The same 3 idempotency seeds are present — same symbol (`record`), same files
> > (`VerifyCorpusStore.swift`, `VerifyEvidenceRecorder.swift` ×2), same depths (5, 5, 3), same
> > `declared: idempotent` / `resolved: non_idempotent` / `provenance: inferred-upward` — and all
> > three now say **`anchor: heuristic`**, where the sixth pass measured `declaration`.
> >
> > **Nothing is broken on either side.** `carriesEnoughEvidenceToDemote` excludes `.heuristic`
> > deliberately (the `save` failure, by the producer's own admission), so the correct behaviour is
> > to withhold, and it does. What changed is upstream's classification of the anchoring
> > declaration, not this repo's reading of it.
> >
> > **Record it because the capability is now unexercised, and that is the state this doc exists to
> > catch.** *"The first time anything in this repository has been demoted on linter-resolved
> > evidence"* was true when written and is not true today; the plumbing is live, the population is
> > zero. A feature that stopped firing is indistinguishable from one that was never wired — which
> > is the §3.6 valid-sequence shape, and the reason `anchor` was worth measuring rather than
> > assuming. **The three seeds are the standing witness: if any of them returns to
> > `anchor: declaration`, the demotion should reappear, and if it does not, that is a defect
> > here.**
>
> **Two defects fell out of building it, and both were found by running rather than reading.**
>
> First: the parity guard did not reach nested objects. `SeedFieldParity` enumerated `Seed`'s keys,
> `effect` was one key, and its sub-object was never opened — so `anchor` was silent here for
> exactly the reason `restriction` had been silent three days earlier, hours after the guard meant
> to end that. It now carries `knownNestedFields`, keyed by holder rather than flattened (a flat set
> would let a field added to the *wrong* object pass), plus a source arm reading `PBTSeedEffect`
> directly. Proven by control: removing `anchor` from the known set fails and names it.
>
> Second, and worse: **widening the rule made a latent precision defect reachable.**
> `SeedEffectResolver` joined on the bare symbol name. Nothing here had ever carried a
> `declared`-provenance effect, so nothing was applied and the looseness cost nothing — admitting
> anchored upward chains applied 3 seeds and the run reported **5**. The extra two were functions
> merely *named* `record` (`ViewModelVerifyEvidence`, `RefactorBridgeAccumulator`) inheriting a tier
> resolved for a different function in a different file: a **false demotion**, in a codebase where
> `record` / `resolve` / `apply` are everywhere. Now keyed `(file basename, symbol)` like
> `SeedFocus` and `SeedRestrictionResolver`; 5 → 2. **The count in the diagnostic is what caught it**
> — it did not match the number of seeds — which is the argument for reporting counts at all.

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

### The three fields this consumer was not reading

Written 2026-08-06, from the consumer side, after this doc's own field table was checked against
`SeedManifest.swift` instead of being believed.

**The class of defect is one thing, not three: `Codable` ignores unknown keys.** A producer *adding*
a field is invisible here — no error, no warning, no changed output. That is the mirror image of the
silent `kind` default the v1 → v2 bump exists to delete, and silent in the same direction. There was
no test that could have failed.

| field | what was wrong | what it cost |
|---|---|---|
| `restriction` | not decoded at all, 2026-08-03 → 08-06 | the remedy this repo prints was wrong for a whole shape, and a patch generator acted on it |
| `rule` | optional here, non-optional upstream; **read by nothing** | warnings could not name the rule; the "attribution" cell above was fiction |
| `effect` | (already closed by `f33dfd1`) | — |

**`restriction` is the expensive one, and the cost was not the missing field.** This repo answers
the same access question locally, in `FunctionScanner.accessRestriction` — and it was answering it
wrongly. The declaration's own `private` was tested *before* anything about the enclosing type, so
a `private` member of a `private` type came back `.notVisibleToTests`, which is the one **widenable**
answer. `SpeculativeWidening` would then snapshot the package to delete a keyword that exposes
nothing and report `"widening X exposed the symbol but no template proposed a law — the TEMPLATE
gate decides this"` — both halves false, a patch failure attributed to the catalogue.

Its own doc claimed that case was excluded, via `.nestedLocal`, which is a different shape (a
function inside another *body*). Nothing produced the case being described, and the test asserted
the exclusion **using that same wrong case**, so it passed green over an unguarded trap. *A doc
asserting a guard is not a guard.*

Measured over this repo's `Sources/`: **83 of 963 set-aside rows carried the wrong reason** — 15
were genuine bogus widening candidates, 68 were never widenable but were told *"a same-package test
target using `@testable import` can call it"*, which is false for a `private` enclosing type.
Membership did not move: 877+15 / 68+1 / 2 reconstructs the same 963, so no suggestion appeared or
disappeared. Only the advice changed.

**What the field is worth now that the local bug is fixed: on this corpus, nothing — and that is
the honest reading.** Against the live manifest, 659 rows matched, **659 agree, 0 corrected, 0
disagreements**. The local classifier now reaches the producer's conclusion independently for every
directly nested case. What the field still covers is the residual blind spot: the enclosing-type
stack is **same-declaration only**, so a member of an unmarked `extension PrivateType { … }` reads
locally as blocked by its own modifier, and resolving that needs the type's declaration, which may
be visited later or live in another file. This repo contains no instance of it.

So the field's live contribution is a **cross-check that passes**, plus a case the local analysis
structurally cannot reach. Before the local fix the same measurement would have shown 15
corrections — derived from the classification split, not re-run.

Two design notes worth keeping, both about not over-trusting the manifest:

- **Only one direction of disagreement is arbitrated.** Manifest `enclosing-type` + local
  `.notVisibleToTests` → the manifest wins, because that pair has a known structural cause.
  Preferring the manifest wholesale would let a stale seed overrule a syntactic reading of the
  declaration in front of us, and the failure would be invisible, because both answers are
  plausible sentences about access. Everything else is *reported* — one aggregate line, the
  `ProtocolCoverageAudit` shape — because two tools disagreeing without saying so is exactly how
  `restricted-function` went wrong the first time.
- **Reconciled once, at the scan.** Three places turn an `AccessRestriction` into advice, and
  fixing the one in front of you is how the original defect's computed-property arm nearly outlived
  its own fix.

**A second bug fell out of the first.** The rescued suggestion's caveat ended every remedy with
*"and it is one keyword"* — true of exactly one of the four restrictions. That clause is what makes
a reader act now rather than later, so attaching it to a refactor that is not one keyword spends
the credibility the caveat exists to build.

**The guard.** `SeedFieldParity` derives the read-field set from the coding keys, and
`SeedFieldParityTests` compares it to what a *real* producer emits, two arms:
`SwiftInferProperties/fixtures/seed-manifest-parity/seeds.json` (real output at `08a4b09`, one seed per shape, nine
shapes covering all eight fields — always runs, and **cannot catch a field added after capture**),
plus a read of `PBTSeed`'s stored properties out of a sibling `../SwiftProjectLint` checkout (cannot
go stale, does not run without the sibling). Verified by control: injecting a `confidence` key made
both arms fail and name it.

**`rule` is now required and read.** The producer's field is non-optional and 0 of 2,099 measured
seeds lacked it, so absence means a malformed document, not an honest unknown. It is read in the
unrecognised-`kind` warning: *"kind 'x' is unrecognised"* tells a reader to upgrade, while naming
the rule tells them which half of the producer moved.

### The seven seeding rules

```swift
static let seedKinds: [RuleIdentifier: PBTSeedKind] = [
    .pureFunctionCandidate:  .pureFunction,
    .idempotencyViolation:   .idempotency,
    .extractablePureKernel:  .extractableKernel,
    .pureClosureCandidate:   .extractableKernel,
    // The domain-type family. Their symbol is a type name — see `PBTSeedKind.carrier`.
    .primitiveBypassingItsDomainType: .carrier,
    .primitiveNamedForItsDomainType:  .carrier,
    .sharedDomainEnumField:           .carrier
]
```

> **This section was headed "The four seeding rules" until 2026-08-15.** The bottom three landed
> with `9dbc335d` and are §1b's decline, reversed — see the banner there. The count matters beyond
> bookkeeping: *"`PBTSeedsFormatter.seedKinds` maps exactly four rules"* is quoted twice more in
> this doc as the reason the domain-type family is invisible to the pipeline.

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

**`kind` — analysable vs refactor-pending.** **Five** cases produced, **six** recognised
(2026-08-15; four and five before `carrier`):

| kind | produced by | `isAnalysable` | what it means |
|---|---|---|---|
| `pure-function` | `.pureFunctionCandidate` | ✅ | pure and total; index it, propose laws |
| `idempotency` | `.idempotencyViolation` | ✅ | arrives with a ready-made property to verify |
| `restricted-function` | *demotion* of `pure-function` | ✅ | named and analysable; `private`, so not *verifiable* cross-module |
| **`carrier`** | the three domain-type rules (§ 1b) | ✅ | **`symbol` is a TYPE name, not a function** — joins unscoped by file |
| `extractable-kernel` | `.extractablePureKernel`, `.pureClosureCandidate` | ❌ | the logic has no name yet; `symbol` is the **enclosing** function |
| `unrecognised(_)` | — *consumer-side only* | ❌ | a spelling this consumer does not know; fails loudly, never silently |

> **`carrier` is the one kind whose `symbol` is not a function**, which is the whole reason it
> needed a join change here rather than a schema change there. A reader wiring anything new onto
> `symbol` should branch on the kind rather than assume a callable.

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

**The census flood.** On its own repository a default run produces **975 findings, 734 of them (75%)
from the two candidate rules** — 507 pure functions and 227 pure closures. That is not a bug in either
rule; the pipeline needs every one.

> **Re-measured 2026-08-15 at `e06e39fc`** (was 876 / 664 / 76% / 460 / 204 at `d59cd782`). The
> flood grew with the codebase and **the ratio did not move** — 76% → 75% — which is the durable
> half of this finding. The next-largest rule is `Missing Documentation` at **32**, an order of
> magnitude down: the distribution is two rules and a long tail, not a gradient.
>
> One number moved for a reason worth knowing: **`Could Be Private Member` is 27, down from the
> hundreds** implied by the `line`-determinism note below (472 of 476 moving findings came from the
> two could-be-private rules). `5edd5e2c` *"Stop the could-be-private rules flagging reachable
> declarations"* landed 2026-08-14. That does not affect the manifest — neither rule seeds — but it
> does mean **the report is materially quieter than when the collapsing behaviour was designed**. It is a bug in what a human sees: the road test's sharpest result
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

Worth reading `SwiftInferProperties/Sources/SwiftInferCLI/Discover+Seeds.swift` in full; the short version:

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

- ~~**Rule counts disagree across four places.**~~ **Mostly FIXED 2026-08-15 — #75 is CLOSED and
  the README is now guarded.** The trap read: README says 160 (in four separate lines, plus "150
  files" of rule docs against **203** on disk), Appendix C says 189, `RuleIdentifier.swift` has
  **202** `case`s, and `SwiftProjectLintRules` registers **192**. Today the README says **202** in
  three places and that is *correct* — it equals `RuleIdentifier.selectableRules.count`
  (204 cases − 2 sentinels) — and `READMERuleCountTests` fails the suite if a new rule lands
  without updating it, per-category table included. **The canonical figure is
  `selectableRules.count`, not `allCases.count`**, which is the refinement the fix added: the
  sentinels are not rules and a user cannot enable, disable or select either one.
  **Two disagreements survive, both unguarded.** `Docs/rules/RULES.md` opens *"all 165 lint
  rules"*, and `Docs/rules/` holds **205** `.md` files against 202 rules. Neither is in any test's
  scope. Do not silently pick whichever number supports the sentence you are writing.
- ~~**The 10-case gap is unexplained and untested.**~~ **Retracted 2026-08-06 — there is no gap, and
  this trap was itself the trap.** 202 = 199 referenced via `name:` across *all* packages + 1 via
  `ruleName:` + 2 sentinels. The "10" came from subtracting one package's registrations from the
  whole enum. Kept struck through rather than deleted because the wrong number is what a reader will
  arrive with — it is the answer the obvious arithmetic gives, and nothing upstream contradicts it
  yet ([#73](https://github.com/Joseph-Cursio/SwiftProjectLint/issues/73)). **A
  declared-but-unregistered identifier would still be a real hazard** — configurable, nameable in a
  severity override, and never firing — which is why the check is worth having even though it
  currently passes.
  **2026-08-15: the check exists (`RuleRegistrationResidualTests`, #73 CLOSED) and the hazard was
  real.** It did *not* "currently pass" — `onTapGestureMissingAccessibility` was registered under
  no pattern and so was filtered out of its own visitor's output, never firing on a default run.
  The last clause of this trap was the right instinct and the sentence before it was wrong.
- **Counting registered rules by grepping `category:` or `name:` overcounts, and the greps have
  their own trap underneath.** `.unknown` `SyntaxPattern` placeholders are not rules — **eight of
  them, in six files, one of them production** (`BasePatternVisitor.placeholderPattern`), which
  this doc miscounted as "six, all test-only" for three passes. And the obvious recursive grep
  sweeps `.build/checkouts/swift-syntax`, which supplied **786 of 1,112** `name:` hits at
  `e06e39fc`; use `git ls-files`. This bit *this doc* twice — see the counting-method note in the
  catalogue section — and the naive numbers are close enough to the right one to survive review.
  **Since 2026-08-15 there is no reason to grep at all: `RuleIdentifier.selectableRules` is the
  answer and a test asserts it against the live registry.**
- ~~**`PBTSeed.role`'s doc comment is stale.**~~ **Fixed upstream 2026-08-06** (`0d56d982`, *"Say how
  many rules classify a seed role, and name them"*). The standing fact it recorded still holds and is
  the thing to remember: **three of the four seeding rules classify a role** — the two candidate
  rules and `ExtractablePureKernelVisitor` — and `.idempotencyViolation` is the only one that does
  not. Kept struck-through rather than deleted because the *count* is what a reader needs and the
  trap is where they will look for it.
- **A producer-side field ADDITION is silent on the consumer, and always will be.** `Codable`
  ignores unknown keys, so a new field arrives, decodes into nothing, and changes no output. That is
  not a bug anyone introduced; it is the default, and it is the opposite direction from the failure
  the `kind`/`rule` requirements guard (a *missing* field). `restriction` sat unread here for three
  days because of it. `SeedFieldParityTests` now fails on an unread field — but **only its
  sibling-checkout arm can catch a field added tomorrow**; the committed fixture arm catches only
  what was present when it was last regenerated. Regenerate `SwiftInferProperties/fixtures/seed-manifest-parity/seeds.json`
  as part of any producer schema change, and treat "the parity test is green" as evidence about the
  fixture's age, not about the producer.
- ~~**Only `PureFunctionCandidateVisitor` sets `testReachability`**~~ ([#74](https://github.com/Joseph-Cursio/SwiftProjectLint/issues/74) **CLOSED 2026-08-06; re-verified
  2026-08-15**). **Two visitors set it now** — `PureFunctionCandidateVisitor` and
  `IdempotencyViolationVisitor` — so the demotion reaches idempotency seeds as well. Everything
  else still leaves it `.unknown`, which `effectiveKind` treats as reachable, deliberately: demoting
  on "the rule did not look" would silently shrink the manifest.
  **`carrier` is excluded from the demotion on purpose, and the reason is worth carrying**: the kind
  it would demote to names *"a pure, total, **named** function that no test can call"*, and a
  carrier's symbol is a type — *"demoting one would hand a consumer a type name under a kind that
  promises a callable."* No domain-type rule computes reachability today, so nothing is lost; the
  guard is there so adding one later fails visibly rather than mislabelling. **A private type is a
  real obstacle that still has no vocabulary in this schema.**
- **The seed count is not a suggestion count.** Re-measured 2026-08-06: **2,096 seeds → 180
  default-tier picks** on SwiftInferProperties (was 1,657 → 21), of which only **3 `strong` + 27
  `likely`** — the other 150 are rescue and advisory rows. A **seeded** run prints **1,738**, *more*
  than an unseeded one, because 662 `restricted-function` seeds vouch for private functions a plain
  run never opens. Never report one count as evidence about the other, and say which reading of
  "default tier" you mean.
  **2026-08-15 — both halves re-measured on the same day, so they may finally be paired.** The
  *seed* side at `e06e39fc`: **2,278 seeds** on SwiftInferProperties — 1,284 `pure-function`, 701
  `restricted-function`, 290 `extractable-kernel`, 3 `idempotency`, **0 `carrier`** (this repo
  declares no domain newtype the three rules recognise, so the new kind is live in the producer
  and unexercised on this corpus). The *pick* side, same seeds, observer at `3548db4`, one
  release binary, **a fresh `git worktree` so `.swiftinfer/` is absent by construction**, default
  flags, summed over all eight targets:

  | | 2026-08-06 | 2026-08-15 |
  |---|---:|---:|
  | seeds | 2,096 | **2,278** |
  | seeded rows | 1,738 | **1,888** |
  | unseeded rows | — | **348** |
  | "default tier" (non-`Advisory`) | 180 | **180** |
  | `Strong` | 3 | **12** |
  | `Likely` | 27 | **7** |

  **The mechanism the trap describes is confirmed and is large: 348 → 1,888, a 5.4× increase from
  seeding.** 701 `restricted-function` seeds vouch for `private` functions a plain run never
  opens, so the seeded run prints *more*, not fewer.

  **Three cautions, and the second is the one that stops this being a trend.**

  *(a) Say which reading you mean, still.* Three defensible numbers come out of one run —
  **1,888** rows total, **180** non-`Advisory`, **19** `Strong`+`Likely`. The middle one is what
  2026-08-06 called "default-tier". `--include-possible` gives a fourth (1,935), which is the
  flags warning below arriving on schedule.

  *(b) The tier split is NOT comparable and the totals are.* This arm is clean by construction;
  the 2026-08-06 arm's `.swiftinfer/` state is **unrecorded**, and the road test's §10 measured
  that a stale `verify-evidence.json` in the working directory moves the headline on its own —
  *"what was run in this directory last week"*. So `3 → 12 Strong` and `27 → 7 Likely` are two
  arms differing in contamination as well as date. **Do not read them as movement.**
  Correspondingly, **non-`Advisory` landing on exactly 180 twice is not evidence of stability** —
  it is unexplained, and with (b) in hand the honest reading is coincidence.

  *(c) Per-target counts are now very nearly additive, which they were not.* Study §10.4 measured
  the same four lifted identities appearing under *every* target — ~203 summed against a true 174,
  a **17%** over-count. Re-measured here by collecting `Identity:` hashes per target and taking
  the distinct set: **1,895 naive → 1,888 distinct, 7 rows, 0.4%.** Three identities appear under
  more than one target. `TestTargetScope` (2026-08-08) is the plain cause — it scoped test-lifting
  to the test targets that transitively depend on the scanned one, which is exactly the population
  §10.4's over-count came from. **So the sum is defensible now and was not when the warning was
  written; the warning should be read as closed rather than obeyed.**

  > **Method note, and it cost an hour: the first run of this measurement reported a confident
  > zero on all eight targets.** `--seeds <path>` was passed through an unquoted zsh variable, and
  > **zsh does not word-split unquoted parameters**, so ArgumentParser received one argument named
  > `"--seeds /…/seeds.json"` and rejected it. stdout was empty, stderr was going to `/dev/null`,
  > and the harness dutifully tabulated `0` eight times. The tool was never involved.
  >
  > Two things this repeats. **The failure shape is `confident zero`** — the exact thing
  > `Discover+Seeds` is designed to make impossible on the tool's side, reproduced one level up in
  > the apparatus reading it. And **`2>/dev/null` is what hid it**, which is
  > `Discover+EvidenceDiagnostics`' own recorded finding — its coverage `note:` went unseen through
  > an entire eight-corpus census run for the same reason, *including the runs whose numbers went
  > into the findings doc*. **When a measurement returns zero, read stderr before believing it.**
- **The repo's own README opens with "THIS IS AN EXPERIMENT IN VIBE-CODING"** and says outright that
  some rules are bad ideas, some are poorly implemented, and some are both. The testability and
  idempotency families are the road-tested ones; treat a rule outside them as unvetted until measured.

---

## Where to look

| question | file |
|---|---|
| the manifest schema, seed kinds, dropped-seed detection | `SwiftProjectLint/Sources/Core/Export/PBTSeedsFormatter.swift` |
| the effect tier, its provenance, and why both travel | `SwiftProjectLint/Packages/SwiftProjectLintModels/…/PBTSeedEffect.swift` |
| which rules exist at all, and the count nothing tests | `SwiftProjectLint/Packages/SwiftProjectLintModels/…/RuleIdentifier.swift` |
| what a role is and why these six | `SwiftProjectLint/Packages/SwiftProjectLintModels/…/PBTSeedRole.swift` |
| reachability's three values | `SwiftProjectLint/Packages/SwiftProjectLintModels/…/TestReachability.swift` |
| why the report collapses candidates but the manifest does not | `SwiftProjectLint/Sources/Core/Export/CandidateInventory.swift` |
| what counts as a pure-function candidate | `SwiftProjectLint/Packages/SwiftProjectLintVisitors/…/PropertyTestCandidacy.swift` |
| the kernel motivating case, with its two real bugs | `SwiftProjectLint/Docs/rules/extractable-pure-kernel.md` |
| policing the cure vs detecting the disease | `SwiftProjectLint/Docs/design/primitive-bypassing-domain-type-rule-design.md` |
| the format wiring and the exit-gate bypass | `SwiftProjectLint/Sources/CLI/OutputFormat.swift`, `SwiftProjectLintCLI.swift` |
| consumer side of the same hop | `SwiftInferProperties/Sources/SwiftInferCLI/Discover+Seeds.swift`, `SeedManifest.swift`, `SeedRole.swift` |
| which fields this consumer reads, and the guard that says so | `SwiftInferProperties/Sources/SwiftInferCore/SeedField.swift` (`SeedFieldParity`) + `SwiftInferProperties/Tests/SwiftInferCoreTests/SeedFieldParityTests.swift` + `SwiftInferProperties/fixtures/seed-manifest-parity/` |
| what `restriction` corrects, and the one disagreement it is allowed to settle | `SwiftInferProperties/Sources/SwiftInferCore/SeedRestriction.swift`, `SeedRestrictionResolver.swift` |
| why the declaration's own `private` is **not** tested first | `SwiftInferProperties/Sources/SwiftInferCore/FunctionScannerVisitor+AccessRestriction.swift`, `RestrictedFunction.swift` |
| the patch generator that acted on the wrong answer | `SwiftInferProperties/Sources/SwiftInferCore/SpeculativeWidening.swift` |
| the vocabulary, both sides | `docs/design-internal/glossary.md` — *Seed / seed manifest*, *Role-entailed*, *Confident zero* |
