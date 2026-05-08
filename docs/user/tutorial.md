# Tutorial — Surface your first property suggestion

> **Audience.** A Swift developer who has never used SwiftInferProperties. By the end of this page you will have surfaced, accepted, and run an inferred property test against your own code.
>
> **Time.** ~15 minutes.
>
> **Tracks v1.4.** The `swift-infer metrics` subcommand mentioned at the end ships in v1.4; everything else works on v1.3 too.

## What you'll build

A toy `Slug` codec — two functions, `encode` and `decode` — that should round-trip: `decode(encode(s)) == s` for every string. SwiftInferProperties will recognize the function-pair shape on its own, propose a property test for the round-trip, and write the test stub to disk on your acceptance. You will then run it with `swift test`.

The same workflow scales unchanged to real codebases — the tool isn't doing anything special for tutorial code.

## Prerequisites

- Swift 6.1+ toolchain (`swift --version`).
- An empty directory you don't mind committing throwaway code into.

You do **not** need an existing project — we'll build one from scratch.

## Step 1 — Set up a minimal package

Create a fresh SwiftPM package:

```sh
mkdir slug-tutorial && cd slug-tutorial
swift package init --type library --name Slug
```

Replace the generated `Package.swift` with:

```swift
// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "Slug",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/Joseph-Cursio/SwiftInferProperties", from: "1.4.0"),
        .package(url: "https://github.com/Joseph-Cursio/SwiftPropertyLaws", from: "2.0.0")
    ],
    targets: [
        .target(name: "Slug"),
        .testTarget(
            name: "SlugTests",
            dependencies: [
                "Slug",
                .product(name: "PropertyLawKit", package: "SwiftPropertyLaws")
            ]
        )
    ]
)
```

The first dep gives you the `swift-infer` executable. The second gives the test target the `PropertyLawKit` runtime that generated property tests import.

Replace `Sources/Slug/Slug.swift` with:

```swift
public enum Slug {

    /// Encode a string for use in a URL path segment.
    /// Spaces become hyphens; everything else passes through.
    public static func encode(_ input: String) -> String {
        input.replacingOccurrences(of: " ", with: "-")
    }

    /// Decode a slug back into a human string.
    public static func decode(_ encoded: String) -> String {
        encoded.replacingOccurrences(of: "-", with: " ")
    }
}
```

> **Aside.** This implementation is wrong on purpose — `encode` collapses no information that would prevent round-trip, but the sample is small enough that a property test on it actually passes. We'll come back to "what happens if it didn't" in the user guide.

Verify the package compiles:

```sh
swift build
```

## Step 2 — Run `swift-infer discover`

Point the tool at your target:

```sh
swift run swift-infer discover --target Slug
```

You should see output like:

```
1 suggestion.

[Suggestion]
Template: round-trip
Score:    70 (Likely)

Why suggested:
  ✓ Type-symmetry signature: String -> String ↔ String -> String
  ✓ Curated inverse name pair: encode/decode

Why this might be wrong:
  ✓ no known caveats for this template

Generator: Gen<Character>.letterOrNumber.string(of: 0...8)
Sampling:  256-bit seed derived from suggestion identity
Identity:  checkProperty.roundTrip|encode|decode|...
Suppress:  // swiftinfer: skip checkProperty.roundTrip|encode|decode|...
```

Three things to read out of that block:

1. **Template + tier.** The tool recognized `encode`/`decode` as a curated-name inverse pair (`+40` weight) on top of the type-symmetric signatures (`+30` weight) — total 70, which lands in **Likely** tier (40–74). Likely-tier suggestions are visible by default. *Strong* tier (≥75) requires additional signals like an `@Discoverable(group:)` annotation; we'll cover that in the user guide.
2. **Two-sided explainability.** Every suggestion ships both *why suggested* and *why this might be wrong* (PRD §4.5). For round-trip with no caveats, the tool says so explicitly rather than leaving the section blank.
3. **Suppress hint.** If you want to permanently silence this suggestion without going through triage, paste the `// swiftinfer: skip ...` comment anywhere in your sources. We won't use it in this tutorial.

The tool wrote nothing to disk on this run. Discover without flags is read-only.

## Step 3 — Triage interactively

Now run with `--interactive` to triage:

```sh
swift run swift-infer discover --target Slug --interactive
```

The same suggestion block appears, followed by a prompt:

```
[1/1] Accept (A) / Skip (s) / Reject (n) / Help (?)
```

Type `a` and press Enter:

- `a` (accept) writes a property-test stub to disk **and** records the decision in `.swiftinfer/decisions.json`.
- `s` (skip) records nothing permanent — the suggestion will re-surface on the next run.
- `n` (reject) records a negative decision; the suggestion will not surface again.
- `?` shows the full help block (including the `b` / `b'` arms used for RefactorBridge protocol-conformance proposals — not relevant for round-trip).

After accepting, the tool prints the path it wrote and exits.

## Step 4 — Inspect what was written

Two files are new:

```sh
ls Tests/Generated/SwiftInfer/round-trip/
ls .swiftinfer/
```

`Tests/Generated/SwiftInfer/round-trip/encode_decode.swift`:

```swift
@Test func encode_decode_roundTrip() async {
    let backend = SwiftPropertyBasedBackend()
    let seed = Seed(
        stateA: 0x...,
        stateB: 0x...,
        stateC: 0x...,
        stateD: 0x...
    )
    let result = await backend.check(
        trials: 100,
        seed: seed,
        sample: { rng in (Gen<Character>.letterOrNumber.string(of: 0...8)).run(&rng) },
        property: { value in Slug.decode(Slug.encode(value)) == value }
    )
    if case let .failed(_, _, input, error) = result {
        Issue.record(
            "encode/decode round-trip failed at input \(input)."
                + " \(error?.message ?? "")"
        )
    }
}
```

The seed numbers are derived from the suggestion's stable identity hash (PRD §16 #6), so re-runs of `swift test` exercise the same input sequence and produce the same pass/fail outcome.

You'll need to add the missing `import` lines and target prefix at the top of the file before it compiles in your test target:

```swift
import Testing
import PropertyLawKit
@testable import Slug
```

`.swiftinfer/decisions.json` is a small JSON record:

```json
{
  "schemaVersion": 2,
  "records": [
    {
      "identityHash": "AB12CD34EF567890",
      "template": "round-trip",
      "scoreAtDecision": 70,
      "tier": "likely",
      "decision": "accepted",
      "timestamp": "2026-05-07T...",
      "signalWeights": [
        { "kind": "typeSymmetrySignature", "weight": 30 },
        { "kind": "exactNameMatch", "weight": 40 }
      ]
    }
  ]
}
```

This file is the source of truth for "which suggestions has the developer already triaged?" Future `discover` runs read it and suppress already-decided suggestions; `swift-infer drift` reads it to decide which new Strong-tier candidates to warn on; `swift-infer metrics` reads it to compute acceptance / rejection rates.

Both files are intended to be committed. The decisions.json is your project's audit log of inferred-property judgements.

## Step 5 — Run the property test

```sh
swift test
```

You should see the new `encode_decode_roundTrip()` test pass. The backend ran 100 trials with the seeded random generator and the property held on every input.

> **What if it had failed?** The `Issue.record(...)` call would print the offending input. The user guide covers feeding such a counterexample back into the loop with `swift-infer convert-counterexample`, which writes a regression-test stub pinned to that exact input.

## Step 6 — Run discover again

```sh
swift run swift-infer discover --target Slug
```

Output:

```
0 suggestions.
```

The decisions.json suppresses already-accepted suggestions, so re-running discover is idempotent — it only ever surfaces *new* candidates the developer hasn't triaged yet. This is what makes discover safe to run on every PR.

## What you've seen

- `swift-infer discover --target T` is read-only; it surfaces ranked suggestions with two-sided explainability.
- `--interactive` walks suggestions one at a time. Acceptance writes a stub to `Tests/Generated/SwiftInfer/<template>/` and records the decision.
- `.swiftinfer/decisions.json` is the persistence layer — committed, hand-editable, the input to drift + metrics.
- Generated tests use a deterministic seed derived from the suggestion's identity, so reproducibility is byte-stable.
- All output is opt-in. The tool never edits your source, never auto-commits, never auto-runs the tests it generates.

## Where to next

- **[User guide](guide.md)** — task-oriented walkthroughs for each major feature: `--update-baseline` + `swift-infer drift` for CI; `swift-infer convert-counterexample` for replaying failed property tests; vocabulary files for project-specific naming conventions; RefactorBridge protocol-conformance proposals; `swift-infer metrics` for calibration; the full set of templates and detectors.
- **[Reference](reference.md)** — every CLI subcommand and flag, every template name, the `decisions.json` / `baseline.json` / vocabulary / config TOML schemas, tier thresholds, exit codes.
- **[PRD v1.0](../SwiftInferProperties%20PRD%20v1.0.md)** — design rationale, conservative-bias philosophy (PRD §3.5), the calibration loop (§17.3), and the §13 / §16 release-blocking guarantees.
