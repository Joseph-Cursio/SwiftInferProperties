# TCA determinism measured-verify — open follow-ups

## Status

Stage 3 (dependency-pinned determinism measured-verify for TCA reducers)
shipped and verified green under Swift 6.3.3 — the three-way
`tca-determinism-corpus` (pure / proper-dependency / snuck-raw). This note
registers the four follow-ups deferred at that point. **None are built.** See
`tca-determinism-verify-scope.md` for the shipped design.

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

## 4. Tier-2 curated-compilable real-TCA measured corpus

- **Current:** two corpora. `tca-determinism-corpus` (synthetic three-way
  pure / proper-dependency / snuck-raw) is **measured** — Stage 3, green under
  6.3.3. `tca-examples-corpus` (13 vendored Point-Free files) is
  **discovery-only** — parsed, never compiled or measured.
- **Open:** a **Tier-2** corpus of real vendored TCA reducers that actually
  **compiles and runs** the determinism measured-verify — the highest-fidelity
  proof the pipeline works on idiomatic TCA, not just synthetic fixtures.
- **Newly feasible:** this was blocked by the Swift 6.2.4 compiler crash on The
  Composable Architecture, which the switch to the 6.3.3 toolchain this cycle
  resolved — so a compilable real-TCA corpus is now buildable.
- Connects to `tca-determinism-verify-scope.md` "Open questions for sign-off"
  #3 (is the synthetic three-way corpus sufficient, or do we need real TCA?).

## Sequencing

(3) is cheapest — the family already discovers; it needs the measured arm.
(4) is now unblocked by the 6.3.3 toolchain and would validate the whole line
end-to-end on real code. (1) and (2) are triggered by specific project shapes
(multi-module composition; structured-payload actions) — build when a real
target demands them, not speculatively.
