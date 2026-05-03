# TestLifter M8 — `swift-infer convert-counterexample` (Plan)

**Supersedes:** PRD v0.4 §7.9 row M8 ("Counterexample-to-unit-test conversion tooling") + §3.6 step 6 + §5.9 capability table row.

## What M8 ships (PRD v0.4 §7.9 + §3.6 + §5.9)

PRD §3.6 step 6 reads "Counterexample feedback. When a property fails, the shrunk counterexample is convertible into a focused unit test via `swift-infer convert-counterexample` (TestLifter M8)." This closes the discovery loop: user accepts a property suggestion (M3.3 writeout) → runs the test → sees a failure with a shrunk counterexample → uses M8 to pin that exact input as a regression test alongside the property test.

The user-visible flow:
1. `swift-infer discover --interactive` accepts a suggestion. M3.3 writes `Tests/Generated/SwiftInfer/<template>/<callee>.swift` with a `forAll`-style property test.
2. `swift test` runs the property test. SwiftPropertyBased emits `.failed(seed:counterexample:...)` for some trial; the `Issue.record(...)` line in the existing emitter renders the failure with the counterexample value visible in the test output.
3. User runs `swift-infer convert-counterexample --template <name> --callee <name> --type <type> --counterexample '<swift-source>'` (or `--reverse-callee <name>` for round-trip / inverse-pair shapes). The subcommand emits a regression test pinning that specific input.
4. Regression test lands at `Tests/Generated/SwiftInfer/<template>/<callee>_regression_<hash>.swift`. The hash is derived from the counterexample source so multiple regressions on the same property don't collide.

The regression test is a deterministic single-trial assertion — no `forAll`, no generator, no seed. It hard-codes the counterexample value as a `let` binding and asserts the same property the original test asserted (e.g. `#expect(decode(encode(value)) == value)` for round-trip).

The non-goals — explicitly out of scope for M8, reaffirmed:

- **Auto-pasting into the user's source.** Regression tests land under `Tests/Generated/SwiftInfer/` per PRD §16 #1 — never inside the user's existing `Tests/<Target>Tests/` files.
- **Parsing the failing-test output.** The user supplies the counterexample as an explicit CLI arg; the subcommand doesn't scrape stderr. This keeps the surface narrow + composable (the user can also generate a regression for any value, not just one that came from a real failure).
- **`--seed-override`.** Per PRD §16 #6, the seed-override flag is v1.1+. M8's regression tests are deterministic single-trial assertions; they don't sample, so they don't need a seed.
- **Counterexample shrinking.** SwiftPropertyBased already shrinks before reporting; M8 consumes the already-shrunk value verbatim.
- **Expanded outputs** (preconditions, domains, equivalence classes) — TestLifter M9.

### Important scope clarifications

- **Counterexample SOURCE form.** The user supplies the counterexample as a Swift expression string (e.g. `'42'`, `'"hello\n"'`, `'[1, 2, -1]'`, `'Doc(title: "X", count: -1)'`). M8 doesn't parse it — embeds verbatim. The user is responsible for ensuring the expression compiles in the resulting regression test's import context.
- **Regression-test FILE NAME.** `<callee>_regression_<short-hash>.swift` where the hash is the first 8 hex chars of `SHA256(counterexample-source)`. Same callee + same counterexample → same file (idempotent re-run); different counterexamples produce distinct files. Mirrors the M3.3 `<callee>.swift` naming for the original property test.
- **Sandbox guarantee.** PRD §16 #1 — regression files land at `Tests/Generated/SwiftInfer/<template>/<callee>_regression_<hash>.swift`, the same root as the M3.3 + M5.5 + M6.3 accept-flow writeouts. No source-tree writes outside this root.
- **Per-template regression-arm coverage.** All eight TemplateEngine-side templates (`idempotence`, `round-trip`, `monotonicity`, `invariant-preservation`, `commutativity`, `associativity`, `identity-element`, `inverse-pair`) PLUS the two M5.5 lifted-only arms (`liftedCountInvariance`, `liftedReduceEquivalence`) get parallel `<arm>Regression(...)` arms. A property template without a regression arm would be dead end the user can't escape.
- **Pair-shaped templates.** `round-trip` and `inverse-pair` need `--reverse-callee`; `identity-element` needs the identity-name and the type's identity-element binding (e.g. `--identity-element 'IntSet.empty'`); `reduce-equivalence` needs the `seedSource` (e.g. `--seed-source '0'`). Each of these surface knobs becomes a CLI flag.
- **Where the regression assertion lives.** Direct `#expect(...)` (Swift Testing) inside an `@Test func` peer. No backend / seed / sample machinery — just the bare assertion the original property would have made on this specific input.

## Sub-milestone breakdown

| Sub | Scope | Why this order |
|---|---|---|
| **M8.0** | **`LiftedTestEmitter` regression-stub arms.** New `Sources/SwiftInferTemplates/LiftedTestEmitter+Regression.swift` companion file with one `<arm>Regression(...)` arm per shipped property template + the two M5.5 lifted-only arms (10 arms total). Each takes an `inputSource: String` (the counterexample expression verbatim) plus the same per-template parameters its non-regression sibling takes (funcName / typeName / etc., minus the seed + generator). Emits a single-trial deterministic test stub: `@Test func <name>_regression_<hash>() { let value: <Type> = <inputSource>; #expect(<property>) }`. Pair-shaped templates take additional explicit args (`reverseCallee`, `identityName`, `seedSource`). **Acceptance:** new `LiftedTestEmitterRegressionTests` covers byte-stable goldens for the 10 arms; existing `LiftedTestEmitter*Tests` keep passing. | First piece — establishes the regression-stub vocabulary. M8.1 (CLI surface) consumes these arms via the existing `chooseGenerator(for:typeName:)`-style dispatch path. |
| **M8.1** | **`swift-infer convert-counterexample` subcommand.** New `SwiftInferCommand.ConvertCounterexample: AsyncParsableCommand`. CLI flags: `--template <name>` (required); `--callee <name>` (required); `--type <name>` (required for non-trivial types; `?` sentinel preserved as a non-compiling stub); `--counterexample '<swift-source>'` (required); `--reverse-callee <name>` (round-trip / inverse-pair); `--identity-element '<source>'` (identity-element); `--seed-source '<source>'` + `--reduce-element-type <name>` (reduce-equivalence); `--invariant-keypath '<source>'` (invariant-preservation); `--package-root <path>` (override walk-up). The subcommand routes to the matching `LiftedTestEmitter+Regression` arm based on `--template`, computes the file path via the same `Tests/Generated/SwiftInfer/<template>/<callee>_regression_<hash>.swift` convention, wraps the stub with the M3.3 file header (`// Auto-generated by swift-infer convert-counterexample` + provenance comment + imports), and writes atomically. **Acceptance:** new `ConvertCounterexampleCLITests` covers (i) `--template idempotence` + `--callee normalize` + `--type String` + `--counterexample '"hello\n"'` writes the expected file at the expected path; (ii) `--template round-trip` requires `--reverse-callee`, errors clearly otherwise; (iii) re-running with the same counterexample is idempotent (overwrites with byte-identical content); (iv) different counterexamples produce distinct files (per-counterexample hash collision-safe within reasonable bounds); (v) `--package-root` override works for non-conventional layouts. | Sequenced after M8.0 because the CLI dispatcher consumes the regression-stub arms. Independent of M8.2. |
| **M8.2** | **Validation suite.** Adds (a) **§16 #1 hard-guarantee re-check** — `ConvertCounterexampleHardGuaranteeTests` confirms the subcommand's writeouts stay rooted at `<package-root>/Tests/Generated/SwiftInfer/`; (b) **end-to-end CLI smoke test** — runs the subcommand binary (or directly invokes the AsyncParsableCommand) with realistic args for each of the 10 templates, confirms the file is written and contains the expected stub content; (c) **idempotence regression** — running the subcommand twice with the same args produces byte-identical output (PRD §16 #6 reproducibility guarantee). | Validation, not new code. Closes the M8 acceptance bar. |

## M8 acceptance bar

Mirroring PRD §7.9 + §3.6 + the M5/M6/M7 cadence, M8 is not done until:

a. **`LiftedTestEmitter` exposes a regression arm per shipped template.** All eight TemplateEngine-side templates + the two M5.5 lifted-only arms have parallel `<arm>Regression(...)` functions. Verified by `LiftedTestEmitterRegressionTests` byte-stable goldens.

b. **`swift-infer convert-counterexample` is a working CLI subcommand.** `swift-infer convert-counterexample --help` lists the flags; `--template` + `--callee` + `--type` + `--counterexample` is the minimal arg set.

c. **Regression files land under `Tests/Generated/SwiftInfer/<template>/`.** No source-tree writes outside that root. Verified by `ConvertCounterexampleHardGuaranteeTests`.

d. **Pair-shaped templates accept their additional flags.** `round-trip` + `inverse-pair` accept `--reverse-callee`; `identity-element` accepts `--identity-element`; `reduce-equivalence` accepts `--seed-source` + `--reduce-element-type`; `invariant-preservation` accepts `--invariant-keypath`. Missing-required-flag errors cite the missing flag's name.

e. **Re-running the subcommand with identical args is idempotent.** Same counterexample → same hash → same file path → byte-identical content overwritten. Different counterexamples → distinct hashes → distinct files (no collision within the same `(template, callee)` pair under reasonable use).

f. **§13 100-test-file perf budget unchanged.** M8 doesn't touch the discover pipeline; the perf test still passes.

g. **§16 #1 hard guarantee preserved** — the subcommand's writeouts stay sandboxed.

h. **`Package.swift` stays at `from: "1.9.0"`** — no kit-side coordination needed for M8.

## Out of scope for M8 (re-stated for clarity)

- **Expanded outputs** (preconditions / domains / equivalence classes) — TestLifter M9.
- **Counterexample shrinking** — already done by SwiftPropertyBased upstream.
- **Auto-paste / source-tree mutation** — out of v1.
- **`--seed-override`** — v1.1+ per PRD §16 #6.
- **Failure-output scraping** — out of v1; user supplies counterexample as explicit arg.
- **Cross-repo coordination with SwiftProtocolLaws.** No kit-side changes for TestLifter M8.

## Open decisions to make in-flight

1. **Regression-test file naming: `<callee>_regression_<hash>.swift` or `<callee>_<hash>.swift`?** Default proposal: keep the `_regression_` infix for clarity — distinguishes regression stubs from the original property test (`<callee>.swift`) at a glance. **Default: (a) `_regression_` infix.**

2. **Hash length: 8, 12, or 16 hex chars?** Collision risk at 8 chars (32 bits) is ~1 in 4 billion; at 12 chars (48 bits) is ~1 in 281 trillion. For per-(template, callee) scope (probably <100 regressions ever in any single project), 8 chars is plenty. **Default: (a) 8 hex chars from `SHA256(counterexample-source)`.**

3. **Counterexample type-annotation form: `let value: <Type> =` or `let value =`?** With explicit annotation, the user's regression test compiles even if the counterexample expression's inferred type is ambiguous (e.g. integer literal `42` could be Int / Int32 / etc.). **Default: (a) explicit annotation when `--type` is provided; bare `let value =` when `--type` is omitted (the `?` sentinel case).**

4. **`--package-root` override default: walk-up from CWD, or require explicit?** Default proposal: walk-up like `swift-infer discover` does — find `Package.swift`, write under `<root>/Tests/Generated/SwiftInfer/<template>/`. Mirror the M6.0 walk-up pattern. **Default: (a) walk-up from CWD; explicit `--package-root` override available.**

5. **What happens when `--template <name>` doesn't match a shipped template?** Default proposal: error with the list of valid template names. Don't silently no-op. Mirrors the existing `liftedTestStub(for:)` switch's nil return → "no stub writeout available" diagnostic, but the convert-counterexample subcommand surfaces it as a CLI error rather than a silent skip. **Default: (a) error + list valid templates.**

## New dependencies introduced in M8

None. All work is pure SwiftInferProperties internal — `LiftedTestEmitter` (Templates), `SwiftInferCommand` (CLI), `Tests/Generated/SwiftInfer/` directory convention. `Package.swift` stays at `from: "1.9.0"`.

## Target layout impact

Two new source files:
- `Sources/SwiftInferTemplates/LiftedTestEmitter+Regression.swift` (M8.0) — 10 regression arms.
- `Sources/SwiftInferCLI/ConvertCounterexampleCommand.swift` (M8.1) — the AsyncParsableCommand.

One existing source file modified:
- `Sources/SwiftInferCLI/SwiftInferCommand.swift` — wires the new subcommand into the AsyncParsableCommand `subcommands` list.

Test files:
- `Tests/SwiftInferTemplatesTests/LiftedTestEmitterRegressionTests.swift` (M8.0)
- `Tests/SwiftInferCLITests/ConvertCounterexampleCLITests.swift` (M8.1)
- `Tests/SwiftInferIntegrationTests/ConvertCounterexampleHardGuaranteeTests.swift` (M8.2)

## Closes after M8 ships

After M8, the discovery loop is complete: user accepts a property suggestion, runs the test, sees a counterexample, uses `swift-infer convert-counterexample` to pin the regression. PRD §3.6 step 6 closes; the v1 TestLifter surface is feature-complete (M9 expanded outputs is post-v1.0 per §7.8 scope).

The remaining post-v1 surface (PRD §20: SemanticIndex, IDE integration, `swift-infer apply`, `swift-infer metrics`) consumes the M8 surface unchanged — none of those v1.1+ features require widening the regression-stub vocabulary.
