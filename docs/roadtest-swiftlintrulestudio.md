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
| Throwing functions earn a law | 2 (re-diagnosed) | ✅ `9e1e066` — see correction below |
| Generator derivation | 3 | ✅ discover-side composite fallback (`3bf23e0`) + upstream nested-`zip` >10 members (`SwiftPropertyLaws v3.17.0`; floor-bumped `830c344`) |
| Selection-ancestry template | 1 (`layerChain`) | ✅ `selection-subset` template (`288fdc4`) — `layerChain` owes `result ⊆ ConfigTree.configs` |
| Diff characterization template | 1 (`generateDiff`) | ✅ `diff-disjointness` template (`f723744`) — `generateDiff` owes `added ∩ removed = ∅` |
| Refutability decides visibility (the tier cut) | 4 | ✅ `52a16d7` — role-entailed refutable laws (incl. filter/selection/diff) surface on a default run, not just `--include-possible` |
| Report the linter gap | 5 | ✗ withdrawn — verified a phantom: `swiftprojectlint --format pbt-seeds` emits 85 seeds and *does* seed the pure predicates; the warning came from an incomplete hand-written manifest (see the correction under root cause 5) |

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
(domain-specific — belong in the app's hand-written suite, not a template); the
`serialize ↔ parse` round-trip (needs an app-side `parse(String) -> YAMLConfig`);
and — the honest boundary — `YAMLConfig`'s external Yams `Node` field, which no
auto-derivation can reach (`.todo` is the right answer there). *Withdrawn:* the
"linter seeding gap" (root cause 5) was a phantom — see the correction above.

## Net

- **Runs:** 2 (`discover` unseeded + seeded), fully categorised.
- **Confirmed:** the low yield is structural, not access — every miss traces to a
  missing template, a determinism gate on `throws`, or an underivable generator,
  none to a permissions/scan problem.
- **Fixes landed:** subset/filter template (`748dd81`), throwing-function
  determinism (`9e1e066`), generator derivation (`3bf23e0` + `SwiftPropertyLaws
  v3.17.0`), selection-subset (`288fdc4`), diff-disjointness (`f723744`), and
  refutability-decides-visibility (`52a16d7`). "not derived" fell 20 → 6, and a
  **default** `discover` now surfaces `filterViolations`/`layerChain`/`generateDiff`.
  Root cause 5 (linter gap) was verified a phantom and withdrawn. See
  [Fixes shipped](#fixes-shipped-reconciled-2026-07-22).
- **Still open:** `parseParameters`' metamorphic laws (out-of-catalog, → the app's
  hand-written suite) and the app-side `parse(String) -> YAMLConfig` extraction
  that would unlock the `serialize ↔ parse` round-trip.
