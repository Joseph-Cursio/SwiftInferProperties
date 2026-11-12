# Does #670's boundary walk have a population? One emittable row in 31,016 functions: DECLINE (#670)

> **Status:** `measured` · **As of:** 2026-11-11
>
> **Decision: DECLINE (population)** under `docs/plans/count-threshold-boundary-census-scope.md` §7. One row
> is emittable (`compactText`), against a bar of 5. It also fails the second test, since all of `E` sits in one
> repository. The kill arm turned #670's REASONED kills into MEASURED ones, cell for cell. The gate A/B is
> recorded as a separate, smaller candidate and is not decided here.

#670 argues that a count threshold's off-by-one (`compactText`'s `count > 80` → `>= 80`) is caught only by a law
on the side the boundary sits on, drawn at the boundary. It proposes three changes to guard-domain:
- **(a)** a walk at `N − 1`, `N`, `N + 1`;
- **(b)** the complementary branch of a cut-first body;
- **(c)** reading past the first statement, with a label-aware free-identifier gate.

Its Direction asks for step 0 (run the kill) and step 1 (count with the reader's rules under a stop condition
fixed first) before anything is built. The rules, universe, controls, predictions and decision were frozen in
the scope (`fe780cf7`) before the harness read any subject.

## Instrument

| piece | where |
|---|---|
| scope, frozen first | `docs/plans/count-threshold-boundary-census-scope.md` (`fe780cf7`) |
| kill arm | `fixtures/count-threshold/kill-arm/`, run by `scripts/count_threshold_kill_arm.py` → `fixtures/count-threshold/kill-arm-2026-11-11.json` |
| census harness | `fixtures/count-threshold/census-run/` (committed at `9ffd9877`, before the run) → `fixtures/count-threshold/census-2026-11-11.json` |
| universe, decision | `scripts/count_threshold_census.py` (`controls` → `fixtures/count-threshold/subjects-2026-11-11.json`; `report`) |
| hand-check | `fixtures/count-threshold/handcheck-2026-11-11.json` |

- **The harness** reads every `func` with a body three ways:
  - with the shipped `GuardDomainReader.read`;
  - with a replica of it, under today's text gate and under the label-aware gate;
  - with the prototype extended reader.

  The prototype lives only in the harness; `Sources/` is unchanged.
- **The replica guard** (scope §2.4.2): the text-gate replica agrees with the shipped reader on **all 31,016
  functions** and on the 17 functions in guard-domain's own test fixtures. So the A/B below compares two
  readers that differ only in the gate.
- **Subject revisions:** SwiftUMLStudio `9ad7631`, SwiftAssist `8e1bc8d`, SwiftProjectLint `6a231cda`. Every
  root's revision and dirty state is in the subject list. Three roots were dirty, and that is recorded rather
  than refused: SwiftLintRuleStudio (both as a manifest corpus and as a funnel repository) and MacCloud_server.

### The universe: 31,016 functions, not 33,150

The 20 resolving manifest corpora plus the 19 funnel repositories, `Sources/` only: 4,054 files and 31,016
functions. `rewrite-postcondition.md` names this universe at 33,150, but its harness was never committed, so
the two counts cannot be reconciled. Three differences are known:
- **Two funnel repositories have no `Sources` directory** (`MacCloud_client_MacOS` and `SwiftMarkdownWiki` are
  Xcode app projects), so the frozen rule reads none of their files.
- **The roots are deduplicated by resolved path.** SwiftProjectLint and SwiftEffectInference are read once,
  under the manifest; their funnel entries contribute 0 files.
- **This unit counts nested functions**, which the scanner skips. A nested function cannot be a template row
  (`inScan: false`), so it is never emittable.

## Step 0: the kill arm, MEASURED

`compactText` at both revisions was copied verbatim into a package on the pinned kit. The three mutants
swift-mutation-testing made at `:200` were applied by text edit. Seeds are fixed, and each sampled pass runs
100 trials. The walk draws 20 letters-and-digits strings at each of 79, 80 and 81 Characters.

| law | negate | `>` → `<` | `>` → `>=` |
|---|---|---|---|
| Law 1, `e(x).count <= 80 ⟹ f(x) == e(x)`, walked | killed | killed | **killed** |
| Law 2, the cap `f(x).count <= 80`, walk + 100 draws | killed | killed | survived |
| `idempotence`, as emitted (100 edge-biased draws) | killed | killed | survived |

- **The matrix is identical at `e36da59` and at `9ad7631`,** and every original passes all three laws.
- **#670's prediction held in every cell** (scope §1.4).
- **What it settles:** only Law 1 at the boundary sees `>=`.
- **What it does not settle:** as #670 says, the arm cannot fail by construction, because the laws restate the
  body. It turns the REASONED rows into MEASURED ones and decides nothing.
- **⚠ `compactText` changed after #670 was written.** At `9ad7631` it is one `let` splitting on
  `.whitespacesAndNewlines`. The scope added that set to the walk allowlist before the run, since it is also the
  identity on letters-and-digits input.

## Step 1: the census

### (a) Today's guard-domain rows that compare a count: 9, 2 beyond reach

| repository | function | condition | law side | reach | beyond reach | `NOT APPLIED` | walk-eligible |
|---|---|---|---|---|---|---|---|
| SwiftInferProperties | `Visitor.visit` | `node.elements.count >= 3` | ≤2 | 10 | no | no | no |
| swift-collections | `UnsafeMutableBufferPointer.initialize` | `source.count > 0` | ≤0 | 10 | no | no | no |
| SwiftProjectLint | `BooleanControlCouplingVisitor.isSubstantialArm` | `block.statements.count >= 2` | ≥2 | 10 | no | no | no |
| SwiftProjectLint | `SubsumedConditionVisitor.visit` | `node.count >= 2` | ≤1 | 10 | no | no | no |
| SwiftProjectLint | `InsecureTransportVisitor.truncateURL` | `urlString.count > 60` | ≥61 | 11 | **yes** | **yes** | yes |
| pbt-book | `swiftOrgSortVerifier` | `output.count > 1` | ≤1 | 10 | no | no | no |
| SwiftAssist | `CIAdapter.truncateOutput` | `output.count <= Self.maxErrorOutputLength` (10,000) | ≤10000 | 10 | **yes** | no | yes |
| SwiftPropertyLaws | `DerivationStrategist.takesPrivateStorage` | `initializer.parameters.count > 1` | ≤1 | 10 | no | no | no |
| SwiftUMLStudio | `SVGRenderer.renderEdge` | `edge.points.count >= 2` | ≤1 | 31 | no | no | no |

- **Seven of the nine use small `N` (0 to 3)** on syntax nodes or arrays. The generator already draws both
  sides, and none is a `String` input, so the walk has nothing to add there.
- **The two beyond reach are #670's own sites:**
  - `truncateURL` gets today's `NOT APPLIED`, because it states the cut and no draw reaches 61.
  - `truncateOutput` is a method of a `public actor`.
- **`renderEdge` is F4's other half,** a count on a composite input's stored field. The scope sets it aside.
- **Reach** is `max(10, L + 8)` for the function's longest harvested literal `L` (scope §2.3).

### (b) and (c): the extended reader admits 5, 4 of them new

| repository | function | form | needs | (c) because | cut | new | walk-eligible |
|---|---|---|---|---|---|---|---|
| SwiftUMLStudio | `ActivityGraphBuilder.compactText` | cut-first | b, c | `let`, labels | `prefix` + marker | yes | yes |
| SwiftProjectLint | `InsecureTransportVisitor.truncateURL` | cut-first | b | (none) | `prefix` + marker | yes | yes |
| SwiftAssist | `MLXValidateCommand.preview` | ternary | b, c | `let`, labels | `prefix` + marker | yes | yes |
| SwiftAssist | `ThinkingRecipeExtractor.trimStep` | identity-first `guard` | c | `let`, labels, bare static (240) | (none) | yes | yes |
| SwiftAssist | `CIAdapter.truncateOutput` | identity-first | (none) | (none) | (none) | no, today's row | yes |

These are exactly the five sites #670's recall probe found that fit the shape. The sixth, `deriveName`, is
refused as the scope predicted: it opens with `guard let`. **The reader finds no site the probe missed in
31,016 functions.**

The extended reader also refused 154 functions that hold a top-level count threshold:

| refusal | count |
|---|---|
| not unary | 66 |
| `guard` with more than one predicate or more than one statement | 28 |
| statement after the `let`s is not a threshold | 14 |
| cut-first `guard` (outside the frozen rules) | 10 |
| mutating | 10 |
| async or throws | 9 |
| other | 17 |

**The ten cut-first `guard`s could not have moved the decision.** None is a `String` truncation. They return a
sentinel (`.visitChildren`, `""`, `false`, `0`) over `node`, `edge.points` or `initializer.parameters`, none
walk-eligible.

### The hand-check, and the decision

Every admitted row and every today's count row was read against its source. **All 12 are law-right and
counted-right**: the boundary is on the right side, `let`s are inlined correctly, and the bare static resolves
to 240 at `ThinkingRecipeExtractor.swift:40`. That leaves the three emittable candidates:

| candidate | verdict | why |
|---|---|---|
| `compactText` | **emittable** | internal static on an internal struct in the `SwiftUMLBridgeFramework` library, with a `String` input and no receiver to draw |
| `truncateURL` | not today | an instance method on `final class InsecureTransportVisitor: BasePatternVisitor`, whose only init is `init(pattern: SyntaxPattern, viewMode:)`. guard-domain's writer **draws** its receiver from a derived generator and does not construct one, and no generator derives for this class (REASONED from the writer, not run) |
| `preview` | not today | `MLXValidateCommand: AsyncParsableCommand` is in the `swift-assist-cli` **executable target**, which a test target cannot import |

Not candidates under the frozen rules: `trimStep` (`private static`) and `truncateOutput` (an actor method).

**E = 1 < 5, and 1 of 1 is in SwiftUMLStudio. DECLINE on both tests.** This matches the issue's own estimate,
"emittable today: about one".

## The gate A/B: a separate, smaller candidate

Today's text gate reads any name not preceded by a `.` as free. The label-aware gate reads free names off the
syntax: argument labels, member names and closure parameters are never free.

| | rows the reader admits |
|---|---|
| today's gate | 265 |
| label-aware gate | 317 |
| gained | 54 (35 that guard-domain would propose) |
| lost | 2 |

**Of the 35 template-eligible gains**, by what today's gate tripped on:
- **27 are argument labels.** Examples: `contains(anyOf:)`, `isIdentical(to:)`, `shouldTraverse(node:)`,
  `contains(where: { $0.label?.text == … })`, `truncatingRemainder(dividingBy:)`, and memberwise
  initialisers such as SwiftAssist's `ConfidenceSignal(source:weight:passed:detail:)`.
  - One of the 27, swift-foundation's `UInt128._ascii(_:)`, takes an `inout` parameter, which the writer
    declines.
- **4 are words inside a string literal.** Today's literal mask skips multi-line and interpolated literals:
  - `"it extends \(name), which is @MainActor"`;
  - pbt-workbook-corpus's `"\(count) item"` (twice, both planted-bug subjects);
  - a multi-line message in SwiftAssist.
- **2 are the `unsafe` keyword** (stdlib `isEqual`).
- **2 are false gains.** swift-format returns `super.visit(node)`, which no test can call. The prototype gate
  does not count `super` as free. A shipped gate must.

That leaves **32 gains whose every name a stub can bind**, over 9 repositories, the largest SwiftAssist with
9.

**The 2 losses are corrections, not regressions** (the scope predicted none):
- MacCloud_server's `File.canAccess(user:)` and `canWrite(user:)` test `user.id == $user.id`.
- `$user` is the model's property-wrapper projection, which is instance state. Today's text gate reads it as
  the parameter `user` and admits a law that is not about the argument. The label-aware gate refuses it.
- **This is a defect in the shipped reader,** and it is independent of #670.

Under scope §7 the A/B is reported, not decided. It is the cheapest part of #670's proposal, it is not bounded
by truncation, and it fixes one live false admission. If it is taken up, it is its own change: a syntax-level
`mentionsOnly`, with `super` free and an A/B over the shipped template's rows.

**Taken up the same day:** `docs/measurements/guard-domain-syntax-gate.md` (+52 reader rows, −2 false, `super`
free).

## Predictions (scope §6)

| prediction | outcome |
|---|---|
| Step 0: Law 1 kills 3; Law 2 and idempotence kill the negation and `<` | **held**, both revisions |
| (a): fewer than 20 beyond reach, fewer than 5 emittable | **held** (2 beyond reach, 0 emittable from (a) alone) |
| (b)+(c): fewer than 15 new, at most 3 emittable | **held** (4 new, 1 emittable) |
| A/B: gains, loses none | **half held**: +54, but −2 (both corrections) |
| Decision: DECLINE on population | **held** |

## What this does not answer

- **Whether a characterisation law on `compactText` alone is worth writing by hand.** The kill arm's Law 1 is
  that law. SwiftUMLStudio could adopt it as an ordinary test.
- **The cap (Law 2).** Measured only on `compactText`, where it holds. Its SwiftAssist failures (`preview`,
  `trimStep`, `deriveName` keep the full budget and then append `…`) are the author's to rule on, or a
  linter's, as #670 argues.
- **Receivers.** `truncateURL`'s non-derivation is read from the writer's rules. If guard-domain's writer
  learns to construct a receiver, as the totality arms do, `truncateURL` becomes emittable, and `E` rises to 2.
  That is still a decline.
- **A wider universe.** The 13 unmet subjects and the layout corpus were not read. #670's population is
  application code, and the funnel repositories are where its witnesses live.

## Reproduce

```
python3 scripts/count_threshold_kill_arm.py fixtures/count-threshold/kill-arm-<date>.json
python3 scripts/count_threshold_census.py controls fixtures/count-threshold/subjects-<date>.json
cd fixtures/count-threshold/census-run && swift run -c release CountThresholdCensus run ../subjects-<date>.json ../census-<date>.json
python3 scripts/count_threshold_census.py report fixtures/count-threshold/census-<date>.json fixtures/count-threshold/handcheck-2026-11-11.json
```
