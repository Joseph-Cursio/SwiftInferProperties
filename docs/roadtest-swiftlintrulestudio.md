# Road-test — SwiftLintRuleStudio (2026-07-22)

Toolchain-facing record of pointing `swift-infer discover` at a third-party
subject — **SwiftLintRuleStudio**, a macOS SwiftUI app with a SwiftPM Core
package (`SwiftLintRuleStudioCore`). Unlike the MacCloud road-tests, the driving
question here was **not** "find bugs" but **"why did the pipeline recommend so
little?"** — the owner ran the loop, got a handful of suggestions for a Core
package full of pure kernels, and wanted the *confident-zero* diagnosed rather
than worked around.

The verdict: **the tool is not broken, it is out-of-catalog.** The subject's
interesting kernels are filter / selection / set-algebra / parse shapes the law
families don't name; one key kernel is gated out by `throws`; and everything
that isn't a primitive-typed pure function scores below the visibility cut for
lack of a derivable generator.

> **Reconciled 2026-07-22.** This began as the pre-fix write-up. Three of the
> prioritised fixes have since shipped (subset/filter template, throwing-function
> determinism, generator derivation incl. the upstream >10-member kit change) —
> see [Fixes shipped](#fixes-shipped-reconciled-2026-07-22), which also carries a
> correction to root cause 2. The diagnosis below is left as the record of what
> was found.
>
> **Re-measured 2026-07-24.** The 07-22 numbers reproduce exactly — but running
> the linter and the inference engine *as a pipeline*, rather than checking each
> fix on its own, showed two of those closures claiming more than they deliver.
> The `throws` seam is now fixed (the leaf separates transparency from totality);
> the owed-law warning still fires on five subjects when the seed manifest is the
> linter's own. Read
> [Finding A, corrected](#finding-a-corrected--throws-was-never-what-blocked-serialize)
> if you read nothing else here: the fix shipped, and measuring it refuted the
> premise that motivated it. See
> [Re-measured 2026-07-24](#re-measured-2026-07-24--two-closures-that-do-not-survive-the-real-pipeline).
>
> **Fourth pass, same day.** The app owner closed candidate §3 (`generateDiff`),
> taking the loop to three kernels and `swift test --filter PropertyLaw` to 16
> tests in 5 suites. Along the way the `#10` registered-generator row went the
> way of Finding A: registering `Node` for real changes `discover` by nothing at
> all, because the carrier it was supposed to unblock is never derived to begin
> with. It had been verified on a `YAMLConfig`-shaped probe. See
> [Finding C](#finding-c--the-registered-generator-hook-does-not-reach-the-real-yamlconfig).
>
> **Fifth pass, 07-24.** The self-method-call gate — the item Finding A left open
> as "what would reach `serialize`" — was built and closed, soundly and
> cross-file, worth 4 seeds. `serialize` is **still** not seeded: a propagated
> `try`, into **Yams**, refutes it a third time, and no whole-program pass reaches
> a dependency. Three passes have each named the remaining blocker and been wrong.
> See [Finding D](#finding-d--the-self-method-call-gate-is-closed-and-serialize-is-still-out-of-reach).

## Setup (honesty)

- **Not a scored benchmark.** No hand-written answer key (that must predate the
  tools — Appendix C). This is a *coverage investigation*: run the pipeline,
  categorise every disposition, trace each to its cause in the source.
- Subject: `SwiftLintRuleStudioCore` (SwiftPM), scanned via
  `discover --target SwiftLintRuleStudioCore`. Prebuilt `.build/debug/swift-infer`
  (2026-07-21), all packs enabled.
- Prior fixes from this subject already landed in the kit (earlier session):
  `(T?) -> T` idempotence recognition, the corrected "not derived" message, and
  the String-collection idempotence generator recipe. So this is the *second*
  pass — the gaps below are what remains after those.
- The "real kernels" referenced throughout are the eight the subject's own PBT
  exploration doc identified: `mergedWith`, `deindent`, `filterViolations`,
  `layerChain`, `generateDiff` / `diffBetween`, `parseParameters`,
  `serialize` (↔ parse round-trip), `levenshteinDistance`. `mergedWith`,
  `deindent`, and `levenshtein` already carry hand-written laws.

## The two runs

### Run 1 — unseeded, whole target

```
$ swift-infer discover --target SwiftLintRuleStudioCore --stats-only --include-possible
30 suggestions across 9 templates.
  codable-round-trip: 1 (1 Likely)   consumer-producer-chain: 2 (2 Advisory)
  idempotence: 10 (1 Likely, 9 Possible)   inverse-pair: 1 (1 Possible)
  measure-non-negativity: 2 (Possible)   monotonicity: 3 (Possible)
  predicate: 6 (Possible)   round-trip: 3 (Possible)   state-machine: 2 (Possible)
```

Two numbers matter:

- **Tier: 26 Possible / 2 Likely / 2 Advisory.** "Possible" (score 20–39) is
  **hidden by default** (`--include-possible` off). A default run surfaces ~4.
  The tool *knows about 30 candidates and shows 4.*
- **Generator: 20 of 30 print `not derived (no strategy matched this type)`**,
  7 `.todo`, 3 `.derivedInitializer`. ~90% have no runnable generator.

These two are linked (see root cause 3): no derivable generator ⇒ low score ⇒
Possible ⇒ hidden.

Also noted — **noise, not silence**: the `round-trip` template proposed a
spurious type-symmetry pairing on `CustomRuleConflict`, pairing the initializer
`ruleIdentifier(String) -> CustomRuleConflict` with unrelated `String` getters
(`id()`, `message()`) as if they were its inverse. So the surface is *both*
missing the real kernels *and* emitting false pairs.

### Run 2 — seeded with the eight real kernels

A hand-written v2 seed manifest naming the real kernels as `pure-function`.
stderr is the diagnosis:

```
focused on 7 analysable seed(s): kept 2 of 28 seedable suggestion(s)
synthesized 4 generic determinism law(s) for seeded functions
warning: `predicate` on isVersion…, looksLikePlaceholderYAML…, columnIsNull… —
  owed by ROLE … the manifest SHOULD have named it: this is a LINTER gap
```

Per-kernel disposition:

| Kernel | Signature | Result | Cause |
|---|---|---|---|
| `mergedWith` | `([String]?) -> [String]` | **idempotence, Likely (50)** ✅ | template matched |
| `deindent` | `([String]) -> [String]` | **idempotence, Possible (35)** ✅ | template matched |
| `filterViolations` | `([Violation],[URL],URL) -> [Violation]` | `f(x)==f(x)` (Advisory 30) | **no subset/filter template** |
| `layerChain` | `(URL, ConfigTree) -> [DiscoveredConfig]` | `f(x)==f(x)` (Advisory 30) | **no selection/ancestry template** |
| `generateDiff` | `(YAMLConfig) -> ConfigDiff` | `f(x)==f(x)` (Advisory 30) | **no set-algebra-diff template** |
| `parseParameters` | `(String,String) -> [RuleParameter]?` | `f(x)==f(x)` (Advisory 30) | **no parse/metamorphic template** |
| `serialize` | `(YAMLConfig) throws -> String` | **nothing — not indexed** | **`throws` refutes purity at index time** |

The synthesized "determinism" laws are `f(x) == f(x)` — the non-refutable
fallback Appendix C's *score-refutability* rule exists to discount. For the
subject's four most interesting kernels, the pipeline's honest output is a
tautology. `serialize` — one half of the highest-value law (parse ↔ serialize
round-trip) — produced nothing at all: it never reached the determinism fallback
either, because `throws` refuted its purity before indexing.

## Root causes, ranked by leverage

**1. Template-catalog gaps (dominant).** For the subject's interesting kernels
the catalog has no matching law family, so `discover` falls back to `f(x)==f(x)`.
This is the `intersect`→`intersection` failure mode generalised: the *shapes* are
present, the *catalog's name/shape signals* don't fire.
  - `filterViolations`: `[T]->[T]` filtering — owes **subset** (`result ⊆ input`),
    **idempotence under same batch**, **membership**. No template.
  - `layerChain`: selection by path-prefix — owes **ancestry** (every result is an
    ancestor of the target) and **monotonicity under descent**. `MonotonicityTemplate`
    exists but its name/shape signal didn't fire on `layerChain`.
  - `generateDiff` / `diffBetween`: owes **set-algebra** (added = keys(b)\keys(a),
    disjointness) and **swap-symmetry** (added↔removed). No template.
  - `parseParameters`: parser with no serialiser inverse — owes **metamorphic**
    laws (comment/blank-line insensitivity, order preservation). No template, and
    no inverse to pair for round-trip.

  *Highest leverage:* a subset/filter family and a selection-monotonicity family
  turn 3 of the 4 tautologies into refutable laws.

**2. Purity veto refuses `throws`.** `serialize` is killed at indexing because it
throws — even though `RoundTripTemplate` already knows how to narrow a throwing
law's domain to its success set (it says so in its own caveats). One `throws` on
the *producer* side of a round-trip should narrow the domain, not delete the
candidate. This blocks the single highest-value law on the subject.

**3. No generator strategy for the domain types.** `DerivationStrategist` derives
`Gen` for CaseIterable / RawRepresentable / small memberwise-init structs / enum
payloads / Codable / registered types. The subject's carriers —
`YAMLConfig` (holds `[String: RuleConfiguration]`), `ConfigTree`, `Violation`,
`ConfigDiff`, `DiscoveredConfig`, `RuleParameter` — exceed that (dictionaries of
custom values, nested types, arity). Result: `not derived` for 20/30, which both
makes the law unrunnable *and* scores it into the hidden tier.

**4. Default tier cut hides Possible (20–39).** Compounds 3: a matched, refutable
law about a `YAMLConfig` is invisible on a default run purely because its
generator is `.todo`. The reader sees 4 of 30 and reasonably concludes "there's
nothing here."

**5. Linter gap upstream (secondary).** The seeded run's `owedLawWarning` shows
six role-entailed `predicate` laws that SwiftProjectLint's pure-function rule
*failed to seed* — "a shape the linter cannot see (a computed-property read, a
call to `min`)." Part of the under-recommendation is upstream of `swift-infer`.

> **Correction (2026-07-22, verified) — this was a phantom.** Root cause 5 was
> misattributed. The `owedLawWarning` fired against the **hand-written** seed
> manifest used for Run 2, which listed only the seven exploration kernels and
> omitted `isVersion` et al. — it was *my manifest* that was incomplete, not the
> linter. Running the linter directly settles it: `swiftprojectlint --format
> pbt-seeds` over `SwiftLintRuleStudioCore` emits **85 seeds** (62 pure-function,
> 23 extractable-kernel) and *does* seed `isVersion`, `looksLikePlaceholderYAML`,
> and `isUnavailableForLinting`, while correctly excluding the state-reading
> `columnIsNull` / `boolValue`. There is no under-seeding gap; the linter's
> pure-function rule works. The lesson is the appendix's own: verify the claim
> against the tool's actual output before fixing it.

## Prioritised toolchain fixes

1. **Throws-tolerant round-trip pairing** (root cause 2) — smallest change,
   unblocks the highest-value law (`serialize ↔ parse`). Let a throwing producer
   pair for a round-trip with its domain narrowed to the success set, matching the
   caveat the template already prints.
2. **Subset/filter law family** (root cause 1) — for `[T] -> [T]` (and
   `[T],… -> [T]`) functions whose name/shape reads as a filter/selection: emit
   `result ⊆ input` + idempotence-under-same-args. Converts `filterViolations`
   (and `layerChain`, framed as selection) from tautology to refutable.
3. **Widen `MonotonicityTemplate` / add a selection-ancestry signal** so
   `layerChain`-shaped path-prefix selectors are proposed.
4. **Generator derivation for dictionary-bearing / nested-custom structs**
   (root cause 3) — or, cheaper, stop letting `.todo` generators sink a matched
   *refutable* law below the visibility cut (root cause 4): a law's refutability,
   not its generator's readiness, should decide whether the reader sees it.
5. **Report the linter gap** (root cause 5) upstream in SwiftProjectLint's
   pure-function detection (computed-property reads, `min`/`max` calls).

## Fixes shipped (reconciled 2026-07-22)

The prioritised list above is now a changelog. What landed — and one correction
to the diagnosis:

| Fix | Root cause | Status |
|---|---|---|
| Subset/filter law family | 1 | ✅ `filter-subset` template (`748dd81`) — `filterViolations` owes a refutable `Set(result) ⊆ Set(haystack)` instead of `f(x)==f(x)` |
| Throwing functions earn a law | 2 (re-diagnosed twice) | ✅ `9e1e066` on the consumer side, and the producer side closed 2026-07-24: the leaf now separates transparency from totality (`PurityVerdict.pureButPartial`) and the linter seeds throwing pure functions. **Does not unblock `serialize`** — see [Finding A, corrected](#finding-a-corrected--throws-was-never-what-blocked-serialize) |
| Generator derivation | 3 | ✅ discover-side composite fallback (`3bf23e0`) + upstream nested-`zip` >10 members (`SwiftPropertyLaws v3.17.0`; floor-bumped `830c344`) |
| Selection-ancestry template | 1 (`layerChain`) | ✅ `selection-subset` template (`288fdc4`) — `layerChain` owes `result ⊆ ConfigTree.configs` |
| Diff characterization template | 1 (`generateDiff`) | ✅ `diff-disjointness` template (`f723744`) — `generateDiff` owes `added ∩ removed = ∅` |
| Refutability decides visibility (the tier cut) | 4 | ✅ `52a16d7` — role-entailed refutable laws (incl. filter/selection/diff) surface on a default run, not just `--include-possible` |
| Stop the spurious `CustomRuleConflict` round-trip pairing (the "noise" finding) | — | ✅ #10 — `FunctionPairing` admits a synthetic init-decode half only when the encode name embeds the init's argument-label stem (the same predicate `RoundTripTemplate` scores +40 on), so `CustomRuleConflict(ruleIdentifier:)` no longer pairs with the unrelated `id()` / `message()` getters |
| Registered-generator hook for the external `Node` boundary | 3 (residual) | ⚠️ #10 shipped, **unverified on the real subject**. `Vocabulary.registeredGenerators` supplies a generator for an underivable external member (`{ "Node": { "expression": "Node.gen()", "imports": ["Yams"] } }`), and `discover` on a `YAMLConfig`-*shaped* struct moves from `Generator: .todo` to a derived generator. On the actual `YAMLConfigurationEngine.YAMLConfig` it changes **nothing** — see [Finding C](#finding-c--the-registered-generator-hook-does-not-reach-the-real-yamlconfig) |
| Report the linter gap | 5 | ⚠️ withdrawn, then **partly reinstated**. The original phantom stands (`swiftprojectlint --format pbt-seeds` emits 85 — now **95** — seeds and *does* seed the pure predicates; the warning came from an incomplete hand-written manifest). But re-run against the linter's *own* manifest the warning still fires on five subjects — see [Re-measured 2026-07-24](#re-measured-2026-07-24--two-closures-that-do-not-survive-the-real-pipeline) |

**Correction to root cause 2.** *"`throws` refutes purity at index time"* was
wrong, and tracing the code showed why: the `round-trip` template already
*tolerates* `throws` (it renders a domain-narrowing caveat, not a veto).
`serialize` produced nothing for two other reasons — the generic **determinism**
fallback explicitly excluded throwing functions (`qualifiesForDeterminism`'s
`isThrows == false` guard), and the `serialize ↔ parse` round-trip can't form
because the app exposes no `String -> YAMLConfig` inverse (`load()` mutates
`self`). The fix (`9e1e066`) un-gates the determinism synthesis for throwing pure
functions and emits a sound `(try? f(x)) == (try? f(x))` stub (a throwing input
collapses to `nil == nil`, so no false positive). That earns `serialize` the
determinism **floor** — a tautology, not the round-trip. The refutable round-trip
still needs an app-side `parse(String) -> YAMLConfig`; the tool is correctly
silent until one exists.

**After the fixes (same two commands):**
- Unseeded whole-target *"not derived"*: **20 → 6**. The 15 that flipped to
  `.derivedComposite` are the stdlib/collection carriers (`deindent`,
  `mergedWith`, `isVersion`, …) the selection layer used to skip.
- With the >10-member nesting, `filterViolations`'s `[Violation]` carrier now
  derives (`.derivedComposite`) — it needed **both** the composite fallback *and*
  `Violation`'s 11 members composing past the old zip-10 wall.
- `serialize` moved from *nothing* to the determinism floor, with a throws-aware
  caveat.

**Still open, by design or scope:** `parseParameters`' metamorphic laws
(domain-specific — belong in the app's hand-written suite, not a template); and
the `serialize ↔ parse` round-trip (needs an app-side `parse(String) ->
YAMLConfig`). *Closed by #10:* the `CustomRuleConflict` round-trip noise (a
pairing tightening). *Not closed, contrary to what this section originally
claimed:* the `YAMLConfig` external-`Node` boundary. `#10` turns it from a hard
`.todo` wall into a *registration* on a `YAMLConfig`-**shaped** probe, but on the
real `YAMLConfigurationEngine.YAMLConfig` the registration changes nothing — see
[Finding C](#finding-c--the-registered-generator-hook-does-not-reach-the-real-yamlconfig).
*Withdrawn:* the "linter seeding gap" (root cause 5) was a phantom — see the
correction above.

## Re-measured 2026-07-24 — two closures that do not survive the real pipeline

Third pass, driven by a different question again: *how much did the two days
after the reconcile move?* Answer: **nothing, on this subject** — and the
measurement that establishes that also caught two rows of the changelog above
claiming more than they can deliver end to end.

**Method.** Built `swift-infer` at the 07-22 tip (`bfc0988`, the reconcile
commit) and `swiftprojectlint` at `e4a7a86` in throwaway worktrees, and ran both
against HEAD. Unseeded `discover`, seeded `discover`, and the seed manifest are
**byte-identical** across the two days (`diff -q` clean on all three). The
07-23/07-24 commits — list-derivation refactors, false-positive suppressions,
the new duplication-rule family — move nothing here. The 07-22 numbers *do*
reproduce, which is the useful half of a null result:

| Claim | Reproduced today |
|---|---|
| Default run surfaces the three new families | ✅ 15 of 29 suggestions (was ~4 of 30) |
| `filterViolations` → `filter-subset` | ✅ score 35, generator `.derivedComposite` |
| `layerChain` → `selection-subset` | ✅ `result ⊆ ConfigTree.configs` |
| `generateDiff` → `diff-disjointness` | ✅ `added ∩ removed = ∅` |
| `CustomRuleConflict` noise gone | ✅ `round-trip` 3 → 0, `inverse-pair` 1 → 0 |
| *"not derived"* 20 → 6 | ✅ measures **5** today (the doc's 6 predates two 07-22 commits) |
| Seed manifest 85 | ✅ measures **87** (64 pure-function + 23 extractable-kernel) |

And the app closed its half: `swift test --filter PropertyLaw` on
`SwiftLintRuleStudioCore` runs **13 tests in 4 suites, all green**, including
*"filterViolations is a subset, membership-exact, and idempotent"* and
*"layerChain selects tree ancestors of the target, ordered by depth"*. Two of the
four tautology kernels went proposal → written → passing. That is the loop
working as advertised, and it is the strongest thing this road test has to show.

Neither finding below is a regression — both were equally true on 07-22. They are
what the reconcile missed by measuring each fix in isolation instead of running
the pipeline end to end.

### Finding A — the two ends of the loop disagreed about `throws`

> **Fixed and re-diagnosed 2026-07-24.** The disagreement below was real and is
> now closed. Its stated *consequence* — that closing it would unblock
> `serialize` — was wrong, and finding out why is the more useful half. See
> [Finding A, corrected](#finding-a-corrected--throws-was-never-what-blocked-serialize).

The changelog credits `9e1e066` with moving `serialize` from *nothing* to the
determinism floor. The synthesis does work: hand-seed a one-entry manifest naming
`serialize` and `discover` reports `synthesized 1 generic determinism law(s)`.

But **`swiftprojectlint --format pbt-seeds` never emitted `serialize`.** The
linter's purity oracle refuted `throws`, so the symbol was absent from all 87
seeds — `YAMLConfigurationEngine+Serialization.swift` contributed
`indentBlockSequences`, `warningOnlyInt`, and `topLevelRuleValue`, and nothing
else. `PBTSeedsFormatter.swift` said so in its own doc comment, in passing:
*"`uploadRemainingChunks` is `private async throws`, which refutes purity."*

So the two ends of the loop openly disagreed. `swift-infer` says a throwing pure
function earns a determinism law; the linter said `throws` refutes purity and
declined to name it. `qualifiesForDeterminism`'s un-gating was reachable only by
a hand-written manifest, and Appendix C's claim that the shared `PurityInferrer`
means the linter and the inference engine *"can never disagree about what is
pure"* did not hold at that seam.

**How it was settled.** The leaf was conflating two different properties.
`Effect.pure` is a conjunction — referentially transparent **and** total — and
`throws` refutes only the second clause. `SwiftEffectInference` now answers with
`PurityVerdict { pure, pureButPartial, refuted }`; `isPure` / `inferredEffect`
are defined as `verdict == .pure`, so no existing consumer's answer moved, and
`PropertyTestCandidacy` is the one caller that opts into the partial tier.

### Finding A, corrected — `throws` was never what blocked `serialize`

Shipping the fix and *measuring* it refuted the premise twice over. Both
refutations came from running the tool, not from reading it — the same lesson
root cause 5 taught, arriving by a new route.

**First: `throws` was silently doing a second job.** Admitting throwing
candidates took the manifest from 87 seeds to **98**, and about ten of the eleven
new ones were I/O. The worst was `runSwiftLint(executable:workingDirectory:lintFile:)`
— it builds a `Process`, wires up a `Pipe`, and calls `try process.run()` — judged
pure. That is the lattice-bottom mistake `PurityInferrer`'s own soundness note
forbids, and the cause is that **nearly all real Swift I/O throws**, so gating on
`throws` had been masking every impurity marker the set does not name: `Process`,
`Pipe`, `FileHandle`, `String(contentsOf:)`, `Data(contentsOf:)`, the SQLite
surface. Remove the gate and they all walk in at once.

The distinction that survives is *where the error comes from*. A function that
raises **its own** error (`guard let v = Int(text) else { throw ParseError.bad }`)
is partial and pure. A function that `try`s into a callee is doubt about the
callee, and doubt refutes. With that second gate the subject moves 87 → **90**:
`decodeRuleText`, `collectRows` (a pure loop over injected effect closures — a
genuinely good find), and `resolveFileURL`.

**Second, and the actual correction: `serialize` is still not seeded, and this
work could never have reached it.** Two independent blockers, both defensible:

1. Its throwing is *entirely propagated* — `try orderedTopLevelPairs(for:)` and
   `try Yams.serialize(node:)`. The new gate correctly refuses it.
2. Independently, it calls other methods on `self`, and `SelfAccessAnalyzer`
   refuses what it cannot resolve. A probe settles that this is a separate cause
   rather than the same one twice: a method that calls a sibling method on `self`
   and **does not throw at all** is refused identically.

So the seam disagreement was real, is fixed, and is worth three seeds — but it
was never the binding constraint on `serialize`. The original reasoning inferred
"the linter refuses `throws`, therefore `throws` is why `serialize` is missing"
from a doc comment and the leaf's gate ordering, without testing whether removing
that gate was *sufficient*. It was not. A refuter that fires first hides every
refuter behind it, and reading the code cannot tell you how many are queued up —
only running it can.

> **Closed 2026-07-24, and it did not reach `serialize` either.** The
> self-method-call gate (blocker 2) is now shut — soundly, cross-file — and
> `serialize` is *still* unseeded, because a third refuter sits behind the two
> named here. See
> [Finding D](#finding-d--the-self-method-call-gate-is-closed-and-serialize-is-still-out-of-reach).
> This paragraph's proposal is what got built; its prediction was wrong.

**What would reach `serialize`** is relaxing the self-method-call gate, which is
a different and much riskier change: that gate is what keeps `unresolvedOrMutable`
sound on application code, where almost all logic is instance methods. Left open
deliberately. The `serialize ↔ parse` round trip still additionally needs an
app-side `parse(String) -> YAMLConfig`, which does not exist.

### Finding B — the owed-law warning still fires against the linter's own manifest

Root cause 5 was withdrawn on the strength of the right check (the linter *does*
seed `isVersion`, `looksLikePlaceholderYAML`, `isUnavailableForLinting`), but the
withdrawal was never re-tested the way the pipeline actually runs: feed
`discover --seeds` the linter's own manifest rather than a hand-written one. Do
that, and the `owedLawWarning` still names five subjects:

- `layerChain`, `filterViolations`, `generateDiff` — seeded, but only as
  `extractable-kernel`. `PBTSeedKind.isAnalysable` is `false` for that kind, so
  the focus cannot see them: the linter is pointing at an unnamed kernel *inside*
  each function while the template has a law owed by the function itself.
- `columnIsNull(at:)` and `boolValue(for:)` — not seeded at all. The correction
  above reads their absence as the linter *correctly* excluding state-reading
  functions; `swift-infer` reads them as role-owed `predicate` laws the manifest
  should have named. That disagreement is unresolved, not settled.

> **Re-checked twice, against a growing manifest, and it does not move.** First
> measured on the 87-seed manifest; re-run at 90 seeds after the `throws` producer
> fix; re-run again at **95** seeds (subject `9801dff`, `swiftprojectlint feeea0f`,
> `swift-infer 7ac71fd`) after Finding D. Every time the warning names **the same
> five subjects, for the same reasons**: `layerChain` / `filterViolations` /
> `generateDiff` are still seeded `extractable-kernel` only, and `columnIsNull` /
> `boolValue` are still not seeded at all. Both rounds of newly admitted seeds —
> `decodeRuleText` / `collectRows` / `resolveFileURL`, then `reinsertComments` /
> `calculateCategoryBalance` / `calculatePathConfiguration` /
> `shouldSkipWorkspaceScan` — are disjoint from the five. **Eight more seeds have
> not touched the gap**, which is the strongest evidence yet that it is
> kind-granularity and not under-seeding: adding seeds does not help when the
> problem is the *kind* a subject is seeded under.

The honest reading is narrower than the original root cause 5 and wider than its
withdrawal: there is no *under-seeding* gap (95 seeds is thorough), but there is
a **kind-granularity** gap. A function can owe a law at its own boundary and
still be seeded only as a location to refactor, and the focus filter cannot tell
the difference.

This also promotes `52a16d7` (refutability decides visibility) from a tier-cut
convenience to a **load-bearing** fix: it is the only reason `filterViolations`,
`layerChain`, and `generateDiff` survive a seeded run at all. The manifest alone
would have hidden all three — the confident zero arriving by the route
`PBTSeedsFormatter`'s doc comment warns about, through the door it was written to
close.

### Finding C — the registered-generator hook does not reach the real `YAMLConfig`

> **Added later the same day**, on a fourth pass driven by the app owner rather
> than the toolchain: *close candidate §3 (`generateDiff`) in the app's own PBT
> doc, using the `#10` registration hook to unblock the generator.* The suite got
> written and it passes. The hook did nothing, and that is the finding.

`#10` above claims the `Vocabulary.registeredGenerators` hook closes the external
`Node` boundary: *"`discover` on a `YAMLConfig`-shaped struct moves from
`Generator: .todo` to a derived generator once `Node`'s generator is
registered."* The app registered it for real —
`.swiftinfer/vocabulary.json` naming `{ "Node": { "expression": "Node.gen()",
"imports": ["Yams"] } }`, with a matching `Node.gen()` written in the test
target. Measured three ways against `SwiftLintRuleStudioCore` at
`swiftprojectlint 23c0133` / `swift-infer 1ea657c`:

| Run | Suggestions | `Generator: .todo` |
|---|---|---|
| Registration absent | 14 | 7 |
| Registration present (conventional path) | 14 | 7 |
| Registration passed explicitly via `--vocabulary` | 14 | 7 |

Identical, and `generateDiff` stays `Generator: .todo` in all three.

**Why it cannot bite.** `swift-infer scaffold --target SwiftLintRuleStudioCore`
emits 21 stubs, and **neither `YAMLConfig` nor `ConfigDiff` is among them**. That
absence is on its own ambiguous — `Scaffold+Pipeline.swift:105` emits a stub only
for a type whose strategy is `.todo`, and `:108` silently skips any type whose
`ScaffoldEmitter.stub` returns nil, so a name can be missing because it derived
*fully* or because the emitter bailed. What settles it is where the two names do
appear: only as unresolved `<#Generator<YAMLConfigurationEngine.YAMLConfig>#>` /
`<#Generator<YAMLConfigurationEngine.ConfigDiff>#>` placeholders *inside other
types' generators* (`ConfigEntry`, `ConfigImportPreview`, `DiscoveredConfig`, …).
An unresolved placeholder is not what a fully-derived type leaves behind, so the
carrier is never derived at all, and a missing member generator was never the
binding constraint — the same shape as Finding A, one layer out: **a refuter that
fires first hides the ones behind it.**

A correlation worth chasing, offered as a lead and not a root cause: all 21
scaffolded types are emitted with *unqualified* names, and the two that fail are
exactly the two referenced *qualified* — both are nested inside
`YAMLConfigurationEngine`. But nesting alone does not explain it, because
`FilterQuery` is also nested (`private struct` inside the `ViolationStorageActor`
queries extension) and *is* scaffolded — as bare `extension FilterQuery`, a name
that would not compile. So the scaffolder does reach some nested types and
mis-names them, while missing these two entirely. Unresolved.

**What this costs the changelog.** `#10`'s `Node` row was verified against a
*"`YAMLConfig`-shaped struct"* — a top-level probe built to match the real type's
members. It passes there and fails here, and the difference is a property of the
carrier the probe did not reproduce. That is the same methodological error the
07-24 pass was written to catch, arriving through the door it built: **a probe is
not the subject.** The `Node` row should read *built and unverified on real
subjects*, the label §C's docstring-mode experiment earned.

**The app's half closed anyway, and by hand.** `generateDiff` went proposal →
hand-written suite → passing without any generator help: the app states the full
characterization (set algebra over rule keys, modified domain, sortedness,
`hasChanges` agreement, self-diff, swap symmetry) rather than stopping at the
proposed `added ∩ removed = ∅`, and verified it *refutable* by mutating `removed`
to `proposed \ current` — the swift-collections `symmetricDifference` bug shape —
which fails with a shrunk one-key counterexample. Their own note is the honest
part: the self-diff law **survives** that mutant, since with `a == b` both
subtractions are empty either way. `swift test --filter PropertyLaw` is now **16
tests in 5 suites**, green; three kernels have closed the loop, not two.

**One suggestion retired itself, correctly.** The default-tier count moved 15 →
14 — not between the three runs above, which report 14 apiece, but against the
third pass's reproduction table, which measured *"15 of 29 suggestions"*. The
vocabulary had nothing to do with it: the dropped entry is
the `consumer-producer-chain` advisory reading *"every observed call to
`generateDiff(_:)` received `getConfig(_:)` output as its argument — author a
property that exercises `generateDiff` against arbitrary `YAMLConfig`s if the
broader domain is also intended."* The app wrote exactly that property, TestLifter
saw it, and the advisory withdrew. That is the one thing in this section that
worked end to end as designed, and it is worth more than the `.todo` count: the
advisory named a real gap in words the reader could act on, and stopped naming it
when the gap closed.

### Finding D — the self-method-call gate is closed, and `serialize` is still out of reach

> **Added 2026-07-24**, on a fifth pass driven by the owner: *close the
> self-method-call gate on `serialize`.* The gate is closed. `serialize` is still
> not seeded, and the third refuter behind it is one this document had not seen.

**What was measured first.** Four probes against the real analyzer, before
touching anything, because the previous two findings were both cases of reasoning
from the code instead of running it:

| Construct | Seeded? |
|---|---|
| Free function calling an unknown callee | ✅ yes |
| Instance method calling a **same-file** sibling | ❌ no |
| Instance method calling a **cross-file** sibling | ❌ no |
| Implicit `catch` binding (`error.localizedDescription`) | ❌ no |

Two things fall out. The first row is the asymmetry that justifies the change: an
instance method was refused for a construct a free function is seeded for without
its callee ever being checked. The second is that `serialize` had **three**
refuters, not the two Finding A named — the untyped `catch` binds `error` where
no pattern collector can see it, and `$0` shorthand parameters were being read as
possible instance state, which alone refuted every method containing a
`filter { … $0 … }`.

**What shipped** (`swiftprojectlint` `69c6ee0`, `feeea0f`). A project-wide
`CleanInstanceMethodCatalog`: per type, the methods that are themselves functions
of their inputs, resolved to a **fixpoint** in `ProjectLinter`'s pre-scan and
injected like `knownEquatableTypes`. Membership is earned — every declaration of
the name must be non-`mutating`, pass the purity oracle, and be clean itself — so
refusal propagates to callers and mutable state cannot be laundered through a
level of indirection. A name the pre-scan never cleared is still refused, so the
"every doubt resolves to `.unresolvedOrMutable`" posture holds outside the
catalog. It is built project-wide rather than per-file because the case that
motivated it has caller and callee in **different files** (`…+Serialization.swift`
and `…+Comments.swift`), so a single-file answer would have closed the easy half
and left the motivating case open.

Measured on `SwiftLintRuleStudioCore` at subject `9801dff`, holding the subject
fixed and swapping only the linter: **91 → 95** seeds (67 → 71 pure-function,
extractable-kernel unchanged at 24), nothing removed, and **`reinsertComments` is
now seeded** — the cross-file sibling that `serialize` calls. The four admitted
are `reinsertComments`, `calculateCategoryBalance`, `calculatePathConfiguration`,
`shouldSkipWorkspaceScan`.

> **Pin the subject when quoting a count.** This was first measured as 90 → 94 at
> subject `3d58747`; re-running it days later gave 97, and the difference was the
> app owner editing `YAMLConfigurationEngine` in an uncommitted working tree, not
> anything in the linter. The *delta* is stable at +4 across both subject
> revisions — it is the base that moves. Every seed count in this document is
> therefore quoted against a named subject SHA, measured from a clean export
> rather than a live checkout.

**And `serialize` is still not seeded.** The third refuter is the *propagated
`try`*, measured rather than inferred:

| Body | Verdict |
|---|---|
| `throws`, no `try` in body | `pureButPartial` |
| `throws` **with `try f()` in body** | `refuted` |

`serialize` is `try orderedTopLevelPairs(…)` / `try Yams.serialize(…)`, so it is
refuted there — and so are `collectTopLevelKeyValues`, `ruleNode`, and
`disabledRulesNode`, which is why none of them enters the catalog either.

**This gate is correct, and it is the one thing here not to touch.** Finding A
already recorded why, one layer up: `throws` had been doing double duty as an
impurity refuter, and removing it re-admitted `Process` / `Pipe` / `FileHandle` /
`String(contentsOf:)` / SQLite in one go, with a subprocess-spawning
`runSwiftLint(…)` judged pure. The leaf's own note names the right escape hatch
and it is the shape the catalog already takes — *"`EffectSymbolTable` is where a
caller with the whole program in hand can do better."*

**But a whole-program pass would not reach `serialize` either**, and this is the
point worth keeping. Its two `try`s split: `try orderedTopLevelPairs(for: config)`
is internal and resolvable, `try Yams.serialize(node: node)` is **third-party**.
`collectTopLevelKeyValues` splits the same way — `try disabledRulesNode` and
`try ruleNode` internal, `try Node(included)` Yams again. A whole-*project* view
does not cover a dependency, so the doubt stands on exactly the calls that decide
it. Clearing them would take curated trust in named external throwing callees —
which is the mechanism the leaf's note argues against, and the one that let the
subprocess spawner through.

**So `serialize` is out of reach, not one fix away.** Three passes have now each
named "the remaining blocker" and been wrong: `throws` (Finding A), the
self-method-call gate (this one), and now a propagated `try` into a dependency.
The pattern is no longer a surprise, it is the finding — *a refuter that fires
first hides every refuter behind it*, and the only way to learn how many are
queued is to remove one and re-run. Each removal was still worth it on its own
terms (3 seeds, then 4); none was worth it for the reason predicted.

### Sizing — the whole-project `try` resolver, measured and declined

Finding D leaves one option open: the leaf refuses a propagated `try` for want of a
cross-file view, and names `EffectSymbolTable` as where "a caller with the whole
program in hand can do better". That caller would be the linter. Before building
it, it was **sized** — the same discipline the previous three findings had to
learn the hard way.

**Method.** For every refuted function, strip the `try` keywords and re-run the
verdict: if it flips to `.pureButPartial`, the `try` gate was the *only* refuter.
Then classify each `try` callee as project-internal or external, and finally apply
the requirement a real resolver carries — every callee must itself be clean,
resolved to a fixpoint. That last step is what separates *resolvable by name* from
*would actually flip*.

| Codebase | functions | refuted | only by the `try` gate | callees all internal | **would flip** |
|---|---|---|---|---|---|
| `SwiftLintRuleStudioCore` (subject) | 482 | 231 | 43 | 11 | **1** |
| `SwiftProjectLint` (the linter) | 1459 | 41 | 0 | 0 | **0** |
| `SwiftInferProperties` | 2141 | 252 | 124 | 85 | **34** |

**It collapses in the middle columns.** Of the subject's 43 try-gated functions,
32 have at least one *external* `try` callee; requiring the rest to be recursively
clean takes 11 down to **one function, `execute`**. The linter yields zero — its
refuted functions are refuted by markers, not propagation.

The external callees are the same names in every column, and they are the reason:
`Node` (Yams) ×7, `database.prepare` ×6, `database.execute` ×3, `container.encode`
×4, `String(contentsOf…)` ×3, `content.write` ×3, `fileManager.removeItem` ×2. On
`SwiftInferProperties` `container.encode` ×35 dominates — `Codable` conformances,
which are not law-bearing kernels anyway. **Propagated `try` in real Swift
overwhelmingly terminates in a dependency or in I/O**, which is the observation the
leaf's gate was built on in the first place.

**Cost, for contrast.** (1) A leaf API change: `verdict(for:)` refutes on `try`
before a caller can intervene, so the linter cannot ask *"was `try` the only
refuter?"* — that needs an additive `SwiftEffectInference` change exposing the
refutation reason, plus pin bumps in both consumers. (2) Real type-qualified callee
resolution; bare-name matching is far too loose for production, where `serialize`
alone collides across types. (3) The failure mode is the one the gate exists to
prevent — get resolution wrong and `process.run` / `database.execute` /
`fileManager.removeItem` walk back in, the subprocess-spawner mistake Finding A
already recorded once.

**Declined.** One seed on the subject that motivated the question, zero on the
linter, and the 34 elsewhere are `encode`/`parse` internals. That is a poor return
for a leaf release plus a resolver whose bugs are unsound in the direction this
project treats as forbidden.

*Caveats, in both directions:* the flip count is optimistic because name-based
resolution over-resolves, and pessimistic because the probe drops any function
containing `try!` and strips `try` textually. Treat 1 / 0 / 34 as the right order
of magnitude, not exact figures.

### Linter side, same two days

489 → 491 issues on `SwiftLintRuleStudioCore`. The entire delta is two hits of
the new *SwiftProjectLint Suppression* rule, reporting the two suppression
comments the app added on 07-23. The new duplication family — Parallel List
Drift, Duplicate Enum Mapping, Parallel Enum Shape, Duplicate Struct Shape —
fires **zero** times on this package.

## Net

- **Runs:** 4 passes — `discover` unseeded + seeded (fully categorised), a 07-24
  re-measurement against the 07-22 binaries, then a fourth against
  `swiftprojectlint 23c0133` / `swift-infer 1ea657c` driven by the app owner
  closing candidate §3. The `throws` producer fix reproduces its predicted
  yield exactly: the seed manifest measured **90** (67 pure-function + 23
  extractable-kernel) at subject `3d58747`, with `decodeRuleText`, `collectRows`,
  and `resolveFileURL` the three admitted, and `serialize` still absent. (At
  subject `9801dff` with the Finding D linter it measures **95**; see the pinning
  note there.)
- **Confirmed:** the low yield is structural, not access — every miss traces to a
  missing template, a determinism gate on `throws`, or an underivable generator,
  none to a permissions/scan problem.
- **Fixes landed:** subset/filter template (`748dd81`), throwing-function
  determinism (`9e1e066`), generator derivation (`3bf23e0` + `SwiftPropertyLaws
  v3.17.0`), selection-subset (`288fdc4`), diff-disjointness (`f723744`), and
  refutability-decides-visibility (`52a16d7`). "not derived" fell 20 → **5**, and a
  **default** `discover` now surfaces `filterViolations`/`layerChain`/`generateDiff`.
  See [Fixes shipped](#fixes-shipped-reconciled-2026-07-22).
- **The loop closed on three kernels.** `filterViolations`, `layerChain`, and now
  `generateDiff` went proposal → hand-written suite → passing (`swift test
  --filter PropertyLaw`: **16 tests, 5 suites**, green — was 13 in 4). That, not
  the suggestion count, is the result. In each case the app wrote a law *stronger*
  than the proposal: the tool named disjointness, the suite states the set algebra.
- **`#10`'s `Node` row does not survive contact with the real subject.** The
  registration was made for real and measured three ways; `discover` is
  bit-identical with it present, absent, or passed explicitly, because neither
  `YAMLConfig` nor `ConfigDiff` is ever scaffolded in the first place. It was
  verified on a `YAMLConfig`-*shaped* probe, and a probe is not the subject. See
  [Finding C](#finding-c--the-registered-generator-hook-does-not-reach-the-real-yamlconfig).
- **Two closures re-opened 07-24**, both found by running the pipeline end to end
  instead of checking each fix alone. The `throws` seam — the linter and
  `swift-infer` disagreeing about a property the shared oracle is supposed to make
  them agree on — is **now fixed**, worth 3 seeds. The owed-law warning still
  fires on the same five subjects against the linter's own manifest — re-checked
  at 90 and again at 95 seeds, not just the 87-seed manifest it was first measured
  on, and all eight of the seeds added since are disjoint from the five. So it is
  a **kind-granularity** gap, not the under-seeding gap root cause 5 alleged. See
  [Re-measured 2026-07-24](#re-measured-2026-07-24--two-closures-that-do-not-survive-the-real-pipeline).
- **The `throws` fix refuted its own premise**, which is the most useful thing
  this pass produced. `serialize` is still not seeded — its throwing is propagated,
  and independently it calls methods on `self` that cannot be resolved. `throws`
  was a refuter that fired *first* and hid the ones behind it; only running the
  fixed tool showed that removing it was not sufficient. Reading the code had said
  otherwise, twice.
- **The self-method-call gate is closed** (`swiftprojectlint` `69c6ee0`,
  `feeea0f`) — a project-wide, fixpoint-resolved catalog of sibling methods that
  are functions of their inputs, plus two implicit bindings (`$0`, the untyped
  `catch`) that were refuting alongside it. Manifest **91 → 95** at subject
  `9801dff` (linter `23c0133` → `feeea0f`), nothing removed.
  **It did not reach `serialize`**, which is refuted a third time by a propagated
  `try` — and a `try` into **Yams**, so no whole-program pass reaches it either.
  Three passes have now each named "the remaining blocker" and been wrong; that
  repetition is the finding. See
  [Finding D](#finding-d--the-self-method-call-gate-is-closed-and-serialize-is-still-out-of-reach).
  The one option it left open — a whole-project `try` resolver — was **sized and
  declined**: it would clear **one** function on this subject and zero on the
  linter, because propagated `try` almost always terminates in a dependency or in
  I/O. See
  [Sizing](#sizing--the-whole-project-try-resolver-measured-and-declined).
- **Still open:** `parseParameters`' metamorphic laws (out-of-catalog, → the app's
  hand-written suite); the app-side `parse(String) -> YAMLConfig` extraction that
  would unlock the `serialize ↔ parse` round-trip; and `serialize` itself, which
  is now understood as **out of reach** rather than one fix away — clearing it
  would take curated trust in named third-party throwing callees, the mechanism
  the leaf's soundness note argues against.
- **#10 closed one** of the two smaller items: the `CustomRuleConflict` round-trip
  noise (`FunctionPairing` label-stem admission gate). Its second item — the
  external-`Node` generator boundary (`Vocabulary.registeredGenerators` hook) —
  is **not** closed: the hook works on a `YAMLConfig`-shaped probe and does
  nothing on the real one, per the bullet above and Finding C.
