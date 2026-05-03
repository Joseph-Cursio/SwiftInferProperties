# TestLifter M6 — Decisions Persistence + Skip Honoring + `--test-dir` (Plan)

**Supersedes:** PRD v0.4 §7.9 row M6 + M2 plan deferral note (M2-plan OD #2: `--test-dir` deferred to M6) + the standing TestLifter M5 archive note ("Out of scope for M5: decisions.json persistence + `// swiftinfer: skip` honoring on the test side — TestLifter M6").

## What M6 ships (PRD v0.4 §7.9 + §7.5 + §16 #5)

PRD §7.9 row M6 reads "Suggestion-identity hashing, decisions.json persistence, `// swiftinfer: skip` honoring." Per the PRD §5.9 rewrite, suggestion-identity hashing already shipped at TemplateEngine M1.5; decisions.json persistence already shipped at TemplateEngine M6 (the `DecisionsLoader` + `Decisions` schema in `SwiftInferCLI` / `SwiftInferCore`); `// swiftinfer: skip` honoring shipped at TemplateEngine M1.5 — *for TemplateEngine-side suggestions*. TestLifter M6 is "make the same three things work on the lifted-side suggestions that M3.2's `LiftedSuggestionPipeline.promote` adds to the visible stream."

Concretely TestLifter M6 ships:

1. **Skip-marker filter applied to lifted suggestions.** `SkipMarkerScanner.skipHashes(in: directory)` already walks every `.swift` file in the discover target including under `Tests/` — test-side `// swiftinfer: skip <hash>` markers ARE collected today. The existing filter in `TemplateRegistry.discoverArtifacts` only applies to TemplateEngine suggestions; promoted lifted suggestions bypass the filter (they enter the stream after `discoverArtifacts` returns, in `Discover+Pipeline.collectVisibleSuggestions`'s `combined = artifacts.suggestions + promotedLifted`). The fix: thread the skip hashes out of `discoverArtifacts` (or recompute them at the pipeline layer) and apply the same filter to the promoted lifted suggestions before the `combined` concat.

2. **`--test-dir` CLI override.** Today the discover pipeline runs TestLifter against the same directory as `TemplateRegistry.discoverArtifacts`, which the CLI resolves to `Sources/<target>/` from the `--target Foo` flag. That means real CLI invocations don't see test files at all (tests live in `Tests/FooTests/` at the package root, outside `Sources/<target>/`). The integration tests work today because they pass the package-root directory directly to `Discover.collectVisibleSuggestions`. A real CLI user gets no test-side cross-validation. The fix: a new `--test-dir <path>` flag that overrides where TestLifter looks for tests, plus a sane default that walks up from the production target to the package root and scans `<package-root>/Tests/` if it exists.

3. **decisions.json filtering for lifted suggestions on subsequent runs.** This is *probably* already wired — `InteractiveTriage.run` filters out suggestions whose `identity.normalized` already has a record in `existingDecisions` regardless of TE-vs-lifted origin (M5.5's `lifted|<template>|<calleeNames>` identity scheme produces normalized hashes the same way). M6 adds explicit per-pattern integration tests that confirm the filter holds for lifted-side identities + a regression test for the case where the user previously rejected a lifted suggestion and re-runs `swift-infer discover --interactive` (the rejected lifted should not surface again).

The non-goals — explicitly out of scope for M6, reaffirmed:

- **Counter-signal scanning** (asymmetric assertions vetoing candidate symmetric / monotonic / count-preserving properties; non-deterministic body in mock-synthesis suppression) — TestLifter M7.
- **`swift-infer convert-counterexample`** — TestLifter M8.
- **Expanded outputs** (inferred preconditions, inferred domains, equivalence-class detection) — TestLifter M9.
- **Marker-binding precision** (PRD §7.5's "future work: bind a marker to a specific declaration" line in `SkipMarkerScanner`'s file-level docstring) — out of TestLifter M6 because the M5.5 lifted suggestion's `identity.normalized` IS already the natural binding for a marker; no AST-shape extension needed for the M6 surface to work.

### Important scope clarifications

- **Skip-marker SOURCE.** A user can put `// swiftinfer: skip <hash>` in *either* the production-side source file OR the test file — `SkipMarkerScanner.skipHashes(in: directory)` walks the whole discover-target tree, so both placements work. M6 doesn't gate which file the marker lives in; it just ensures lifted-side identities are honored alongside TE-side identities.

- **decisions.json SCHEMA.** The TemplateEngine M6 `DecisionRecord` schema (under `SwiftInferCore.Decisions`) carries `identityHash` + `template` + `decision` + `timestamp` + `signalWeights`. Lifted-side decisions use the same schema unchanged — `identityHash` is `lifted|<template>|<calleeNames>` normalized; `template` is the lifted suggestion's `templateName` (`"round-trip"`, `"idempotence"`, `"commutativity"`, `"monotonicity"`, `"invariant-preservation"`, `"associativity"`). M6 doesn't grow the schema; the existing one already accommodates lifted records.

- **`--test-dir` PRECEDENCE.** Mirrors the existing `--vocabulary` / `--config` precedence: explicit CLI arg wins; otherwise walk up from the production target to find the package root and try `<package-root>/Tests/` if it exists; otherwise no test-side scanning (the same behavior as today's misconfigured CLI invocations — degraded but not broken).

- **Interactive flow existing-decision filter.** `InteractiveTriage.run` already filters via `existingDecisions.record(for: suggestion.identity.normalized) == nil` (line 116, no TE-vs-lifted distinction); M6 doesn't modify this — it adds tests that pin the contract for the lifted side.

## Sub-milestone breakdown

| Sub | Scope | Why this order |
|---|---|---|
| **M6.0** | **`--test-dir` CLI override.** New `@Option public var testDir: String?` on `SwiftInferCommand.Discover`. New `effectiveTestDirectory(productionTarget:explicitTestDir:)` helper in `Discover+Pipeline` that returns the URL TestLifter should scan: (a) explicit `--test-dir` arg if provided; (b) walk up from `productionTarget` to find a directory containing `Package.swift`, then return `<that>/Tests/` if it exists; (c) fall back to `productionTarget` (current behavior, broken-but-degraded). Thread the resolved test directory into `TestLifter.discover(in:)` separately from the production-target directory the rest of the pipeline uses. **Acceptance:** `--test-dir` integration test that runs `swift-infer discover --target Foo --test-dir /path/to/Tests`-equivalent flow and confirms TestLifter scans the explicit dir; a default-walk-up test that runs against a package-root fixture and confirms TestLifter finds `<root>/Tests/`; a degraded-fallback test that confirms when no Package.swift is found, TestLifter scans the production target (no crash). | Independent of M6.1 / M6.2. The CLI flag is the user-visible payoff for the M2-plan deferral; doing it first means M6.1's skip-marker work runs against the new `testDir`-resolved directory in tests too. |
| **M6.1** | **Skip-marker filter for lifted suggestions.** Extend `Discover+Pipeline.collectVisibleSuggestions` to recompute (or thread through) the skip-hash set after `LiftedSuggestionPipeline.promote` returns, then apply the same `!skipHashes.contains(suggestion.identity.normalized)` filter the TemplateEngine side already uses. The skip hashes come from BOTH the production target AND the test directory — `SkipMarkerScanner.skipHashes(in:)` is called twice (once per directory), then unioned, OR a single call with a directory union helper. **Acceptance:** new `LiftedSkipMarkerHonoringTests` integration suite covers: (i) a test-side `// swiftinfer: skip <lifted-hash>` filters the matching lifted suggestion; (ii) a production-side marker filters the matching TE-side suggestion AND the matching lifted-side suggestion (so the user can suppress both with one marker if they share an identity — relevant when the lifted's cross-validation key matches a TE suggestion that was already suppressed); (iii) a marker for a non-matching hash is a no-op; (iv) malformed markers (non-hex, missing token) are no-ops per the existing `SkipMarkerScanner.normalize` contract. | Sequenced after M6.0 because the `testDir` resolver determines which directory to scan for skip markers. Independent of M6.2 / M6.3. |
| **M6.2** | **Decisions.json regression coverage for lifted suggestions.** New `LiftedDecisionsPersistenceTests` integration suite covers: (i) accept gesture on a lifted suggestion produces a `DecisionRecord` whose `identityHash` matches the lifted identity (`lifted|<template>|<calleeNames>` normalized) and whose `template` matches the lifted `templateName`; (ii) on a subsequent run, the lifted suggestion is filtered out by `InteractiveTriage.run`'s `existingDecisions` filter (no double-prompt); (iii) reject gesture on a lifted suggestion produces a `DecisionRecord` with `decision: .reject` and the same identity-hash key; (iv) skip gesture similarly. **No new code** — the existing `InteractiveTriage` flow already handles the lifted-side identity uniformly with the TE-side identity. M6.2 is pure regression coverage that pins the contract so a future refactor can't accidentally bypass it for lifted suggestions. | Independent of M6.0 / M6.1 — pure regression coverage. Doing it last means the test fixtures can use the `--test-dir`-aware setup from M6.0 + the skip-filter behavior from M6.1 if needed. |
| **M6.3** | **Validation suite.** Adds (a) **§13 perf re-check** — extends `TestLifterPerformanceTests` to assert the `< 3s` 100-test-file budget still holds with M6.0–M6.2 active (skip-hash recomputation is the only added discover-time work; should be sub-millisecond); (b) **§16 #1 hard-guarantee re-check** — `LiftedDecisionsPersistenceTests` and `LiftedSkipMarkerHonoringTests` confirm M6's writeouts (decisions.json updates) stay rooted at `<package-root>/.swiftinfer/decisions.json` and don't escape; (c) **`--test-dir` CLI surface lint** — new `DiscoverCLITestDirTests` confirms the flag's help text matches the M6.0 contract, the precedence (CLI > walk-up > fallback) holds, and `--test-dir` is accepted alongside the existing `--target` / `--vocabulary` / `--config` flags without conflict. | Validation, not new code. Closes the M6 acceptance bar. |

## M6 acceptance bar

Mirroring PRD §7.9 + §7.5 + §16 + the v0.4 §5.8 acceptance-bar pattern + the M1 / M2 / M3 / M4 / M5 cadence, M6 is not done until:

a. **`--test-dir <path>` CLI flag accepted by `swift-infer discover`** with the precedence (CLI > walk-up > fallback) the M6.0 row spells out. Verified by `DiscoverCLITestDirTests`.

b. **Default walk-up resolution finds `<package-root>/Tests/`** when the user runs `swift-infer discover --target Foo` and the package root contains a `Tests/` directory. Real CLI users get test-side cross-validation by default — the v1 release-blocking gap (cross-validation seam never fires for real CLI invocations) is closed.

c. **`// swiftinfer: skip <lifted-hash>` markers honored.** A test-side or production-side marker whose hash matches a lifted suggestion's `identity.normalized` filters the lifted suggestion out of the visible stream. Verified by `LiftedSkipMarkerHonoringTests`.

d. **decisions.json round-trip works for lifted suggestions.** Accept / reject / skip gestures on a lifted suggestion produce schema-correct `DecisionRecord` entries; subsequent runs filter the suggestion out via `InteractiveTriage`'s `existingDecisions` filter. Verified by `LiftedDecisionsPersistenceTests`.

e. **§13 100-test-file perf budget still holds** with M6.0–M6.2 active. The added work (skip-hash recomputation against the test directory + the Lifted-side filter pass) is sub-millisecond on the synthetic 100-file corpus.

f. **§16 #1 hard guarantee preserved** — M6's decisions.json + skip-marker writeouts stay rooted at `<package-root>/.swiftinfer/`. No source-tree modification.

g. **`Package.swift` stays at `from: "1.9.0"`** — no kit-side coordination needed for M6. The CLI surface widening + skip + decisions wiring all live in SwiftInferProperties; nothing in SwiftProtocolLaws changes.

## Out of scope for M6 (re-stated for clarity)

- **Counter-signal scanning** — TestLifter M7.
- **`swift-infer convert-counterexample`** — TestLifter M8.
- **Expanded outputs** (preconditions, domains, equivalence classes) — TestLifter M9.
- **Marker-binding precision** (`SkipMarkerScanner` future-work line about binding markers to a specific declaration) — not needed for M6's acceptance bar; the lifted suggestion's `identity.normalized` is the binding. Out of v1.
- **`--test-dir` glob-pattern support** (e.g. `--test-dir "Tests/**/Unit"`) — out of v1 scope. M6.0 ships single-directory args only.
- **Cross-repo coordination with SwiftProtocolLaws.** No kit-side changes for TestLifter M6.

## Open decisions to make in-flight

1. **`--test-dir` default walk-up: when the package root has multiple `Tests/` subdirectories (e.g. `Tests/FooTests/` and `Tests/BarTests/`), do we scan all of them, scan only `Tests/`, or scan only `Tests/<targetName>Tests/`?** Default proposal: scan `Tests/` recursively (matches today's behavior — `TestSuiteParser` recursively walks). Cost: minimal, since `TestSuiteParser` ignores files without recognized test methods. **Default: (a) scan `Tests/` recursively.** Reversible if real users want narrower scope.

2. **Skip-marker filter ordering: apply before or after `LiftedSuggestionPipeline.promote`'s suppression pass?** Default proposal: AFTER. The suppression pass dedups TE-vs-lifted by cross-validation key; the skip filter then operates on whatever survives. Order matters when a TE suggestion AND its matching lifted suggestion both hit a skip marker — the TE side gets filtered first (in `discoverArtifacts`), the lifted side is suppressed by the cross-validation-key dedup, and the user's marker effectively suppresses both. Putting the lifted-side skip filter AFTER suppression is the natural place. **Default: (a) skip filter after suppression.**

3. **Interactive flow rejected-lifted on subsequent run: surface or hide?** The existing flow hides — `InteractiveTriage.run` filters `existingDecisions.record(for: suggestion.identity.normalized) == nil`. So a previously-rejected lifted is hidden on the next run. M6.2 just pins this contract with a regression test. No decision needed; it's already the contract. **Default: (a) hide previously-decided lifted suggestions** — matches TE-side behavior.

4. **`--test-dir` validation: error or warn on missing directory?** Default proposal: warn-and-degrade. If the user passes `--test-dir /does/not/exist`, emit a warning to diagnostics and fall through to the walk-up resolver (or no test-side scanning if walk-up also fails). Mirrors the existing `--vocabulary` / `--config` warn-and-degrade posture. **Default: (a) warn-and-degrade.**

5. **decisions.json schema migration for the `lifted|...` identity scheme: any change needed?** No. The schema is identity-agnostic; `lifted|<template>|<callees>` is just a string the same way `<template>|<canonicalSignature>` is. No schema bump. **Default: (a) no schema change** — pinned by M6.2 regression tests.

## New dependencies introduced in M6

None. All work is pure SwiftInferProperties internal — `SkipMarkerScanner`, `Decisions`, `DecisionsLoader`, `InteractiveTriage`, `Discover+Pipeline`, and `SwiftInferCommand` are all existing modules. `Package.swift` stays at `from: "1.9.0"`.

## Target layout impact

Three new test files under `Tests/SwiftInferIntegrationTests/`:
- `LiftedSkipMarkerHonoringTests.swift` (M6.1)
- `LiftedDecisionsPersistenceTests.swift` (M6.2)
- `DiscoverCLITestDirTests.swift` (M6.3) — under `Tests/SwiftInferCLITests/` if the existing CLI-tests directory is the right home; the M5.5 `InteractiveTriageTests.swift` extension pattern suggests so.

Two existing source files modified:
- `Sources/SwiftInferCLI/SwiftInferCommand.swift` — adds `@Option public var testDir: String?` and threads it into `Discover.run`.
- `Sources/SwiftInferCLI/Discover+Pipeline.swift` — adds `effectiveTestDirectory(...)` helper, threads `testDirectory` through `collectVisibleSuggestions`, applies skip-hash filter to lifted suggestions.

One existing source file possibly modified:
- `Sources/SwiftInferTemplates/SwiftInferTemplates.swift` — if the M6.1 fix needs to expose `skipHashes` from `discoverArtifacts` rather than recompute (cleaner; avoids walking the directory twice). Decided in-flight.

## Closes after M6 ships

After M6, TestLifter exposes the same persistence + skip-marker surface for lifted suggestions that TemplateEngine has had since M1.5 + M6. `swift-infer discover` becomes the single-command entry point that scans both production code and tests, surfaces both TE-side and TestLifter-side suggestions, honors per-suggestion skip markers regardless of which side they target, and persists user decisions through the same `.swiftinfer/decisions.json` file. The M2-plan `--test-dir` deferral closes. PRD §7.9 row M6 is satisfied for both the TemplateEngine and TestLifter halves.

The remaining TestLifter milestones (M7 counter-signal scanning, M8 convert-counterexample, M9 expanded outputs) ship on top of this surface; none of them require widening the persistence or skip-marker layers M6 closes.
