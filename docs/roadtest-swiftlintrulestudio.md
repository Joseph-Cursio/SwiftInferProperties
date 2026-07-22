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
lack of a derivable generator. No fixes landed yet — this is the write-up that
precedes them.

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

## Prioritised toolchain fixes (for the follow-up, not done here)

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

## Net

- **Runs:** 2 (`discover` unseeded + seeded), fully categorised.
- **Confirmed:** the low yield is structural, not access — every miss traces to a
  missing template, the `throws` veto, or an underivable generator, none to a
  permissions/scan problem.
- **Fixes landed:** 0 (deliberate — this is the pre-fix write-up).
- **Next:** fix (1) then (2), test-first against the kit suite, then re-run this
  road-test's two commands and diff the disposition table.
