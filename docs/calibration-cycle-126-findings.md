# Calibration cycle 126 — Phase C scoping (corpus-scale TCA survey)

> **STATUS: SCOPING (no binary change — investigation + decision record).**
> Scopes Phase C of the `.tca` epic: run the measured survey over the real
> tca-10/tca-25 corpora. **Finding: the survey machinery already exists;
> the blocker is that the discovery corpora were built for AST-only
> analysis and don't compile** — not as a whole, and not even one file in
> isolation. A reducer-only *slice* does compile, so Phase C's real core is
> a **reducer-slice extractor**, gated three ways. Recommendation: prefer
> **curating a verify-ready real-TCA corpus (C2)** over retrofitting the
> non-compilable discovery corpora (C1). Captured 2026-06-15. **No version
> bump.**

## What Phase C is *not*

The survey is already built: `verify-interaction --all` (cycle 114,
parallelized cycle 120) does discover → measured-verify → batch-record over
a target, and discovery uses the **real witness detector**
(`DiscoverInteraction.collectSuggestions`) — not the hand-built invariants
the measured *tests* use. Phase C adds **no** survey logic and **no**
detector work. The only gap: make a real corpus *buildable* so measured
verify can run against it.

## The proven blocker

The discovery corpora (`tca-10`/`tca-25-discovery`) were assembled for
AST-only discovery and were never meant to compile. Three experiments
settle it:

- **Whole-corpus co-compile** fails — ~69 files mixing reducers, SwiftUI
  Views, `App`/`@main` entries, `#Preview`s, **9 UIKit files** (won't build
  for the macOS verifier), and asset/resource references.
- **Single-file slice** fails too — even the simplest reducer file
  (`01-GettingStarted-Counter.swift`) references `AboutView` from *another*
  file, because the file bundles the reducer with View code
  (`CounterView`/`CounterDemoView`/`#Preview`) that reaches across files.
- **Reducer-only slice compiles** ✓ — dropping the `View`/`#Preview`/`readMe`
  decls and keeping just the `@Reducer` type + nested `State`/`Action`
  builds cleanly against ComposableArchitecture.

## The Phase C core: a reducer-slice extractor

Direct source inclusion (the Phase A architecture) at corpus scale needs a
**drop-UI-decls extractor**: from each corpus file emit only the reducer +
its domain types (`@Reducer` / `Reducer`-conforming structs, their nested
`State`/`Action`, plus domain helpers the *reducer* references), dropping
`: View` structs, `App` entries, `#Preview` macros, and view-only top-level
decls. The UI-decl filtering is mechanical with SwiftSyntax; the hard tail
is **cross-file *domain* references** — a reducer whose `State` uses an
`enum Tab` defined in another file still needs that type pulled in, which
requires symbol resolution across the corpus.

## Reachability gates (stacked on Phase B's ~73/99)

1. **Drop-UI slice must be self-contained.** Reducers referencing cross-file
   *domain* types still fail to compile. The cycle-120 survey is already
   error-tolerant (a failed verify → `measured-error`, surfaced not fatal),
   so these are disclosed, not crashes — but not verified.
2. **UIKit files excluded** — 9 files won't build for the macOS verifier.
3. Phase B's constructible-Action gate still applies on top.

The *literal* reachable count is therefore well below 73/99 and unknown
until the extractor is spiked — the same evidence-first pattern as every
prior phase.

## The fork

- **C1 — extractor over the real discovery corpora.** Build the drop-UI
  extractor (+ cross-file domain handling), run the survey against sliced
  tca-10/tca-25, tolerate per-reducer build failures. Delivers the "literal
  corpus" 50.5% delta. **Cost: a real new component** + ongoing fragility
  (retrofitting corpora that were explicitly AST-only), for a reachable
  subset that's small and gated three ways.
- **C2 — curate a verify-ready real-TCA corpus.** Hand-curate / extract a
  small set of self-contained, real-`@Reducer`-shaped reducers (like today's
  `Tests/Fixtures/idempotence-survey-corpus/`, but TCA-macro-based). Phase B
  verifies them directly — **no extractor needed.** Clean, durable
  measured-coverage demonstration; cost is curation, not engineering. Does
  not run against the *literal* discovery corpora.

## Decision

**Recommended: C2.** The discovery corpora's non-compilability makes C1's
extractor a disproportionate investment — a fragile source-transformer to
retrofit AST-only corpora, for a literal-corpus number whose reachable
subset is small and triple-gated. C2 gives a clean, durable measured-coverage
story (real `@Reducer` shapes verified end-to-end) at curation cost, and is
the natural home for regression-guarding Phases A/B.

If the *literal discovery-corpus* number is specifically the goal, C1 is the
only route — but **spike the extractor's clean-slice rate on ~5 reducers
first** to size the reachable subset before committing, exactly as
reachability was measured before Phases A/B.

**Overall:** the `.tca` epic's *engineering* is essentially complete at
Phase B. Phase C is mostly **corpus curation (C2)**, not new capability.

## Reproduction

Throwaway slice experiments (not committed), under `/tmp/tca-spike`: copy a
real corpus reducer file into a CA-bearing verifier target and `swift build`
— the whole file fails (cross-file `AboutView`); a hand-reduced
reducer-only slice (UI decls removed) builds. Corpus UIKit/SwiftUI counts:
`grep -rl "import UIKit"` = 9, `import SwiftUI` = 52, of 69 `.tca`-bearing
files.

## What's next

`.tca` epic: **Phase A + B shipped; Phase C is corpus curation (C2 rec.)**.
Other untouched optionals: the shared prebuilt user-package artifact
(cycle 120 perf tail). Default idempotence stays `.likely`; the other four
interaction families stay `.possible` behind `--include-possible`.
