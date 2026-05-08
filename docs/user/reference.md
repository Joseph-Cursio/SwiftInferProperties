# Reference

Lookup-style documentation for the SwiftInferProperties tool. Every CLI flag, every template, every file schema. For task-oriented walkthroughs, see the [user guide](guide.md). For the design rationale behind any particular threshold or weight, follow the PRD §-references in the relevant section.

> **Tracks v1.4.** All flag tables and schemas reflect the v1.4 surface unless explicitly marked.

## Contents

- [Command-line interface](#command-line-interface)
  - [`discover`](#discover)
  - [`drift`](#drift)
  - [`convert-counterexample`](#convert-counterexample)
  - [`metrics`](#metrics)
  - [Exit codes](#exit-codes)
- [Templates](#templates)
- [TestLifter detectors](#testlifter-detectors)
- [Inferred preconditions](#inferred-preconditions)
- [Inferred domains](#inferred-domains)
- [Equivalence-class hints](#equivalence-class-hints)
- [Signals and scoring](#signals-and-scoring)
- [Tier definitions](#tier-definitions)
- [Vetoes](#vetoes)
- [RefactorBridge protocol clusters](#refactorbridge-protocol-clusters)
- [File schemas](#file-schemas)
  - [`decisions.json`](#decisionsjson)
  - [`baseline.json`](#baselinejson)
  - [`vocabulary.json`](#vocabularyjson)
  - [`config.toml`](#configtoml)
- [Generated output layout](#generated-output-layout)
- [Skip annotation syntax](#skip-annotation-syntax)
- [Suggestion identity hashes](#suggestion-identity-hashes)
- [Discover output format](#discover-output-format)

---

## Command-line interface

`swift-infer` exposes four subcommands: `discover` (default), `drift`, `convert-counterexample`, `metrics`. Run any subcommand with `--help` to see locally rendered usage.

### `discover`

Scan a target for inferred property candidates. Read-only by default; `--interactive` and `--update-baseline` are the only flags that write to disk.

| Flag | Type | Default | Description |
|---|---|---|---|
| `--target <name>` | String | *required* | SwiftPM target name. Resolved to `Sources/<target>/` relative to the working directory. |
| `--include-possible` / `--no-include-possible` | Bool | `false` | Show Possible-tier suggestions (score 20–39). Hidden by default per PRD §4.2. |
| `--vocabulary <path>` | Path | walk-up | Vocabulary file. When omitted, falls back to `[discover].vocabularyPath` in `config.toml`, then to `<package-root>/.swiftinfer/vocabulary.json`. |
| `--config <path>` | Path | walk-up | Config file. When omitted, walks up from `--target` directory to `<package-root>/.swiftinfer/config.toml`. |
| `--test-dir <path>` | Path | `<package-root>/Tests/` | Directory the TestLifter pass scans. Missing path warns on stderr and falls back to walk-up resolver. |
| `--stats-only` | Bool | `false` | Render per-template / per-tier counts instead of full explainability blocks. |
| `--interactive` | Bool | `false` | Walk surviving suggestions one at a time with Accept / Skip / Reject / B / B' prompts. Mutually exclusive with `--update-baseline`. |
| `--update-baseline` | Bool | `false` | Snapshot visible suggestion identities to `<package-root>/.swiftinfer/baseline.json` for `swift-infer drift`. |
| `--dry-run` | Bool | `false` | With `--interactive`, suppress writes (file stub + `decisions.json` update) but still print would-be paths. No-op without `--interactive`. |

**Walk-up resolution.** The `--vocabulary`, `--config`, and `--test-dir` defaults all walk up from `Sources/<target>/` until they find `Package.swift`, then look for the conventional location relative to the package root.

**Precedence** (most → least specific): CLI flag > `config.toml` > built-in default.

**Output.** `discover` writes to stdout (the rendered suggestion stream) and stderr (warnings: vocabulary load failures, config parse warnings, missing test directory, etc.). Stdout is byte-stable as a function of (target sources, vocabulary, config) per PRD §16 #6.

### `drift`

Diff current discovery output against `<package-root>/.swiftinfer/baseline.json`; emit non-fatal warnings for new Strong-tier suggestions that lack a recorded decision.

| Flag | Type | Default | Description |
|---|---|---|---|
| `--target <name>` | String | *required* | Same shape as `discover`. |
| `--baseline <path>` | Path | walk-up | Explicit baseline file. Default: `<package-root>/.swiftinfer/baseline.json`. |
| `--vocabulary <path>` | Path | walk-up | Same shape as `discover`. |
| `--config <path>` | Path | walk-up | Same shape as `discover`. |

**Detection rule.** A suggestion triggers a drift warning iff:

1. Its identity hash is **not** in `baseline.json`.
2. Its identity hash is **not** in `decisions.json`.
3. It is **Strong** tier (score ≥ 75).

Likely / Possible / Advisory tiers never trigger drift, even when new.

**Output.** Warnings to stderr (one line each, prefixed `warning: drift:`). Summary to stdout (`N drift warnings emitted.` or `No drift detected.`). Always exits 0 — drift never fails the build (PRD §3 non-goal). To fail CI on drift, grep stderr for `warning: drift:` and exit non-zero from your CI script.

### `convert-counterexample`

Pin a counterexample input as a regression test. Useful when a generated property test fails and you want the failing input committed as a permanent test case before fixing the underlying bug.

| Flag | Type | Required for | Description |
|---|---|---|---|
| `--template <name>` | String | all | Template name. See valid values below. |
| `--callee <name>` | String | all | Function being tested. |
| `--type <name>` | String | all | Type of the counterexample value. |
| `--counterexample <source>` | String | all | Swift expression source for the failing input. Quoted as a single argument. |
| `--reverse-callee <name>` | String | round-trip, inverse-pair | Inverse function. |
| `--identity-element <source>` | String | identity-element | Swift expression for the identity value. |
| `--seed-source <source>` | String | reduce-equivalence | Swift expression for the reducer's seed value. |
| `--reduce-element-type <name>` | String | reduce-equivalence, count-invariance | Element type of the collection being reduced. |
| `--invariant-keypath <keypath>` | String | invariant-preservation | KeyPath expression naming the preserved invariant. |
| `--package-root <path>` | Path | optional | Override the default walk-up to find `Package.swift`. |

**Valid `--template` values:** `idempotence`, `round-trip`, `monotonicity`, `invariant-preservation`, `commutativity`, `associativity`, `identity-element`, `inverse-pair`, `count-invariance`, `reduce-equivalence`.

**Output.** Writes a self-contained `@Test` function to `<package-root>/Tests/Generated/SwiftInfer/<template>/<callee>_regression_<hash>.swift` where `<hash>` is the first 8 hex characters of `SHA256(--counterexample)`. Prints the path to stdout. The emitted test runs `trials: 1` against the pinned input with the seed derived from the hash, so re-runs are byte-stable.

Re-running the command with the same `--counterexample` value is idempotent — the file path is a function of the input hash. Different counterexamples for the same callee produce different files.

### `metrics`

Aggregate one or more `decisions.json` files into per-template acceptance / rejection / suppression rates plus a tier-mix breakdown. Closes PRD §17.2's deferred surface (v1.4).

| Flag | Type | Default | Description |
|---|---|---|---|
| `--directory <path>` | Path | CWD | Override the package-root for default-mode walk-up. Ignored when `--decisions` is passed. |
| `--decisions <path>` | Path (repeatable) | none | Explicit decisions.json file. Repeat for multi-corpus aggregation. |

**Default mode** (no `--decisions`): walk up from `--directory` (or CWD) to find `Package.swift`, then read `<package-root>/.swiftinfer/decisions.json`.

**Aggregation mode** (one or more `--decisions`): read each file, merge via `Decisions.merge(_:)` (most-recent timestamp wins per identity hash), render a single combined table.

**Output.** Combined report to stdout. Warnings (missing files, schema mismatches) to stderr. The tabular layout is fixed and documented in [discover output format](#discover-output-format) below.

**Scope limits (v1.4).** Three of PRD §17.2's five metrics ship; two are deferred to v1.5+:
- Time-to-adoption (requires `surfacedAt: Date` field on `DecisionRecord`)
- Post-acceptance failure rate (requires `firstCommitPasses: Bool?` field + CI hook)

JSON output mode and per-corpus breakdowns are also deferred (table-only, single combined view in v1.4).

### Exit codes

| Subcommand | 0 (success) | non-zero |
|---|---|---|
| `discover` | always (validation errors throw with ArgumentParser exit) | bad `--target`, missing `Sources/<target>/`, malformed flags |
| `drift` | always (drift never fails) | bad `--target`, missing `Sources/<target>/`, malformed flags |
| `convert-counterexample` | success | invalid `--template`, missing required flags for the template, package root not found |
| `metrics` | success | missing decisions file (when `--decisions` is explicit), malformed JSON beyond what the loader can recover from |

The non-fatal posture for `discover` + `drift` is deliberate (PRD §3 non-goal: "never fails the build"). To gate CI on suggestions, parse stderr.

Malformed `vocabulary.json` and `config.toml` produce stderr warnings but do not throw — the loader falls back to defaults and continues.

---

## Templates

Each template fires under specific shape conditions and contributes signals to a score. Score ≥ 75 → Strong; 40–74 → Likely; 20–39 → Possible (hidden by default); < 20 or any veto → Suppressed.

| Template | Property | Trigger shape |
|---|---|---|
| `idempotence` | `f(f(x)) == f(x)` | Single-param `(T) -> T`; curated verb (normalize, canonicalize, trim, flatten, sort, deduplicate, sanitize, format) or vocabulary match |
| `round-trip` | `g(f(x)) == x` | Function pair `(T) -> U` + `(U) -> T`; curated inverse pair or vocabulary match |
| `inverse-pair` | `g(f(x)) == x` | Same shape as round-trip; curated inverse-element verbs (mirror, antipodal) — distinct from codec naming |
| `commutativity` | `f(a, b) == f(b, a)` | `(T, T) -> T`; curated verb (add, combine, merge, union, intersect) |
| `associativity` | `f(f(a, b), c) == f(a, f(b, c))` | `(T, T) -> T`; reuses commutativity verb list; +20 when corpus uses the function as a reducer |
| `identity-element` | `f(x, e) == x` for some `e` | `(T, T) -> T` plus a constant named `empty`, `zero`, `identity`, `none`, `default` |
| `monotonicity` | `a <= b ==> f(a) <= f(b)` | Single-param `(T) -> U` where `U` is Comparable (`Int`, `Double`, `Float`, `String`, `Date`, `Duration`); curated verbs (length, count, size, priority, score, depth, height, weight) or `Count`/`Size` suffix |
| `invariant-preservation` | `inv(f(x)) == inv(x)` | `@CheckProperty(.preservesInvariant(\.path))` annotation (+80, the only signal — annotation-driven only) |
| `count-invariance` | `f(xs).count == xs.count` | TestLifter-only — fires from `assert(f(x).count == x.count)` test bodies |
| `reduce-equivalence` | `xs.reduce(seed, op) == xs.alternativeReduce(seed, op)` | TestLifter-only — fires from `assert(xs.reduce(...) == xs.reversed().reduce(...))` shapes |

**Per-template scoring breakdown:**

```
idempotence:           +30 typeSymmetrySignature
                       +40 exactNameMatch (curated or vocabulary)
                       +20 selfComposition (body uses self-composition)
                          veto: nonDeterministicBody

round-trip:            +30 typeSymmetrySignature
                       +40 exactNameMatch (curated or vocabulary)
                       +35 discoverableAnnotation (both halves share @Discoverable group)
                          veto: nonDeterministicBody

commutativity:         +30 typeSymmetrySignature
                       +40 exactNameMatch
                       -30 antiCommutativityNaming (subtract, divide, prepend, append, etc.)
                       -10 floatingPointStorage (Float / Double / CGFloat parameter)
                          veto: nonDeterministicBody

associativity:         +30 typeSymmetrySignature
                       +40 exactNameMatch
                       +20 reduceFoldUsage (corpus-wide reducer detection)
                       -10 floatingPointStorage
                          veto: nonDeterministicBody

identity-element:      +30 typeSymmetrySignature
                       +40 exactNameMatch (identity constant naming)
                       +20 reduceFoldUsage
                          veto: nonDeterministicBody

inverse-pair:          +25 typeSymmetrySignature (lower than round-trip)
                       +10 exactNameMatch (lower; ships at Possible tier)
                       -10 floatingPointStorage
                          veto: nonDeterministicBody

monotonicity:          +25 orderedCodomainSignature
                       +10 exactNameMatch
                          veto: nonDeterministicBody

invariant-preservation:+80 discoverableAnnotation (@CheckProperty)
                          veto: nonDeterministicBody
```

Cross-validation from TestLifter adds **+20** to any template whose `(templateName, callee)` matches a TestLifter detector hit (PRD §4.1).

**Advisory templates** — surfaced at `Tier.advisory` (no score; comment-only writeouts):

| Template | Trigger | Writeout |
|---|---|---|
| `equivalence-class` | TestLifter sees a binary or N-class predicate partition (Valid/Invalid markers, MarkerSet enums) with both buckets ≥ 3 sites | `Tests/Generated/SwiftInfer/equivalence-class/EquivalenceClasses_<predicate>[_<markerSetName>].swift` |
| `consumer-producer-chain` | TestLifter sees a function whose argument is reliably the output of another function, with the chain not forming a round-trip | `Tests/Generated/SwiftInfer/consumer-producer-chain/<consumer>_<producer>.swift` |

---

## TestLifter detectors

The TestLifter pass scans the test target for assertion shapes that imply a property the TemplateEngine also surfaced — agreement adds a `+20` cross-validation signal. Detectors that have no TemplateEngine counterpart (equivalence-class, consumer-producer-chain) emit advisory-only suggestions.

| Detector | Shape | Emits | Weight |
|---|---|---|---|
| `AssertAfterTransformDetector` (M1) | `assert(g(f(x)) == x)` | `round-trip` cross-validation | +20 |
| `AssertAfterDoubleApplyDetector` (M2) | `assert(f(f(x)) == f(x))` | `idempotence` cross-validation | +20 |
| `AssertSymmetryDetector` (M3) | `assert(f(a, b) == f(b, a))` | `commutativity` cross-validation | +20 |
| `AssertOrderingPreservedDetector` (M5) | `assert(a < b && f(a) <= f(b))` | `monotonicity` cross-validation | +20 |
| `AssertCountChangeDetector` (M5) | `assert(f(x).count == x.count)` | `count-invariance` (invariant-preservation cluster) | +20 |
| `AssertReduceEquivalenceDetector` (M5) | `assert(xs.reduce(...) == xs.reversed().reduce(...))` | `associativity` (via reduce-equivalence) | +20 |
| `PredicateEquivalenceClassDetector` (M11) | Binary partition (`Valid`/`Invalid` markers) with both buckets ≥ 3 sites | `equivalence-class` advisory | n/a (advisory) |
| `NClassEquivalenceClassDetector` (M13.2) | N-way partition over a `MarkerSet` (≥ 3 markers, each ≥ 3 sites) | `equivalence-class` advisory | n/a (advisory) |
| `ConsumerProducerChainDetector` (M16) | `f(g(x))` chain across ≥ 3 sites; producer is generatable, no inverse named | `consumer-producer-chain` advisory | n/a (advisory) |

**Counter-signals (M7):** `-25` to a TestLifter cross-validation suggestion when the body uses asymmetric assertions (`XCTAssertGreaterThan`, etc. — the test exercises a *non-symmetric* property of the same function).

**Skip honoring (M6.1+):** TestLifter respects the same `// swiftinfer: skip <hash>` annotations the TemplateEngine does — see [skip annotation syntax](#skip-annotation-syntax).

---

## Inferred preconditions

When TestLifter sees ≥ 3 test sites passing the same callee with concrete literal values, it infers a precondition pattern and surfaces it as an advisory comment in the generated property test (PRD §7.8 first example, M9 + M15).

| Pattern | Trigger condition | Suggested generator |
|---|---|---|
| `.positiveInt` | All observed `Int` literals > 0 | `Gen.int(in: 1...)` |
| `.nonNegativeInt` | All observed `Int` literals ≥ 0 | `Gen.int(in: 0...)` |
| `.negativeInt` | All observed `Int` literals < 0 | `Gen.int(in: ...(-1))` |
| `.intRange(low, high)` | Int literals ∈ `[low, high]`; ≥ 2 distinct | `Gen.int(in: low...high)` |
| `.nonEmptyString` | All observed `String` literals non-empty | (advisory comment; no generator) |
| `.stringLength(low, high)` | String lengths ∈ `[low, high]`; ≥ 2 distinct | `Gen.string(of: low...high)` |
| `.constantBool(value)` | All observed `Bool` literals == `value` | (advisory comment; opposite case untested) |
| `.positiveDouble` | All observed `Double` literals > 0 (finite) | `Gen.double(in: 0.0.nextUp...)` |
| `.nonNegativeDouble` | All observed `Double` literals ≥ 0 (finite) | `Gen.double(in: 0.0...)` |
| `.negativeDouble` | All observed `Double` literals < 0 (finite) | `Gen.double(in: ...0.0.nextDown)` |
| `.doubleRange(low, high)` | `Double` literals ∈ `[low, high]`; ≥ 2 distinct (finite) | `Gen.double(in: low...high)` |

**Threshold:** Minimum 3 distinct test sites observing the same callee + parameter (`PreconditionInferrer.minimumSiteCount`).

**Priority (M9 OD #4):** Range patterns (`intRange`, `stringLength`, `doubleRange`) preempt sign-bound patterns when ≥ 2 distinct values are observed. So 5 sites with values `{2, 4, 6, 8, 10}` produce `.intRange(2, 10)` rather than `.positiveInt`.

**Hex / scientific / underscore handling:** `0x...` literals are explicitly rejected by the integer detector (M9) and the double detector (M15) — the textual proxy is intentionally narrow to avoid surface-area bugs. Underscore-separated literals are tolerated. Non-finite doubles (`.nan`, `.infinity`) are killed by an `!isFinite` defensive check.

The advisory surfaces in the generated property test as a comment block above the generator:

```swift
// Inferred precondition: ratio — all observed values are in [1.5, 5.5]
// Generator: Gen.double(in: 1.5...5.5)
```

---

## Inferred domains

When the TestLifter pass sees a function whose argument is reliably the output of another function, it surfaces a `DomainHint` that overrides the generator with the producer's output (PRD §7.8 second example).

**`HintOrigin`:**

| Origin | Source | Generator override |
|---|---|---|
| `.roundTripPair` (M10) | `(forward, reverse)` pair where the reverse-side test corpus uniformly receives forward-side output | `Gen<T>.map(forward)` (when not vetoed) |
| `.consumerProducerChain` (M16) | General `f(g(x))` chain across ≥ 3 sites | comment-only advisory (no generator override; see consumer-producer-chain template above) |

**Threshold:** ≥ 3 sites (mirrors M4.3 + M9).

**`ProducerVetoReason` enum:**

| Veto | Trigger | Effect |
|---|---|---|
| `.producerThrows` | Producer is `throws` (or `try`/`try?`/`try!` is in the chain) | Comment-only fallback; no `Gen<T>.map(producer)` |
| `.producerAsync` | Producer is `async` (or `await` is in the chain) | Comment-only fallback |
| `.producerMultiArg` | Producer takes > 1 argument | Comment-only fallback |
| `.producerArgNotGeneratable` | Producer's argument type is not auto-generatable (`DerivationStrategist` returns `.todo` or `.userGen`) | Comment-only fallback |

When vetoed, the hint renders as a comment that names the veto reason rather than emitting a wrong generator.

**Type-alignment (M16):** Consumer-producer chain detection requires the producer's return type and the consumer's parameter type to match by **textual** type name (not the SemanticIndex — that's deferred to v1.5+). Aliases and `where`-clause constraints can produce false negatives here; this is a conservative-bias tradeoff per PRD §3.5.

---

## Equivalence-class hints

Two flavors, both advisory-tier, both writing comment-only files.

**`EquivalenceClassHint` (M11, two-class):**

| Field | Type | Notes |
|---|---|---|
| `predicateName` | `String` | Function name being partitioned |
| `argTypeName` | `String` | Type `T` over which generators are constructed |
| `positiveMarker` | `String` | Positive-bucket marker name (e.g. `"Valid"`) |
| `negativeMarker` | `String` | Negative-bucket marker name (e.g. `"Invalid"`) |
| `positiveSiteCount` | `Int` | ≥ 3 |
| `negativeSiteCount` | `Int` | ≥ 3 |
| `predicateVeto` | `PredicateVetoReason?` | Veto when predicate `throws`, `async`, multi-arg, or arg not generatable |
| `suggestedPositiveGenerator` | `String` | `Gen<T>.filter(predicate)` or comment text |
| `suggestedNegativeGenerator` | `String` | `Gen<T>.filter { !predicate($0) }` or comment text |
| `coversDomain` | `Bool` | Syntactic domain coverage (M13.3): true when both `XCTAssertTrue` and `XCTAssertFalse` cases exist with no `!` negation |

**`NClassEquivalenceClassHint` (M13, N-class):**

| Field | Type | Notes |
|---|---|---|
| `predicateName` | `String` | Function name |
| `argTypeName` | `String` | Argument type |
| `returnTypeName` | `String` | Predicate return type (typically an enum) |
| `markerSetName` | `String` | `MarkerSet` name (used as a file-naming suffix) |
| `markers` | `[String]` | Ordered marker names that reached the ≥ 3 threshold |
| `siteCountsByMarker` | `[String: Int]` | Per-marker site counts, each ≥ 3 |
| `predicateVeto` | `PredicateVetoReason?` | Same veto reasons as `EquivalenceClassHint` |
| `suggestedGeneratorsByMarker` | `[String: String]` | Per-bucket generator expressions |
| `coversDomain` | `Bool` | Enum-case exhaustiveness (M14): true when every `enumCaseNames` entry on the same target is matched by a marker |

**`PredicateVetoReason` enum:**

| Veto | Trigger |
|---|---|
| `.predicateThrows` | Predicate is `throws` |
| `.predicateAsync` | Predicate is `async` |
| `.predicateMultiArg` | Predicate takes > 1 argument |
| `.predicateArgNotGeneratable` | `DerivationStrategist` cannot synthesize a generator for the argument |
| `.predicateReturnNotEquatable` | Predicate's return type is not `Equatable` (M13.2 textual proxy) |

**Marker pairs / sets** — defaults curated in `MarkerTable.curatedPairs` (M13.1):

```
MarkerPair: Valid/Invalid, Success/Failure, Accept/Reject,
            Pass/Fail, Allowed/Forbidden
MarkerSet:  (no curated defaults — supply via vocabulary.json)
```

Project-extensible via `vocabulary.json`'s `markerPairs` and `markerSets` keys — see [vocabulary.json schema](#vocabularyjson) below.

---

## Signals and scoring

Every suggestion's score is the sum of its signal weights. Signal weights are static defaults today (PRD §4.1); v1.4 calibration (PRD §17.3) adjusts them empirically based on `decisions.json` data.

**Positive signals:**

| Kind | Default weight | Used by |
|---|---|---|
| `.exactNameMatch` | +40 (round-trip, idempotence, commutativity, associativity, identity-element, inverse-element); +10 (inverse-pair, monotonicity) | Curated naming or vocabulary inverse-pair / verb match |
| `.typeSymmetrySignature` | +30 (most templates); +25 (inverse-pair) | Symmetric-type signature shape |
| `.orderedCodomainSignature` | +25 | Monotonicity (Comparable codomain) |
| `.discoverableAnnotation` | +35 (round-trip cross-pair group); +80 (invariant-preservation `@CheckProperty`) | `@Discoverable(group:)` or `@CheckProperty(.preservesInvariant(...))` |
| `.reduceFoldUsage` | +20 | Associativity (corpus uses function as a reducer); identity-element (accumulator-with-empty-seed) |
| `.selfComposition` | +20 | Idempotence (function calls itself in body) |
| `.crossValidation` | +20 | TestLifter detector match on `(template, callee)` |
| `.algebraicStructureCluster` | (defined; not active in M1 templates) | Reserved |
| `.testBodyPattern` | (defined; not active) | Reserved |
| `.samplingPass` | (defined; not active) | Reserved |

**Negative signals (dock weight, not veto):**

| Kind | Default weight | Used by |
|---|---|---|
| `.antiCommutativityNaming` | -30 | Commutativity, when name matches anti-verb (subtract, difference, divide, apply, prepend, append, concat, concatenate, concatenated) |
| `.floatingPointStorage` | -10 | Commutativity, associativity, inverse-pair, when the parameter type is `Float` / `Double` / `CGFloat` / `Float32` / `Float64` / `Float80` (FP arithmetic isn't truly associative; counter-signal per V1.4.3) |
| `.sideEffectPenalty` | (defined; not active) | Reserved |
| `.generatorQualityPenalty` | (defined; not active) | Reserved |
| `.asymmetricAssertion` | (defined; not active in scoring; -25 in TestLifter counter-signal) | Reserved on the score path |
| `.partialFunction` | (defined; not active) | Reserved |

**Veto signals (force `.suppressed`):**

| Kind | Trigger |
|---|---|
| `.nonDeterministicBody` | `FunctionSummary.bodySignals.hasNonDeterministicCall == true` (system clock, `Date()`, `random*`, network calls, etc.) — applied by all templates with body-signal access |
| `.nonEquatableOutput` | Defined; reserved for future use (return-type non-Equatable will short-circuit when SemanticIndex lands in v1.5+) |

Veto weight is `Int.min` per `Signal.vetoWeight`; any non-empty veto on a suggestion drops its tier to `.suppressed` regardless of positive contributions.

---

## Tier definitions

Score → Tier (`Sources/SwiftInferCore/Tier.swift`):

| Tier | Score range | Visible by default | Triggers drift | Triageable in `--interactive` |
|---|---|---|---|---|
| `.strong` | ≥ 75 | yes | yes | yes |
| `.likely` | 40 – 74 | yes | no | yes |
| `.possible` | 20 – 39 | no (set `--include-possible`) | no | yes (when visible) |
| `.suppressed` | < 20 OR any veto | no (never shown) | no | no |
| `.advisory` | n/a (set explicitly) | yes | no | yes (with comment-only writeout) |

**Tier labels** (rendered in the suggestion block):

| Tier enum case | Label string |
|---|---|
| `.strong` | `"Strong"` |
| `.likely` | `"Likely"` |
| `.possible` | `"Possible"` |
| `.suppressed` | `"Suppressed"` |
| `.advisory` | `"Advisory"` |

`.advisory` is set explicitly by templates that surface comment-only suggestions (M11+ equivalence-class, M16 consumer-producer-chain). It is never derived from a score.

---

## Vetoes

Vetoes are signals that force `Tier.suppressed` regardless of accumulated weight. The two veto kinds:

### `.nonDeterministicBody`

Fires when the function body calls a non-deterministic API. The detector is a textual heuristic (`FunctionSummary.bodySignals.nonDeterministicAPIsDetected`); recognized non-determinism sources include:

- `Date()`, `Date.now`, `Date.timeIntervalSinceReferenceDate`
- `Calendar`, `DateFormatter`, `ISO8601DateFormatter`
- `random()`, `random(in:)`, `randomElement()`
- `URLSession`, `URLRequest`, `URL.dataTask`, network shorthands
- `FileManager`, `FileHandle.standardInput`
- `getenv`, `ProcessInfo.processInfo.environment`
- Mutex / lock APIs that block on shared state

Applied by: idempotence, round-trip, commutativity, associativity, identity-element, inverse-pair, monotonicity, invariant-preservation.

When fired, the rendered explainability block surfaces the API name(s) so the developer can see *why* the suggestion was vetoed (and decide whether to refactor the function for testability).

### `.nonEquatableOutput`

Defined but not currently emitted. Reserved for the v1.5+ SemanticIndex integration that can definitively answer "is type `T` Equatable?" — the v1.4 textual proxy isn't reliable enough to ship as a veto. Until then, suggestions on non-Equatable types simply fail to compile when accepted; this is a known surface where v1.4's conservative bias errs.

---

## RefactorBridge protocol clusters

When discover detects multiple template suggestions on the same type that together imply protocol conformance, RefactorBridge promotes those suggestions to a `B` (or `B'`) arm in the interactive triage prompt. Accepting writes a conformance extension instead of (or alongside) a property-test stub.

**Promotion table** (`Sources/SwiftInferCLI/RefactorBridgeOrchestrator.swift`):

| Evidence on type T | Proposal | Witnesses (kit's required ops) |
|---|---|---|
| `associativity` | `Semigroup` | `combine` |
| `associativity` + `identity-element` | `Monoid` | `combine`, `identity` |
| `associativity` + `identity-element` + `commutativity` | `CommutativeMonoid` | `combine`, `identity` |
| `associativity` + `identity-element` + inverse-element | `Group` | `combine`, `identity`, `inverse` |
| `associativity` + `commutativity` + `idempotence` (± `identity-element`) | `Semilattice` | `combine`, `identity` |
| Semilattice + set-named op (`union`, `intersect`, `subtract`) | `SetAlgebra` (secondary) | set ops |
| Per-op: associativity + identity (additive AND multiplicative) | `Numeric` / `Ring` (secondary) | additive + multiplicative ops |
| Standard equality patterns | `Equatable` | `==` |
| Standard ordering patterns | `Comparable` | `<` |

**Writeout path:** `Tests/Generated/SwiftInferRefactors/<TypeName>/<ProtocolName>.swift` (PRD §16 #1).

**Primary vs. secondary arm.** The interactive prompt renders position 0 in the proposal list as `B` and position 1+ as `B'` (alias `c`). Order:

- Single proposal → `[A/B/s/n/?]`
- Two proposals (peer / incomparable arms, e.g. `Equatable` + `SetAlgebra`) → `[A/B/B'/s/n/?]`
- More than two → only the first two are exposed as arms; the rest re-surface on subsequent runs after one is accepted.

**One-conformance-per-type-per-run.** Once a `B` (or `B'`) is accepted for a type during a single `--interactive` walk, subsequent suggestions on that type collapse back to `[A/s/n/?]`. RefactorBridge intentionally does not let a single run write conflicting conformances (e.g. `B` Semigroup and `B'` Monoid on the same type).

**Kit-side gaps** (as of v1.4):

- `Ring`: Numeric is the canonical writeout target per PRD §5.4 row 5 — no separate Ring extension.
- `CommutativeGroup`: M8.4.b.1 emits separate proposals when both `Group` + `CommutativeMonoid` apply; no `CommutativeGroup` extension.
- `Group acting on T`: Function-space carrier doesn't fit the per-type protocol shape.

---

## File schemas

### `decisions.json`

Path: `<package-root>/.swiftinfer/decisions.json`. Committed; hand-editable.

```json
{
  "schemaVersion": 2,
  "records": [
    {
      "identityHash": "AB12CD34EF567890",
      "template": "round-trip",
      "scoreAtDecision": 90,
      "tier": "strong",
      "decision": "accepted",
      "timestamp": "2026-05-07T10:30:00Z",
      "signalWeights": [
        { "kind": "typeSymmetrySignature", "weight": 30 },
        { "kind": "exactNameMatch", "weight": 40 }
      ]
    }
  ]
}
```

| Field | Type | Notes |
|---|---|---|
| `schemaVersion` | Int | Current: `2`. v1 readers fail on records using `acceptedAsConformance`; loader warns when schemaVersion exceeds known max. |
| `records[].identityHash` | String | 16-char uppercase hex; no `0x` prefix on disk. Identity is canonical per PRD §7.5. |
| `records[].template` | String | Template name (e.g. `"round-trip"`). |
| `records[].scoreAtDecision` | Int | Score at the moment of triage. Frozen — does not update if scoring weights change later. |
| `records[].tier` | String | `"strong"` / `"likely"` / `"possible"` / `"suppressed"`. (`"advisory"` for advisory templates.) |
| `records[].decision` | String | `"accepted"` / `"acceptedAsConformance"` / `"rejected"` / `"skipped"`. |
| `records[].timestamp` | ISO 8601 String | UTC. |
| `records[].signalWeights[]` | Array | Each entry: `{ "kind": "<Signal.Kind>", "weight": <Int> }`. Captures the score breakdown at decision time so metrics can analyze signal-by-signal acceptance. |

**Merge semantics** (`Decisions.merge(_:)`): keyed by `identityHash`; on collision, the record with the larger `timestamp` wins. Output records are sorted by `(timestamp, identityHash)` for byte-stability. The merged `schemaVersion` takes the higher of the two inputs.

**Schema migration:**

- v1 → v2: `Decision.acceptedAsConformance` added in M7.5. v1 readers fail on v2 records with the new value.
- Beyond v2: loader warns on `schemaVersion > 2` but still reads recognized records with default-fallback for unknown fields.

### `baseline.json`

Path: `<package-root>/.swiftinfer/baseline.json`. Committed.

```json
{
  "schemaVersion": 1,
  "entries": [
    {
      "identityHash": "AB12CD34EF567890",
      "template": "round-trip",
      "scoreAtSnapshot": 75,
      "tier": "strong"
    }
  ]
}
```

| Field | Type | Notes |
|---|---|---|
| `schemaVersion` | Int | Current: `1`. No migrations yet. |
| `entries[].identityHash` | String | Same shape as `decisions.json`. |
| `entries[].template` | String | Template name. |
| `entries[].scoreAtSnapshot` | Int | Score at snapshot time. |
| `entries[].tier` | String | Tier at snapshot time. |

The baseline is the input to `swift-infer drift`. Re-run `swift-infer discover --target <name> --update-baseline` to rewrite it; mutually exclusive with `--interactive`.

### `vocabulary.json`

Path: `<package-root>/.swiftinfer/vocabulary.json`. Or via `--vocabulary <path>` / `[discover].vocabularyPath` in config. All keys optional; missing keys default to empty arrays.

```json
{
  "inversePairs": [
    ["pickle", "unpickle"],
    ["render", "load"]
  ],
  "idempotenceVerbs": ["sanitizeXML", "rewritePath"],
  "commutativityVerbs": ["unionGraphs"],
  "antiCommutativityVerbs": ["concatenateOrdered"],
  "monotonicityVerbs": ["depth"],
  "inverseElementVerbs": ["mirror", "antipodal"],
  "markerPairs": [
    ["Pass", "Fail"]
  ],
  "markerSets": [
    { "name": "tristate", "values": ["Allowed", "Denied", "Pending"] }
  ]
}
```

| Key | Type | Used by |
|---|---|---|
| `inversePairs` | `[[String, String]]` | round-trip + inverse-pair name signal (each pair is `[forward, reverse]`) |
| `idempotenceVerbs` | `[String]` | idempotence name signal |
| `commutativityVerbs` | `[String]` | commutativity + associativity name signal (positive) |
| `antiCommutativityVerbs` | `[String]` | commutativity name signal (negative; `-30`) |
| `monotonicityVerbs` | `[String]` | monotonicity name signal |
| `inverseElementVerbs` | `[String]` | inverse-pair name signal |
| `markerPairs` | `[[String, String]]` | M13 two-class equivalence-class detector |
| `markerSets` | `[{ "name": String, "values": [String] }]` | M13.2 N-class equivalence-class detector |

**Curated baselines.** The curated lists (e.g., the 11 inverse pairs in `RoundTripTemplate.curatedInversePairs`) take precedence over project vocabulary — repeating a curated entry is a no-op rather than a double-fire. Project vocabulary contributes the same weights as curated entries; only the rendered detail line differs (`Project-vocabulary inverse name pair: ...` vs. `Curated inverse name pair: ...`).

**Unknown keys** are silently ignored (forward compatibility).

### `config.toml`

Path: `<package-root>/.swiftinfer/config.toml`. Or via `--config <path>`. All keys optional.

```toml
[discover]
includePossible = true
vocabularyPath = "path/to/vocab.json"
```

| Section | Key | Type | Equivalent CLI flag |
|---|---|---|---|
| `[discover]` | `includePossible` | Bool | `--include-possible` / `--no-include-possible` |
| `[discover]` | `vocabularyPath` | String | `--vocabulary <path>` |

**Precedence.** CLI flag > config > built-in default. So `--no-include-possible` overrides `includePossible = true`.

**TOML subset supported:**

- Section headers (`[section]`)
- Bare-identifier keys (`[A-Za-z0-9_-]`)
- Booleans (`true` / `false`)
- Double-quoted strings with escapes (`\\`, `\"`, `\n`, `\t`)
- `#` line comments

**Not supported** (will produce stderr warnings):

- Numbers, dates, arrays, inline tables
- Dotted keys
- Multi-line strings, literal strings (single-quote)

Unknown sections and keys are silently ignored.

---

## Generated output layout

All generated files land under `<package-root>/Tests/Generated/`. The tool never edits an existing file — accepting a duplicate suggestion overwrites only files the tool itself wrote (PRD §16 #1).

```
<package-root>/
├── Tests/Generated/SwiftInfer/
│   ├── idempotence/                  ← --interactive Accept (A)
│   │   └── normalize.swift
│   ├── round-trip/
│   │   └── encode_decode.swift
│   ├── commutativity/
│   │   └── union.swift
│   ├── associativity/
│   │   └── combine.swift
│   ├── identity-element/
│   │   └── concat.swift
│   ├── inverse-pair/
│   │   └── mirror_unmirror.swift
│   ├── monotonicity/
│   │   └── length.swift
│   ├── invariant-preservation/
│   │   └── adjust.swift
│   ├── count-invariance/
│   │   └── reverse.swift
│   ├── reduce-equivalence/
│   │   └── sumLeftRight.swift
│   ├── equivalence-class/             ← M11 / M13 advisory
│   │   ├── EquivalenceClasses_isValidUsername.swift
│   │   └── EquivalenceClasses_classify_tristate.swift
│   └── consumer-producer-chain/       ← M16 advisory
│       └── validate_format.swift
└── Tests/Generated/SwiftInferRefactors/
    ├── Counter/
    │   ├── Semigroup.swift
    │   └── Monoid.swift
    └── BitSet/
        ├── Equatable.swift
        └── SetAlgebra.swift
```

**File naming:**

| Template | File name |
|---|---|
| Single-function templates (`idempotence`, `monotonicity`, `invariant-preservation`) | `<funcName>.swift` |
| Pair templates (`round-trip`, `inverse-pair`) | `<forwardName>_<reverseName>.swift` |
| Binary-op templates (`commutativity`, `associativity`, `identity-element`) | `<funcName>.swift` |
| Reduce templates (`count-invariance`, `reduce-equivalence`) | `<funcName>.swift` |
| Equivalence-class advisory (two-class) | `EquivalenceClasses_<predicate>.swift` |
| Equivalence-class advisory (N-class) | `EquivalenceClasses_<predicate>_<markerSetName>.swift` |
| Consumer-producer chain advisory | `<consumerName>_<producerName>.swift` |
| Counterexample regression (any template) | `<callee>_regression_<hash8>.swift` |
| RefactorBridge conformance | `<protocolName>.swift` (under `<TypeName>/` subdirectory) |

**Header comments.** Every emitted file has a leading comment block that names the template, the suggestion's identity, and (for advisory shapes) the inferred provenance:

```swift
// Auto-generated by swift-infer discover — do not edit by hand.
// Template: round-trip
// Identity: AB12CD34EF567890
// Inferred domain: corpus uses encode(_:) output as decode(_:) input across 7 sites.
```

Counterexample-regression files include the hash prefix and the literal counterexample source for traceability:

```swift
// Auto-generated by `swift-infer convert-counterexample` — do not edit.
// Counterexample for: round-trip / encode
// Counterexample source: Document(text: "")
// SHA256 prefix: a1b2c3d4
```

**Imports the generated files use:**

```swift
import Testing
import PropertyLawKit
```

Plus `@testable import <YourModule>` if the test exercises non-public functions. The generated files do not include this import — the developer adds it (the tool can't know whether the function under test is `public` or not without the SemanticIndex deferred to v1.5+).

---

## Skip annotation syntax

```
// swiftinfer: skip <hash>
```

| Token | Rules |
|---|---|
| `//` | Standard Swift line comment. |
| `swiftinfer` | Case-insensitive (`SwiftInfer`, `SWIFTINFER` all work). |
| `:` | Required separator. Whitespace tolerated either side. |
| `skip` | Case-insensitive. |
| `<hash>` | 16-char hex, optional `0x` / `0X` prefix. Normalized to uppercase. Anything after the hash on the same line is ignored — append a free-text comment if you like. |

**Where the scanner looks:** every `.swift` file under `Sources/` and `Tests/` (the test directory is also walked so test-only suppressions work). Skip annotations are scanned in deterministic sorted-path order so the output is reproducible across machines.

**What it suppresses:** the *one* suggestion whose identity hash matches. Other suggestions on the same function (e.g. an `idempotence` suggestion and a `monotonicity` suggestion on the same getter) require separate skip annotations.

**Stacking.** Multiple skip lines in the same file are all honored. There is no `// swiftinfer: skip-all` form — the tool's conservative bias avoids global suppressions.

**Skip annotation vs. `decisions.json` rejection:**

| Skip annotation | `decisions.json` rejection |
|---|---|
| Lives in source, next to the function. | Lives in the audit log. |
| Survives `decisions.json` deletion. | Lost if the file is deleted or schema-migrated. |
| Right tool when reason is *intrinsic to the code*. | Right tool when reason is *stylistic / triage-time*. |
| Not visible to `swift-infer metrics` (no signal-weight breakdown). | Visible to metrics — feeds the rejection-rate numerator. |

---

## Suggestion identity hashes

Identity is the canonical input that produces a suggestion's `identityHash`. Per PRD §7.5:

```
identity = <templateID> | <canonical-signature-A> | <canonical-signature-B> | ...
```

For pair templates (round-trip, inverse-pair), the two signatures are sorted lexicographically before concatenation, so the hash is orientation-agnostic — `(encode, decode)` and `(decode, encode)` produce the same identity.

The hash is the first 16 characters of `SHA-256(identity)` in uppercase hex. The display format used by the renderer's `Suppress:` line is the same 16-char form; the `0x` prefix is optional in skip annotations.

Identity is **stable across tool versions** — an upgrade that adjusts signal weights does not invalidate existing `decisions.json` entries. Identity changes only when the canonical signature of the underlying function changes (e.g., parameter rename, signature refactor); in that case the decision needs to be re-triaged because the property is, in a real sense, a different property.

---

## Discover output format

### Default rendering

```
<N> suggestions.

[Suggestion]
Template: <templateName>
Score:    <score> (<tierLabel>)

Why suggested:
  ✓ <signal description>
  ✓ <signal description>
  ...

Why this might be wrong:
  ⚠ <caveat>
  ⚠ <caveat>
  ...

Generator: <generator description>
Sampling:  <sampling description>
Identity:  <16-char hash>
Suppress:  // swiftinfer: skip <16-char hash>

[Suggestion]
...
```

- Count header: `"0 suggestions."` for empty; `"1 suggestion."` for singular; `"N suggestions."` for plural.
- Block separator: double newline (`\n\n`).
- "Why this might be wrong" is always present; with no caveats, prints `"  ✓ no known caveats for this template"`.
- Identity and Suppress lines align to the same column (4 spaces after the colon).

### Stats-only rendering (`--stats-only`)

```
<N> suggestions across <M> templates.
  associativity:        2 (1 Strong, 1 Likely)
  commutativity:        9 (3 Strong, 4 Likely, 2 Possible)
  idempotence:         12 (8 Strong, 3 Likely, 1 Possible)
  monotonicity:         4 (2 Strong, 2 Likely)
  round-trip:          10 (7 Strong, 3 Likely)
```

- Templates sorted alphabetically.
- Tiers in `Strong / Likely / Possible / Advisory` order; empty tiers omitted.
- `.suppressed` excluded entirely (suppressed suggestions never reach the renderer).

### Metrics rendering (`swift-infer metrics`)

```
swift-infer metrics — calibration aggregate (PRD §17.2)

Decisions: <total> across <N> source[s]
  1. <path-1>
  2. <path-2>

Per-template adoption:
  note: <template> has fewer than 20 decisions; rates are advisory only.
  | Template               | Total | Accepted | Rejected | Skipped | Acceptance | Rejection | Suppression |
  |------------------------|------:|---------:|---------:|--------:|-----------:|----------:|------------:|
  | round-trip             |    25 |       21 |        2 |       2 |       84.0% |       8.0% |        8.0% |

Tier-mix at decision time:
  | Tier       | Total | Accepted | Acceptance |
  |------------|------:|---------:|-----------:|
  | Strong     |    42 |       38 |       90.5% |
  | Likely     |     5 |        3 |       60.0% |
```

- `acceptedAsConformance` counts as `Accepted`.
- Templates with < 20 decisions print an advisory-only note; rates still render.
- Retirement candidates (≥ 20 decisions, < 50% acceptance) print at the bottom under a `Retirement candidates (PRD §17.2):` heading.

---

For the design rationale behind tier thresholds, signal weights, and the calibration loop, see PRD §3.5 (conservative bias), §4 (scoring), §5 (templates), §7 (TestLifter), §13 (performance budgets), §16 (hard guarantees), and §17 (calibration). The PRD is the source of truth for *why*; this reference is the source of truth for *what*.
