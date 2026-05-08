# User Guide

Task-oriented walkthroughs for each major workflow. If you've never used the tool before, work through the [tutorial](tutorial.md) first — this guide assumes you have a project set up and want to do something specific. For exhaustive flag and schema tables, see the [reference](reference.md).

> **Tracks v1.4.** The `swift-infer metrics` subcommand and the v1.4 calibration posture are documented here; everything else has worked since v1.3.

## Contents

- [Adding the tool to a project](#adding-the-tool-to-a-project)
- [Running discover](#running-discover)
- [Triaging interactively](#triaging-interactively)
- [Working with `.swiftinfer/decisions.json`](#working-with-swiftinferdecisionsjson)
- [Suppressing a suggestion with a skip annotation](#suppressing-a-suggestion-with-a-skip-annotation)
- [Extending the naming vocabulary](#extending-the-naming-vocabulary)
- [Configuring defaults with config.toml](#configuring-defaults-with-configtoml)
- [Pointing at a non-default test directory](#pointing-at-a-non-default-test-directory)
- [Running drift in CI](#running-drift-in-ci)
- [Replaying a failed property test](#replaying-a-failed-property-test)
- [Triaging RefactorBridge protocol-conformance proposals](#triaging-refactorbridge-protocol-conformance-proposals)
- [Reading advisory suggestions](#reading-advisory-suggestions)
- [Calibrating signal weights with the metrics command](#calibrating-signal-weights-with-the-metrics-command)
- [Reading the generated tests](#reading-the-generated-tests)
- [Templates at a glance](#templates-at-a-glance)

---

## Adding the tool to a project

In `Package.swift`:

```swift
.package(url: "https://github.com/Joseph-Cursio/SwiftInferProperties", from: "1.4.0"),
.package(url: "https://github.com/Joseph-Cursio/SwiftPropertyLaws", from: "2.0.0")
```

The first dependency gives you the `swift-infer` executable. The second gives the test target the `PropertyLawKit` runtime that generated property tests import. Wire `PropertyLawKit` into your `.testTarget(...)` dependencies — `swift-infer` itself does not need to appear there.

To run the executable as a one-off without committing the dep, you can also clone this repo and `swift run swift-infer ...` from there.

The four subcommands:

| Subcommand | Purpose |
|---|---|
| `discover` | Scan a target and surface ranked property suggestions. |
| `drift` | Compare current discovery output against a baseline; emit non-fatal warnings for new Strong-tier suggestions. |
| `convert-counterexample` | Pin a failed property-test counterexample as a regression test. |
| `metrics` | Aggregate `.swiftinfer/decisions.json` into per-template acceptance / rejection / suppression rates. |

`discover` is the default subcommand: `swift run swift-infer --target Foo` is shorthand for `swift run swift-infer discover --target Foo`.

## Running discover

The simplest invocation:

```sh
swift run swift-infer discover --target Foo
```

This walks `Sources/Foo/`, runs every template + detector, and prints the ranked suggestion list to stdout. No files are written.

By default the output includes **Strong** (≥75), **Likely** (40–74), and **Advisory** suggestions. **Possible** (20–39) suggestions are hidden — they exist but the tool's conservative-bias posture (PRD §3.5) keeps them off the default surface to avoid the "Daikon trap" of overwhelming the developer with low-confidence candidates.

To include Possible-tier:

```sh
swift run swift-infer discover --target Foo --include-possible
```

### Common flag combinations

For a CI dashboard tracking suggestion-count regressions over time, render only the per-template / per-tier counts:

```sh
swift run swift-infer discover --target Foo --stats-only
```

Output:

```
37 suggestions across 5 templates.
  associativity:       2 (1 Strong, 1 Likely)
  commutativity:       9 (3 Strong, 4 Likely, 2 Possible)
  idempotence:        12 (8 Strong, 3 Likely, 1 Possible)
  monotonicity:        4 (2 Strong, 2 Likely)
  round-trip:         10 (7 Strong, 3 Likely)
```

Templates sort alphabetically; empty tiers are omitted; suppressed suggestions are excluded entirely.

For a single full triage pass:

```sh
swift run swift-infer discover --target Foo --interactive
```

For triage that *previews* what would happen without writing anything:

```sh
swift run swift-infer discover --target Foo --interactive --dry-run
```

Accept (A) gestures still print the would-be file path on stdout but skip both the file write and the `.swiftinfer/decisions.json` update.

For an exhaustive list of flags including `--vocabulary`, `--config`, `--update-baseline`, see the [reference](reference.md#discover).

## Triaging interactively

Pass `--interactive` to walk surviving suggestions one at a time. For each, the tool renders the explainability block followed by a prompt:

```
[3/12] Accept (A) / Skip (s) / Reject (n) / Help (?)
```

The four primary gestures:

| Key | Action | Persisted |
|---|---|---|
| `a` | **Accept.** Writes a property-test stub to `Tests/Generated/SwiftInfer/<template>/<func>.swift` and records `.accepted` in `.swiftinfer/decisions.json`. | Yes |
| `s` (or Enter) | **Skip.** Re-surfaces on future runs. Records `.skipped` so metrics can track suppression rates. | Yes (advisory) |
| `n` | **Reject.** Hides the suggestion from future runs. | Yes |
| `?`, `h`, `help` | Show the full help block and re-prompt. | No |

When the suggestion belongs to a type that has accumulated enough algebraic evidence for a protocol conformance, two extra arms appear:

```
[3/12] Accept (A) / B (Equatable) / B' (SetAlgebra) / Skip (s) / Reject (n) / Help (?)
```

- `b` — accept the **primary** RefactorBridge conformance proposal. Writes `Tests/Generated/SwiftInferRefactors/<TypeName>/<ProtocolName>.swift`. Once chosen for a type, subsequent suggestions on that type collapse back to `[A/s/n/?]` — you only get one conformance choice per type per run.
- `b'` (alias `c`) — accept the **secondary** conformance proposal (used when the primary and secondary are incomparable, e.g. `Equatable` vs. `SetAlgebra` on a set-like type, or when the kit-defined `Semigroup` and the stdlib `AdditiveArithmetic` both apply).

Input is case-insensitive; an empty line is treated as `s`.

The interactive walk does not paginate — every visible suggestion is shown until the list is exhausted or you `Ctrl+C`. For a 100-suggestion target, expect to either commit to the full pass or stop midway and resume on the next run (your skips and rejects persist).

## Working with `.swiftinfer/decisions.json`

This file is the audit log of every triage decision. It lives at the package root and is intended to be **committed**. A typical entry:

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
        { "kind": "exactNameMatch", "weight": 40 },
        { "kind": "discoverableAnnotation", "weight": 35 }
      ]
    }
  ]
}
```

Three things future `discover` runs do with this file:

1. **Suppress already-decided suggestions** so the discover output stays focused on what's new.
2. **Feed the metrics command** — `swift-infer metrics` aggregates these records into per-template adoption rates.
3. **Inform drift detection** — only Strong-tier suggestions *not* already in this file qualify as drift.

### Editing it by hand

The file is plain JSON; reverting a triage decision is as simple as deleting the relevant `records[]` entry. Common edits:

- **Re-surface a rejected suggestion** — delete the entry. The next discover run will offer it again.
- **Re-record a different decision** — change `decision` from `"rejected"` to `"skipped"` (or vice versa). Note that re-recording from `"accepted"` does *not* delete the previously written test file; that's a separate manual cleanup.
- **Manually capture a decision made outside the tool** — append an entry. Identity hashes are 16-char uppercase hex; the `Suppress:` line in any rendered suggestion gives you the canonical form.

Decisions are de-duplicated by `identityHash`. If you create a duplicate manually, the merge logic keeps the most recent one (per `Decisions.upserting(...)`).

### What the four `decision` values mean

| Value | Meaning |
|---|---|
| `accepted` | Property-test stub was written. |
| `acceptedAsConformance` | RefactorBridge conformance extension was written instead of (or alongside) a property test. |
| `rejected` | The user judged this is *not* a property of the function. Hidden permanently. |
| `skipped` | "Not now." Re-surfaces on future runs. Tracked separately so metrics can distinguish "haven't decided yet" from "decided no." |

Per-record `signalWeights` is what made up the score at the time of the decision. The metrics command uses this to answer "is signal X paying off across the corpus, or is it surfacing too many false positives?"

### Schema versions

`schemaVersion: 2` is the current shape. Loaders accept v1 files (M6.1) and tolerate forward-compatible v2 records added by newer tool versions. If `schemaVersion` is greater than the loader knows about, you'll see a warning on stderr but the file still loads with the records the loader recognizes.

## Suppressing a suggestion with a skip annotation

Some suggestions are noise the tool can't tell are noise — for example, a function that *looks* idempotent but isn't because it depends on a side effect the scanner can't see. Rather than rejecting it through `--interactive` and committing a `decisions.json` change, you can paste the suppression directive directly into your source:

```swift
// swiftinfer: skip AB12CD34EF567890
public func updateCounter() { ... }
```

The hash comes from the `Suppress:` line in the rendered suggestion:

```
Suppress:  // swiftinfer: skip AB12CD34EF567890
```

Where to put it:

- Anywhere in any `.swift` file under `Sources/` or `Tests/` — the scanner walks both trees deterministically.
- The `0x` prefix is optional (`// swiftinfer: skip 0xAB12CD34EF567890` works too); both forms normalize to the same identity.
- The `swiftinfer` and `skip` tokens are case-insensitive; the hash itself is normalized to uppercase.
- Multiple skip annotations stack: each line suppresses one identity.

Why use a skip annotation instead of a `rejected` decision record:

- The annotation lives **next to the function**, so a future reader sees both the function and the rationale (you can append a comment after the hash).
- It survives `decisions.json` deletion or schema migrations.
- It's the right tool when the suppression reason is *intrinsic to the code*, not a transient triage call.

Conversely, prefer `--interactive` rejection when the reason is *stylistic* (e.g. "we don't write property tests for trivial getters") — it keeps your source cleaner and the rejection is recorded with timestamp + signal weights, which the metrics command needs.

## Extending the naming vocabulary

SwiftInferProperties ships a curated list of inverse-function name pairs (`encode`/`decode`, `serialize`/`deserialize`, `compress`/`decompress`, `encrypt`/`decrypt`, `parse`/`format`, `push`/`pop`, `insert`/`remove`, `open`/`close`, `marshal`/`unmarshal`, `pack`/`unpack`, `lock`/`unlock`) plus curated lists for idempotence verbs, commutativity verbs, monotonicity verbs, inverse-element verbs, and equivalence-class marker pairs.

If your project uses a different naming convention — say, your codec methods are named `pickle`/`unpickle` — drop a vocabulary file at `.swiftinfer/vocabulary.json`:

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

All keys are optional; missing keys default to empty arrays.

How to verify the vocabulary is being read:

- The discover output for a matched pair will say `Project-vocabulary inverse name pair: pickle/unpickle` instead of `Curated inverse name pair: encode/decode`.
- The curated list takes precedence — if your `inversePairs` repeats `["encode", "decode"]`, you get the curated rendering.

To override the default file location:

```sh
swift run swift-infer discover --target Foo --vocabulary path/to/custom.json
```

Or set it persistently in `.swiftinfer/config.toml` — see below.

For the full per-key field reference, see [reference.md → Vocabulary](reference.md#vocabulary).

## Configuring defaults with config.toml

If you're tired of typing `--include-possible` on every run, drop a `.swiftinfer/config.toml`:

```toml
[discover]
includePossible = true
vocabularyPath = "path/to/custom-vocab.json"
```

Precedence is **CLI flag > config file > built-in default**. So `swift-infer discover --target Foo --no-include-possible` overrides `includePossible = true` from config.

The TOML parser is intentionally minimal (PRD §16: no third-party TOML lib): supports section headers, key-value pairs, booleans, double-quoted strings, and `#` comments. Numbers, arrays, dates, dotted keys, multi-line strings, and inline tables are **not** supported and will produce a parse warning on stderr. If you need any of those, file an issue — most config keys do not need them.

Walk-up resolution: discover walks up from the `Sources/Foo/` directory until it finds `Package.swift`, then looks for `<package-root>/.swiftinfer/config.toml`. To override the lookup explicitly:

```sh
swift run swift-infer discover --target Foo --config path/to/config.toml
```

Unknown keys are silently ignored for forward compatibility; new tool versions can add config keys without breaking older config files.

## Pointing at a non-default test directory

By default, the TestLifter pass scans `<package-root>/Tests/`. Some projects keep their tests elsewhere (e.g., `Sources/Foo/Tests/` for SwiftPM packages with co-located tests, or a sibling-checkout layout):

```sh
swift run swift-infer discover --target Foo --test-dir ../FooTests/
```

If the explicit path doesn't exist, the tool warns on stderr and falls back to the default walk-up resolver — discover never silently runs without test cross-validation just because the override was wrong.

## Running drift in CI

The `drift` subcommand answers "what *new* Strong-tier suggestions would my CI complain about, given a frozen baseline?"

The two-step flow:

1. **Snapshot a baseline once** — typically when you first adopt the tool or after a calibration pass:

   ```sh
   swift run swift-infer discover --target Foo --update-baseline
   ```

   This writes `.swiftinfer/baseline.json` with the identity-hash list of every visible suggestion at the snapshot moment. Commit the file.

2. **Run drift on every PR**:

   ```sh
   swift run swift-infer drift --target Foo
   ```

   Output on stdout:

   ```
   2 drift warnings emitted.
   ```

   Output on stderr (one line per new Strong-tier suggestion that lacks a recorded decision):

   ```
   warning: drift: new Strong suggestion 0xAB12CD34EF567890 for normalize(_:) at Sources/Foo/Sanitizer.swift:42 — idempotence (no recorded decision)
   warning: drift: new Strong suggestion 0xCD34EF567890AB12 for encode(_:) at Sources/Foo/Codec.swift:88 — round-trip (no recorded decision)
   ```

`drift` always exits 0. The non-fatal posture is deliberate (PRD §9): drift surfaces information, never blocks a merge. CI integrations that want to fail on drift can grep stderr for `warning: drift:` lines:

```sh
swift run swift-infer drift --target Foo 2> drift.log
if grep -q '^warning: drift:' drift.log; then
    echo "::error::SwiftInfer drift detected — run swift-infer discover --target Foo --interactive locally"
    exit 1
fi
```

What drift considers "new":

- The suggestion's identity hash is **not** in `.swiftinfer/baseline.json`.
- The suggestion's identity hash is **not** in `.swiftinfer/decisions.json` (if you've already triaged it, drift stays quiet).
- The suggestion is **Strong** tier. Likely / Possible / Advisory suggestions never trigger drift, even when new.

To re-baseline (e.g. after accepting a batch of new suggestions through `--interactive`), run `discover --target Foo --update-baseline` again. `--update-baseline` is mutually exclusive with `--interactive` — pick one gesture per run; if you pass both, `--update-baseline` is ignored and a warning prints on stderr.

## Replaying a failed property test

When `swift test` reports a property-test failure, you typically want to:

1. Pin the failing input as a regression test so future commits keep it covered.
2. Fix the underlying code.
3. Verify the regression test now passes.

Step 1 is what `convert-counterexample` does:

```sh
swift run swift-infer convert-counterexample \
    --template round-trip \
    --callee encode \
    --reverse-callee decode \
    --type Document \
    --counterexample 'Document(text: "")'
```

This writes `Tests/Generated/SwiftInfer/round-trip/encode_decode_regression_<hash>.swift` — a self-contained `@Test` function that runs exactly one trial against the counterexample input, with the seed pinned so re-runs are byte-stable.

The `<hash>` is the first 8 characters of `SHA256(counterexample-source)`, so re-running the same conversion is idempotent. Two different counterexamples for the same callee land in two different files.

The required flags vary by template:

| Template | Required flags |
|---|---|
| `idempotence` / `monotonicity` | `--callee`, `--type`, `--counterexample` |
| `round-trip` / `inverse-pair` | `--callee`, `--reverse-callee`, `--type`, `--counterexample` |
| `commutativity` / `associativity` | `--callee`, `--type`, `--counterexample` |
| `identity-element` | `--callee`, `--type`, `--counterexample`, `--identity-element` |
| `invariant-preservation` | `--callee`, `--type`, `--counterexample`, `--invariant-keypath` |
| `count-invariance` / `reduce-equivalence` | `--callee`, `--type`, `--counterexample`, `--reduce-element-type`, `--seed-source` |

For exhaustive flag tables and template→flags coverage, see [reference.md → convert-counterexample](reference.md#convert-counterexample).

## Triaging RefactorBridge protocol-conformance proposals

When discover detects an *algebraic-structure cluster* — multiple suggestions on the same type that together imply the type satisfies a protocol's laws — it surfaces a **RefactorBridge proposal** as a `B` arm in the interactive prompt:

```
[Suggestion]
Template: associativity
Score:    85 (Strong)
...

[3/12] Accept (A) / B (Semigroup) / Skip (s) / Reject (n) / Help (?)
```

The arms map to:

| Arm | Writes |
|---|---|
| `a` | Property-test stub at `Tests/Generated/SwiftInfer/associativity/<func>.swift` (proves *this specific law* on this specific function). |
| `b` | Conformance extension at `Tests/Generated/SwiftInferRefactors/<TypeName>/Semigroup.swift`. The extension declares `extension Counter: Semigroup {}` and re-uses `PropertyLawKit`'s law machinery, which exercises **all** of Semigroup's laws on every CI run thereafter. |

Why two arms:

- **Property test (A)** is conservative — proves one law on one function. Use this when you're not yet confident the type satisfies the full protocol.
- **Conformance extension (B)** is broader — declares the type conforms to the protocol and lets `SwiftPropertyLaws` verify *all* of the protocol's laws (associativity + identity for `Monoid`, etc.) automatically. Use this when discover surfaces enough suggestions on the type to cover the protocol's full law set.

When two protocols apply incomparably (e.g., `Equatable` and `SetAlgebra`), a `B'` arm appears alongside `B`:

```
[3/12] Accept (A) / B (Equatable) / B' (SetAlgebra) / Skip (s) / Reject (n) / Help (?)
```

The two arms write to different paths and are independent — accepting `B` does not commit you to or against `B'`.

Once you accept `B` for a type in a single discover run, subsequent suggestions on that same type collapse back to `[A/s/n/?]`. RefactorBridge issues at most one conformance-write per type per run; the bookkeeping prevents you from accepting both `B` (Semigroup) and `B'` (Monoid) on the same type if they conflict.

The protocols RefactorBridge can propose against (as of v1.4): `Equatable`, `Comparable`, `Numeric`, `SetAlgebra`, and the kit-defined `Semigroup`, `Monoid`, `CommutativeMonoid`, `Group`, `Semilattice`. For exhaustive law-cluster mapping, see [reference.md → RefactorBridge](reference.md#refactorbridge).

## Reading advisory suggestions

Some suggestions ship as **advisory** rather than testable property suggestions. They surface in the discover output with `Tier: Advisory` and a comment-only writeout on accept (no executable `@Test` is generated). Two shapes:

### Predicate equivalence-class advisories

Surface when your test suite partitions inputs into named buckets like `[Valid/Invalid]` or `[Success/Failure]` and exercises the same predicate on both. Example: `XCTAssertTrue(isValid(x))` for one set of inputs and `XCTAssertFalse(isValid(y))` for another. The advisory is "your inputs naturally form a 2-class equivalence class on `isValid`," and on accept the tool writes a comment-only document at `Tests/Generated/SwiftInfer/equivalence-class/EquivalenceClasses_<predicate>.swift` summarizing the partition.

The advisory carries a `coversDomain` annotation when the partition exhaustively covers the domain — for two-class partitions, when both `XCTAssertTrue` and `XCTAssertFalse` cases exist; for N-class enum-typed predicates, when every enum case is covered by a marker.

### Consumer-producer chain advisories

Surface when discover detects a function whose input is reliably the output of another function, but the chain doesn't form a round-trip. Example: `validate(format(t))` appears in many tests with no inverse `unformat`. The advisory is "`validate` likely consumes `format`'s output; here's a comment-only proposal for an inferred input domain via `Gen<T>.map(format)`." Writeouts land at `Tests/Generated/SwiftInfer/consumer-producer-chain/<consumer>_<producer>.swift`.

Why advisories are comment-only: PRD §13 row 4 caps the memory ceiling on the side-map carriers that propagate these hints through the pipeline, and PRD §3.5's conservative-bias posture prefers a documented hint over a wrong test stub. The advisory tells you what the tool *thinks* the property is, without committing you to a specific generator.

## Calibrating signal weights with the metrics command

After a project has been using SwiftInferProperties for a few weeks and accumulated a meaningful `decisions.json` (≥ 20 records per template you care about), you can ask the tool how its signal weights are paying off:

```sh
swift run swift-infer metrics
```

Output:

```
swift-infer metrics — calibration aggregate (PRD §17.2)

Decisions: 47 across 1 source
  1. /Users/me/myproject/.swiftinfer/decisions.json

Per-template adoption:
  | Template               | Total | Accepted | Rejected | Skipped | Acceptance | Rejection | Suppression |
  |------------------------|------:|---------:|---------:|--------:|-----------:|----------:|------------:|
  | round-trip             |    25 |       21 |        2 |       2 |       84.0% |       8.0% |        8.0% |
  | idempotence            |    18 |       12 |        4 |       2 |       66.7% |      22.2% |       11.1% |

Tier-mix at decision time:
  | Tier       | Total | Accepted | Acceptance |
  |------------|------:|---------:|-----------:|
  | Strong     |    42 |       38 |       90.5% |
  | Likely     |     5 |        3 |       60.0% |
```

What to read:

- **Per-template acceptance rate.** Templates below 50% acceptance after ≥ 20 decisions are PRD §17.2 retirement candidates — the tool surfaces too many false positives in this template's domain. Lower its scoring weights or add stricter pre-filters.
- **Per-tier acceptance rate.** Strong-tier acceptance should be ≥ 80% if the score thresholds are calibrated. Lower numbers mean Strong is firing on cases the developer doesn't actually want.
- **Suppression rate.** "Skipped, never re-decided" — a high number suggests the suggestion is plausible but the developer doesn't have time to follow up. Different from outright rejection.

Templates with fewer than 20 decisions get a `note: <template> has fewer than 20 decisions; rates are advisory only` line above the table — small-sample statistics are not load-bearing.

### Aggregating across multiple projects

For calibration cycles that pool decisions from several benchmark corpora:

```sh
swift run swift-infer metrics \
    --decisions ~/proj-a/.swiftinfer/decisions.json \
    --decisions ~/proj-b/.swiftinfer/decisions.json \
    --decisions ~/proj-c/.swiftinfer/decisions.json
```

The tool merges by `identityHash` (de-duping; most recent wins on collisions) and renders one combined table. Per-source breakdown is not shown — see [reference.md → metrics](reference.md#metrics) for the limitation.

## Reading the generated tests

Every accepted property suggestion produces a Swift Testing `@Test` function. The structure is the same across templates:

```swift
@Test func encode_decode_roundTrip() async {
    let backend = SwiftPropertyBasedBackend()
    let seed = Seed(
        stateA: 0xAAAAAAAAAAAAAAAA,
        stateB: 0xBBBBBBBBBBBBBBBB,
        stateC: 0xCCCCCCCCCCCCCCCC,
        stateD: 0xDDDDDDDDDDDDDDDD
    )
    let result = await backend.check(
        trials: 100,
        seed: seed,
        sample: { rng in MyType.gen().run(&rng) },
        property: { value in decode(encode(value)) == value }
    )
    if case let .failed(_, _, input, error) = result {
        Issue.record(
            "encode/decode round-trip failed at input \(input)."
                + " \(error?.message ?? "")"
        )
    }
}
```

Anatomy:

- **`backend.check(...)`** comes from `PropertyLawKit`'s `SwiftPropertyBasedBackend`. It runs `trials` independent samples and reports the first failure.
- **`seed`** is derived from the suggestion's identity hash, so two runs of `swift test` produce byte-identical input sequences. This is the §16 #6 reproducibility guarantee — an accepted test that passes locally on Tuesday will pass identically in CI on Friday, modulo source-of-truth code changes.
- **`sample: { rng in ... }`** is the generator. Common shapes:
  - `Int` parameter: `Gen<Int>.int().run(&rng)`
  - `String` parameter: `Gen<Character>.letterOrNumber.string(of: 0...8).run(&rng)`
  - User-defined type: `MyType.gen().run(&rng)` — assumes you've defined `MyType.gen()`. The header comment of the generated file documents what generator was inferred.
  - When the tool can't infer a generator, the file emits a TODO-shaped placeholder rather than a stub that won't compile; you fill in the generator before the test runs.
- **`property: { value in ... }`** captures the template semantics:
  - `idempotence`: `f(f(value)) == f(value)`
  - `round-trip`: `inverse(forward(value)) == value`
  - `commutativity`: `f(a, b) == f(b, a)`
  - `monotonicity`: `value <= other ==> f(value) <= f(other)`
  - And so on — see [reference.md → Templates](reference.md#templates) for the full table.
- **`Issue.record(...)`** uses Swift Testing's `Issue` API rather than `#expect` so the failure message includes the offending input value.

### Editing the generated test

The generated stub is a starting point, not a contract. You can edit it freely — change the trial count, swap the generator, add `setUp` logic. The stub does not get re-emitted on subsequent discover runs (the decision record marks the identity as `accepted`), so your edits survive.

### Counterexample regression tests

Files written by `convert-counterexample` have the same shape but `trials: 1` and an explicit value rather than a generator:

```swift
@Test func encode_decode_roundTrip_regression_a1b2c3d4() async {
    ...
    sample: { _ in Document(text: "") },  // pinned counterexample
    property: { value in decode(encode(value)) == value }
}
```

These coexist with the generator-driven test. Keep both: the generator covers the *space*, the regression test covers the *known-bad point*.

## Templates at a glance

The templates discover surfaces and what they mean:

| Template | Property checked |
|---|---|
| `idempotence` | `f(f(x)) == f(x)` |
| `round-trip` | `g(f(x)) == x` for inverse-named pairs |
| `inverse-pair` | Same shape as round-trip; fired by inverse-element vocabulary verbs (`mirror`, `antipodal`) rather than codec-style names |
| `commutativity` | `f(a, b) == f(b, a)` |
| `associativity` | `f(f(a, b), c) == f(a, f(b, c))` |
| `identity-element` | `f(x, e) == x` for some `e` |
| `monotonicity` | `a <= b ==> f(a) <= f(b)` |
| `invariant-preservation` | `inv(f(x)) == inv(x)` for some keypath `inv` |
| `count-invariance` | `f(xs).count == xs.count` |
| `reduce-equivalence` | `xs.reduce(...) == xs.alternativeReduce(...)` |
| `equivalence-class` (advisory) | Predicate partitions inputs into named buckets |
| `consumer-producer-chain` (advisory) | A function reliably consumes another's output |

The full discussion of what evidence each template requires + how the score is computed lives in [reference.md → Templates](reference.md#templates) and PRD §5.

---

For exhaustive flag tables, schema specs, and tier thresholds, continue to the [reference](reference.md). For the design philosophy behind these features, see PRD §3 (non-goals), §3.5 (conservative bias), and §17 (calibration loop).
