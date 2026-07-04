# TCA determinism measured-verify — open follow-ups

## Status

Stage 3 (dependency-pinned determinism measured-verify for TCA reducers)
shipped and verified green under Swift 6.3.3 — the three-way
`tca-determinism-corpus` (pure / proper-dependency / snuck-raw). This note
registers the four follow-ups deferred at that point. **Item 4 is now built
(2026-07-03); items 1–3 remain open.** See `tca-determinism-verify-scope.md`
for the shipped design.

## 1. Multi-module reducer pins / cross-module disambiguation

- **Current:** `ReducerPin` parses a 3-component `<module>.<type>.<func>` pin,
  but the **module prefix is ignored in matching** — a redundant qualifier
  (`ReducerPin.swift:36`; `:24` "cross-module disambiguation is deferred to
  multi-module [plumbing]"). Both entry points punt: "defer to M2+ when
  multi-module plumbing lands" (`VerifyInteractionCommand.swift:55`,
  `DiscoverInteractionCommand.swift:59`).
- **Open:** real disambiguation when two modules declare same-named reducer
  types — the pin must resolve *by module*, and discovery must carry module
  identity through the candidate so the match isn't ambiguous.
- **Trigger:** a project composing internal packages with same-named reducers
  in different modules. Build when a real target needs it.

## 2. Structured associated-value action payloads

- **Current:** Phase B classifies action-case constructibility from
  `payloadTypes` and emits the **constructible subset** — payload-free plus
  single-recognized-raw-type cases (`ReducerCandidate.swift:97-99`, `225-231`;
  `ReducerDiscoverer+TCAWalk.swift:65-93`). The verifier enumerates those
  without bailing on richer payloads.
- **Open:** **non-raw / structured payloads** — cases carrying custom types,
  nested enums, or multiple/labeled associated values. These are currently
  skipped (not constructed), so a reducer whose interesting behavior sits
  behind a structured-payload action gets thinner action coverage.
- **Risk:** constructing arbitrary payload types needs a generator per type,
  which overlaps the generator-synthesis machinery — scope carefully rather
  than widening the scanner ad hoc.

## 3. `unknownActionIsNoOp` measured-verify

- **Current:** `ReducerInteractionAnalyzer` **surfaces** `unknownActionIsNoOp`
  (`reduce(s, unknown) == s`) as a discovery-side family, for **open alphabets
  only** — a closed enum makes "unknown action" unrepresentable, so the claim
  is vacuous and gets skipped (`ReducerInteractionAnalyzer.swift:51-56`,
  `92-102`). It is a sibling family to determinism over the `.redux` family.
- **Open:** give it the same **measured-verify** treatment determinism got in
  Stage 3 — a stub-emitter arm plus a measured corpus proving it fires on an
  open-alphabet reducer and correctly skips closed ones. The family/analyzer
  plumbing exists; the measured e2e does not.
- **Cheapest of the four** — discovery already emits it; it needs the measured
  arm, not new discovery.

## 4. Tier-2 curated-compilable real-TCA measured corpus — ✅ BUILT (2026-07-03)

- **Shipped:** `Tests/Fixtures/tca-examples-measured-corpus/` — three real
  Point-Free reducers curated from the `Examples/` tree (SwiftUI View / `#Preview`
  scaffolding stripped, `@Reducer` verbatim): `Counter` (pure), `OptionalBasics`
  (pure, composes `Counter` via `.ifLet`), `Timers` (one pinned CA built-in
  dependency, `\.continuousClock`). `TCAExamplesMeasuredTests` packages them via
  `CorpusPackager`, runs a real `swift build` against ComposableArchitecture in
  the verify-workdir, and measures determinism: 3 identities → 3 measured-bothPass
  → all Verified (~62s under 6.3.3). `.subprocess`-tagged, 6.3.3-gated.
- **Curation rule (minimal & faithful):** only reducers that co-compile against
  CA alone are included — `03-Effects-Basics` and others were excluded because
  they reference custom `DependencyKey` types (`\.factClient`) or app-level
  navigation/shared-model types that don't resolve in a flat module.
- The discovery-only `tca-examples-corpus` (13 vendored files) stays as-is; this
  is the separate curated compilable subset its ATTRIBUTION.md always pointed to.
- Answers `tca-determinism-verify-scope.md` "Open questions for sign-off" #3 in
  the affirmative: the pipeline works on real idiomatic TCA, not just synthetic
  fixtures.

## Sequencing

(4) is **done** (see above) — real TCA now compiles-and-measures end-to-end.
(3) is the cheapest remaining — the family already discovers; it needs only the
measured arm. (1) and (2) are triggered by specific project shapes (multi-module
composition; structured-payload actions) — build when a real target demands
them, not speculatively.
