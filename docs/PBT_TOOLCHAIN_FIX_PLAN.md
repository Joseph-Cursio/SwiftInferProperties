# Fix plan: the five-repo PBT adoption loop

Companion to `PBT_ROAD_TEST.md`, which records what broke. This is what to do about it, in what
order, and how to know it worked.

---

## The benchmark

The re-run is the acceptance test, so pin it now.

| | |
|---|---|
| **Fixture** | `MacCloud_client_iOS` @ `main` (`f3dbb6f`) — the app *before* any PBT work. Bugs present, no property tests, no SPM deps. |
| **Answer key** | branch `pbt-road-test-reference` (`f3575b7`) — the pure kernels, the 4 property suites, the 3 bug fixes. |
| **Question** | Starting from the fixture, does the toolchain lead a competent reader to the answer key? |

Today's score, measured this session:

| step | at the start | now |
|---|---|---|
| `swiftprojectlint . --format pbt-seeds` | **2 seeds**, both `static func ==` | **9 seeds** (v2) — 7 analysable + 2 kernels |
| `swift-infer discover --seeds <manifest>` | **0** — `kept 0 of 6` | **7 suggestions + 2 kernels named** |
| **proposed laws that could ever fail** *(default flags)* | **0** | **1 of 7** (phase 1) · **3 of 9** (phase 2) |
| pure kernels suggested | **0** of 2 | **2 of 2** — `FileListing` via B1, `ChunkPlan` via B2 |
| bug *sites* pointed at | **0** of 3 | **3 of 3** — grandchild via B1; resume-counter and empty-file via B2 |
| **row 9 — cold readers reach the bug, from default output** | **0/3** | **walk 9 (measured): 3/3** — grandchild **3/3** · empty-file **3/3** · resume-counter **3/3** (↑ from 2/3 once B19 stopped the reader clamping the shipped generator); **all 3 readers reach all three**. Upper bound — same fixture, eight walks (B8, B20). See B17–B20 |

**The loop has been walked cold eight times — twenty-four readers, each sealed from the answer key,
each given the fixture and the two documented commands.** The current score is **walk 9**, and it is
the only one that counts:

> **As of walk 9, the loop reaches all three bugs, 3/3, and ALL THREE readers reach ALL THREE on
> their own. Row 9 is met.** Grandchild **3/3** (walks 7–9). Empty-file **3/3** (walk-8's 2/3 was a
> single weak reader, recovered at walk 9), on B13's *"name the empty case or it passes vacuously"*
> advisory. Resume-counter **1/3 → 2/3 → 3/3** across walks 6 → 8 → 9: B16 + B15a landed the tiler
> shape and the runnable `-50...500` generator (walk 7), B18 closed the scalar-extraction miss but the
> miss **relocated to the generator** — a reader clamped it with `min(queued, total)`, typing the
> bug's own assumption (walk 8) — and **B19 stopped the clamp** (the walk-8 clamper pasted the
> generator verbatim at walk 9). No single fix earned row 9; the chain B1/B2 → B3/B12 → B13/B15a →
> B16/B18 → B19 did, and pulling any link drops it. See B17 (walk 7), B19 (walk 8), B20 (walk 9).
> **The one caveat that outranks the number: 3/3 is the loop on bugs in its sweet spot. Measured on
> tool-blind bugs it is 1 of 4 on the same app (B21) and 4 of 4 on a different app (B22) — and the
> spread is the finding: the loop reaches a bug when the code offers a pure kernel AND a stated intent
> (SplitKit's documented pure API), and is nearly blind when either is missing (B21's impure or
> undocumented bugs). Yield is a property of the codebase, not the tools. Quote all three (B8, B20–B22).**
> **The walk history below runs 1 → 5; B15 carries walk 6, B17 walk 7, B19 walk 8, B20 walk 9.**

**Walk 1 — before B7: all three readers found nothing.** Every law the loop proposed on the default
path was a determinism law, and every one of them passed. Row 9 was **0/3**, and the bugs were
reachable only by overriding the tools twice — dropping `--seeds` and passing `--include-possible`,
both of which the loop's own text discourages. That is B6, and it is why B7 exists.

**Walk 2 — after B7 (`Refutability`): the default path carries laws that can fail.** Phase 1 goes
from 6 suggestions / 0 refutable to **7 / 1**; phase 2 from 6 / 0 to **9 / 3**. No flags. Three fresh
readers reached the empty-file bug **3 of 3** and the resume-counter bug **2 of 3**, all from default
output — where walk 1 had reached neither.

**Walk 4 — after B6b: the grandchild bug goes 1/3 → 3/3.** All three readers reached it from default
output, and all three name the same cause. **Not the law's score — its caveat:**

> *"Bias the generator toward inputs where structure COLLIDES — a small alphabet, repeated
> components… The counterexample lives in the collisions, and you have to generate them on purpose."*

**Walk 5 — after B9, B10, B11: grandchild holds at 3/3, and the chunked-upload bugs are lost.** The
first walk on a fixture clean *by construction*, and the first where the shim compiled so readers
could **run** a law. Grandchild **3/3** again, by the same route. But **resume-counter 0/3** — not
because the linter failed to seed `ChunkPlan` (B9 fixed that; it *is* seeded), but because **all
three readers wrote `chunk(of:at:) -> Data` where the partition template demands `-> Range<Int>`.**
The template is built around the *reference's* shape, which no real reader reaches for. That is
**B12**, and it is what four walks of "extraction lottery" were actually pointing at.

Reader 1 produced 432 counterexamples; reader 3 measured **5341 of 20000** collision-biased inputs
disagreeing with the reference definition. Reader 3 stated the lesson exactly: *"a wide alphabet never
repeats `currentPath` inside the path, and never hits root."* That is the sentence B8 kept when it cut
the answer key out — **the technique, not the answer** — and it is what earns row 9.

**B3 was right, and the shape of being right is worth naming.** No law *catches* this bug; the
`predicate` law's totality clause **passes**. What the template supplies is an instruction — *state
the reference definition in one English sentence* — and a generator strategy. The reader supplies the
sentence. A tool that had invented the law would have been guessing; a tool that says *"the
interesting law is not free, here is how to hunt for it"* got three readers to the bug.

**And the tool's confidence ranking is inverted.** The highest-scoring law in every walk — `comparator`
at 40 — was **clean every time**, checked to 20k triples and five locales. The **20-point** law found
the bug.

**A fourth bug, not in the answer key, and the loop earned it.** A reader followed the state-machine
law's invariant — *"`currentPath` always ends in a separator"* — forward into its consumer and found
that **every non-root folder renders an empty navigation title** (`FileListView.swift:191`:
`"/Documents/".components(separatedBy: "/").last` is `""`, and the `?? "Folder"` fallback is dead
code). The round-trip law it proposed *passes*; the invariant in its caveat is what paid.

The pipeline no longer reports a confident zero for code it found six properties in. But read the
row-9 line before celebrating any of the others, because **the reader is the only judge that counts.**

The six are *determinism* laws over `getFileIcon(for:)`, `formatFileSize`, `formatDate`,
`isValidFolderName` and the two `==` operators. The emitted law is literally `f(x) == f(x)` — call it
twice, compare (`OutputDeterminismVerifierEmitter.swift:117`). **For a function the purity analyser
has already graded pure, that assertion cannot fail.** It is a tautology, closed under the very
analysis that proposed it. The only thing that could break it is the purity inferrer having been
wrong — a hidden cache, a `lazy var`, a global — which makes it a *soundness check on the tool*, not
a test of the app. Six suggestions; zero refutable claims; zero bugs. Those numbers were never in
tension.

**The principle, and it is the one to put in the book: purity is a licence, not a hypothesis.** It
says a function *may* be property-tested — a generator needs determinism, and shrinking is meaningless
without it — but it carries no information about *what should be true*. Ask a tool that knows only
"this is pure" for a law and it can only hand back the definition of purity.

**Laws come from role, not from purity.** Every falsifiable law in this whole exercise comes from
knowing what a function is *for* — its position in a known algebraic context — and none from knowing
it is pure:

| the function's *role* | the law | where |
|---|---|---|
| passed to `sorted` | strict weak ordering | B1 |
| passed to `reduce` | associativity, identity | B1 |
| passed to `filter` | totality; agreement with a reference definition | B1 |
| a chunking kernel | `concat(parts) == whole`; count `== ceil(n/k)` | B2 |
| a state-machine pair | `up ∘ down == id` | B3 |

In SwiftProjectLint's closure rule the law is a field of `CollectionOperation` — a property of **the
operation the closure is passed to**, not of the closure. `PurityInferrer` is only the gate. This
recasts **B3** from a nice-to-have into the load-bearing item: the template catalogue is the only
mechanism in the toolchain that *can* produce a law capable of failing.

What is still missing is the *kernels*: nothing yet tells a reader that `uploadRemainingChunks` has
a pure chunking core inside it, or that `fetchLocalFiles` has a predicate and a comparator. Those
are B1 and B2, and they are where the three bugs live.

> **Unscored, and deliberately so: the toolchain found a kernel the answer key does not have.** B1's
> closure rule also fires on `MacCloudViewModel+Helpers.swift:35` — `filteredFiles`, the search
> predicate `{ $0.name.localizedCaseInsensitiveContains(searchText) }`. It is not one of the two
> kernels on `pbt-road-test-reference`; the hand-written road test walked past it.
>
> **It stays out of the score.** The answer key is the *independent standard*, and it stops being
> independent the moment it is edited in response to the tool's output. Scoring this would turn
> "1 of 2" into "2 of 3" — a better number, arrived at by adjusting the denominator to fit the
> measurement, which is the same sin as tuning against the fixture. **The answer key is frozen at
> `f3575b7`.** Nothing the tools say may be added to it.
>
> **But it is a real find, and row 4a is how we can say so without taking the linter's word for it.**
> Apply the refutability test cold: an empty query matches everything; a match implies a
> case-insensitive substring; the result is always a subset of the input; filtering twice on the same
> query changes nothing. Each of those rejects some plausible, type-correct implementation, so each is
> a law that could fail. `filteredFiles` is a genuine property-test candidate by the benchmark's own
> criterion, independent of the tool that proposed it.
>
> The honest reading cuts both ways, and both halves belong in the book. A *human* doing this road
> test by hand missed a kernel that carries four refutable laws — which is exactly as interesting as a
> tool missing one, and a useful corrective to the assumption that the hand-written key is ground
> truth rather than one careful reader's best effort. What it is not is a point on the scoreboard.

---

## Tier A — the tools give *wrong* answers — **ALL CLOSED**

Every item in this tier is done. They were cheap, and each one was a case of the toolchain telling
the reader "there is nothing here" when there was — the failure mode that matters most, because a
confident zero is believed.

The recurring shape, worth naming for the book: **eleven of these defects were pinned as intended
behaviour by a passing test.** `emptyManifestFocusesToZero`, `keyLabelAbsentAtCallSite_noDiagnostic`,
`ignoresInstanceMethod`, `determinismQualificationFilters`, `FunctionSignature.from(call:)`'s "this
matches the Swift compiler's own call-signature encoding" (it does not), and the five A5 tests named
for the silence they were pinning (`conventionalLawsDoNotThrowByDefault` and its four siblings).
None of them slipped past review — they were *ratified* by it. Each was a claim about all inputs,
defended by one example.

**And this header was itself an instance of it.** It read *"ALL CLOSED — every item in this tier is
done"* for three weeks while A5 sat open, unfixed and without a closure block, because the commit
that wrote it (`8353a93`) checked four items and generalised over five. A claim about all of them,
defended by most of them. In the document that names the failure mode.

### A1. ~~`--seeds` filters to zero instead of not filtering~~ — **DONE**

> **Closed.** SwiftInferProperties `6c327f0`. 3,821 tests in 564 suites green (was 3,817).
>
> The behaviour was *deliberate*, and said so in the source: *"An empty manifest focuses to
> nothing — 'focus on these zero functions' means zero suggestions, not 'no filter'."* Defensible
> for a manifest someone sat down and wrote. But nobody writes this manifest — it is whatever the
> producing linter found, and a linter with a blind spot emits an empty one.
>
> An empty manifest now applies **no focus**, with a warning saying that an empty manifest usually
> means the *linter* found nothing rather than that the code has nothing — and naming instance
> methods as the likely blind spot. Seeds that match nothing still honour the focus (the user asked
> for it) but warn loudly that they emptied the run and name the join key that failed. That second
> trap was not in this plan; it is the same silent zero by another route.
>
> **Deviation from the plan, deliberate:** the plan called for making `--seeds` *additive by
> default*. I did not. That guts the feature's purpose — narrowing a large codebase — and the
> defect was never focusing. It was **silence**. Focus stays the default; a silent zero is now
> impossible.
>
> `SeedFocus.filter` had exactly one test, and it asserted the bug
> (`emptyManifestFocusesToZero`, named after the doc comment).

<details><summary>Original entry</summary>

### A1. `--seeds` filters to zero instead of not filtering — `SwiftInferProperties` · S

`discover --seeds` treats the manifest as a hard filter with no empty-manifest guard, so an empty
manifest rejects everything (`kept 0 of 6`). Composed with A2, the documented pipeline is strictly
worse than running `swift-infer` alone.

- Empty manifest ⇒ **no focus applied**, plus a loud warning on stderr.
- Make seeding **additive by default**: a seeded symbol gets a score boost, it does not exclude the
  unseeded. Preserve today's behaviour behind `--seeds-strict` for anyone depending on it.
- Always print the arithmetic: `focused on N seed(s): kept X of Y` is good — but when `X < Y`, say
  what was dropped and why.

**Accept:** `discover --seeds <empty manifest>` on the `Canary2` fixture returns 6, not 0.

</details>

### A2. ~~The pure-function rule is blind to instance methods~~ — **DONE**

> **Closed.** SwiftProjectLint `59a597c`; SwiftInferProperties `917b249`.
> SPL 2,757 tests green; SIP 3,826 tests green.
>
> **The same blanket refusal existed in two repos, in the same words.** SwiftProjectLint refused
> instance methods ("instance methods can read mutable `self`") and so did `swift-infer`'s
> determinism synthesiser ("an instance method could read mutable `self`"). Fixing the linter alone
> changed nothing — every new seed was discarded one layer down.
>
> `SelfAccessAnalyzer` now *asks* rather than assumes: a method reading nothing from `self` is a
> function of its arguments; one reading only immutable stored state is a function of `(self, args)`
> and a nullary one qualifies too, because `self` **is** the input. Only mutable or derived reads
> disqualify. Doubt refutes — an identifier that cannot be tied to a parameter, a local or a type is
> assumed to be instance state even when it is a global.
>
> **And a third gate, which is the most interesting of all.** `swift-infer` drops `private` /
> `fileprivate` / SPI functions, carefully, over three calibration cycles measured against
> **swift-numerics, swift-collections, swift-algorithms** — an external verifier genuinely cannot
> call them. All correct *for a library*, whose interesting surface **is** its public API. **An app
> has no public API.** Its pure logic lives almost entirely in `private` helpers inside views and
> view models, which are its best property candidates and precisely what this drops. *The precision
> lever tuned on libraries is the thing that hides the properties in an app.* A seed now rescues
> them — unseeded discovery is untouched — with the caveat leading: *"No test can run this law as
> written: it is `private`… Widen it to `internal`, or lift the logic into a type of its own."*

<details><summary>Original entry</summary>

### A2. The pure-function rule is blind to instance methods — `SwiftProjectLint` · M

Fires on free functions and `static` methods only. `func double(_ v: Int) -> Int { v * 2 }` on a
plain struct produces no seed. App logic is *all* instance methods, so the seed manifest arrives
empty — which is what makes A1 fatal.

- Extend the rule to instance methods whose body reads only parameters, locals, and **immutable
  stored properties of `self`**, and calls only symbols SwiftEffectInference grades pure.
- Ask SEI's `PurityInferrer` — do not reimplement purity in the rule.
- Emit two kinds, because they are property-tested differently:
  - `pure-function` — a function of its arguments alone (`isValidFolderName`)
  - `pure-of-self` — deterministic given `(self, args)`; still testable, needs `self` constructed
    (`getFileIcon(for:)`, `filteredFiles`)

**Accept:** on the fixture, ≥6 seeds including `getFileIcon(for:)`, `isValidFolderName(_:)`,
`SelectedFileRow.getFileIcon()`.

</details>

### A3. ~~A missing target directory is a silent success~~ — **DONE**

> **Closed.** SwiftInferProperties `5532286`. 3,832 tests in 566 suites green.
>
> The bug was in **all ten subcommands** — each resolved `--target` inline with no existence check.
> One resolver now serves them all and fails loudly: a missing target names the path it looked for
> *and lists the targets that do exist*; a missing `Sources/` says so and **names the Xcode case
> outright**, which is the situation the reader is actually in.
>
> **Deviation, and the tests caught me.** The plan called for a `scanned N file(s) in <path>` line
> on every run. That is wrong: stderr is a byte-stable contract here (PRD §16 #6) and an absolute
> path differs from machine to machine, so printing one unconditionally makes identical inputs
> produce different output. The existing diagnostic tests broke, correctly. Only the **empty case**
> speaks now — a target holding no `.swift` files warns. The silence on a populated target is safe
> because the two ways a zero could lie are both closed, and what is left is a zero worth believing.
>
> The symlink half of this item was already fixed: `SwiftSourceFiles.sorted` resolves a symlinked
> root. The original road-test note was against an older build.

<details><summary>Original entry</summary>

### A3. A missing target directory is a silent success — `SwiftInferProperties` · S

`discover --target DoesNotExist` prints `0 suggestions.` and exits **0**. Since `--target` resolves
to `Sources/<target>/`, this is *how every Xcode user first meets the tool* — and it tells them their
code has no properties without having opened a file.

- Missing/empty target directory ⇒ **hard error, non-zero exit**.
- Traverse symlinks (a symlinked `Sources/<target>` also silently yields 0 today).
- Report the resolved absolute path and the file count in every run: `scanned 22 file(s) in …`.

**Accept:** `discover --target Nonsense` exits non-zero with a message naming the path it looked for.

</details>

### A4. ~~The effect override is dead, and grading is lexical~~ — **DONE**, and the diagnosis was wrong

> **Closed.** SEI `8fd3519`, `d82d01d`, `91f425b`; SwiftProjectLint `e7f79bf`.
>
> **The real cause was not the name heuristic.** A declaration's signature names every
> parameter; a call site's names only the arguments actually *written*. Any parameter with a
> default makes those two label lists differ, so the symbol-table lookup missed — and missed
> *silently*. The annotation never landed, and the caller fell through to name-based inference.
> `createRequest(endpoint:method:body:queryItems:)`, called as `createRequest(endpoint:method:)`,
> is exactly that shape. This explains the thing that made no sense in the road-test: why *no*
> annotation worked, at any tier, in either spelling. The escape hatch was never broken — it was
> unreachable, because the lookup never found the declaration to attach it to.
>
> `DeclarationShape` now records which parameters may be omitted (defaulted or variadic), and
> `accepts(callLabels:)` applies Swift's actual rule — arguments in declaration order, only
> omittable parameters skipped. An exact signature still wins, matching Swift's own preference
> for the overload that needs no defaults.
>
> **The name heuristic was left alone, deliberately.** It is the conservative default and it is
> load-bearing. The guard rail proves it: an unannotated `createUser()` that genuinely POSTs is
> *still* graded `non_idempotent` — including when called as `createUser(email:)` with its
> defaulted `name:` omitted. Loosening the lookup did not manufacture false purity, which would
> have been a far worse bug than the one being fixed.
>
> **And the leaf was not the leaf.** Fixing SEI changed nothing at first, because
> SwiftProjectLint never called it: the flagship rule consulted SPL's *own* forked
> `EffectSymbolTable`, `FunctionSignature`, `EffectAnnotationParser` and `UpwardEffectInferrer`,
> importing SEI only for `PurityInferrer`. Appendix C's "single purity oracle the linter's
> flagship rule consults" was aspirational. All four forks are now deleted (−1,047 lines); SEI is
> genuinely the one oracle for the effect axis. `@lint.context` and once-reach stayed in SPL,
> where they belong — they never read an effect, and a retry context is a linting concept
> `swift-infer` has no use for.
>
> SEI 96 tests green (was 80). SPL 2,741 tests in 330 suites green — the same count as before.

<details><summary>Original (incorrect) diagnosis, kept for the record</summary>

### A4. The effect override is dead, and grading is lexical — `SwiftEffectInference` · M

`createRequest` — a pure `URLRequest` builder, no I/O — is graded `non_idempotent` **because its name
begins with `create`**. Neither `@Pure`, nor `/// @lint.effect <tier>` at *any* of the four tiers,
clears it. Only renaming the function does. This kills every `@ExternallyIdempotent` claim upstream
of a request builder.

Fix the **precedence**, not the heuristic:

```
explicit annotation  >  body analysis  >  name heuristic (opaque bodies only)
```

- An explicit annotation must win, unconditionally. Both spellings — `@Pure`/`@Idempotent`/… and
  `/// @lint.effect <tier>` — as Appendix C already claims.
- A body that demonstrably performs no effects must beat any name prefix. `createRequest` assembles a
  value; nothing in the body escapes.
- Keep the name heuristic **only** as a fallback for bodies the analyser cannot resolve. Do not
  delete it — it is the conservative default and it is load-bearing.
- **Guard against the opposite error.** Add a regression test that a real `createUser()` which
  actually POSTs is *still* graded `non_idempotent` — by its body, not its name. Loosening this
  lattice must not manufacture false purity; that would be a far worse bug than the one being fixed.

**Accept:** `createRequest`'s exact body → `pure` (golden test). An annotation-precedence matrix:
5 tiers × 2 spellings × {free func, instance method} all override inference. `createUser`-with-a-POST
stays `non_idempotent`.

</details>

### A5. ~~`checkCodablePropertyLaws` reports a lossy codec as passing~~ — **DONE**

> **Closed.** SwiftPropertyLaws `6025bd6`. 702 tests in 107 suites green, with 7 known issues —
> each one a violation the kit used to swallow.
>
> **It was still open when this header said otherwise.** `8353a93` declared "Tier A is closed —
> A1–A5 all done" and wrote closure blocks for four of the five. A5 never had one, and the code
> confirmed it: `throwIfViolations` filtered to escalating results and dropped the rest on the
> floor, with no `Issue.record` anywhere in `Sources/`. The header was a claim about all five,
> defended by four — which is the shape this whole tier is *about*, committed by me, in the
> document naming it.
>
> The tier semantics were never the defect and are untouched: a Conventional violation still does
> not fail the build, because that is the tier's *purpose* — a type may consciously decline a
> customary law. What was wrong is that **"does not throw" had been implemented as "does not say
> anything."** Silence was never the tier's meaning; not failing the build was. A declined
> violation is now recorded as a **non-fatal Swift Testing issue**.
>
> **No new dependency.** `import Testing` resolves from the toolchain inside a library target, so
> `PropertyLawKit` keeps the zero-footprint posture that `PropertyLawComplex`,
> `PropertyLawCollections` and `PropertyLawAsync` were carved out to protect — the plan's own C4/C5
> complaint, not repeated here. `.suppressed` and `.expectedViolation` stay silent by design: they
> are explicit policy, and re-surfacing them would make suppression useless (PRD §4.7).
>
> **Five existing tests were relying on the silence, and all five are named for it** —
> `conventionalLawsDoNotThrowByDefault`, `ephemeralIDDoesNotThrowByDefault`,
> `unstableHasherDoesNotThrowByDefault`, `detectsDegenerateHashDistribution`,
> `detectsOperatorConsistencyViolation`. The contract they meant to pin was *does not throw*; what
> they pinned was *does not throw **and says nothing***. Two had already written the intent down and
> never noticed it was unmet: one comment reads "warns but doesn't throw" (the warning went
> nowhere), and one asserts "expected `stabilityWithinProcess` to be **reported** as a violation even
> in default mode" (the only report was an array nobody was obliged to read). **That is a sixth
> instance of the tier's signature failure**, and it brings the count in this document to eleven.
>
> `@discardableResult` is left alone. Dropping it is a source-breaking change and the defect is
> closed without it — but it is what made the silence reachable from the idiomatic one-liner, and it
> is still worth removing in the next major.

<details><summary>Original entry</summary>

### A5. `checkCodablePropertyLaws` reports a lossy codec as passing — `SwiftPropertyLaws` · S

`Codable.roundTripFidelity` is Conventional-tier; `EnforcementMode.default` reports Conventional
violations **without throwing**; the function is `@discardableResult`. So the idiomatic spelling
silently swallows a genuine violation. Verified side-by-side against a hand-written check that fails.

Least-disruptive fix that actually closes it:

- Under `.default`, a Conventional violation must **record a non-fatal Swift Testing issue**
  (`Issue.record`) rather than returning in silence. The tier semantics survive — the test does not
  fail — but the violation becomes *visible*, which is the entire point of the kit.
- Consider dropping `@discardableResult` from the check functions in the next major, so ignoring the
  results is a deliberate act.

**Accept:** the road-test's `FileResponse` + `.iso8601` codec produces a visible Testing issue under
`.default`, and still fails under `.strict`.

</details>

---

---

## The call-site-sugar bug class — a family, not a bug

A4 was not one defect. It was one member of a family, and once named, the family turned up in
**four of the five repos**. The class:

> A declaration's parameter list names *every* parameter. A call site's argument list names only
> what was **written**. Any code that builds a key from one and matches it against the other will
> miss — and the miss is **silent**: the annotation never lands, and some heuristic quietly
> answers in its place.

Members of the family — every sugar that opens the gap:

| sugar | example | written labels |
|---|---|---|
| omitted default | `createRequest(endpoint:method:)` | `[endpoint, method]` |
| **trailing closure** | `perform { }` | `["_"]` — Swift **drops** the label |
| trailing closure after args | `retry(count: 3) { }` | `[count, "_"]` |
| multiple trailing closures | `load { } onFailure: { }` | `["_", onFailure]` |
| variadic, spread | `publish(events: "a", "b")` | `[events, "_"]` |
| variadic, empty | `publish()` | `[]` |

**Trailing closures are the severe one** — Swift is made of them (`Task { }`, `.run { }`, every
completion handler), and the retry/idempotency domain these tools serve is *definitionally*
closure-shaped. A declared effect on a closure-taking function could not land at any idiomatic
call site, and there was no escape: an exact-signature hit is impossible when the label doesn't
exist at the call site at all.

### Found and fixed

| # | where | fixed |
|---|---|---|
| **S1** | `SwiftEffectInference` — trailing closures, variadics | `a7e365d` — `CallSiteShape` records how a call was *written*; `DeclarationShape` records each parameter's default/variadic status; trailing closures bind from the tail inwards |
| **S2** | `SwiftProjectLint` — `ContextSymbolTable` | `798b20f` — **the table written to fix S1 reproduced the bug it was fixing.** `@lint.context once` lost its contract to a single omitted default; and because `onceReach` walks call sites, one miss *truncates the chain* and every caller upstream loses reachability too |
| **S3** | `SwiftIdempotency` — `@IdempotencyTests` | `c26b42c` — filtered on `parameters.isEmpty`, but the emitted test calls with no *arguments*. `func status(verbose: Bool = false)` was dropped, and with nothing left to emit the macro returned no extension at all: green build, both annotations present, **zero idempotency checks**. Now filters on callability, and a function that genuinely needs arguments *warns* rather than vanishing |
| **S4** | `SwiftIdempotency` `@ExternallyIdempotent(by:)` + `SwiftProjectLint` `missingIdempotencyKey` | `c26b42c` + `a570973` — the macro checked the key label *existed*, never that a caller could not omit it; the linter's fallback then *documented* the hole. Both now reject an omittable key. **The proof that a default is always wrong:** Swift forbids a default from referring to another parameter, so a defaulted key can never derive from the operation's inputs — it is a constant (every operation collides on one key; the second is deduplicated as a replay of the first) or nondeterministic (every retry mints a fresh key and the operation runs twice) |

### Found, still open

| # | where | what breaks | severity |
|---|---|---|---|
| **S5** | `SwiftPropertyLaws` · `MemberBlockInspector.swift:60`, `InitializerBasedDerivation.swift:72` | `InitializerParameter` records `label` + `typeName`, never `hasDefault`. So `init(id:name:logger: Logger = .shared)` is *declined* — the strategist can't generate a `Logger`, so it abandons a type that `Type(id:name:)` would have derived perfectly. Spurious `.todo`. The arity limit counts declared params too. | medium |
| **S6** | `SwiftInferProperties` · the three `*StubEmitter.swift` | `parameterCount == 0` filters the mutation surface, but `func normalize(strict: Bool = false)` *is* callable as `x.normalize()`. Under-coverage rather than a wrong verdict. | medium-low |
| **S7** | `SwiftInferProperties` · `ReducerDiscoverer.swift:248` | `guard parameters.count == 2` drops a reducer with a defaulted trailing param. | low |

### Clean

`swift-infer`'s `--seeds` matching is **immune by design** — it strips labels and joins on
`(file, bare symbol)`. Every SwiftProjectLint rule *outside* the idempotency family keys on the
bare name. `PropertyLawKit`'s law entry points reason about values, not parameter lists.

**The lesson worth putting in the book:** the tools that got this right avoided the problem by
never matching label lists at all. The tools that got it wrong all did the same natural thing —
build a key from the declaration, look it up from the call site — and all failed the same silent
way. *A missing match must never be indistinguishable from "no annotation."*

---

## Tier B — coverage gaps: the tools give *no* answer

This is where the real value is. A1–A5 stop the loop lying; B1–B4 make it useful.

### B1. ~~"Pure closure candidate"~~ — **DONE**

> **Closed.** SwiftEffectInference `36e588a`; SwiftProjectLint `4a0ecbe`, `1135122`.
> SEI 113 tests green; SPL 2,771 tests green.
>
> **The toolchain now points at a real bug's location on its own** — the first time in this whole
> exercise. On MacCloud @ `main`:
>
> ```
> MacCloudViewModel+FileOperations.swift:57  [Pure Closure] the closure passed to `filter` is pure …
> MacCloudViewModel+FileOperations.swift:62  [Pure Closure] the closure passed to `sorted` is pure —
>                                            a comparator must be a strict weak ordering …
> ```
>
> Line 57 **is** the grandchild bug.
>
> **The design turned on one decision: a capture is not an impurity.** That predicate captures
> `currentPath`, a `var` on the view model. The obvious rule — "free variables must be the closure's
> own parameters" — would have refused it, and refused the single most valuable finding in the
> codebase. Lift the body into `isImmediateChild(_ path:of:)` and the capture simply *becomes a
> parameter*. What no extraction rescues is a closure that **writes** to what it captured; those are
> refuted.
>
> **A comparator is flagged only when its ordering can be got wrong** (`1135122`). The first cut
> floored every operation on body *size*, and for comparators that is the wrong axis — the shortest
> comparators are the wrong ones. `{ $0.name <= $1.name }` is reflexive and `{ $0.a > $1.a || $0.b <
> $1.b }` is intransitive; both fit on one line and both can crash `sorted(by:)`. Meanwhile
> `{ $0.date > $1.date }` inherits its ordering from `Comparable` and *cannot* be got wrong, and the
> old floor fired on it — the exact noise that teaches people to switch a category off. The
> discriminator is whether the ordering is **free**: one strict comparison, same key both sides. The
> guard also has to read a `SequenceExprSyntax` — `Parser.parse` does not fold infix operators, so
> matching the folded `InfixOperatorExprSyntax` is a guard that never fires, and it fails *open*.
>
> **This is a refactor prompt, not a seed** — `swift-infer` cannot index a nameless closure.
>
> **And the reason to take the prompt does not depend on any tool, which is the version to put in the
> book.** The first draft of this entry argued that *"naming it is what lets every other tool see
> it"* — which reads as **change your code so my tool can index it**, and a competent Swift
> programmer should refuse that. Tooling does not get to dictate code shape. The argument that
> actually holds is the one the bug itself makes: **an anonymous closure inlined in a method body has
> no test seam at all** — not a property test, *any* test. You cannot call it, cannot construct its
> inputs, cannot observe its output except by driving the whole method around it. The grandchild bug
> survived not because it was subtle but because *there was nothing to write a test against*. Naming
> the closure is what makes the logic addressable; property inference is merely the first consumer to
> notice. That `pureFunctionCandidate` then seeds it and the pipeline proposes its laws is a
> **consequence** of naming it, not the argument for it.

<details><summary>Original entry</summary>

### B1. "Pure closure candidate" — `SwiftProjectLint` · S · **best value per line of code**

A closure passed to `filter` / `sorted(by:)` / `map` / `reduce` whose body is pure and whose free
variables are its own parameters is a property-test candidate that is *invisible today* because it
has no name.

This rule alone catches **both halves of `fetchLocalFiles`** — the immediate-children predicate and
the folders-first comparator — which is one of the two kernels in the answer key, and the site of one
of the three bugs.

> `MacCloudViewModel+FileOperations.swift:57`: this `filter` predicate is pure and depends only on
> `file.path` and `currentPath`. Name it and it becomes property-testable — a comparator, in
> particular, should be checked for strict weak ordering.

High precision, cheap to detect, immediately actionable.

</details>

### B2. ~~"Extractable pure kernel"~~ — **DONE** — the flagship

> **Closed.** SwiftProjectLint `4cbeb64` (the rule) + `aed7fd6` (seed emission);
> SwiftInferProperties `b410a35` (the consumer). SPL 2,791 tests green; SIP 3,838 tests green.
>
> **On the fixture: 2 fires, 0 false positives, across 85 functions.**
> `uploadRemainingChunks` — the flagship, where two of the three bugs live — and `collect`.
>
> **The test set was built before the rule, and that is the whole story of this item.** A kernel has
> no syntactic boundary, so precision *is* the design and cannot be got at by intuition. All 85
> functions in the app were hand-classified first. The audit paid for itself three times:
>
> - **It found a site this plan never knew about.** `MacCloudAPIService.collect` (`:244`) throttles
>   download progress inside an `async` byte stream — and it is the **same defect family as bug #3**:
>   omit `Content-Length`, `expectedBytes <= 0`, and progress is never reported at all. The rule
>   *generalises a bug class* rather than re-finding one bug, which is a far stronger result than
>   this entry asked for.
> - **It found a false positive that revealed a missing clause.** A first cut fires on
>   `isValidFolderName` — an already-named pure function with nothing to extract, and one of A2's 7
>   seeds. Hence a **gate this plan never stated: the enclosing function must be impure.** Without it
>   the rule re-reports every pure function in the codebase.
> - **It showed B1 had already taken `fetchLocalFiles` off this rule's plate.** The kernel there *is*
>   the filter closure, which `pureClosureCandidate` reports today. The acceptance criterion below
>   was written before B1 existed and is **stale**: firing both rules there is one finding wearing
>   two hats. Closure bodies are now skipped.
>
> **The third gate marks the B2/B3 boundary, and it is worth keeping.** Arithmetic must *govern*
> something — a loop bound, an index, a slice, a comparison, a fraction. `navigateUp`'s pure path
> arithmetic is therefore **not** reported: its result is *assigned*, not used as a bound. That shape
> is a state-machine law (`up ∘ down == id`) and belongs to **B3**. The rule staying quiet there is
> correct, not a miss.
>
> **The seed had to be a *location*, not a *subject*** (`aed7fd6`). A kernel is *less* indexable than
> a closure, not more: a closure at least exists as a syntactic object; a kernel does not exist until
> a human draws a boundary. Emit it as an ordinary seed and `swift-infer` narrows to
> `uploadRemainingChunks`, correctly refuses it (`private async throws` refutes purity), and reports
> `kept 0` — **a confident zero, which is A1 arriving by a new route.** So the manifest gained a
> `kind` with a *semantic*: `isAnalysable`. A kernel is neither focused on nor dropped — it is
> **named, with the one instruction that unblocks it**. An *unrecognised* kind is also non-analysable
> and warns loudly, because the two ways to guess wrong are not symmetric: guess "analysable" and a
> future kind gets silently zeroed; guess "not" and it is merely skipped, out loud.
>
> Manifest is now v2, 9 seeds on MacCloud: the 7 pure-function seeds unchanged, plus the 2 kernels.

<details><summary>Original entry</summary>

### B2. "Extractable pure kernel" — `SwiftProjectLint` · L · **the flagship**

The single rule that would have led a reader to `ChunkPlan`. The chunking arithmetic is the most
valuable property in the app and guarded a real bug — and it is invisible to every tool in the set,
because it lives inlined inside a `private async` method that also does network I/O.

Detect: within a function graded impure, a maximal set of statements/expressions `S` where

- every free variable in `S` is a parameter, a local bound in `S`, or an immutable stored property of
  `self`; **and**
- every callee in `S` is graded pure by SEI; **and**
- `S` produces a value used as a **loop bound, an index, a slice range, a predicate, or a progress
  fraction**; **and**
- `S` is non-trivial (≥2 bindings, or arithmetic feeding a comparison) — the size floor is what keeps
  this from firing on everything.

Report it as the refactor, not as a smell:

> `MacCloudAPIService+ChunkedUpload.swift:73`: `totalChunks`, the chunk offsets and the progress
> fraction depend only on `data.count`, `chunkSize` and `index` — nothing else in this method
> reaches them. Lift them into a value type and they become property-testable: the chunks should
> tile the payload exactly, and progress should terminate at 1.0.

**Accept:** fires on `uploadRemainingChunks` and on `fetchLocalFiles`, and on neither `login()` nor
`downloadFile()` (which have no separable kernel). Both kernel sites appear in `--format pbt-seeds`
with `kind: extractable-kernel`.

</details>

### B3. ~~Templates for the shapes app code actually has~~ — **DONE** — the load-bearing item

**Reclassified.** This reads like a coverage nice-to-have and it is not: the template catalogue is the
**only mechanism in the toolchain that can produce a law capable of failing.** Purity is a licence,
not a hypothesis — ask a tool that knows only "this function is pure" for a law and it hands back the
definition of purity (`f(x) == f(x)`, which cannot fail). A law comes from a function's *role*, and a
role is what a template encodes. Every refutable law in this exercise traces to one. See row 4a.

> **Partition / tiling — DONE.** SwiftInferProperties `460bc9c`. 3,845 tests in 567 suites green.
>
> **The first law this toolchain has ever proposed that can fail.** On the phase-2 tree it fires on
> `ChunkPlan` at Score 60 (Likely), and the four laws it states are written as *what they reject* —
> because a law that rejects nothing is a tautology wearing a template's clothes:
>
> - **tiling** — parts abut, never overlap, cover the whole. Rejects a chunker that drops the
>   remainder or double-counts a boundary byte.
> - **totality** — an out-of-range index yields an empty range, *not a trap*. Rejects the
>   `dropFirst(negative)` family — and a negative index is exactly what a corrupt server counter
>   supplies. **This is bug #2.**
> - **progress terminates at 1.0, *including for an empty whole*.** **This is bug #3** — and the
>   caveat says out loud why it must be named: a general "monotonic and ends at 1.0" property passes
>   **vacuously** on an empty input, because its sample array is empty and there is no last element to
>   check. A boundary case still has to be named, even under PBT.
> - **the resume index must be clamped to `0...count`** — the law quantifies over the whole integer
>   range *on purpose*, because that value came over the network and is not yours to trust.
>
> **Matched by signature, not by name.** The tell is one member — `func byteRange(ofChunk: Int) ->
> Range<Int>`: *give me a part index, get the slice of the whole it covers.* Nothing else has that
> signature by accident. Keying on vocabulary would have found `byteRange(ofChunk:)` and missed
> `slice(at:)` — the same mistake the effect lattice made when it graded `createRequest` by its
> prefix.
>
> Measured: **0** partition suggestions on the pristine fixture (the shape is not there — the
> arithmetic is loose statements inside an `async` method, which is what B2 reports), and exactly
> **1** after a reader performs the extraction. The two-phase loop, working: **B2 supplies the role,
> B3 supplies the law for it.**
>
> **The other three — DONE.** SwiftInferProperties `<pending>`.
>
> | template | fires on | law |
> |---|---|---|
> | **comparator** | `precedes(_:_:)` — the folders-first sort | strict weak ordering, all four clauses |
> | **predicate** | `isImmediateChild(_:of:)` — **the grandchild bug site** | totality, and *a hole* (below) |
> | **state-machine** | `navigateToFolder` / `navigateUp` | `up ∘ down == id`, plus an invariant over any sequence |
>
> **A comparator and a binary predicate have the same signature, and the labels tell them apart.**
> `precedes(_ lhs:, _ rhs:)` and `isImmediateChild(_ path:, of: parent)` are both `(T, T) -> Bool`.
> The comparator's operands are *positional* — interchangeable, which is exactly why an ordering law
> is stateable over them — while the predicate gives its second operand a **role**. In Swift a label
> *is* part of the signature, so this stays a signature test and not the name-matching that produced
> A4.
>
> **The state-machine template fires on the pristine fixture**, with no refactor needed:
> `navigateUp`/`navigateToFolder` already have names. It is the one refutable law the loop can offer
> in phase 1 — and note that **B2 deliberately stays silent on the same code** (its arithmetic is
> *assigned*, not used as a bound), so the two rules meet at that boundary exactly as intended
> rather than fighting over it.
>
> **My first cut proposed a law that was FALSE, and that is the finding worth keeping.** It paired
> `selectAllFiles()` with `deselectAllFiles()` and asserted `deselectAll ∘ selectAll == id`. *That is
> not true* — `selectAll` sets the selection to everything, `deselectAll` clears it, and composing
> them yields the empty set, not the state you began in. A reader who wrote that test would watch it
> fail for a reason that is **not a bug**. **A tool that proposes a false law is worse than one that
> proposes nothing**: it spends the reader's trust and returns nothing. The gate is principled — *the
> forward move must take an argument*, because an inverse pair needs the forward to say **which** move
> it made so the backward has something specific to undo. `navigateToFolder(folder)` names the folder;
> `selectAllFiles()` names nothing, because it is not a move at all but an absolute setter, and two
> absolute setters never compose to the identity.
>
> **And the predicate exposed the honest limit of "laws come from role."** A comparator owes a strict
> weak ordering and a partition owes a tiling *by virtue of being one*. **A bare predicate owes
> nothing from its shape.** What universal claim follows from `isValidFolderName(_:) -> Bool` merely
> because it returns a `Bool`? None — validity is *domain knowledge*, and a tool that invented a law
> here would be making one up. So the template proposes the one law that **is** free (**totality**) and
> states plainly that the interesting law is a hole only the author can fill:
>
> > *"THE INTERESTING LAW IS NOT FREE, and no tool can invent it for you… State that reference
> > definition in one English sentence, then encode it — that sentence is the property."*
>
> **Not every role carries a free law.** That is the boundary of the idea, and the tool now says so
> rather than manufacturing a confident-sounding suggestion with nothing behind it — which is the
> `f(x) == f(x)` failure wearing a template's clothes.

The catalogue is algebraic (`T -> T`, `(T,T) -> T`, encode/decode). MacCloud's real properties match
none of them. Add:

| template | fires on | law |
|---|---|---|
| **partition / tiling** | `(payload, k) -> [Slice]` | `concat(parts) == whole`; sizes uniform but the last; count `== ceil(n/k)` |
| **state-machine inverse pair** | void-returning mutators (`navigateUp` / `navigateToFolder`) | `up ∘ down == id`; plus a class invariant (`currentPath.hasSuffix("/")`) that must hold after *any* action sequence |
| **comparator** | `(T, T) -> Bool` passed to `sorted(by:)` | strict weak ordering; sort is idempotent; the partition key is preserved |
| **predicate / classifier** | `T -> Bool` | totality; agreement with a stated reference definition |

The partition template is the one that would have described the chunking law.

### B5. ~~The seed focus discards the refutable law and keeps the tautologies~~ — **DONE** — found by B3, and a Tier A shape

> **Closed.** SwiftInferProperties `<pending-b5>`.
>
> The fix is `SeedFocus.seedIndependentTemplates`, and the insight is narrower than the obvious one.
> **The seed focus was designed to narrow a search for *pure functions*.** A state machine's subject
> is two impure `Void` mutators; a pure-function manifest cannot name one, ever, by construction. So
> that law is not being *narrowed out* — **it was never in the search that the seeds narrow.** The
> focus has no business filtering it.
>
> Not "make seeding additive": A1 considered that and declined it, and the reasoning still holds —
> focus exists to narrow a large codebase, and gutting it costs more than it buys. Adding a template
> to the exempt set is a deliberate, reviewable act, and the doc comment demands a justification: *if
> the answer is "a manifest could name it, the linter just doesn't yet," the fix belongs in the linter,
> not here.*
>
> On the pristine fixture, seeded:
>
> ```
> focused on 7 analysable seed(s): kept 0 of 0 seedable suggestion(s)
> kept 1 law(s) no seed manifest could name — their subjects are impure …
> synthesized 6 generic determinism law(s) for seeded functions
> 7 suggestions.
> ```
>
> **Row 4a moves off zero in phase 1 for the first time: 1 refutable claim of 7, where it was 0 of 6.**
> And the counting is honest — `kept 0 of 0 **seedable**` keeps the exempt law out of the seed-match
> numerator rather than smuggling it in, and A1's "the focus discarded everything" warning correctly
> stays silent, because with zero seedable suggestions there was nothing to discard and saying so
> would have been a lie.

<details><summary>Original entry</summary>

Found by B3, on the pristine fixture, with the whole pipeline wired:

```
focused on 7 analysable seed(s): kept 0 of 1 suggestion(s)
synthesized 6 generic determinism law(s) for seeded functions
6 suggestions.
```

Read those three lines together. Discovery **found** a state-machine suggestion — `navigateToFolder`
/ `navigateUp`, `up ∘ down == id`, **a law that can fail.** The focus filter then **threw it away**,
and synthesized six determinism laws that **cannot**. The reader is handed six suggestions, every one
of them a tautology, and the only refutable claim in the run is in the bin.

**This is A1's disease in a new organ.** The seed manifest contains what the linter's *pure-function*
rule found. B3's templates now cover **impure** shapes — a state machine's moves are `Void`-returning
mutators, which that rule will never seed and never could. So the focus joins on a manifest that *by
construction* cannot contain them, misses, and discards. The producer's blind spot defines the filter,
and the filter removes precisely what the producer cannot see. Running the documented `lint → infer`
pipeline is once again **strictly worse** than running `swift-infer` alone — the exact sentence A1 was
raised to delete.

**It is not silent, which is the one mercy.** A1's guard fires: *"none of the 7 analysable seed(s)
matched any of the 1 suggestion(s) found, so the focus discarded all of them… Re-run without --seeds
to see what was discarded."* The reader is told. But a warning they must act on is not a fix, and the
default output still says "6 suggestions" while showing nothing that could ever go red.

**The tension is real and A1 already picked a side.** A1 explicitly *declined* to make seeding
additive — *"that guts the feature's purpose, which is narrowing a large codebase."* That reasoning
still holds. So the fix is not "make seeds additive"; it is to notice that **the seed focus was
designed to narrow a search for pure functions**, and a template whose subject is impure by nature was
never in that search to begin with.

Options, in the order I would try them:

- **Exempt templates the manifest cannot express.** A state-machine subject is a pair of impure
  mutators; a pure-function manifest can never name one, so the focus has no business filtering it.
  Mark such templates *seed-independent* and let them through. Narrowing still works for everything
  the seeds *can* address.
- **Widen the manifest.** Teach the linter to seed the impure shapes too (a `state-machine` kind
  alongside `extractable-kernel`). Honest, but it couples the linter to `swift-infer`'s template list,
  and every new template becomes a two-repo change.
- **Do nothing and lean on the warning.** Rejected: "6 suggestions" with zero refutable claims is the
  headline number, and the warning is a footnote.

**Accept:** on the pristine fixture, `discover --seeds` keeps the state-machine law. Row 4a moves off
zero *in phase 1*.

</details>

### B6. The cold walk — **row 9 measured: 0/3** — and what it exposed · **load-bearing**

Row 9 was scored the only way it can honestly be scored: by readers who had never seen the answer
key. Three of them, independently, each given a sealed copy of the fixture (no `.git`, no
`PBT_ROAD_TEST.md`, no this-file), the two documented commands, and no count of how many bugs exist.

**All three, following the documented loop, found nothing.**

```
$ CLI . --format pbt-seeds && swift-infer discover --target MacCloud --seeds seeds.json
focused on 7 analysable seed(s): kept 0 of 0 seedable suggestion(s)
synthesized 6 generic determinism law(s) for seeded functions
6 suggestions.
```

Six laws, all `determinism`, all of which **pass**. Every reader ran them; none failed. The loop as
documented is a dead end, and row 9 is **0/3**.

Bugs appeared only when readers **overrode the tools twice** — dropping `--seeds` and passing
`--include-possible`, both of which the loop's own text discourages:

| bug | R1 | R2 | R3 | how it was reached |
|---|---|---|---|---|
| empty-file | ✅ | ✅ | ✅ | extraction → **drop `--seeds`** |
| resume-counter | ✅ | ✅ | ❌ | extraction → drop `--seeds` → *partition* law |
| grandchild | ✅ | ✅ | ✅ | **no proposed law — see below** |

**Finding 1 — the grandchild bug is reached by no law, in any run.** R1 found it by plain code
reading and said so. R2 and R3 found it from the *caveat prose* on the state-machine suggestion — a
law which **passes**. R3's words: *"credit to a warning paragraph, not to the law it proposed."* The
law that does fire at the site is the **predicate** law, and B3 already conceded that template *"owes
nothing from its shape."* **The hole B3 documented is the hole the reader falls into.** B3 was right
to refuse to invent a law there — and that refusal is exactly why row 9 cannot reach 3/3 by this
route. A predicate template will never catch this bug. Only the reader's *reference definition* will.

**Finding 2 — the resume-counter bug is a coin flip, decided by which shape you happen to extract.**
R1 and R2 lifted a `byteRange(ofChunk:)`-style API, drew the **partition** template, and got its
clamp hazard — which names the bug almost verbatim. R3 lifted `progress(afterCompleting:)`, drew
**monotonicity** instead, was never told about clamping, and **missed the bug entirely.** The loop
does not converge on a destination; it converges on whatever the reader happened to name. Two honest
readers, same fixture, same tools, different bug counts.

**Finding 3 — B5 is not closed. `--seeds` still eats the only law that can fail.** In *phase 2*,
after the reader performs the extraction the linter demanded:

```
kept 0 of 1 seedable suggestion(s)          # ← the partition law, found and then discarded
synthesized 6 generic determinism law(s)
6 suggestions.                              # every one of them a tautology
```

Drop `--seeds` and the same run yields `partition: 1 (Likely)` — **the one law that catches the
resume-counter bug.** The cause is A1's disease in the organ B5 left untouched: B5 exempted only
templates whose subjects are *impure*, and a freshly-extracted `ChunkPlan` is a **pure value type**,
so it is seedable *in principle* and the focus is entitled to filter it. But the linter cannot see
methods on the type **it just told the reader to create**, so the manifest never names them, the join
misses, and the law dies. **Running `lint → infer` is once again strictly worse than running
`swift-infer` alone** — the exact sentence A1 was raised to delete, back for the third time.

**Finding 4 — row 4a's "1 of 7" was behind a non-default flag.** The state-machine law scores in the
`Possible` tier (20–39), which `swift-infer` **hides by default**. B5 got the law past the seed focus
and straight into a second filter nobody had counted. Two filters in series; the scoreboard credited
B5 for clearing both.

**Finding 5 — the fixture leaks its own answer key.** `PBT_ROAD_TEST.md` is committed on `main` and
names all three bugs with line numbers. Any "cold" reader in the real repo reads it in thirty seconds.
It had to be deleted from the sealed copies for this walk to mean anything. **A benchmark whose answer
key ships inside the fixture cannot be walked cold by anyone but a stranger.**

**Finding 6 — the partition template's hazard prose was written *after* the bug was known.**
`PartitionTemplate.swift:81,103` says *"a negative index is exactly what a corrupt server counter
supplies"* and *"a partition over a resumable index needs its start CLAMPED."* That is not inferred
from the code; it is a canned string added in `460bc9c`, during this exercise. It is a real pointer
and it did walk two readers to the bug — but it is **recitation, not inference**, and row 5 should be
read with that in mind.

**What row 9 needs, in the order that would move it:**

- **B6a + B6c → done, as B7 below.** These turned out to be *one* bug, not two, and that is the whole
  lesson: there were **two filters in series**, each able to discard the last refutable law on its
  own. Fixing one and crediting it for both is exactly the mistake B5 made.
- **B6b — DONE.** The closure rule now seeds, so `fetchLocalFiles` is named at `:57` and `:62`, the
  comparator law fires (row 6), and the grandchild bug went **1/3 → 3/3**. SwiftProjectLint `0923325`.
- **B6d — DONE.** `PBT_ROAD_TEST.md` is off `main`. It survives, byte-identical, on
  `pbt-road-test-reference` beside the answer-key code it describes. **The fixture can now be walked
  cold without deleting anything first** — which, for six walks, it could not.

### B7. ~~The last refutable law is never filtered~~ — **DONE** — row 9 moved

> **Closed.** SwiftInferProperties `b21a374`. Row 4a on the **default path**: phase 1 **1 of 7**
> (was 0 of 6), phase 2 **3 of 9** (was 0 of 6). Row 9: empty-file **3/3**, resume-counter **2/3**.

**The invariant.** *The reader is never handed a non-empty answer containing zero refutable laws,
when the run found one.* Stated once, in `Refutability`, and applied to the **finished answer** —
not inside either filter.

**Why not inside the filters, which is where I put it first and got it wrong.** A filter cannot tell,
on its own, whether hiding a law is honest. When the tier cut hides every `Possible` pick and the run
prints "0 suggestions", that is the cut *working*: a `Possible` law is a guess, defaulting to hide
guesses is the point, and `--include-possible` is right there. Guarding inside the cut makes that flag
a no-op — **eight existing tests said so**, and they were right. What turns the same hiding into a lie
is a **later** stage: `--seeds` synthesizes determinism laws *downstream of the cut*, and the reader
is handed a confident "6 suggestions", every one a tautology, with the only refutable claim in the
bin. Whether a filter told the truth is a property of the **final answer**, and only the last stage
can see it. So an **empty** answer stays empty — an honest *"nothing confident here"*. A **non-empty**
answer that cannot fail is the lie, and the law comes back.

**A rescue is a bug report, and the two causes demand opposite fixes**, so they get opposite messages:

| the law was eaten by | the message says | because the fix is in |
|---|---|---|
| the **tier cut** | *"treat this as a SCORING bug"* | `swift-infer`'s scorer — a law that can be refuted is worth more than any number that cannot |
| the **seed focus** | *"treat this as a LINTER bug"* | **SwiftProjectLint** — the manifest should have named that pure function and did not |

That second message is the one that matters, because it is the tool **correctly diagnosing B6b on its
own**: *"the usual cause is a shape the linter cannot see — methods on a value type it just told you
to extract."* Which is precisely what happens to `ChunkPlan`.

**What it did not fix, and could not.** The grandchild bug is not being *filtered* — **no law exists
to filter.** B7 can only stop a law from being thrown away; it cannot conjure one. And the extraction
lottery survives: one walk-2 reader lifted a `byteRange`-shaped API and drew the **partition** law
(whose clamp clause names the resume-counter bug), while another lifted `progress(afterUploading:)`
and drew **monotonicity** instead — and had to deviate to reach the same bug. **Which law you get
still depends on where you draw the boundary.** That is B6b/B6c territory: the kernel advisory should
name the *shape* it wants, not merely the site.

### B8. The predicate template was reciting the answer key — **DONE**, and a warning about this whole exercise

> **Closed.** SwiftInferProperties `e2b75e8` (the example is now drawn from another domain).

Walk-2's first reader reported the grandchild bug as *reached from default output*. It was — because
`PredicateTemplate` **printed it**:

> *"…the code that implements it stripped EVERY occurrence of the prefix rather than the leading one,
> so `/a/b/a/c` collapsed to `bc` and a grandchild was reported as a child."*

That caveat fires on **every predicate**. On the fixture it recited MacCloud's grandchild bug while
analysing an unrelated download-progress throttle. The reader read the example, went looking for that
pattern, and found `fetchLocalFiles`. **That is not inference; it is the tool having a good memory.**

**As product prose a worked example is good pedagogy — the sin is that the example was the fixture's
own answer.** The example now comes from a domain MacCloud does not contain (case-folding one side of
an address comparison). The generator advice survives intact, because *it* is the part that actually
finds this class of bug: bias inputs toward **collisions** — a small alphabet, repeated components —
since a predicate that has confused two notions agrees with the right answer everywhere the two
coincide.

**The general hazard, which outlives this one fix.** `PartitionTemplate`'s clamp prose — *"a negative
index is exactly what a corrupt server counter supplies"* — was written in `460bc9c`, **during this
exercise, after the bugs were known.** It is a defensible, transferable claim about resumable
partitions, so it stays. But rows 5 and 9 are both leaning on it, and **a benchmark cannot measure a
tool that has been told the answer.** The only real test is a *second fixture the templates have never
seen.* Until that exists, treat every number in this document as an upper bound.

---

### B9. ~~The linter cannot see the value type it just told you to extract~~ — **DONE**

> **Closed.** SwiftEffectInference `2ffc05b`; SwiftProjectLint `305803b`.
>
> On the **answer key's own `ChunkPlan`** — the extraction this project's reference performs — the
> linter went from **no seeds at all** to seeding `byteRange` and `progress`, and `swift-infer` now
> proposes **`partition`, score 60 (Likely)**: the law that carries the clamp hazard.
>
> **Two refusals, one cause:** any lowercase identifier that was neither a local nor a *stored*
> property was assumed to be a mutable global.
>
> - **`min(...)`** is now waved through — but **only in callee position.** A global `var min` read as
>   a *value* still refutes. That asymmetry is the whole reason the tiny allowlist is sound.
> - **Computed properties** are promoted to immutable by a **fixpoint** (a derived property may read
>   another; a cycle simply never promotes, which is the right answer and costs no cycle detection).
>
> **The derived-property check has two independent halves, and dropping either breaks it.** The names
> must resolve to immutable state, **and** the getter body must pass the marker scan. The second half
> earns its keep on exactly one case: `var now: Date { Date() }` reads no mutable state at all, so a
> names-only check sees an uppercase type reference and walks **a clock** into a function claimed
> pure. Pinned by a test in both repos.
>
> **A pre-existing test had to be reversed, and its comment was the bug.**
> `ignoresInstanceMethodReadingComputedState` asserted that reading `var derived: Int { raw * 2 }`
> refutes purity, *"because a computed `var` can read anything at all."* True of an arbitrary one;
> false of a **derived** one, which reads a single `let` and is exactly as pure as it is. The half of
> that rule which was right — an *unresolvable* name in the getter still refutes — survives as a
> sibling test.

<details><summary>Original entry — found by all three walk-4 readers, independently</summary>

> Reader 3: *"The round trip through the loop **destroyed** information that step 1's prose already
> had."*

`PurityInferrer` refuses a function that **calls the global `min(_:_:)`** or **reads its own computed
property**. Both are transparently pure. Probe:

```
seeded:      rangeNoMin, progressInline
NOT seeded:  rangeWithMin        ← calls min(_:_:)
             progressViaComputed ← reads its own computed property
```

**The answer key's own `ChunkPlan` does both** (`min` at lines 50/84/96, `var totalChunks` at 57). So a
reader who performs the extraction *exactly as this project's reference does it* gets **zero seeds
back**, and no law is ever proposed for the chunk math. Walk 4's readers all extracted `ChunkPlan`,
all had it refused, and the resume-counter bug — reached 2/3 in walk 2 — was reached by **none of
them**. The empty-file bug survived only because the **linter's prose** had already stated it
(*"progress should terminate at 1.0 — including for an empty input"*), which is a law that never
became a law.

**A rule that reports a refactor and then refuses its own output is the loop eating itself.** Fix the
inferrer: a call to a known-pure stdlib function is not an impurity, and a `let`-backed computed
property on a value type is not hidden state.

</details>

### B11. ~~The extraction loop does not converge~~ — **DONE**

> **Closed.** SwiftProjectLint `8d613e6`. On all three walk-4 readers' post-extraction trees:
> **3 kernels re-flagged forever → 0.**

**A rule that cannot recognise its own advice being taken never terminates.** The linter told readers
to lift a closure's logic into a named function; the call site they were left with is *itself a
closure* — a forwarding one — and the rule reported it **again**, saying *"extract it into a named
value type"* about a closure whose entire body is a call to the type they had created one step
earlier. Reader 2 walked the loop three times before stopping.

**The discrimination cannot be made locally, and that is the whole finding.** These two closures are
the *same shape* — one call, plain operands:

```swift
{ $0.name.localizedCaseInsensitiveContains(query) }   // must still fire
{ search.matches(name: $0.name) }                     // must not
```

The difference is **ownership**, which is not a syntactic fact. `matches(name:)` is *ours* — declared
here, already seeded, laws already proposed for it, boundary already drawn. `localizedCaseInsensitiveContains`
is Foundation's: it cannot be seeded, so its law must be stated **at the closure or nowhere** — which
is precisely why the rule errs toward firing on call-shaped predicates to begin with. A new
`DeclaredFunctionCollector` joins the project-wide pre-scan and answers the one question that
separates them: *did we write this function?* It matches on the **labelled** name, so an exemption
needs the same name *and* the same argument labels.

**And then the adapter, which is where I got it wrong and the tests caught me.** After extracting a
comparator, what remains is:

```swift
.sorted { a, b in precedes(Key(a.isFolder, a.name), Key(b.isFolder, b.name)) }
```

Refusing to treat that as plumbing **never converges** — extract the projection and you simply get
another nested call, forever. So a *coherent projection* (every field drawn from one source) is
exempt. My first cut then also exempted:

```swift
precedes(Key(b.isFolder, b.name), Key(b.isFolder, b.name))   // ← `a` is never used
```

Each projection is *individually* coherent, and the comparator **ignores its left operand entirely.**
That is a real bug — and **no law on `precedes` can see it**, because the law is checked against
*generated* keys and never runs the adapter. Exempting it would have silenced the only rule that
could have spoken. Every closure parameter must now reach the call.

> **The general lesson, and it outlives this rule.** A property test on an extracted function does
> **not** test the *adapter* that feeds it. The law runs on generated inputs; the projection from real
> data into those inputs is untested by construction. Extraction moves logic *out* of the reach of the
> law it enables — a little of it stays behind, at the call site, in the shape of a transposition
> waiting to happen.

**Not caught, deliberately:** a *reversed* projection (`precedes(Key(b…), Key(a…))`), which is
indistinguishable from a descending sort — a thing people legitimately write.

### B12. ~~The partition law fires on a shape no real reader writes~~ — **DONE**

> **Closed.** SwiftInferProperties `f1eca11`. `PartitionPairing` now recognises **both** tiler
> shapes — the range form the reference wrote *and* the slice form every real reader wrote:
>
> ```swift
> func byteRange(ofChunk index: Int) -> Range<Int>   // give me an index, get a RANGE
> func chunk(of data: Data, at index: Int) -> Data   // give me the whole + an index, get a PART
> ```
>
> The two owe **different** laws — a range tiler owes "consecutive parts abut", a slice tiler owes
> "concatenating the parts reproduces the whole" — and stating the range law at a byte-returning
> function would send the reader hunting for upper bounds it does not have, so the template branches
> on the form. The slice form also needs a tiebreak the range form does not: `(C, Int) -> C` is a
> filter, a prefix, a page *and* a partition, so the integer must read as a **position** (`at`,
> `index`, `ofChunk`) — not a quantity (`threshold`, `count`) — or the template proposes a tiling law
> over `above(_ items:, threshold:)`, which tiles nothing. That is the B10 false-law mistake, and the
> tiebreak stops it. On all three walk-5 trees: partition law **0 → 1**, at score 60 (Likely), with
> the clamp clause that names the resume-counter bug.
>
> The original doc comment said *"deliberately not keyed on names — the signature is the evidence."*
> Right about the principle, and then keyed on **one author's signature** — the same mistake in a
> better disguise. That is now written into the file.

<details><summary>Walk 5 — the measurement that found it</summary>

> **Walk 5, three cold readers, full toolchain (B6b + B7 + B9 + B10 + B11).** The first walk on a
> fixture that was clean *by construction* — B6d having moved the answer key off `main` — and the
> first where the shim actually compiled, so readers could **run** a law instead of reasoning about
> one. **Row 9: grandchild 3/3. Empty-file 0/3. Resume-counter 0/3.**

**The grandchild result holds, and it holds for the reason B3 predicted.** All three readers reached
it from default output, all three by the same route, and all three quote the same sentence — *"bias
the generator toward inputs where structure COLLIDES — a small alphabet, repeated components."*
Reader 3 measured 957/3000 generated pairs disagreeing with the reference definition; reader 2,
1266/20000. Reader 1 stated the design lesson outright: **"the lowest-scored law shown was the only
one that found a bug, and the three highest-confidence laws all passed."** B10's promotion is what
put that 20-point law on screen.

**But the chunked-upload bugs are gone, and the cause is not a seeding gap. B9 worked.** All three
readers' `ChunkPlan` **is** seeded. The `partition` law simply never fires — because **all three
independently wrote the same shape, and it is not the shape the template wants:**

```swift
func chunk(of data: Data, at index: Int) -> Data      // ← what 3 of 3 readers wrote
func byteRange(ofChunk index: Int) -> Range<Int>      // ← what PartitionPairing requires
```

**Five walks of "the extraction lottery" collapse here into one reproducible fact.** It was never
noise: `PartitionPairing` demands a tiler returning `Range<Int>`, and *the reference implementation's
shape is the outlier*. Row 5 has been passing only because **I** fed the template the reference's
own `ChunkPlan`. A real reader reaches for the slice, every time.

**So the fix is not to prescribe the signature — it is to widen the template.** When three
independent readers write the same thing, the tool is wrong to demand a different one. And a
slice-returning tiler carries both clauses intact: the parts concatenate to the whole, and an
out-of-range index must yield **empty, not a trap** — `dropFirst(negative)` *traps*, and that **is**
the resume-counter bug.

**Three more findings from the same walk, all corroborated by more than one reader:**

- **Half the mandated extraction buys nothing.** 3 of the 6 kernels the linter orders you to extract
  are never re-seeded: `ChunkPlan.totalChunks` (a computed `var`), `DownloadProgressTracker.progress`
  (`mutating`), `FileResponseMapper.makeFile` (returns a class). The pure-function rule seeds only
  non-`mutating` `func`s returning an `Equatable` value. Reader 3: *"the only law content the
  toolchain ever produced for the upload/download kernels survived only as prose I carried forward by
  hand."*
- **The linter's `collect` prose is a FALSE law**, and two readers caught it. *"Progress should …
  terminate at 1.0"* is violated by the kernel (last report `0.99`) and **satisfied by the
  composition** — `downloadFile` bookends with `progressHandler(1)`, and says so in its doc comment.
  **Judging an extracted kernel in isolation, which is exactly what the loop invites, manufactures a
  bug report here.** This is the `monotonicity`-on-`key.count` mistake (B10) in the *linter's* half of
  the toolchain, and it is not yet fixed there.
- **The `state-machine` law still vanishes when you do the work.** It appears in run 1 only via B7's
  rescue ("every other suggestion is a tautology"); once extraction yields a real comparator law, the
  rescue stops firing and the law drops below the cut. Two readers kept it only by saving run 1's
  transcript. B7's guarantee is *per-run*, and this is the per-function gap again.

**A fifth bug, and the toolchain proposed nothing that could catch it.** Reader 2 found — and I
verified — that `selectAllFiles()` selects from `files` (`MacCloudViewModel+Helpers.swift:24`) while
`FileListView` renders `filteredFiles` (`:83`), and Delete acts on `selectedFiles` (`:113`). **With a
search active, "Select All" → Delete destroys files the user never saw, locally and on the server.**
The irony is worth keeping: **B3 examined `selectAllFiles`/`deselectAllFiles` and correctly rejected
the pairing** (`deselectAll ∘ selectAll ≠ id`) — while the real bug sat two lines away, in *which
collection* `selectAll` reads. No shape-derived law reaches a "two views of the same state disagree"
bug.

</details>

### B13. ~~The template describes the generator its law needs — and makes the reader write it~~ — **DONE**

> **Closed.** SwiftInferProperties `7b4af37`. Templates now **emit** the generator the law needs, as
> runnable Swift, instead of describing it in prose.

**Every walk said the same thing, and it is the deepest finding in the whole exercise:** the loop
*points at* bugs it cannot *catch*, because a law and the inputs it runs on are one artefact and the
tool was shipping only half of it. Every cold reader who found the grandchild bug found it the same
way — by reading the caveat *"bias the generator toward inputs where structure COLLIDES — a small
alphabet, repeated components"* and then **hand-writing that generator themselves.** Reader 1 measured
5341 failures in 20000 inputs once they did; under a wide alphabet the identical law passes clean.

So the template's knowledge reached the reader as *English to re-derive*, not as *code to run* — the
same failure as a linter that prints a finding it never seeds (B6b), one layer further in. The fix:
`GeneratorRecipe` + `CollisionBias`, and each template declares the generator its law needs.

- **predicate** → a four-symbol alphabet *including the separator*, so substrings repeat and any path
  contains its own ancestors — **plus a recipe for the carrier's own state**, because
  `isImmediateChild(_ path:)` on a type holding `currentPath` puts one half of the collision in each,
  and a generator varying only the argument cannot produce it. That reasoning is exactly what three
  readers had to derive alone.
- **partition** → `Gen<Int>.int(in: -50...500)` — negative and past-the-end *on purpose*, because a
  generator over `0..<count` checks totality against the indices that were never in doubt.
- **comparator** → a small key universe so **ties occur**; transitivity of incomparability is vacuous
  without them.

**Two mistakes on the way, both worth the tests they now carry.** First: I shipped a *path* generator
for every `String` parameter, and it handed the **search** predicate `/a/b/c`. What generalises is not
the *shape* but the **alphabet** — a template cannot know a `String` is a path. Second, and sharper:
the recipes **vanished between the template and the renderer.** `Suggestion` was rebuilt field-by-field
in **eight** places, and `GeneratorSelection` carried a comment saying this exact loss had *already
happened once* (`carrierTypeName`, V1.151) — the lesson written down and the trap left armed. It ate
`generatorRecipes` next. Fixed by making the fields `var` and replacing every rebuild with a mutating
copy, and pinned by an invariant test: populate every field, apply a transform, undo its one change,
require equality — so a field added next year is covered the day it is added.

### B14. **The trap that outgrew the toolchain: `Lossy Struct Rebuild`** — a lint rule, and a 19-bug fleet sweep

B13's silent field-drop was not a one-off. `Suggestion` had it eight times; `GeneratorSelection` and
`CrossValidation` carried comments proving it had been *found and re-armed* three separate times. The
shape is: **a value rebuilt field-by-field from one you already have, whose initialiser has defaulted
parameters — so a field you forget takes its default silently, and the code compiles.** The defaults
are the whole mechanism; with all-required parameters the omission is a compile error.

That is exactly what a linter is for, so it became one — **`Lossy Struct Rebuild`** in SwiftProjectLint
(`5234d13`), warning severity, with a project-wide `DefaultedInitializerCollector` to see the one fact
that separates a hazard from a habit: *does the initialiser have defaults?* It was validated against
SwiftInferProperties at the commit before the fixes — **8 of the 8 real sites caught** — and every
refinement was forced by a real miss or false positive (implicit-`self` rebuilds it was blind to; nine
false positives from `static` factories reading their own parameters; a cross-type projection the ratio
over-fired on). The write-up lives in `docs/rules/lossy-struct-rebuild.md`.

**Then it was run across all 18 owned repos. It found 19 field-by-field rebuilds — and two of them
were live production bugs.**

| repo | fixed | kind |
|---|---|---|
| **SwiftPropertyLaws** | 2 | **LIVE** — inherited law checks silently dropped `allowNaN` + replay options (5 of 8 fields copied); suppressing a failure discarded its shrunk counterexample + coverage (8 of 12) |
| SwiftInferProperties | 12 | mixed; two carried "preserve this field" comments — prior fixes that re-armed the trap |
| SwiftLintRuleStudioTeam | 3 | latent; `FleetRepo.realigned()`'s doc comment *asserted* the invariant it could not keep |
| SwiftAssist | 1 | a seven-field rebuild that changed **nothing** — already `= pair` |
| SwiftUMLStudio | 1 | latent; the base came from a function return, so the rule hedged rather than confirmed |
| MacCloud (×3), + 12 others | 0 | clean |

**The meta-point.** This is the PBT process turned on its own toolchain and then on the whole fleet: a
note about one function became a rule that found nineteen instances of the same bug across six
codebases, two of them shipping wrong answers today. The two live ones are in **SwiftPropertyLaws — the
law kit the whole exercise depends on** — which is the sharpest possible statement of why the loop
exists. And the rule's own limit is honest and recorded: a copy whose source is a function *return*
(not a constructor) is found but only *hedged*, never type-confirmed — the SwiftUMLStudio hit is the
example.

**One thing this closes on the loop itself:** the two chunked-upload bugs the PBT process found on the
iOS client were ported and fixed on the **macOS** client too (`MacCloud_client_MacOS`, mutation-verified
— the tests trap against the old loop, pass against the `ChunkPlan` clamp). And `Lossy Struct Rebuild`
is clean on both MacCloud clients and the server: **a static shape-matcher cannot see an unclamped index
or a divide-by-zero**, which is precisely the boundary between what a linter catches and what only a
property test can.

### B15. **Walk 6 — the resume-counter bug moves off zero, and the generators earn their keep (mostly)**

> **Three cold readers, current toolchain (B12 + B13 shipped), fixture clean by construction, shim
> compiles.** The first walk where readers were handed *runnable generators* instead of
> `Generator: not yet computed`. **Row 9: grandchild 3/3 · resume-counter 1/3 · empty-file 0/3.**

**The headline: the resume-counter bug was reached by a cold reader for the first time.** Walk 5 had
it at 0/3; walk 6, 1/3 — and the one who got it did so *exactly* along the B12→B13 path. Reader 2
extracted a **slice tiler** (`func slice(_ data: Data, index: Int) -> Data`), which B12's widened
detection recognised, which fired the `partition` law, which shipped `Gen<Int>.int(in: -50...500)`,
whose negative range **crashed the shipped code** on `dropFirst(negative)`. Reader 2's own words:
*"the shipped `Gen<Int>.int(in: -50...500)` deliberately spans negatives. A naive in-range generator
would never find this… Essential."* That is the whole thesis of B12+B13, measured cold.

**B13's core claim — that the generator, not the prose, is what finds the bug — is proven on the
grandchild bug 3/3.** Every reader ran the shipped collision generator and every reader ran a *uniform
control*, and the controls came back empty: reader 3 measured **759 failures in 4238 biased samples
vs 0 in 20000 uniform**; reader 1, *"passes vacuously"*; reader 2, *"would almost never hit the
collision."* For four walks readers hand-wrote that generator from the caveat; walk 6 shows the
shipped one does the job — when it compiles (below).

**Why resume-counter is 1/3 and not 3/3: the extraction lottery, unchanged.** B12 widened the *shapes*
a tiler may take, but it cannot fire if the reader does not write a tiler at all. Readers 1 and 3
extracted the chunk **count** (`chunkCount(byteCount:chunkSize:) -> Int`, a scalar) rather than a
slicer, so no partition law was proposed for them and neither reached the bug. Which of the three
bugs a reader reaches still depends on the shape they happen to lift — the kernel advisory says
"extract the arithmetic," not "extract a tiler." Closing that gap is a linter-advisory problem, not a
template one.

**Two real toolchain defects, flagged independently by all three readers:**

- **B15a — the shipped generators did not compile against the vendored kit.** ~~Open.~~ **DONE**,
  SwiftInferProperties `4ef63be`. This was the sharp one, because it undercut B13 directly. `CollisionBias`
  emitted `Gen.frequency(…)` (`@available(swift 6.2)`, dead in an older language mode),
  `Gen.array(of:count:)` (a *static* form that does not exist — the kit has only an **instance**
  `.array(of:)`), and `\(Type).gen()` for the carrier recipe (no such method). *Correct in spirit,
  wrong in API*, so all three readers hand-re-implemented — the toil B13 set out to remove.
  > **Fixed and verified the only way a "does not compile" bug can be:** a harness against the exact
  > pinned kit first *reproduced* the readers' error verbatim (`type 'Gen<Value>' has no member
  > 'array'`), then the release binary's **actual emitted output** — all three generator blocks —
  > compiled verbatim. `frequency` is gone (the `"/"` root case now falls out of a zero-length array
  > draw, no weighting combinator needed); `array(of:)` is the instance form; the carrier recipe ships
  > the runnable colliding-string half and names the one manual init step in a comment instead of a
  > fake `.gen()`. `GeneratorRecipeCompileSafetyTests` bans the three constructs from returning.
- **B15b — the structured `Generator:` field stays blank.** Every suggestion still prints
  `Generator: not yet computed (M3 prerequisite)` / `.todo`; the runnable recipe lives only in the
  separate "Generators the law needs" prose block. A consumer machine-reading the field concludes no
  generator shipped. Cosmetic next to B15a, but it means the two channels disagree about the same
  fact.

**Empty-file stays 0/3.** Even reader 2, who held the partition law, pursued its *totality* clause
(the negative-index crash) rather than its *progress-terminates-at-1.0* clause — the empty-payload
progress bug is reachable through the same law but was not the counterexample the generator drove to.
No reader reached it.

**Net.** Walk 6 is the first walk to move a chunked-upload bug off zero, and it moved it by precisely
the mechanism B12+B13 were built for. Of the two things that held it to 1/3, **B15a is now fixed** —
the shipped generators compile, verified against the pinned kit — so a reader who extracts a tiler can
now paste-and-run as promised. The one remaining gap is the **extraction lottery**: 2 of 3 readers
lifted a scalar `chunkCount` instead of a slicer, so no partition law was proposed for them. That is a
*kernel-advisory* problem — the linter says "extract the arithmetic," not "extract a tiler that maps an
index to its slice" — and it is the natural next item, and the last thing standing between
resume-counter's 1/3 and 3/3.

### B16. ~~The kernel advisory names the location but not the tiler shape~~ — **DONE** (nudge; unmeasured)

> **Fixed.** SwiftProjectLint `21f0f5d`. The `ExtractablePureKernel` advisory now **branches on
> whether the kernel slices**, the same way its law text already did.

Walk 6 isolated the last lever on resume-counter to a single sentence in the linter. *"Extract the
arithmetic into a value type"* is under-specified in the one case where the reader has a real choice:
given chunking math, 2 of 3 cold readers lifted the scalar **count** (`func chunkCount(...) -> Int`),
because a scalar is the most obvious "arithmetic." **A count is a pure function but not a tiler** — no
law over it says the parts tile the whole — so the `partition` law that catches the resume-counter and
empty-payload bugs was never proposed for them, and the bug sat one method away.

The advisory now says, *when slicing arithmetic is present*: extract a value type whose key method
**maps a part index to its slice or byte range** — `func chunk(of whole:, at index:) -> Part` or
`func byteRange(ofChunk:) -> Range<Int>` — because *that* method carries the tiling law and a bare
count does not. A fraction-only kernel (a progress throttle) keeps the generic advice; naming a tiler
there would be cargo-culting. Verified on the fixture: the chunk kernel gets the tiler advice, the
`collect` progress kernel stays generic; both pinned by tests.

**This is a nudge, not a guarantee** — the reader still chooses what to extract, and the advisory can
only make the tiler the obvious choice. **Walk 7 measured it: 1/3 → 2/3.** Two of three readers took
the tiler advice and reached the bug; the third lifted a scalar resume-index and drew a red herring —
the nudge landed for two readers, not the third. See B17.

### B17. **Walk 7 — the loop reaches all three bugs for the first time, and the extraction lottery is the last one standing**

> **Three cold readers, current toolchain (B12 + B13 + B15a + B16 shipped), fixture clean by
> construction, shim compiles, kit lab pre-validated by the examiner (a faithfully-ported tiler +
> the shipped `Gen<Int>.int(in: -50...500)` crashes on `dropFirst(negative)` before any reader is
> dispatched — so a miss is a reader gap, not a broken harness).** **Row 9: grandchild 3/3 ·
> empty-file 3/3 · resume-counter 2/3 — and 2 of 3 readers reached ALL THREE.** Every reader
> reached at least two. Walk 6 was the loop reliably finding *one*; walk 7 is the first walk that
> reaches all three across readers, and the first where any single reader reaches all three.

**Empty-file moved 0/3 → 3/3, and it is B13's vacuity warning that paid — measured cold on three
readers.** Every reader wrote the obvious "progress ends at 1.0" law over a wide integer range
first, and every one of them watched it pass **green while the bug was live** — because 100 uniform
draws over `0...4_000_000` (reader 2), `0...2000` (reader 3) or `0...10_000` (reader 1) never sample
the empty payload. All three then followed the advisory's instruction — *"name the empty case
explicitly, or it passes VACUOUSLY"* (B13, and echoed in B16's kernel prose: *"progress should
terminate at 1.0 — including for an empty input"* printed at the extraction site) — wrote the
`byteCount == 0` case as its own test, and caught it: `emittedProgress().last → nil == 1.0`. Reader
2's words: *"the wide generator passed vacuously… only the boundary bias catches it."* Reader 3:
*"following the advisory's 'name the empty case' instruction was load-bearing."* This is the
clearest cold measurement yet that **a generator, not a law, is what finds a boundary bug** — the
same B13 thesis the grandchild result proved, now proven on the empty case the four prior walks all
missed.

**And the empty-file find is the real bug, not the B12 false positive — the readers checked.** The
walk-5 hazard was that judging an extracted progress kernel *in isolation* manufactures a bug the
composition does not have: `downloadFile` bookends `collect`'s `0.99` with a terminal
`progressHandler(1)`. Two readers independently confirmed the **upload** path has no such bookend —
`uploadRemainingChunks` calls `progressHandler` **only inside the `while` loop** (`:80`), so an empty
payload (`totalChunks == 0`, loop body never runs) returns with the bar stranded, and `uploadFile`'s
0-byte short-circuit does not cover `uploadFileChunked` / `resumeChunkedUpload` /
`retryPendingChunkedUpload`. The distinction B12 drew — isolation-false on download, real on upload —
held under three cold readings.

**Resume-counter moved 1/3 → 2/3, exactly along the B16→B15a path, and the third miss is the whole
remaining story.** Readers 1 and 3 took B16's tiler advice literally — both lifted
`byteRange(ofChunk index: Int) -> Range<Int>`, the shape the advisory now names — which fired the
partition law, which shipped `Gen<Int>.int(in: -50...500)`, whose negative range ran **verbatim,
uncompiled-around** (B15a) straight into the app's ungated `dropFirst(index * chunkSize)`. Reader 3
reproduced walk-6-reader-2's crash with **no hand-editing of the generator** —
`Swift/Collection.swift:1252: Fatal error: Can't drop a negative number of elements` — which is
precisely what B15a was built to make possible and walk 6 could not yet show. Reader 1 drove the
same law's *overshoot* branch (`queuedChunks ≥ totalChunks` → silently completes) and named the
negative-trap in prose. Both reached the canonical unclamped-index bug the reference's
`min(max(queuedChunks, 0), total)` clamp fixes.

**The third reader is the extraction lottery, undefeated.** Reader 2 did not lift a tiler. It lifted
a **scalar** — `resumeStartIndex(queuedChunks:verifiedChunks:) -> Int` — and a `(Int, Int) -> Int`
signature draws the **associativity / commutativity** templates (*"proven analog: Int is a
commutative monoid under +"*), which are pure red herrings: `resumeStartIndex` is neither `+` nor
associative. No partition law, no `-50...500` generator, no clamp hazard. Reasoning by hand instead,
reader 2 pointed at the *same line* (`:74`) but described a **different** defect — *"resume no
further than `verifiedChunks`, not `queuedChunks`"* — a plausible field-choice concern that rests on
a server-semantics assumption reader 2 explicitly declined to confirm, and that **the answer key does
not assert** (the reference *clamps* `queuedChunks`; it does not switch fields). **It is not scored
as reaching the resume-counter bug** — for the same reason B3's `selectAllFiles` pairing and B10's
`monotonicity`-on-`key.count` were not scored: a reach that names a *different* claim at the right
line is not the bug, and crediting it would be grading the tool's homework. Same site, different bug,
because a different shape was extracted. **B16 is a nudge, not a guarantee, exactly as it said of
itself: the nudge landed for two readers of three.**

**What this isolates.** The lottery is now the *single* lever between resume-counter's 2/3 and 3/3,
and it has narrowed to a sharper point than "extract a tiler, not a count." B16 already warns that a
bare chunk **count** walks past the bug — but reader 2 did not extract a count; it extracted a
resume **index** function, a shape B16's prose does not cover. The next advisory move is to name
that shape too: *the resume start is not a kernel of its own — it is the `startIndex` of the tiler,
and it is where the clamp lives.* That is a linter-advisory item (**B18**, now built — see below),
not a template one — the template did its job for every reader who reached it.

**Three toolchain frictions surfaced, all corroborated by more than one reader:**

- **A trapping law aborts the whole Swift Testing run, and `--skip` / `--filter` cannot save it.**
  Swift Testing runs a suite's tests as concurrent tasks in one process, so the resume-counter
  `fatalError` takes the passing laws down with it regardless of filtering. Readers 1 and 3 both had
  to split the trapping totality law into its own suite and run the rest with an explicit exclude.
  Worth a book note next to §28.1.1 — a property that traps rather than records an issue is a
  first-class reproduction hazard, and the kit's non-fatal-failure posture (SwiftIdempotency §26.6)
  is the contrast to draw.
- **The scalar-arithmetic templates over-fire under `--include-possible`.** `(Int, Int) -> Int`
  pulled `associativity` and `commutativity` for reader 2 with a "proven analog" citation, which is
  the `idempotence`-on-`offset(of:)` noise B10 set out to narrow — surviving here because
  `--include-possible` (which the documented re-run protocol passes) reopens exactly the tier B10
  closes by default. Candidate: role-entailment should gate these the same way it gates the others,
  even with the flag.
- **The seed join still reads as a failure before the extraction.** All three readers hit
  `kept 0 of 1 seedable suggestion(s)` in phase 1 and had to notice the kernel pointers *below* the
  warning were the real guide. B7's diagnosis is correct and the message is honest, but "kept 0"
  above the fold still reads as "nothing here" to a reader who has not yet learned the two-phase
  shape.

**Two unscored finds, adjudicated by row 4a, not by the tool.** Reader 3 (via a failing range law)
and readers 1 & 2 (via code reading) turned up **unclamped progress fractions the answer key does not
contain**: `MacCloudAPIService.collect` (`:244`) divides by `expectedBytes` with no upper clamp, so a
server that over-sends drives `FileOperationProgress.progress` past `1.0`; and
`getStorageUsagePercentage()` (`Helpers.swift:93`) returns `used / total` unclamped. Neither is on
`pbt-road-test-reference`, so **neither is scored** — the key is frozen at `f3575b7` and nothing the
tools find may be added to it (the `filteredFiles` rule again). But each carries a refutable law on
the benchmark's own terms — *a progress fraction is bounded in `0...1`* rejects the unclamped
implementation and admits the clamped one — so each is a genuine candidate, independent of the tool
that proposed it. Recorded as unscored, exactly as the plan requires.

**The honesty caveat that outlives every walk (B8).** This is still the *same fixture*, and the
templates have now seen it across seven walks. B15a's generator fix and B16's advisory were both
written after the bugs were known. Walk 7 shows the shipped artefacts *work cold* — the generators
compile and run, the advisory steers two of three readers to the right shape — but it cannot show the
templates would find these shapes on a fixture they have never seen. Every number here is an upper
bound until a second fixture exists.

### B18. ~~The tiler advisory names the slice shape but not the resume index~~ — **DONE** (nudge; **measured, walk 8: closed the scalar miss, did not reach 3/3**)

> **Fixed.** SwiftProjectLint `70ff2f7`. The `ExtractablePureKernel` tiler advisory now also
> names the **resume index** when the kernel has one, and warns the reader off lifting it as a
> separate scalar — the shape that held resume-counter at 2/3 in walk 7.

Walk 7 moved resume-counter 1/3 → 2/3 and isolated the last miss to a single reader's *extraction
choice*: reader 2 lifted the resume point — `var index = current.queuedChunks` — as its own
`func resumeIndex(queuedChunks:verifiedChunks:) -> Int`, a `(Int, Int) -> Int` scalar that draws the
associativity/commutativity red herrings, carries no tiling law, and pointed at the right line
(`:74`) while naming a *different* defect. B16 already warns that a bare **count** walks past the
bug — but a resume **index** is a shape B16's prose did not cover.

B18 covers it, and the precision is the whole point. When a tiler's loop is seeded from a
**non-literal** — a `var` sourced from outside the kernel (`var index = current.queuedChunks`), *not*
a literal `0` — and that variable drives the slice, the advisory appends: *the resume point is not a
kernel of its own; do not lift it as a separate `func resumeIndex(...) -> Int`; it is the tiler's
clamped `startIndex`, and an unclamped start from a server counter either traps (negative) or
silently completes a partial upload (too large) — the clamp is the property the tiler owes.* The
signal is a **`var` seeded from a non-literal that appears in slicing arithmetic**, not a blanket:
a tiler seeded from a literal `0` has no resume concept and keeps the shorter B16 advice, so a clamp
is never cargo-culted onto a bug the code cannot have. Verified on the fixture — `uploadRemainingChunks`
gets the resume clause, the `collect` progress kernel stays generic, and a `var index = 0` tiler
keeps plain tiler advice; all three pinned by tests.

**This is a nudge, not a guarantee** — it steers the reader who would otherwise extract a scalar
toward folding the index into the tiler, but the reader still chooses what to lift. **Walk 8 measured
it (below): B18 did exactly what it was built to do and no more — every reader folded the index into a
tiler, the scalar miss is closed — but resume-counter held at 2/3, because the lottery relocated to a
place a linter advisory cannot reach.** That relocation is B19.

### B19. **Walk 8 — B18 closes the scalar miss, the lottery relocates to the generator, and the fix follows**

> **Three cold readers, current toolchain (B18 shipped), same fixture and harness as walk 7, only the
> linter advisory changed.** **Row 9: grandchild 3/3 · resume-counter 2/3 · empty-file 2/3 — 2 of 3
> readers reached all three, unchanged from walk 7.** B18 did not move resume-counter to 3/3.

**B18 worked, on its own terms — and this is the part worth keeping.** Walk 7's resume-counter miss
was a reader who lifted the resume point as a *separate scalar* `func resumeIndex(...) -> Int`. In
walk 8 **no reader did that.** All three folded the index into a tiler, exactly as the advisory now
instructs — the scalar-extraction lottery B18 targeted is closed, measured cold. Readers 1 and 3 read
the advisory's clamp language back verbatim (*"the resume index belongs INSIDE the value type, clamped
to `0...count`… an unclamped start either traps (negative) or silently completes a partial upload (too
large)"*), lifted the single-index `byteRange(ofChunk:) -> Range<Int>` tiler, fired the partition law,
ran the shipped `Gen<Int>.int(in: -50...500)`, and reached **both** branches — the negative-index
crash (`Fatal error: Can't drop a negative number of elements`, verified on re-run) and the
too-large-silently-completes branch. Both 3/3 on all three bugs.

**And yet resume-counter stayed 2/3, because the miss moved one layer in.** Reader 2 folded the index
into a tiler as instructed — `remainingRanges(dataCount:queuedChunks:)`, the counter *inside* the
type, no separate scalar — and then **clamped the generator**: its test wrote
`let queued = min(rawQueued, total) // server can't have queued more than exist`, and its kernel wrote
`min(start + chunkSize, dataCount)`. The shipped negatives never reached the code, the totality law
passed, and the bug walked free. **The comment is the bug's own assumption, typed by the reader.**
B18 can put the index in the right place; it cannot stop a reader who "knows" the counter is
trustworthy from narrowing the one generator built to prove otherwise. This is the loop's recurring
shape — a fix closes one route and the miss reappears in the next organ (A1, B5, B7) — arriving this
time on the **generator** side, which no linter advisory can reach.

**Empty-file's 3/3 → 2/3 is reader-2 variance, not a regression.** B18 does not touch empty-file;
reader 2 cleared it by inspecting the *guarded* download `collect` path and overlooking the
*unguarded* chunked-upload path (and its self-clamped kernel never produced the empty case anyway).
Readers 1 and 3 both caught it from the named empty case, as in walk 7.

> **The fix — DONE.** SwiftInferProperties `0894b1a`. The `outOfRangeIndex` generator recipe now
> **warns the reader off clamping it**, in the two places the reader reads — the pasted inline comment
> (*"Do NOT wrap this in `min(index, count)` or `max(0, index)`: clamping the INPUT re-encodes the
> exact assumption the law exists to refute… paste the range as-is; the clamp belongs in the code
> under test"*) and the rationale (*"Do not clamp this generator — a `min(queued, total)` guard on the
> input, however 'sensible,' asserts the counter is trustworthy, which is the one thing this law is
> here to deny"*). It is the exact analogue of `collidingString`'s *"do not widen this alphabet"*
> guard — the two ways a reader defeats an adversarial generator are narrowing its range and widening
> its alphabet, and both now carry an explicit warning that travels with the pasted code. Verified: the
> warning surfaces in `discover`'s phase-2 output for the tiler, the recipe still compiles against the
> pinned kit (the measured compile test), and the guard is pinned by a content test.

**This is a nudge, not a guarantee** — it is the same *kind* of intervention as B16/B18, one layer
further in, and it has the same honest limit: a reader who is determined to trust the counter can
delete the comment. **Walk 9 measured it: resume-counter 2/3 → 3/3, and row 9 reached 3/3 for the
first time.** See B20. And note what it still cannot do: the deeper fix would be to stop the reader
*needing* to paste the generator at all — the discipline B13 started and B15b left open (the structured
`Generator:` field is still blank; the runnable recipe lives only in prose). A generator the reader
runs by reference rather than by copy-paste is one they cannot quietly clamp. That is the standing
B15b debt, and it is what would make row 9's 3/3 hold against a reader who *wants* to trust the counter.

### B20. **Walk 9 — 3/3: every cold reader reaches every bug, and row 9 is met**

> **Three cold readers, current toolchain (B19 shipped), same fixture and harness as walks 7–8, only
> the generator recipe changed.** **Row 9: grandchild 3/3 · empty-file 3/3 · resume-counter 3/3 — and
> all three readers reached all three bugs.** The one number the benchmark exists to move is met.

**B19 landed on exactly the reader it was written for.** Walk 8's resume-counter miss was reader 2,
who folded the index into a tiler as advised and then wrapped the shipped generator in
`min(queued, total)` — the bug's own assumption, typed by the reader. In walk 9 the same slot pasted
the generator **verbatim**: its test carries the comment *"Generator pasted AS GIVEN from discovery:
`Gen<Int>.int(in: -50...500)`"*, it added no `min` guard to the resume input, and it reached both
resume-counter branches. The one behaviour B19 exists to stop, it stopped — measured cold. Readers 1
and 3 also ran the generator raw and both quoted the *"do not clamp"* guidance back as the reason.

**Resume-counter is 3/3, by the canonical bug, though the route varied — and the variance is worth
recording.** Readers 1 and 3 lifted a `byteRange`/`chunk` that calls `dropFirst` directly, so the
shipped negative index produced an **in-suite SIGTRAP** (`Precondition failed: dropFirst requires a
non-negative count`, re-verified on both). Reader 2's tiler kept a partial upper-bound `min(_, dataCount)`
clamp, so *its* negative case surfaced as a **failing totality law** — `byteRange(ofChunk: -1)`
returned a bogus non-empty `-1..<…` instead of the empty range the law demands — plus an external
`dropFirst(-2)` crash repro. All three are genuine reaches of the *same* unclamped-index defect; the
counterexample was delivered by a crash for two readers and by a law-failure-plus-repro for the third.
Both the negative-trap and the too-large-silently-completes branch were reached.

**Empty-file recovered 2/3 → 3/3**, confirming walk 8's dip was a single weak reader, not a
regression: all three walk-9 readers wrote the named empty case and caught `progress.last == nil`.

**The chain that earned row 9, in one line each — because no single fix did it:** B1/B2 named the
kernels; B3/B12 gave the partition law the slice shape a real reader writes; B13/B15a shipped a
generator that compiles and runs; B16/B18 got the reader to extract a *tiler* and fold the resume
index in; B19 stopped them clamping it back out. Pull any one and the walks show row 9 falling back.

**And the honesty caveat is now load-bearing, not a footnote (B8).** Row 9 is 3/3 on a fixture the
templates have been tuned against across **eight cold walks**, with B12/B13/B16/B18/B19 all authored
after the three bugs were known. Every generator, every advisory, every clamp warning is *recitation
proven to transfer to a cold reader* — which is a real and measured result — but it is **not** proof
that the loop would find these shapes on a fixture it has never seen. The 3/3 is an upper bound. The
only test that retires the caveat is a **second fixture**, forked fresh, that the templates have never
touched — and until that exists, the number to quote is "3/3, on the fixture the tools were built
against," with the second clause said as loudly as the first. **B21 ran that second fixture, and the
number it returned is 1 of 4.**

### B21. **The second fixture — new bugs, blind key, and the honest generalization number: 1 of 4**

> **A fresh fixture forked from `f3dbb6f`, the three known bugs fixed inline so only new defects
> remain, four new bugs planted by a *tool-blind* agent that was told nothing about property testing
> or the templates, verified by diff, then walked cold by three readers (shim-free, via `--sources`).
> Result: 1 of 4 new bugs reached — B4, by all three readers. This is the first number in this
> document that is not an upper bound.**

**The method is the point, because I am contaminated and cannot grade my own homework.** Having
authored B12–B19 against the known bugs, I cannot pick a "new" bug without unconsciously choosing one
the templates already cover — the same "adjust the denominator" sin the answer-key rule exists to
stop, one level up. So the bugs were planted by a **blind planter agent** given only the sealed app
and a tool-agnostic brief ("plant four realistic, subtle bugs a developer might write"), with no
mention of PBT, swift-infer, the templates, or the old bugs. Its choices are therefore independent of
what the tools cover. Its written list is the **blind key**, verified against a corrected-vs-planted
diff (exactly four one-line changes, four files, no tells). And the shape-classification + reachability
predictions were **written down before any reader reported**, so the grade could not be rationalized
to fit the outcome.

**The four bugs, and why the loop reached one:**

| bug | site | shape | templates cover it? | reached |
|---|---|---|---|---|
| **B4** | `ChunkedUpload.swift:73` — floor `totalChunks` (`n/k` not `ceil`), drops the trailing partial chunk | **partition count** | yes | **3/3** |
| **B2** | `FileOperations.swift:108` — `navigateUp` uses `.dropFirst()` not `.dropLast()` | **state-machine** | fires, but the mutator is impure | 0/3 |
| **B1** | `Helpers.swift:95` — `getStoragePercentage` × 100, returns 20.0 not 0.2 | numeric 0…1 bound | domain knowledge only | 0/3 |
| **B3** | `SyncSessions.swift:82` — 409↔507 error mapping swapped | error-mapping in an impure switch | no | 0/3 |

**The one win is real generalization, not recitation** — and that matters. B4 is a *different* defect
than the resume-clamp the tools were built against at that method; the general "count == ceil(n/k)"
tiling law caught it on a fixture the templates had never seen, cold, three readers of three. The
loop catches unseen instances of the shape it is built for.

**But three of four were missed, each for a structural reason, and this is the honest headline:**

- **B2 — the template fires and cannot be run.** The state-machine law (`navigateUp ∘ navigateToFolder
  == id`) *was proposed*, and it catches `dropFirst`. All three readers declined to run it, for the
  same reason: `navigateUp` is an impure `@MainActor` view-model mutator that needs a faked
  SwiftData/network harness. The loop is built on extracting **pure** kernels; a state machine over
  impure mutable state does not fit that mold, so "covered in principle" is not "reachable." (This is
  the one prediction I got wrong, and it was wrong for exactly this reason.)
- **B1 — a pure function whose bug needs a bound no template supplies.** `getStoragePercentage` is
  seeded, but swift-infer offers only the determinism law `f(x)==f(x)`, which passes. "Result must be
  0…1" is domain knowledge; nothing proposes it.
- **B3 — a domain spec fact in an impure switch.** "409 → syncConflict" has no pure kernel and no
  template.

**The sharpest caveat, which softens even the win.** B4 sits at the one method the B16/B18 advisory is
*most heavily pre-tuned to point at* — the tiler prose, the "walks past the bug" language, the clamp
warning. That loud advisory drew all three readers straight to that method, where they also found B4.
The tiling *law* is general; the *attention* was tuned against the old bugs there. The bugs in methods
the tools were **not** pre-pointed at — storage, navigation, sync-error mapping — were all missed. And
every reader noted B4's decisive law came from the linter's advisory **prose**, not from swift-infer's
synthesized law (a passing determinism check). So even the win leans on the pre-tuned pointer and the
hand-transcribed prose law, not on the inference engine generalizing to a new location on its own.

**What this does to the 3/3.** The tuned fixture's three bugs were *all* in the loop's sweet spot — a
pure extractable kernel whose role entails a refutable law, with the templates tuned to them. On four
tool-blind bugs, **one** had that profile, and it was caught. The honest one-sentence reading:
**the loop reliably catches the class of bug it is built for, and that catching genuinely generalizes
to unseen instances — but that class is a minority of the bugs a real app contains.** A confident 3/3
and a sobering 1/4 are the same tool measured on two different bug populations, and both belong in the
book.

**What is still not retired.** The planter is tool-blind but is an AI agent, not an independent human;
and this is the **same app** whose structure the tools have seen across nine walks, so B21 retires
"tuned to *these* bugs," not "has never seen this codebase." The cleaner test — a genuinely different
app, new domain, new bug classes — remains the honest next step, and B21's 1-of-4 is the reason to
bother running it. **B22 ran it: a different app, 4 of 4 — and the reason the two numbers differ so
much is the finding.**

### B22. **The different app — SplitKit, 4 of 4, and why that is not the good news it looks like**

> **A genuinely different app: `SplitKit`, a bill-splitting library, *built* by a blind agent (its own
> design — money math, uneven-split rounding, greedy settlement, formatting, a store), then bugged by
> a *second* blind agent, then walked cold by three readers — three separate agents, none told anything
> about property testing. Result: all four planted bugs reached (union 4/4; each reader 3/4). This
> retires B21's "same app" caveat. But the *how* matters more than the number, and it is sobering.**

**Three fixtures, three numbers, one loop:**

| fixture | result | bug population |
|---|---|---|
| MacCloud, tuned (walks 1–9) | **3/3** | hand-picked for the loop's sweet spot; templates tuned to them |
| MacCloud, new bugs (B21) | **1/4** | tool-blind, *same app* — impure / undocumented shapes |
| **SplitKit (B22)** | **4/4 union, 3/4 each** | tool-blind, *unseen app* — pure, documented library |

**The inference engine caught essentially none of the four bugs, and all three readers said so
independently.** `swift-infer discover`'s scored suggestions — associativity, commutativity,
idempotence, determinism over the `Money` operators — pointed at **none** of the defects. The reaches
came from three other places, and naming them is the whole result:

| bug | reached via | route |
|---|---|---|
| **P2** even-split over-allocates by 1¢ (`<` → `<=`) | the **linter's tiling advisory** ("the parts should tile the whole exactly") | tool-led — the one genuine tool reach, 3/3 |
| **P4** thousands separator dropped for 4-digit values (`>3` → `>4`) | the **code's own docstring** (`"$1,234.50"`) turned into a law | reader, from the spec written in the comments — 3/3 |
| **P1** `.bankers` → `.plain` rounding | the **code's own docstring** ("banker's rounding") | reader, from the comments — 1/3 (only the reader who wrote a half-cent law) |
| **P3** settlement transactions reversed (`from`/`to` swapped) | the reader's **domain reasoning** ("applying the settlement should zero every balance") | reader, from knowing what settlement *means* — 2/3 |

So "the loop works on SplitKit" means, precisely: **the linter points at the pure kernels, and a
competent reader turns advisories, docstrings, and domain knowledge into the laws.** The property-
inference engine was a bystander for bug-finding. That is not a dig at a bad tool — it is the same
lesson row 4a and B3 have carried all along (*purity is a licence, not a hypothesis; laws come from
role, not from purity*), now measured on a fresh codebase: the falsifiable law comes from a **reference
definition**, and the tool cannot invent one. It can only point, recite a role's law, or — the new
observation here — surface one the *author* already wrote in a docstring.

**And SplitKit flatters the loop on both axes at once.** It is (a) a clean compiling library of
**public pure functions** — no impure-method barrier, unlike B21's `navigateUp` state machine that
*fired but could not be run* — and (b) **documented**, so the reference definitions the tool cannot
invent were sitting in the comments for the reader to lift. B21's 1/4 was the mirror image: bugs in
impure methods (unrunnable) or undocumented domain facts (no reference to refute against).

**The unifying finding — the one to put in the book.** The loop's yield is governed by two questions,
not by whether "it works":

1. **Is the buggy logic a cleanly-testable pure kernel** — or is it trapped in impure, stateful,
   effectful code the pure-kernel lab cannot drive?
2. **Is a reference definition available** — from a template's role, a linter advisory, a docstring, or
   the reader's own domain knowledge — or must one be invented from nothing?

Where **both** hold, cold readers reach the bug reliably (SplitKit, 4/4). Where **either** fails, they
miss (B21's impure/undocumented bugs, 1/4). The 3/3, the 1/4, and the 4/4 are the same loop measured at
three points on those two axes. The honest one-liner: **the loop reliably finds a bug when the code
offers it a pure kernel and a stated intent, and it is nearly blind otherwise — and how often those two
conditions hold is a property of the *codebase*, not of the tools.**

> **Author's-side corollary, now in the book — Chapter 15 §15.3.3 ("What the refactor is — and what it
> is not").** Axis 1 restated for the person *writing* the code: a bug the loop can point at but not
> drive lives in code that is not testable *by any means*, so clearing the blocker is ordinary
> dependency injection, not tool-appeasement — accept "make this testable," refuse "fit the tool's
> shape." The refactor comes in two sizes (the cheap pure-decision extraction, which clears most
> findings, vs. injecting every effect to drive a whole sequence — MBT, Chapters 19–20), and whether
> even the cheap one pays is a cost-benefit call the linter can flag but never make. That is the
> codebase-yield finding seen from the author's chair, and it is why adopting the loop on an impure
> tangle front-loads a testability refactor the tools cannot perform.

**Predictions, kept honest.** Written before the walk: P2 likely-reached (✓), P3 uncertain (✓), P1 and
P4 likely-miss (**✗, both wrong**). The miss in my own reasoning is the same one the tools make — I did
not credit that a documented library hands the reader its reference definitions for free, so "no
template covers formatting/rounding" was true and irrelevant: the docstring covered them.

**What B22 retires, and what it does not.** It retires B21's "same app" caveat — a genuinely different
domain, never seen, and the reachable class of bug generalized to it cleanly. It does **not** make the
builder, planter, or readers human: three separate blind AI agents are real independence layering, but
a person adopting these tools on their own undocumented code is the population that still has not been
measured — and B22 predicts that reader's yield sits closer to the 1/4 than the 4/4 wherever their code
is impure or undocumented.

### B10. ~~A law the code OWES is never hidden; a law it GUESSES is never promoted~~ — **DONE**

> **Closed.** SwiftInferProperties `3e38e34`. **Two regressions, one of which I shipped and the
> readers caught.**

**Two axes, and B7 shipped only one.**

| | means | example |
|---|---|---|
| **refutable** | a **wrong** implementation *can* fail it | everything but `determinism` |
| **role-entailed** | a **right** implementation *cannot* | `predicate`, `comparator`, `partition`, `state-machine` |

A law worth showing needs **both**, and getting this wrong is symmetric.

**Direction one — I was about to surface false laws.** B6b's promotion showed a `monotonicity` law on
`func get(_ key: String) -> Int { key.count }`, which is **not monotone** — `"aa" < "b"` while
`count("aa") > count("b")`. Correct code, red test. A walk-4 reader hit the identical class in the wild
and called `idempotence` on `offset(of:)` *"a false positive that would waste a developer's
afternoon — the code is right; the law is nonsense."* **That is B3's `selectAllFiles` lesson wearing a
promotion's clothes**, and I reintroduced it one layer up. Only role-entailed laws may be shown below
the confidence cut.

**Direction two — doing what the tool asked LOST coverage, and B7 could not see it.** A reader
performed the extraction; B9 stopped the linter re-seeding it; the focus found no match for the
`partition` law and **dropped it**. B7's guard did not fire, *and was right not to* — it only triggers
when the answer is **entirely** tautologies, and by then B6b's own comparator and predicate laws were
on screen. **One good law was buying silence for the loss of another.** A guarantee of *"at least one
refutable law somewhere"* is not a guarantee about **the law you needed.**

**So the rule is stated on the law, not the run: the focus narrows GUESSES, and never hides a law the
code OWES.** Surfacing an owed law can never cry wolf, so there is nothing for the focus to protect
the reader *from*. Conjectures are still narrowed — which also deletes the signature-shape noise all
three readers complained about (`idempotence`/`round-trip` on `dropCount`/`prefixCount`, proposed
purely because they are `Int -> Int` with a curated name suffix).

On a reader's own post-extraction tree, default flags: **the partition law is back and the artifact
laws are gone.**

### B4. A decode-fidelity law — `SwiftPropertyLaws` · M

`checkCodablePropertyLaws` tests `encode ∘ decode`. **MacCloud never encodes** — there is no
`jsonEncoder()` in the whole app. Client DTOs are usually decode-only, so the kit tests a direction
that does not exist in production while the one that does — *does the server's JSON parse?* — has no
law at all.

- `checkDecodableFidelityPropertyLaws(for:from: Generator<Data>, expecting:)` — generate wire-shaped
  JSON, assert it decodes and that the fields land where they should.
- Warn when the default `CodableCodec.json` is used against a type with `Date` fields: a stock
  `JSONDecoder` is almost never the decoder the app runs.

---

### B23. The docstring advisory — a reference definition the tool already asked for

B21/B22 measured the generalization spread (1/4 same-app vs 4/4 different-app) and named the two
axes that govern it: a **pure testable kernel**, and an **available reference definition**. B12–B19
attacked the first axis. B23 attacks the second — and it does so by noticing the tool was already
*asking* for the thing a docstring supplies.

**What was already there.** Two of the tool's own outputs end with a request the tool cannot fill
itself:

- the `predicate` law: *"it must agree with **a reference definition only you can state**"*
- a TestLifter lift: *"**The reference definition is where the bugs are** … Write the sentence,
  encode THAT"*

A docstring *is* that sentence. So the feature is not "infer a law from prose" — it is "when the
reader already wrote the reference definition the tool is asking for, put it next to the law that
needs it." That framing is what kept it aligned with TestLifter and honest about refutability.

**What it is.** `swift-infer discover --docstring-advice` — a separate advisory channel (like
`--effect-annotations`; off by default, default output byte-identical) that, for a seeded documented
function, pairs the docstring with the law it defines. Three shapes, in priority order:

1. **reference definition — predicate.** A `predicate` law openly owes an external spec. The
   docstring fills it.
2. **reference definition — lifted test.** An example test lifted by TestLifter needs the sentence
   it generalizes. The docstring supplies it. (This is the doc+example synergy: an example plus a
   definition is a refutable property; either alone is not.)
3. **fallback contract.** The templates could offer nothing a *correct* implementation is owed —
   only a `determinism` tautology, or refutable-but-not-role-entailed red herrings (associativity /
   commutativity on a function that is not a monoid; the walk-8 scalar over-fire). The documented
   sentence is then the one refutable contract on the function, and the advisory names the
   shape-matched guesses so the reader sees *why* the sentence is needed.

A function whose law is already **self-contained and role-entailed** — a `comparator`'s strict weak
ordering, a `partition`'s tiling — gets **no** advisory. The tool already handed the reader
something owed; repeating the docstring would only spend trust.

**The gate.** Everything is gated on the docstring being a **contract**, not narration — a checkable
claim about the result ("capped, never negative"; "nearest multiple, ties upward"), not context
("a convenience helper used by the ranking loop"). Precision over recall, in the same spirit as the
`Refutability` sets: a false positive costs the reader's trust, a false negative costs one missed
advisory.

**The trigger went through two wrong versions before a probe corrected it.** First: "fire at the
determinism fallback." Wrong — the probe showed `(Int,Int)->Int` functions match
associativity+commutativity and `(Int)->Int` matches idempotence+monotonicity under
`--include-possible`, so the functions that most need a docstring never reach the determinism
fallback at all. Second: "suppress whenever a role-entailed law fired." Also wrong — `predicate` is
role-entailed *and* the one law that explicitly leaves a hole for the definition, so it should
*pull the docstring in*, not suppress it. The final trigger reuses
`Refutability.isWorthSurfacingBelowCut` (refutable **and** role-entailed) and treats `predicate`
as reference-definition-hungry while `comparator` / `partition` are self-contained.

**Built and mechanism-verified.** `DocCommentExtractor` (leading-trivia extraction, adjacency-aware
— a blank line ends the run), `docComment` threaded onto `FunctionSummary`, `DocstringAdvisor` (the
pure decision), and the CLI wiring (`--docstring-advice`, grouping, renderer). Unit tests:
`DocCommentExtractorTests`, `DocstringAdvisorTests` (the four paths + the contract gate),
`DiscoverDocstringAdviceTests` (end-to-end: flag gates the block, off by default, both shapes reach
the reader). All green.

**Efficacy — measured cold (walk 10), and the honest number is "parity plus noise."** A blind
builder wrote a new documented library (`RecipeScaling`, a domain the feature had never seen); a
blind planter injected 3 doc-vs-code drift bugs that pass all 7 example tests; six cold readers
walked the sealed fixture in two arms — three *with* `--docstring-advice`, three *without* (control).

| bug | function | drift | treatment (3) | control (3) |
|---|---|---|:--:|:--:|
| 1 | `isValidQuantity` | rejects zero; doc says "zero is allowed" | 3/3 | 3/3 |
| 2 | `roundToPlaces` | negative places → `abs`; doc says "treated as zero" | **1/3** | **0/3** |
| 3 | `orderedByQuantity` | ties by name *length*; doc says "name ascending" | 3/3 | 3/3 |

Per-reader mean: treatment 2.33/3, control 2.0/3. The feature's own thesis held — *every* reader who
found a bug found it exactly where the code drifts from its sentence — but three findings undercut
any claim that the flag *caused* that:

1. **Bugs 1 and 3 don't discriminate.** Both are readable straight from the docstring in the source,
   and both arms read every docstring. 6/6 each. A bug that easy can't measure a tool that surfaces
   docstrings.
2. **Bug 2 is the only discriminating bug, and the margin is one reader** (a treatment reader who
   actually ran the negative-`places` input). n=1 is inside reader variance, not an effect.
3. **The control was contaminated.** The base tool *already* emits "state the reference definition;
   the bug is where the code drifts from the sentence" (the `predicate` suggestion text + TestLifter
   guidance), and *every control reader quoted it*. So the control got the same conceptual nudge
   minus the explicit docstring pairing — meaning walk 10 measured the flag's **marginal** value over
   the base tool, and that margin was ~one reader on the hardest bug.

**Verdict: not harmful, not demonstrably better than the base tool on this fixture.** Two design
flaws are mine: the fixture was too easy on 2 of 3 bugs (self-evident contracts need no surfacing),
and LLM readers never skim, so a feature whose value is *directing attention to the contract-critical
function in a large tree* gets no credit when both arms already read all 10 docstrings. A cleaner
measurement would need contract-only bugs the code cannot reveal, a skim-reader profile, and a
control arm with the base tool's reference-definition framing stripped — **but this is explicitly not
planned** (2026-07-16): the marginal number is not worth the walk. B23 therefore rests as **built,
unit-tested, and measured-inconclusive** — the mechanism is sound and the thesis is confirmed, but
the flag's lift over the base tool is unproven and will stay that way unless a reason to revisit
appears. (Fixture + reader reports + answer key retained in the walk-10 scratch harness; no docstring
reused from this repo's probes.)

**Deferred refinement (revisit after walk 10).** Extraction is `///` / `/** */`-only today; a
regular `//` comment carrying a contract is invisible. In app code — where `///` is rare and
contracts live in `//` — that likely leaves real reference definitions on the floor. The
discriminator was never the comment *syntax* but the `isContract` gate, so widening to an adjacent
leading `//` run (still leading-trivia only, still blank-line-bounded) is safe in principle; the open
question is the false-positive rate, which the cold walk should measure before deciding whether `//`
needs a stricter contract bar than `///`.

Repos touched (SwiftInferProperties main): `FunctionSummary.swift`, `FunctionScannerVisitor+Summary.swift`,
`DocCommentExtractor.swift` (new), `DocstringAdvisor.swift` (new), `Discover+GenericLaws.swift`
(two helpers `private`→internal for shared keying), `SwiftInferCommand.swift` (flag),
`Discover+Render.swift`, `Discover+DocstringAdvice.swift` (new), `DocstringAdvisoryRenderer.swift`
(new). Book tie-in: §2.4.2, Appendix C road-test note, Ch15 §15.3.3.

---

### B24. The scalar over-fire — associativity/commutativity from a bare shape

The walk-8 red herring, closed. `associativity` and `commutativity` fired on the bare
`(T, T) -> T` type shape alone: any two-same-type-in, same-type-out function scored 30 → the
Possible tier, so `backoffDelay`, `weighted`, `scaleQuantity`, `score` — arbitrary arithmetic that is
not a monoid — were all proposed a law they need not satisfy. This is precisely the
refutable-but-not-role-entailed noise `Refutability` names (§ the role-entailment axis): a *correct*
`backoffDelay` fails associativity, so the proposal cries wolf. B23's docstring advisory had to
*apologize* for these ("matched by shape, but not owed") — the honest fix is to not propose them.

**The gate.** A counter-signal (`unsupportedAlgebraicShape`, `-20`) drops a shape-only candidate from
Score 30 to 10, below the Possible floor, **unless the shape is corroborated**:

- **associativity** — a curated/vocabulary monoid name (`add`, `combine`, `merge`, `union`,
  `intersect`), a concatenation-family name (`concat`, `append`, `prepend`, `joined`, …), a
  semilattice/order verb (`join`, `meet`, `min`, `max`, `gcd`, `lcm`), the `+`/`*` operators, or
  **reduce-fold usage** in the corpus.
- **commutativity** — a curated/vocabulary commutative name, a semilattice/order verb, or the `+`/`*`
  operators. (The anti-commutativity list — `subtract`, `divide`, `append`, … — already suppressed
  its own names.)

The operators corroborate *without* the `+40` curated-name bump, so `+` keeps its existing
Possible-tier law rather than being promoted. The type shape is necessary but no longer sufficient —
which is the whole point.

**Result.** `add` (both), `concat` (associativity), `+`/`*`, and any reduce-op still fire.
`weighted` / `backoffDelay` / `scaleQuantity` now fall back to the honest `determinism` tautology
instead of a false algebraic law. Verified on a fresh probe and on the walk-10 `RecipeScaling`
fixture (`scaleQuantity` no longer draws assoc/comm at all).

**Synergy with B23.** A *documented* over-fire function now reaches the determinism fallback cleanly,
so the docstring advisory surfaces its contract via the fallback-contract path — the tool points at
the reader's own sentence instead of proposing false algebra. The two fixes compose exactly as
intended.

**Tests.** New `Signal.Kind.unsupportedAlgebraicShape`; counter-signals on both templates. The
bare-shape tests now assert suppression (and that the +30 shape signal is still present but countered
by −20); the FP-counter tests re-anchor on `+` (corroborates without the bump, preserving the exact
30/20 scores they isolate); two contradiction tests re-name to a corroborated `merge` so a suggestion
still reaches the contradiction pass.

The **full suite earned its keep here.** The targeted runs were green, but the algebraic-survey
verify corpus caught a real over-suppression the probes missed: `join` / `meet` (semilattice ops with
non-curated names) were being gated with the arithmetic noise. That is *not* noise — a semilattice is
associative and commutative by definition — so the corroboration set grew the semilattice/order verbs,
restoring their four true positives. `leftBiased` (an arbitrary projection) stays suppressed at
proposal, which is the intended behaviour: the corpus's one commutativity false-positive is now
declined before verify rather than caught by it. Corpus records 17 → 15 accordingly. Full suite green
(3972 tests), tree lint-clean.

Repos touched (SwiftInferProperties main): `Signal.swift`, `AssociativityTemplate.swift`,
`CommutativityTemplate.swift` (+ five test files). No book change — this is precision, not a new
technique.

---

### B25 (issue #1). The reference-oracle stub — the docstring contract, made runnable

Walk 10's sharpest failure was bug 2: five of six readers *named* the property and never *ran* it.
The obvious fix — "make the tool run its proposals" — turned out to already exist (`prove-then-show`
indexes + verifies every pick), and on the walk-10 fixture it caught **0 of 3** bugs. The reason is
exact and it names the real gap:

```
Proven 0 · Disproven 0 · Unverifiable 2 · Inconclusive 1
UNVERIFIABLE  predicate  isValidQuantity(_:)   (unsupported-template: predicate)
```

A `predicate` law is `unsupported-template` at verify time because it has **no oracle** to run
against — "it must agree with a reference definition only you can state." B23 identifies the docstring
as that reference definition, but as prose. Nothing connected them. B25 does.

**The design — "point, don't synthesize," pushed one stage into verify.** For a documented
single-parameter predicate, `discover --docstring-advice` now emits a **runnable reference-oracle
scaffold**: a `<name>_reference` stub carrying the docstring as its guide (`fatalError` body), plus
the property `f(value) == f_reference(value)`. The reader fills the one boolean the docstring already
dictates — the part only a human can state — and the generator finds the input where the code
disagrees with its own documentation — the part the reader skipped by hand. Not NL-parsing the prose
into a boolean (brittle); handing the reader the exact stub and letting the machine do the running.

**The generator has to be edge-biased, and that was proved, not assumed.** Bug 1 (`isValidQuantity`
uses `> 0`; doc says "zero is allowed") manifests at *exactly* `0.0` — a measure-zero boundary a
uniform generator samples with probability ~0. Demonstrated directly: the uniform draw **false-passes**;
an edge-biased draw catches it. So the emitter mixes the uniform baseline (weight 3) with the boundary
values `0`, `±1` (weight 2) via `Gen.frequency` — the numeric analog of the kit's String edge-biasing.
This is exactly the trap the tool's own predicate advisory warns about ("generate the awkward ones:
the boundary").

**Proven end-to-end against walk-10 bug 1.** The reader fills `quantity.isFinite && quantity >= 0`,
runs `swift test`, and the machine reports *"isValidQuantity(_:) disagrees with its documented
reference definition at input 0.0."* — the bug nothing before could reach (templates miss it,
`prove-then-show` calls it Unverifiable). The propose→run gap is closed for predicate contracts.

**Scope.** Predicates of **any arity** — one parameter draws a scalar, several draw a tuple the
property indexes (the commutativity arm's pair shape, generalized), with argument labels preserved so
a `canReach(from:to:)` predicate compares against a `canReach_reference(from:to:)` of the same
signature. Proven end-to-end on a two-parameter `inRange(_:ceiling:)` bug (the `value = 0` slip,
caught). Generalizing also fixed a latent single-param bug — the call `f(value)` ignored a parameter's
label.

**Comparators too — the ordering-key oracle.** A `comparator` is a two-argument predicate on ordering,
so the same emitter serves it, but the *reason* is subtler and it revises B23. B23 gave comparators no
advisory because their strict-weak-ordering law is "self-contained" — true, but only as a *validity*
check: the SWO law verifies the comparator is *a* valid ordering, never *which* one. A comparator that
sorts by the wrong key (name **length** where the docstring says **lexicographic**) is a valid strict
weak order and passes the SWO law clean. So the docstring's ordering key is a reference definition the
SWO law cannot capture — `comparator` joins `predicate` in the reference-definition-hungry set, and the
advisory now rides alongside the SWO law with its own framing ("the SWO law checks it is a VALID
ordering, not WHICH one"). Proven end-to-end: a `precedes(_:_:)` comparator whose tie-break drifts from
its docstring is caught at the pair `("aa", "b")` — a wrong-key bug the SWO law passes.

**The determinism fallback too — and it catches walk-10's bug 2.** When the templates can name nothing
a correct implementation is owed (only the `determinism` tautology or red herrings), the docstring is
the sole contract. The same oracle now serves it: the emitter generalized to any `Equatable` return,
so a `roundToPlaces(_:places:) -> Double` gets a value-typed `_reference` whose body the reader writes
from the docstring (a from-the-spec re-implementation — differential testing, heavier than a predicate
boolean but the way to catch computational drift). Proven end-to-end against walk-10's **bug 2** — the
hardest, missed by five of six cold readers: with the reference filled (`max(places, 0)`, the doc's
"negative → zero"), the property fails at a negative `places` where the buggy `abs(places)` diverges.

**A real hang bug surfaced and was fixed here.** The first `roundToPlaces` run spun at 100% CPU for
half an hour: the emitted integer generator was the unbounded `Gen<Int>.int()`, and `roundToPlaces`
loops `0..<abs(places)` — a billion-scale draw loops effectively forever. The `Double` generator was
already bounded (±1e6); the `Int` one was not. Fixed by drawing the integer baseline from the kit's
`boundedForArithmetic()` (`2^(bitWidth/4)`, ~65k for `Int`) — whose documented purpose is exactly this
— keeping the edge arm for the boundary. Same run now finishes in **0.001s** and still catches the bug.
Without the fix the scaffold would hang on any function that loops on an integer parameter.

**Efficacy — measured in Walk 11, and closed as *unmeasurable by this instrument*.** The mechanism is
proven for predicates, comparators, and the determinism fallback — the three shapes that leave a
function `Unverifiable` or tautologized, now all runnable. Whether the scaffold *changes a cold
reader's outcome* came back 3/3 in both arms (see Walk 11 below): sufficient but not necessary for a
diligent LLM reader. Walk 11 also surfaced the round-trip subdomain-suppression gap.

Repos touched (SwiftInferProperties main): `LiftedTestEmitter+PredicateReference.swift` (new emitter),
`Discover+DocstringAdvice.swift` + `DocstringAdvisoryRenderer.swift` (wiring), + two test files.
Builds on B23 (which points at the docstring) and composes with B24 (which clears the false algebra so
the predicate is what the reader is left with).

---

### B26. The scale road test — swift-algorithms, and the lazy-wrapper reach gap — **found, not fixed**

The fixtures so far are toys: MacCloud (~4k lines) and the walk-10 `RecipeScaling` library (10
functions). The features that *surface* — the docstring advisory, the reference-oracle scaffolds —
can only earn their keep where "which function do I even look at?" is a real question, so the honest
next step was a large, real, documented library. First target: **apple/swift-algorithms** (HEAD
`0b43769`, 28 source files, exhaustively documented). The result is a clean reach gap, and it is worth
more than a clean pass would have been.

`lint → discover --docstring-advice` produced almost nothing usable: **38 `determinism` tautologies,
one `predicate`, and zero docstring advisories** on a library where every public function carries
`///` docs. The distinct seeded symbols tell the whole story:

> `<`, `==`, `distance`, `index`, `next`, `normalizeIndex`, `offsetBackward`, `offsetForward`, `log`, `root`

Every one is **`Collection`-conformance plumbing** — index arithmetic, comparison operators, the
iterator's `next`. Not a single headline algorithm: `uniqued`, `chunked`, `windows`, `rotated` were
never seeded, though all are documented.

**The reason is structural — the extraction lottery (B21) at scale.** swift-algorithms implements its
logic as **lazy `Collection` wrappers**: `uniqued()` returns a `UniquedSequence`, `chunked` a
`ChunkedCollection`. The linter's pure-kernel detector wants a standalone pure function returning a
**value type**; a lazy wrapper is not one, so the algorithm functions are invisible to it, and what
*does* get seeded is the wrappers' `index(after:)` / `distance` / `==` — the conformance boilerplate.
So **both B21/B22 axes miss at once, and neither for the reason the axes name**: the pure kernel is
real (`uniqued` genuinely is a pure function) but not in the extractable *form*; the docstrings are
rich but sit on functions that never enter the seed set.

**What it points at (the fix, deferred).** Seed the **wrapper-returning public API** and test
properties of the **result**, not the wrapper's index math: `uniqued()` yields no duplicates,
`chunked` tiles the input, `rotated` is a permutation, order is preserved. That is exactly what these
docstrings state and exactly what the loop never asks for — a linter reach extension (recognize a
public function returning a lazy `Sequence`/`Collection` wrapper as a candidate) plus a discover
template family over the produced sequence. Until then, an algorithm library structured this way is
**out of the toolchain's reach**, and saying so plainly is the finding: the loop is strong on
value-returning pure kernels and silent on the lazy-wrapper idiom that dominates real Swift collection
code. Next contrast to run: **swift-collections**, whose data structures expose value-semantic
operations (`insert` / `union` / `subtracting`) the linter *can* seed — a prediction that it reaches
materially more.

**B26b — the swift-collections contrast: the prediction held directionally, the mechanism did not, and
the finding got bigger.** Scouted `Sources/OrderedCollections` (61 files). The reach is dramatically
richer than swift-algorithms — but for a subtler reason, and with the *headline algebra still missed*:

| | swift-algorithms | OrderedCollections |
|---|---|---|
| predicate laws | 1 | **43** |
| monotonicity | 0 | **10** |
| determinism (tautology) | 38 | 20 |
| docstring advisories | 0 | **16** |
| runnable scaffolds | 0 | **15** |

So the prediction was directionally right (materially more reach — real predicate + monotonicity laws,
16 documented reference-definition functions). But the algebraic operations that should have carried it
— `union` / `intersection` / `subtracting` — produced **no algebraic law**, and pinning why took three
wrong guesses before a minimal probe settled it. The corrections matter, because two went into an
earlier draft of this entry:

- **Wrong guess 1** — "`union` is a `SetAlgebra` protocol default, not in source." FALSE: `OrderedSet`
  provides a concrete, value-returning `public __consuming func union(_ other: __owned Self) -> Self`.
  (True footnote: `OrderedSet` itself does *not* conform to `SetAlgebra` — only its `UnorderedView`
  does, hence the "Partial SetAlgebra" filenames — but that never stopped `union` from being source.)
- **Wrong guess 2** — "it didn't seed." FALSE: a `union` overload *is* seeded (the `Sequence`-parameter
  one); the *value-semantic* `union(_ other: Self) -> Self` is what fails.
- **Wrong guess 3** — "instance-method binary ops aren't recognized." FALSE: a probe `struct Bag` with
  `func union(_ other: Bag) -> Bag` gets associativity, commutativity, and binary-idempotence — `self`
  is correctly treated as the second operand.

**The verified cause: `Self`-typed parameters are not resolved to the enclosing type.** The decisive
probe declared the same method three ways — `union(_ other: __owned Self) -> Self`,
`union(_ other: Self) -> Self`, and `union(_ other: Ring<Element>) -> Ring<Element>`. **Only the
concrete-spelled one seeds and gets associativity/commutativity**; both `Self`-typed forms are dropped
(`__owned` / `@inlinable` are irrelevant — the no-ownership `Self` form fails too). So `OrderedSet`'s
value-semantic algebra is invisible for one reason: it is written in the idiomatic `func f(_ other:
Self) -> Self` form, and the scanner keeps the parameter type as textual `Self`, which the
type-symmetry check never matches to the containing type.

**The gap is a family — and `Self`-resolution is the sharpest, highest-leverage member:**

| form | example | why the seeder misses it | fix |
|---|---|---|---|
| lazy-wrapper return | `uniqued()` → `UniquedSequence` | return type isn't a value | seed on contract / test the result |
| **`Self`-typed operand** | `union(_ other: Self) -> Self` | `Self` not resolved to the type | **resolve `Self` at scan time** |
| mutating primitive | `formUnion` | `mutating` ≠ pure kernel | seed on contract (mutation property) |

`func f(_ other: Self) -> Self` is *the* idiomatic shape for value-semantic operations across all of
Swift (`SetAlgebra`, `AdditiveArithmetic`, `Numeric`, every protocol-oriented value API), so one
unresolved keyword hides the entire associativity / commutativity / identity surface B24's corroboration
was built for. Resolving `Self` at scan time is a small, self-contained change with outsized reach —
likely the single highest-leverage fix the road tests have surfaced.

**And the docstring machinery works at scale — it was only starved upstream.** The swift-collections
run answered the docstring question from the other side: the advisory fired 16× with 15 scaffolds
*here*, because enough functions seed (`isEqualSet`, `isStrictSubset`, `index(forKey:)`, plus plumbing).
So B23–25 are healthy — swift-algorithms' zero was purely a *seeding-reach* failure. That still makes
the case for moving the `isContract` gate (B25) **upstream into seeding** (a public function whose
docstring states a checkable contract is worth testing whatever its shape), which rescues the
lazy-wrapper and mutating forms. But note it does *not* rescue the `Self`-typed form — a documented
`union(_ other: Self) -> Self` would seed on its contract, yet the type-symmetry check would still fail
to see it as a binary op until `Self` is resolved. So the deferred fixes are two, and they are
**orthogonal**, in priority order: **(1) resolve `Self` at scan time** (unlocks the whole
value-semantic-algebra surface — the sharpest single win), **(2) docstring-as-seeding-signal** (rescues
lazy-wrapper + mutating on the strength of the contract). Honesty note: of the 15 OrderedCollections
scaffolds only `isEqualSet` / `isStrictSubset` are genuinely valuable; the rest are Collection plumbing
(`==` / `distance` / `index`) where a reference oracle adds little — the signal is diluted by the very
missing-headline-operation problem this finding is about.

**B26c — the synthesis: both road-test gaps are one root, and the concrete-typed fixtures structurally
hid it.** swift-algorithms and swift-collections look like two unrelated reach gaps — a lazy-wrapper
return vs a `Self`-typed operand. They are not. A precise count settles that they are not even the
*same* symptom: swift-algorithms has **15** public functions returning a lazy wrapper, **2** returning
`Self` directly, and **0** with a `Self`-typed *parameter* — so the exact shape that killed
swift-collections' algebra does not occur there. But look at *where* `Self` lives in swift-algorithms:
as a generic argument inside the wrapper, `uniqued() -> UniquedSequence<Self, Element>`. Same root,
different face.

The root is that **`FunctionSummary` is textual by design** — its own header says types are "captured as
their source representation" and full semantic resolution is deferred to "v1.1's constraint-engine
upgrade." The scanner keeps a parameter as the literal string `"Self"`, a return as the literal
`"UniquedSequence<Self, Element>"`, and resolves neither. Three faces of the one missing capability:

| the scanner sees (as text) | can't resolve it to | which surfaces as |
|---|---|---|
| `Self` (param / return) | the enclosing type | the swift-collections algebra gap (B26b) |
| `SomethingSequence<Self, …>` (return) | a value whose *result* is worth testing | the swift-algorithms gap (B26) |
| `Self.Index` / `Self.Element` | any concrete type | (unmeasured, same root) |

**Why this was invisible until a real library.** Every fixture we built — MacCloud, RecipeScaling,
DayClock — used concrete `Int` / `Double` / `Bool` / plain structs, where the *source spelling is the
resolved type*, so a textual model is exactly correct. Real Swift libraries are generic and
protocol-oriented — they speak in `Self`, associated types, and wrapper generics — and the textual
model resolves none of it. So it is not merely that we finally ran out-of-distribution (the earlier
"why only today" answer); it is that *all* our fixtures shared the one property — concreteness — that
makes a textual scanner sufficient, and the first two real libraries broke it on the first two tries.

**So the deferred fix is one capability, not a pile of patches: semantic type resolution at scan time.**
Resolving `Self` to the enclosing type is the highest-leverage first slice (small, self-contained,
unlocks the whole value-semantic-algebra surface); resolving wrapper-returns and associated types is
the rest of the same upgrade. Docstring-as-seeding-signal (B26b) remains an orthogonal, complementary
lever — it seeds on the *contract* regardless of type shape, which the textual/semantic axis never
addresses.

**B26d — the textual type model demonstrably shaped the ~2026-06 precision calibration (verified in
the source, not reasoned).** The question was whether the missing semantic resolution corrupted the
month-ago calibration. It did, and the evidence is in the code that cites the (now-absent)
`docs/calibration-cycle-*-findings.md` tables:

- **It was measured on these libraries.** *"The access rules were calibrated against library corpora
  (swift-numerics, swift-collections, swift-algorithms)"* (`RestrictedFunction.swift:11`);
  *"swift-collections OrderedCollections was the calibration anchor"* (`TemplatePack.swift:34`);
  *"swift-numerics ComplexModule was the calibration anchor"* (`TemplatePack.swift:23`).
- **The gap spawned a calibration rule — the smoking gun.** The round-trip pack (`:121`): *"Empirical
  motivation (V1.4.2 cycle-1 baseline): swift-algorithms surfaced 673 round-trip Possible-tier hits,
  the vast majority signature-only matches across distinct `Index` member types
  (`AdjacentPairsCollection.Index` / `Chain2Sequence.Index` …). **SemanticIndex would catch this via
  type resolution; this rule is a cheap pre-SemanticIndex approximation using the textual
  `containingTypeName` field.**"* The textual model made 673 semantically-distinct `Index` types look
  identical, and a dedicated rule exists purely to paper over it. So calibration didn't just *run
  under* the gap — it *built scaffolding around the hole*.
- **The gap runs both directions.** False *negatives* — `Self`-typed `union` never seeds, missing real
  algebra (B26b). False *positives* — textually-identical-but-distinct `Index` types spuriously match
  (the 673). Both are the one textual model; the calibration patched the second while blind to the
  first.
- **The unreachable algebra was hand-curated to compensate.** `StandardLibraryProperties.swift` (V1.145)
  is a hand-written "known-true" catalog that includes exactly `OrderedSet.union`'s laws (*"idempotent
  under union, `x.union(x) == x`"*, *"NOT order-commutative"*). The authors knew these and shipped them
  as a built-in **because discovery can't reach a `Self`-typed `union`** — the knowledge was worth
  encoding by hand; the tool couldn't earn it.

**Verdict, with its boundary.** The calibration was measured on these libraries, demonstrably distorted
(hundreds of false positives requiring bespoke textual work-arounds), and blind to the value-semantic
algebra it then had to hand-curate. What is *not* proven is that the numeric weights (B24's `+30` shape
/ `+40` name) are themselves wrong — only that the tuning was shaped by, and blind to, the gap, and that
some of its machinery exists solely to compensate for it. Clean implication: when `Self`-resolution /
SemanticIndex lands, a chunk of calibration (the `containingTypeName` round-trip rule, parts of the
access-filter cycles) becomes **unnecessary or needs re-running** — it is scaffolding around the hole,
and the visible corpus it was fit to will change.

### B26e — built the fix, and the build corrected the diagnosis. **DONE (swift-infer half)**

Setting out to "resolve `Self` at scan time" (B26b/c/d's named fix), a decisive **unseeded** probe —
the same `union` method declared three ways in one type — corrected the diagnosis before a line was
written. swift-infer, run without the linter's seeds, **already handles a plain `Self` operand**:
`union(_ other: Self) -> Self` fires associativity/commutativity via textual `Self == Self`. What it
choked on was the *ownership annotation*: `union(_ other: __owned Self) -> Self` — OrderedSet's exact
form — kept the type text as the literal `"__owned Self"`, matching nothing. So B26b/c/d's phrasing
("swift-infer never matches `Self` to the containing type") was imprecise: plain `Self` matches;
`__owned Self` did not, and the *linter* separately rejects `Self`-typed functions at seeding.

**The fix (shipped, SwiftInferProperties):** generalize the scanner's existing `inout`-strip to erase
the ownership sigils (`__owned` / `__shared` / `consuming` / `borrowing` / `sending` / `_const`) from
parameter type text — they are calling-convention detail the property never sees; `inout` stays
tracked. `FunctionScannerVisitor.strippingParameterSpecifiers`, ~15 lines. **Verified on real
swift-collections**: unseeded discover on OrderedCollections now surfaces `OrderedSet.union` /
`intersection` (`(Self) -> Self`) with **idempotence, binary-idempotence, and associativity** — the
value-semantic SetAlgebra algebra that was completely silent in B26b. B24's corroboration on real
`union`/`intersection` is, at last, exercisable.

**What this does and does not close.** It fixes the swift-infer half, demonstrated via *unseeded*
discover. Two things remain, both now precisely scoped:
- **The linter-seeding half (SwiftProjectLint, separate repo).** The `--seeds` road-test pipeline still
  won't reach these ops until the linter seeds `Self`-typed functions (it currently rejects them) — the
  associativity law isn't role-entailed, so the seed-focus drops it otherwise. Complementary slice.
- **`Self` → containing-type *resolution* — deferred, and now known to be a *robustness* upgrade, not
  the reach fix.** Plain `Self` already matches textually, so resolution isn't needed for the win; its
  value is preventing cross-type `Self` false positives (the same textual-collision family as the 673
  `Index` matches of B26d) and correct carriers. Worth doing as part of the eventual SemanticIndex, not
  urgent.

So the highest-leverage road-test finding is half-shipped: one ~15-line scanner change turned
OrderedSet's algebra from invisible to discovered.

### B26f — the linter-seeding half: the return-`Self` gate, closed; and the seeding block is a *stack*

The `--seeds` pipeline needs the *linter* (SwiftProjectLint) to seed `Self`-typed functions, which it
did not. Root cause, found: `PropertyTestCandidacy.returnIsAssertable` requires the return type's base
name to be a known-`Equatable` type, and a `Self` return has base name `"Self"` — never in the set,
though it resolves to the (Equatable) enclosing type. **Fix (shipped, SwiftProjectLint):** resolve a
`Self` return to the enclosing type name (mirroring the container walk) and check *its* equatability;
~12 lines. Verified on probes: `func union(_ other: Self) -> Self` on an Equatable `let`-stored value
type now seeds, where before it was dropped — and a `Self` return whose enclosing type is *not*
Equatable is still correctly rejected (no over-fire).

**But building it revealed `OrderedSet.union` is blocked by a *stack* of gates, not one.** Probes
isolated each: a `Self`-returning method seeds only if (a) its return resolves to an Equatable type
[now fixed], (b) it reads only immutable stored state, and (c) its body is provably pure.
`OrderedSet.union` fails (b) and (c): OrderedSet's stored properties are `var` (`_elements`, `_table`,
…), and `union`'s body is `var result = self; result.formUnion(other); return result` — copy-self,
call a `mutating` method on the copy, return it. Probes confirmed the boundary precisely: `unionPure`
and `unionLocalMut` (let-stored, pure / local-`var` body) seed; `unionCopyMutate` (`var copy = self`)
does not; and a `var`-stored type's method does not. So the return-`Self` gate is the one clean,
self-contained slice; **fully seeding `OrderedSet.union` needs deeper purity / self-access work**
(teaching the analyzer that copy-self-then-mutate-the-copy is referentially transparent, and that
*reading* a `var` stored property is not mutation) — a separate slice in the SelfAccessAnalyzer /
PurityInferrer with real false-positive risk, deferred.

**Net across B26e + B26f.** The swift-infer half (ownership-strip) makes OrderedSet's algebra
discoverable *unseeded*, today. The linter half's return-`Self` gate is closed, which unlocks the broad
class of `Self`-returning pure value-semantic functions — but not `OrderedSet.union` specifically,
which sits behind two further purity gates. The reach fix is genuinely incremental: each gate removed
widens the surface, and the highest-leverage two (ownership-strip, return-`Self`) are done.

### B27 — the payoff measurement: re-scanned both real libraries, and the two gates split by *path*

B26e/B26f were proven on probes; this ran the shipped tools end-to-end against the full trees and
diffed against the B26/B26b baselines. swift-algorithms is at the same HEAD as B26 (`0b43769`), so the
diff is clean; OrderedCollections at `19e45ab`. Tools built release; pipeline
`CLI --format pbt-seeds | swift-infer discover --sources <dir> --seeds … --include-possible
--docstring-advice`, plus a bare unseeded `discover --include-possible`.

| metric | swift-algorithms (B26 → now) | OrderedCollections (B26b → now) |
|---|---|---|
| **seeded** predicate | 1 → 1 | 43 → 43 |
| **seeded** monotonicity | 0 → 0 | 10 → 10 |
| **seeded** determinism | 38 → **40** | 20 → 20 |
| `union`/`intersection` algebra, **seeded** | — | 0 → **0** |
| `union`/`intersection` algebra, **unseeded** | — | 0 → **8** |

**The result is that the two gates land on different paths, and that is the finding.**

- **swift-infer's ownership-strip (B26e) is a real, measured reach gain — but only *unseeded*.** Bare
  `discover` on OrderedCollections now surfaces **8 algebraic-law suggestions** on the value-semantic
  set ops that were *100% silent* in B26b: `union` associativity ×2, commutativity ×2,
  binary-idempotence ×2; `intersection` binary-idempotence ×2 — plus 23 `dual-style-consistency`
  pairings (`formUnion` ↔ `union`, `formIntersection` ↔ `intersection`). The SetAlgebra surface B24's
  corroboration was built for is finally exercisable.
- **The linter's return-`Self` gate (B26f) moved the *seeded* pipeline by ~zero on real code.**
  OrderedCollections' seeded numbers are byte-identical (43 / 10 / 20). swift-algorithms gained +2
  determinism *tautologies* only — `element`, `separator`, plumbing, not headline algorithms. Reason,
  exactly as B26f scoped it: the `Self`-returning ops that matter (`union` / `intersection`) are *also*
  behind the `var`-stored-props + copy-self-mutate-body purity stack, so return-`Self` alone does not
  seed them. (swift-algorithms' headline `uniqued` / `chunked` remain absent on *both* paths — the
  orthogonal lazy-wrapper gap, untouched by either gate, as predicted.)

**What the measurement decides (its purpose).** The gap between *"swift-infer **can** reach it"* (8
laws, unseeded) and *"the loop a cold reader **follows** reaches it"* (0, seeded) is now precisely one
component: **the linter's purity / self-access stack** — B26f's deferred slice. So the ranking is no
longer a guess:

- **The deferred purity slice is promoted from "maybe worth it" to "the bridge."** It is the single
  thing standing between a *shipped* swift-infer capability and the reader actually getting
  `union`/`intersection` algebra *through the loop*. The measurement proves it is the only remaining
  gate on that surface — the highest-leverage move on the board.
- **A calibration re-run should wait.** The seeded corpus is essentially unchanged, so calibration's
  *inputs* have not moved; re-running it only becomes meaningful after the purity slice lands and the
  seeded corpus actually gains the algebra. Confirmed ordering: purity slice first.

### B28 — built the purity slice: bare-`self`-as-value for value types, and it closed the B27 gap

Scoping B27's "bridge" first **corrected its own diagnosis** (verify, don't reason). B26f had recorded
`union` as blocked by "(b) `var` stored props and (c) body not provably pure." Isolating probes against
the release linter refuted both: (c) `PurityInferrer` (a marker + totality scan) *already passes*
copy-self-mutate; (b) the operative gate is neither the `var` props nor purity but a **third thing** —
`SelfAccessAnalyzer` classifies a bare `self` used as a value (`var result = self`) as `.disqualifying`
("hands the whole object over"). Probe table: `let`-prop value type with `var result = self` → **not**
seeded (bare-self alone kills it, no `var` prop present); ownership sigils / `Self`-return / `__consuming`
→ all seed fine (never the blocker). So the real fix is one classification branch, narrower than recorded.

**The fix (shipped, SwiftProjectLint `11be125`).** A bare `self` read is a read of the whole input **for
a value type** (`struct`/`enum`) — `self` *is* the value, so copying / returning / comparing it stays
within `(self, args)`; classify it `.immutableSelf`. For a **reference type** the same copy aliases one
shared object, so it stays `.disqualifying` (probe: a class `copy()` correctly still drops). The enclosing
kind is absent from an `extension`'s syntax — and `OrderedSet.union` lives in `extension OrderedSet` in a
different file from `struct OrderedSet` — so a new project-wide **`ValueTypeCollector`** (struct + enum
names) supplies it, threaded through the detector/visitor hops exactly like `knownEquatableTypes`. The
analyzer only ever runs on non-mutating methods, so a bare `self` here is always a read, never `self = …`.

**Verified end-to-end, closing the exact B27 gap:**

| | B27 (before) | B28 (after) |
|---|---|---|
| OrderedCollections seeds | 42 | **47** (`union` ×2, `intersection`, `isSuperset`, `appending`) |
| `union`/`intersection` algebra, **seeded** | **0** | **4** — `union` assoc + comm + binary-idem, `intersection` binary-idem |
| predicate / monotonicity / determinism (seeded) | 43 / 10 / 20 | 43 / 10 / 20 (unchanged — pure addition) |

The value-semantic algebra is now on the **seeded** path — the loop a cold reader follows reaches it,
raised to the swift-infer ceiling B26e opened. No regression: 43/10/20 identical, full suite **2835**
green (+4 tests).

**Honest boundary (not a new gap).** `subtracting` still does not seed: its body is `_subtracting(other)`
— an implicit `self._subtracting(...)` call — which the analyzer conservatively drops because it cannot
prove the private helper pure. That is the *pre-existing* transitive-purity boundary (the analyzer's
findings are candidates, not proofs), and it is exactly why the self-contained `union`/`intersection`
(copy + mutate a **local**) seed while the delegating `subtracting` (call on **self**) does not. Widening
it would need transitive-callee purity — a separate, larger capability, deliberately out of scope.

**Where the reach work now stands.** Three gates shipped in order of leverage — ownership-strip (B26e,
swift-infer), return-`Self` (B26f, linter), bare-`self`-value (B28, linter) — and the headline
value-semantic set algebra now reaches a cold reader through the loop. Remaining, both deferred and
scoped: transitive-callee purity (rescues `subtracting`-style delegators) and the swift-algorithms
lazy-wrapper idiom (orthogonal, needs seed-on-contract / wrapper-result templates). A calibration re-run
is now *meaningfully* actionable — the seeded corpus finally moved.

---

### B29 — the calibration re-run: it says *don't re-tune*, and it found a precision regression instead

With three reach gates shipped (B26e ownership-strip, B26f return-`Self`, B28 bare-`self`-value), the
question was whether the ~2026-06 calibration — fit to swift-numerics / swift-collections /
swift-algorithms under the old textual model (B26d) — now needs re-deriving. Ran the current release
tools against all three anchors. The calibration is not a command; the cycles produced findings docs
(absent) and hand-tuned catalogs, so this "re-run" regenerates the empirical inputs and tests B26d's
concrete claims. **Verify, not reason — and it overturned the tidy hypothesis.**

| anchor | seeds (current) | seeded discover | vs the calibration's assumption |
|---|---|---|---|
| collections / OrderedCollections | 47 (`union`/`intersection` now seed) | 43 predicate, 10 monotonicity, 20 determinism, **+4 set algebra** | shallow algebra now *discovered* — but see the regression |
| numerics / ComplexModule | 28 (`+ - * / ==`, `exp`/`log`/`pow`/`sqrt`, transcendentals) | **12 determinism, 8 round-trip (Possible), 0 algebra** | Complex operators seed but surface no commutativity/associativity (float-backed) — hand-curated int/double laws still needed |
| algorithms / Algorithms | 72 (12 distinct, all `Collection` plumbing) | 40 determinism tautologies, 1 predicate, **round-trip 0** | lazy-wrapper gap persists; the 673-FP class is currently suppressed to 0 |

**The hypothesis going in** (from reasoning) was "B28 makes the hand-curated `StandardLibraryProperties`
set algebra redundant — discovery earns it now." **Running it refuted that.** What discovery actually
produces for `OrderedSet.union` is **two true laws and one false one**:

- **True, correctly surfaced:** associativity and binary-idempotence — both hold for `OrderedSet` even
  though it is order-sensitive (order-preserving append is associative; `x ∪ x == x`).
- **False, surfaced at `Likely` (70):** **commutativity.** `a.union(b) == b.union(a)` is *false* for
  `OrderedSet` — its `==` is `_elements` array equality (`OrderedSet+Equatable.swift:28`, "elements in
  the same order"); the order-*insensitive* comparison is the separate `isEqualSet`. Yet discover emits
  `union → commutativity` at 70 via the **curated verb match `'union'` (+40)**, and its "Why this might
  be wrong" says nothing about ordering. The curated verb list is calibrated for stdlib `Set` (a genuine
  semilattice); the textual model cannot tell order-preserving `OrderedSet` from `Set`, so the reach
  gates — which made `OrderedSet.union` discoverable in the first place — reopened **exactly the caveat
  B26d found hand-encoded** (`StandardLibraryProperties`: "NOT order-commutative").

So the re-run's real result is the opposite of "redundant scaffolding": the hand-curated **caveat is now
*more* load-bearing**, because discovery actively contradicts it. And the one concrete, warranted
calibration change is **new, not a retirement**:

> **Guard the `union`/`intersection` commutativity curated-verb match against order-sensitive carriers.**
> When the carrier's `==` is order-sensitive (`OrderedSet`, `Array`, `OrderedDictionary`), withhold
> commutativity — or drop it below `Likely` with an explicit ordering caveat. Absent SemanticIndex the
> tool can't detect order-sensitivity structurally, so a carrier denylist mirroring the existing
> `StandardLibraryProperties` caveats is the pre-SemanticIndex approximation — the same pattern as the
> round-trip rule (B26d).

**What did *not* move — so no weight re-derivation is warranted.** (1) The numerics algebra never
surfaces (Complex operators yield determinism-only; the int/double laws and float caveats stay
hand-curated). (2) The round-trip textual-`Index` FP class B26d flagged (673 at the cycle-1 baseline) is
a swift-infer textual-model concern B28 never touched, and is currently suppressed to **0** on
algorithms — that scaffolding works. (3) The access-filter calibration (`RestrictedFunction`) is
orthogonal to reach. (4) The deep lattice laws in `setLaws` (distributive, absorption, De Morgan,
symmetricDifference self-inverse) are not derivable by discovery and remain correctly hand-curated.

**Verdict.** The reach gates justify **one** targeted calibration edit — the order-sensitive-carrier
guard on the commutativity verb match — and **no** broad re-tune. The re-run's value was catching that
the reach win carries a precision cost (a false `Likely` law) that only *running* it against a
real order-sensitive carrier revealed; reasoning alone would have shipped the "hand-curation is now
redundant" conclusion and missed it.

### B30 — built the order-sensitive-carrier guard: the false `Likely` law, suppressed

The one edit B29 justified, shipped in swift-infer (`84cbc78`). `CommutativityTemplate` scored
`OrderedSet.union` at 70/Likely (curated `'union'` +40, type-symmetry +30) with no carrier awareness —
a false law, since `OrderedSet.==` is `_elements` array equality (order-sensitive). Added an
**order-sensitive-carrier veto**: when the carrier (`containingTypeName`) is on the curated
`OrderSensitiveCarrierNames` denylist (`OrderedSet`, `OrderedDictionary`, `Deque`, `Array`,
`ContiguousArray`, `ArraySlice`) *and* the op is a set-combination verb
(`union`/`intersection`/`intersect`/`symmetricDifference`), emit a full veto (`Signal.vetoWeight` →
`.suppressed`). Veto, not counter-weight, because the law is *wrong*, not low-confidence — the honest
"union is not order-commutative" fact already lives in the `StandardLibraryProperties` caveat channel
(`kind: .caveat`). The denylist is the pre-SemanticIndex stand-in for detecting an order-sensitive `==`
structurally, mirroring `FloatingPointStorageNames`.

Three swift-infer files (new `OrderSensitiveCarrierNames`, a `.orderSensitiveCarrier` veto kind, the
template signal + wiring), +5 tests. **Verified end-to-end on real OrderedCollections**: the seeded
set-op algebra goes **4 → 3** — union commutativity dropped, and the three true laws (union
associativity, union binary-idempotence, intersection binary-idempotence) retained. Scoped tight:
associativity/idempotence untouched (both hold on order-preserving carriers); stdlib `Set.union` stays
70/Likely (not on the denylist); a `union` on an off-denylist carrier still fires. Full suite **3985**
green (3980 + 5).

**Where the calibration stands after B29 + B30.** The one precision regression the reach gates
introduced is closed; no weight re-derivation was warranted, and none was done. The remaining calibration
scaffolding (round-trip textual-`Index` FP rule, access filter, numerics float caveats, deep lattice
laws) is unchanged and load-bearing, exactly as the re-run found. The reach → measure → guard arc
(B26e/f, B28 → B27 → B29 → B30) is closed: the value-semantic set algebra reaches a cold reader through
the loop, and it reaches them *without* the one false law that reach exposed.

### B31 — the transitive-callee purity slice is *unwinnable* for `subtracting` (verified, not built)

B30 named `subtracting` as the next deferred target — its body is `_subtracting(other)`, an implicit
`self._subtracting(...)` call that `SelfAccessAnalyzer.classify` drops as `.disqualifying`, and the
proposed rescue was "transitive-callee purity": resolve the callee and verify *it* is pure. Scoping it
against the real source killed the rationale before a line was written. Two forms, neither wins:

- **Shallow** (wave through any same-type method call, no recursion) *would* seed `subtracting` — but
  it also seeds every method delegating to a genuinely impure helper, a real false-positive regression
  that abandons the analyzer's documented "candidate, not proof" posture.
- **Transitive** (recurse and verify the callee) is sound but **still drops `subtracting`**, because
  `_subtracting` is not analyzably pure. Its body: `guard count > 0 …`, then
  `_UnsafeBitSet.withTemporaryBitSet(capacity:) { … self._find(item) … assert(c > 0) …
  _extractSubset(using:count:) }`. That is `assert` (a trap → fails `bodyIsTotal`), an unsafe scratch
  buffer on another type, and two further private helpers (`_find`, `_extractSubset`). The method is
  pure *in fact* — a temporary local bitset is a pure computation — but pure by no static analysis short
  of executing it.

So the sound slice has **zero payoff on its own motivating example**, and the version that would rescue
it is unsound. `subtracting`'s "gap" is not a reach limitation; it is "delegates into unsafe stdlib
internals," which the toolchain correctly declines to certify. Recorded as a *don't-build*: `union` /
`intersection` already reach the reader, and `subtracting` is poor ROI. A narrow variant — rescue only
delegators to a same-**file** helper that is itself fully analyzable-pure — is defensible but needs a
real corpus example it actually rescues before it earns a build; `subtracting` is not one. This is the
same verify-first discipline that overturned B26b's three wrong guesses and B29's "redundant" hypothesis.

### B32 — the lazy-wrapper spike, and bridge (1): idempotence gains the instance self-form

The other B26 deferred item — swift-algorithms' lazy-wrapper idiom (`uniqued() -> UniquedSequence`,
`chunked() -> ChunkedByCollection`, neither `Equatable`, so `returnIsAssertable` drops them) — was
scoped as a large cross-repo feature: a new candidacy shape + a materialised-result assertion form +
a property source. Rather than build on that scope, a **spike** first asked the load-bearing question:
*can swift-infer's templates even express these laws?* Probed shapes through `discover`:

| probe shape | fires today? |
|---|---|
| `reverse(_ xs: [Int]) -> [Int]` (eager, free) | ✅ involution 70 |
| `sort(_ xs: [Int]) -> [Int]` (eager, free) | ✅ idempotence 70 |
| `x.reversed() -> Self` (instance self-form) | ✅ involution 70 |
| `x.normalize() -> Self` (instance idempotent, 0-param) | ❌ nothing |
| `uniqued() -> UniqSeq` (lazy wrapper, non-`Equatable`) | ❌ nothing |

**The spike overturned the scope's premise.** The idempotence/involution *law machinery already
exists and fires at Likely* — the feared "new law machinery" is not needed. The gap is pure
**shape-routing** into laws that already work, and it splits into two bridges, neither a new law:
**(1)** the instance self-form (`x.f()`, `self -> Self`) — which `InvolutionTemplate` already handles
but `IdempotenceTemplate` did not (it required `params.count == 1`); **(2)** the materialised
wrapper return (`Base -> WrapperOf<Element>`, tested via `Array(result)`), which no template's
type-symmetry gate matches.

**Bridge (1), built (swift-infer).** Extended `IdempotenceTemplate.typeSymmetrySignal` to accept the
instance self-form (`parameters.isEmpty && containingTypeName == returnType`), exactly mirroring
`InvolutionTemplate.isInvolution`, and added the past-participle spellings (`normalized`, `sorted`,
`deduplicated`, `trimmed`, …) to `curatedVerbs` — the non-mutating instance form Swift names as the
participle, mirroring involution's dual base/participle listing. Verified: `Doc.normalized() -> Doc`
and `Query.canonicalized() -> Query` now fire idempotence at **75 (Strong)** — were **0**; a
non-curated `Widget.rendered() -> Widget` correctly lands at Possible (35); `self -> OtherType`
(the materialisation case) stays out. +5 tests, idempotence suite (incl. golden) green.

One measured-corpus baseline shifted, and it was **read, not blindly bumped**: the algebraic-survey
corpus went 15 → 17 records because idempotence now proposes on its two `reversed()` instance methods —
exactly as it already did on involution-named *free* functions. Both are correct measured outcomes
verified against the fixture bodies: `Latch.reversed` is a buggy identity (`f(x) == x`), so idempotence
`f(f(x)) == f(x)` holds → bothPass; `Toggle.reversed` is a genuine involution, so idempotence is false →
verify disproves it (defaultFails). The baseline updated to 12 bothPass / 5 defaultFails with that
explanation, not a number-bump.

Bridge (1) lights up ordinary value-semantic instance transforms (`x.normalized()`,
`path.canonicalized()`, `x.deduplicated()`) on app and library code — not only swift-algorithms.
**Bridge (2)** — the lazy-wrapper materialisation — stays deferred, but the spike shrank it from an
open-ended feature to a bounded "materialised-symmetry shape + linter seeding of wrapper-returners"
task: the laws are proven ready, only the shape and the `Array(...)` assertion form remain.

---

### Walk 11. The reference-oracle efficacy question (issue #1) — closed as *unmeasurable*, and why

B25's mechanism was proven three times over (bug 1 at `0.0`, comparator at `("aa", "b")`, bug 2 at a
negative `places`). What stayed open was **efficacy**: does handing a cold reader a runnable scaffold
actually change whether they find the bug? Walk 11 was built to answer it — a fresh blind-built,
blind-planted documented fixture (`DayClock`, 24-hour clock arithmetic, 11 functions), three bugs on a
detectability gradient (readable / medium / **subtle-boundary crash**), six cold readers split into
`--docstring-advice` (treatment, scaffolds) vs plain `discover` (control).

**The result is a perfect ceiling: 6 of 6 readers found all 3 bugs — treatment and control alike, 3/3
each.** No lift, no false positives, identical counterexamples. The control arm reached the subtle
`timeOfDay(fromMinutesSinceMidnight: -1441)` crash by exactly the reasoning the scaffold was meant to
shortcut: they read the docstrings, noticed *which edges the example tests never touch* ("never tests
step=1, the overnight opening, or conversions below -1440 — exactly the three gaps"), and wrote probe
tests on those. The scaffold *saves* a diligent reader the writing; it does not change *whether* they
get there. So the scaffold is **sufficient but not necessary** for a capable reader.

**The verdict, split honestly:**
- **Mechanism — proven.** The direct end-to-end proofs stand, and the treatment readers *used* the
  scaffolds (`t1` credited "the large-negative-delta generator for `advance`/`timeOfDay`," `t3` "the
  docstring-reference scaffolds… stressed totality"). The feature works and gets used.
- **Efficacy on cold readers — not demonstrable.** Both arms saturate at 3/3.

**The meta-finding, and walks 10 + 11 now agree on it: the cold-LLM-reader instrument is too capable
to measure a surfacing feature.** These features exist to help a reader who *skips steps* — doesn't
read every docstring, doesn't probe every edge, or can't find the contract-critical function in a
500-file tree. An LLM subagent skips nothing, so the instrument cannot detect the feature's value even
where it plausibly exists (a tired human reviewer; scale). Two walks, same wall. Measuring these
features honestly needs either a *skim-constrained* reader profile or a *large-tree* fixture where
attention-direction is the bottleneck — not a 10-function library a diligent reader walks end to end.

**Sub-finding — round-trip subdomain suppression (found, not fixed).** The subtle bug lived in
`timeOfDay(fromMinutesSinceMidnight:)`, and its docstring scaffold was **suppressed**: the function
pairs with `minutesSinceMidnight` as a round-trip (a role-entailed refutable law), so B23's advisory
declined to surface a reference oracle for it (path 4 — "a self-contained role-entailed law already
serves it"). But the round-trip's inputs come from `minutesSinceMidnight` → always `0...1439`, which
**never reaches the bug's trigger domain** (`< -1440`) — so the "covering" law is structurally
incapable of catching the bug the docstring documents behavior for. A role-entailed law that exercises
only a *subdomain* should not suppress the reference oracle when the docstring documents behavior
outside it. (The mechanism recovered anyway: `advance(_:byMinutes:)` shares the crash path, its Int
parameter is edge-biased/bounded, and *its* scaffold reached the bug — which is how the treatment
readers found it.) The fix, deferred: gate the suppression on the covering law's input domain, or
always surface the oracle when the docstring names an out-of-covered-domain edge.

Fixture + six reader reports + answer key retained in the walk-11 scratch harness. No fixture or
docstring reused from B25's proofs.

---

## Tier C — ergonomics, packaging, docs

Not correctness, but this is the tier that decides whether a reader gets to Tier A at all.

| # | fix | repo | size |
|---|---|---|---|
| C1 | ~~`--sources <dir>` so the tools can be aimed at an `.xcodeproj` instead of requiring a shim SwiftPM package.~~ **DONE** — SwiftInferProperties: `discover --sources <dir>` scans a directory as given, mutually exclusive with `--target`, with an Xcode-aware error on a missing/absent path. Removes the shim for the loop's entry point; verified running on MacCloud's raw `.xcodeproj` tree. (Single-dir; repeatable multi-root and reading `PBXFileSystemSynchronizedRootGroup` from the pbxproj remain a future extension.) | SIP | M |
| C2 | When suggestions are hidden by tier, **say so**: `6 suggestions hidden below tier Likely — pass --include-possible`. One line; would have saved most of this session's confusion. Then recalibrate: a literal semigroup scoring 30/Possible means the thresholds are wrong. | SIP | S |
| C3 | Document `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` — Xcode 26's default — prominently, in all five READMEs. Under it, `propertyCheck` cannot reach app types and the **law kit is entirely unusable** (a MainActor-isolated `Codable` conformance cannot satisfy a `Sendable` requirement). The fix is `nonisolated` on pure types and DTOs. The compiler errors point at concurrency, not at the fix. | all | S |
| C4 | Split `SwiftIdempotencyFluent` into its own package (or gate behind a SwiftPM trait). Today an iOS app that wants two marker macros resolves **fluent-kit, sql-kit, SwiftNIO** and friends — the graph goes 9 → 19 packages. | SwiftIdempotency | M |
| C5 | Reword "keeps the main line dependency-light" (Appendix C). SwiftPM resolves *package-level* deps regardless of product; the opt-in split saves linking, not fetching. `PropertyLawKit` alone pulls 9 packages. | book / SPL | S |
| C6 | Note `-skipMacroValidation` for Xcode + CI. `swift build` has no macro-trust step, so nothing prepares you for the hard build failure. | SwiftIdempotency, SPL | S |
| C7 | Teach the linter its siblings' assertion vocabulary — `propertyCheck`, `assertIdempotentProperty`, `assertIdempotentEffectsProperty`, `check*PropertyLaws`. It currently flags property-based tests as "no assertions". | SwiftProjectLint | S |
| C8 | **Tag SwiftProjectLint and SwiftEffectInference** — both have *zero* git tags and can only be pinned by revision. Reconcile SwiftInferProperties' tags (latest `v1.63.0`, HEAD 530 commits ahead, CLI self-reports `1.148.0`). | SPL, SEI, SIP | S |
| C9 | Ship install artefacts — a Homebrew formula or notarised release binaries. Both CLIs currently require an ~8-minute `swift build -c release` from a clone. | SPL, SIP | M |
| C10 | Rename the linter's executable product from `CLI` to `swiftprojectlint`. | SwiftProjectLint | S |
| C11 | Upstream PR to `x-sheep/swift-property-based`: `Gen.element(of:)` is `Optional`-typed and carries `Shrink.None`, so the commonest generator never shrinks. Add a non-optional `Gen.one(of:)` with index-based shrinking. | upstream | S |

---

## Order of work

Dependency-forced, because SwiftEffectInference is the shared leaf that both the linter and
`swift-infer` consult:

```
Wave 1   SEI: A4 (precedence + lexical grading)          ← everything above reads its grades
           │
Wave 2   ├── SwiftProjectLint: A2, B1, B2                ← produces the seeds
         └── SwiftInferProperties: A1, A3, C2            ← consumes them (independent of Wave 2)
           │
Wave 3   SwiftInferProperties: B3, C1                    ← templates + Xcode targeting
           │
Wave 4   SwiftPropertyLaws: A5, B4, C3                   ← independent; can run in parallel from day 1
Wave 5   SwiftIdempotency: C4, C6                        ← independent; can run in parallel from day 1
Wave 6   Tier C housekeeping: C5, C7–C11
```

Waves 4 and 5 have no dependency on 1–3 and can be done at any time; they are listed last only
because they are lower-leverage for the benchmark.

**If you only do four things:** A1, A3, **B2, B3**. Those four take the benchmark from *"0 suggestions,
exit 0"* to *"here is the pure kernel inside your upload method, and here is the law it should obey."*
That is the entire difference between the loop working and not.

**This list used to read A1, A3, A4, B2, and that was wrong — B2 alone cannot deliver the second half
of its own promise.** B2 finds the kernel; it does not know what a chunker *owes*. Hand `ChunkPlan` to
a `swift-infer` whose catalogue has no partition template and it proposes the only law it has for a
pure function — `f(x) == f(x)` — which cannot fail, and the reader learns nothing. The kernel and the
law are two items, not one: **B2 supplies the role, B3 supplies the law for it.** A4 stays worth doing
and is now closed anyway, but it was never what stood between the loop and a found bug.

---

## The re-run protocol

```bash
git -C MacCloud_client_iOS checkout main        # the pristine fixture, f3dbb6f

# Phase 1 — the linter names the pure kernels.
swiftprojectlint . --format pbt-seeds > seeds.json
swiftprojectlint . --format text --categories testability   # the extract-this-kernel advisories, WITHOUT the style-lint noise (W2)

# swift-infer runs STRAIGHT against the .xcodeproj tree — no SwiftPM shim (C1 / --sources, shipped).
swift-infer discover --sources MacCloud_client_iOS --seeds seeds.json --include-possible
```

**This protocol now runs exactly as written — it used to be aspirational.** Three workflow cleanups
landed after walk 9 made it real, each one a friction every cold reader hit:

- **`--sources` (C1, shipped).** `swift-infer discover` took a `--target` that resolved under
  `Sources/<target>/`, which an app does not have — so the eight cold walks each needed a hand-built
  SwiftPM shim, and the `--sources` in this very protocol named a flag that did not exist. It exists
  now: point it at the folder your `.swift` files live in and the loop runs on the raw `.xcodeproj`.
- **`--categories testability` (W2).** `--format text` emits ~450 advisory lines on this app; every
  reader had to grep the two PBT ones out of the SwiftUI/style noise. The category filter cuts it to
  just the extractable-kernel / pure-closure advisories — which is where the B16/B18 tiler prose the
  reader actually needs lives.
- **The phase-1 `kept 0` line is now a note, not a warning (W1).** Every reader read
  `focused on N analysable seed(s): kept 0 … the focus discarded all of them` as a failure on their
  first run. It never was: before extraction the seeds name pure functions while the only refutable
  law is over an impure kernel, so of course they miss. The message now reads *"kept 0 … EXPECTED
  before you extract … extract those kernels and re-run,"* and keeps the "the tools disagree" reading
  only for the genuine post-extraction case.

**The re-run is two-phase, and the protocol above hides it.** B2 found the gap. A *template* matches a
*shape*, and the shape a partition law needs — a type with a size, a part size, a count and an
index → range function — **does not exist on the fixture**. The chunking arithmetic there is loose
statements inside an `async` method. So the loop necessarily runs:

```
phase 1   fixture, untouched      → "there is pure logic here; name it"   (B1 + B2)
             ↓  the reader performs the extraction the linter asked for
phase 2   fixture + ChunkPlan     → "and here is the law it owes you"     (B3)
```

Rows 5 and 6 below are **phase-2 rows**. They cannot be scored against a pristine fixture, and a run
that reports them as zero there has not found a defect — it has found a reader who has not done the
refactor yet. Score them against the tree *after* the extraction, and score rows 1–4 and 4a before it.

Score against `pbt-road-test-reference`:

| # | check | today | target |
|---|---|---|---|
| 1 | linter seeds | **9** — 7 analysable + 2 kernels | ≥6 pure candidates |
| 2 | extractable-kernel sites | **6** — incl. `fetchLocalFiles` ×2 (B6b) | 2 — `uploadRemainingChunks`, `fetchLocalFiles` |
| 3 | `swift-infer` runs against the `.xcodeproj` without a shim | **yes** — `discover --sources <dir>` (C1) | yes |
| 4 | seeded discovery returns > 0 | **7** | ≥5 |
| 4a | **proposed laws that could ever fail** (default flags) | **1 of 7** (phase 1) · **3 of 9** (phase 2) | **≥5** |
| 5 | a partition/tiling law is proposed for the chunk math | **yes, for a real reader** — B12 taught the template the slice shape 3 of 3 readers actually write; 60 (Likely), clamp clause included | yes |
| 6 | a comparator law is proposed for the folders-first sort | **no** — nobody is asked to extract it, B6b | yes |
| 7 | effect annotations override inference | no | yes |
| 8 | the law kit is usable on app DTOs (after `nonisolated`) | no | yes, and documented |
| 9 | **would a reader following the loop reach all 3 bugs?** | **3/3 — MET (walk 9):** all 3 readers reach all 3 (grandchild, empty-file, resume-counter), once B19 stopped the reader clamping the shipped generator. Upper bound: same fixture, eight walks — a second unseen fixture is what would retire the caveat (B8, B20) | **3/3** ✅ |

Row 9 is the only one that really matters. Rows 1–8 are how you get there.

**Row 4a exists because row 4 can be passed by a tool that finds nothing.** Six determinism laws over
six functions already graded pure satisfy *"seeded discovery returns > 0"* while asserting nothing
that could be false. It is the only row that cannot be gamed by a confident tautology, and it is the
one that actually moves when B2 and B3 land. Count a law as refutable if there exists an
implementation of the function, type-correct and plausible, that the law rejects — `f(x) == f(x)`
admits no such implementation, and `concat(chunks(payload, k)) == payload` admits many.

**Keep the fixture honest.** Do not merge `pbt-road-test-reference` into `main` — the moment the app
contains `ChunkPlan`, the benchmark is spent. If a second run is wanted later, fork a fresh fixture
from `f3dbb6f` rather than reusing a tree the tools have already been tuned against.

**Keep the answer key honest, which is the rule that nearly got broken.** The key is frozen at
`f3575b7`. **Nothing the tools find may be added to it** — not a kernel, not a law, not a bug —
because the key's only value is that it was written *before* the tools were tuned and *without*
consulting them. B1 already turned up a kernel the key does not contain (`filteredFiles`, see the
benchmark note), and folding that in would have moved the score from 1 of 2 to 2 of 3 by adjusting the
denominator to fit the measurement. Record such finds as **unscored** and adjudicate them with row
4a's refutability test, which appeals to the law rather than to the tool that proposed it. A tool that
grades its own homework will always improve.
