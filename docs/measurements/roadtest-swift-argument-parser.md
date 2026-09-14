# Second subject — swift-argument-parser (2026-09-14)

> **Status:** `measured` · **As of:** 2026-09-14

A second subject for the pipeline walk, chosen to test one hypothesis and one
assumption. The hypothesis: **false laws concentrate in the conjectural templates**
(`Refutability.isRoleEntailed == false`). The assumption, never stated as one until
it broke: that SwiftMarkdownWiki's yield was representative.

Apple-maintained, so a failing law is far more likely to be the *law's* fault than
the code's — which is what makes it a usable control on the hypothesis.

## Yield: 33 suggestions → 2 stubs → 1 runnable law

| | SwiftMarkdownWiki | swift-argument-parser |
|---|---:|---:|
| suggestions | 48 | 33 |
| stubs emitted | 21 | **2** |
| clear of both blockers | 9 | **2** |
| laws that ran | 9 | **1** |

**This is the larger finding of the two, and it was not what the walk was looking
for.** The tool's reach depends far more on the *shape of the subject's API* than on
the size of the catalogue.

Where the 31 went, and most of it is legitimate:

- **16 subjects declined `mutating`** — `run()`, `validate()`, `formUnion(_:)`,
  `reduce(to:)`. A `mutating` method returns `Void`; there is no value for a law to
  compare, and the decline says so by name.
- **15 declined with no emitter arm**, of which at least three are misattributed
  (#456) and one is genuinely emittable today.

**An Apple library's public surface is commands and mutating parsers.** The
catalogue is built for `(T) -> T` value transforms, and a CLI framework has almost
none. Nothing here is broken; the population simply is not there.

## The two laws

Predictions were written before the run (`pred_ap.md`), and **1 of 2 was correct**.

| stub | predicted | measured |
|---|---|---|
| `globalHelp_…_message_lifted_round-trip` | no compile | **no compile** — `cannot find 'message' in scope` |
| `message_description_round-trip` | no compile | **passed, and genuinely true** |

The miss is mine: I predicted `CleanExit` had no `description` in reach. It does, and
`CleanExit.message(x).description == x` round-trips exactly — probed by hand across
`""`, `"hello"`, `"a b\nc"`, `"# "`, `"0"`, all verbatim. **A conjecture that is
true and worth keeping**, which is the outcome the catalogue exists to produce.

The compile failure is the unqualified-call defect in the *lifted* arm: the law reads
`message(message(value)) == value` with no carrier, and `message(_ text: String) ->
CleanExit` would not typecheck composed with itself even if it resolved.

## The hypothesis: supported, on a sample too small to rate

Joining both subjects by refutability class:

| | laws run | false |
|---|---:|---:|
| **entailed** (`input-totality`) | 3 | **0** |
| **conjecture** (`idempotence`, `round-trip`) | 5 | **3** |

Direction is consistent and the mechanism is not mysterious — an entailed law is one
a correct implementation *cannot* fail, so zero is what the class means, now shown by
execution rather than asserted.

⚠ **3 and 5 are not rates.** Quoting a percentage from five data points would be the
error this document has caught twice already. What the numbers support is the
*ordering*, not a figure.

⚠ **And tier does not separate them.** `parse` and `parseQuery` are Possible 30 and
true; `mimeType` is Possible 20 and false. Two suggestions at the same tier with
opposite verdicts, so carrying the tier into the emitted stub — the obvious cheap fix
— would not have distinguished them. The **class** predicted every outcome; the tier
predicted none.

## What this changes

`Refutability.isRoleEntailed` already computes the distinction that separated every
outcome across both subjects. It reaches the CLI, it gates
`isWorthSurfacingBelowCut`, and it is **absent from the emitted file** — a green
`idempotence` test and a green `input-totality` test are byte-indistinguishable in
the test target, though one is a theorem and the other a guess read off a type shape.

A passing conjecture means *no counterexample found in 100 draws*. A passing entailed
law means *this held*. Same green tick today.

## Provenance

Instrument: SwiftInferProperties `722754af`, SwiftPropertyLaws v4.6.2. Subject
swift-argument-parser `b53c2f0`, restored clean — the harness ran on a local branch
that is deleted, and `Package.swift` is byte-identical to its original.
