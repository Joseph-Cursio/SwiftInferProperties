# Do #671's dedupe count laws have a population? Two emittable rows in 33,725 functions: ATTACH (#671)

> **Status:** `measured` · **As of:** 2026-11-11
>
> **Decision: ATTACH** under `docs/plans/dedupe-count-law-census-scope.md` §7. E = 2, against the bar of 5 for
> a new template. A = 1: SwiftUMLBridge's `dedupe` is the one emittable row a curated name already proposes. So
> the deliverable is C1 and C2 beside idempotence on recognised dedupe rows that pass the body gate, as #671's
> own fallback says, and not a new template. The kill arm turned #671's REASONED kills into MEASURED ones, cell
> for cell.

#671 argues that idempotence cannot tell a dedupe from the identity or from `[]`. Those are what the two simplest
dedupe bugs produce, so three SwiftUMLBridge mutants of `CoreDataModelExtractor.dedupe(relationships:)` pass it.
It proposes two count laws for a dedupe-role `f: [T] -> [T]`, gated on name **and** body:

- **C1** `xs.allSatisfy { f([$0]).count == 1 }`: a singleton survives;
- **C2** `f(xs + xs).count == f(xs).count`: a duplicate of everything adds nothing.

Its *Measure before building* asks for a hand-run kill, a name-and-body census, and an explicit tier decision.
The scope froze the gates, universe, controls, predictions and decision rule (`c6ec437c`) before the harness read
any subject.

## Instrument

| piece | where |
|---|---|
| scope, frozen first | `docs/plans/dedupe-count-law-census-scope.md` (`c6ec437c`) |
| kill arm | `fixtures/dedupe-count-law/kill-arm/`, run by `scripts/dedupe_count_law_kill_arm.py` → `fixtures/dedupe-count-law/kill-arm-2026-11-11.json` |
| census harness | `fixtures/dedupe-count-law/census-run/` (committed at `b8c8b973`, before the run) → `fixtures/dedupe-count-law/census-2026-11-11.json` |
| universe, decision | `scripts/dedupe_count_law_census.py` (`controls` → `fixtures/dedupe-count-law/subjects-2026-11-11.json`; `report`) |
| hand-check | `fixtures/dedupe-count-law/handcheck-2026-11-11.json` |

- **The harness** gates every `func` with a body on name, shape and body in SwiftSyntax (scope §2). It joins the
  shipped `FunctionScanner` scan for access and for whether `IdempotenceTemplate` fires on the function today.
- **Its 14 controls pass** before the run (scope §4). Four are read verbatim from their files: the witness,
  `ConstructionUniverse.deduplicated`, `dedupedByStateAndAction` and `dedupedByIdentity`. The other ten cover the
  shapes the scope refuses or admits by construction.

## Step 1: the kill arm

`dedupe` is copied verbatim; it is identical at SwiftUMLStudio `e36da59` and `9ad7631`. The generator is the
stub's, written out:
- `ERRelationship` memberwise, with `String` leaves of 0–8 letters and digits;
- the cardinalities drawn as the kit's `.enumCases`;
- `.array(of: 0...8)`.

Each law runs 100 trials from a fixed seed. Toolchain: Swift 6.4.2, SwiftPropertyLaws 4.11.0,
swift-property-based 2.0.1.

| variant | becomes | C1 | C2 | idempotence | Bookstore sanity case |
|---|---|---|---|---|---|
| original | — | pass | pass | pass | pass |
| L162 `seen.insert` deleted | identity | pass | **FAIL** | pass | FAIL |
| L161 `!seen.contains` negated | `[]` | **FAIL** | pass | pass | FAIL |
| L163 `result.append` deleted | `[]` | **FAIL** | pass | pass | FAIL |

**#671's prediction held in every cell.**
- C1 kills both `[]` mutants.
- C2 kills the identity, which agrees with the correct code on every duplicate-free draw, so only C2's
  self-made duplicate exposes it.
- The idempotence law the run scored kills none.

Together, C1 and C2 kill all three from the `[T]` the stub already draws, with no collision bias and no
`Hashable`. As the scope says, the arm cannot fail by construction, so it decides nothing.

## Step 2: the census

33,725 functions in 4,668 files over 40 subjects: #670's 39 roots plus this repository's `Sources/` (scope §3).
Five subjects contribute nothing:
- `cycle27-surface`, MacCloud_client_MacOS, SwiftEffectInference and SwiftMarkdownWiki have no `Sources/`
  under the funnel's rule;
- SwiftProjectLint's files were already read through the `swift-project-lint` manifest corpus.

**The funnel:**

| stage | functions |
|---|---|
| name family (#671's grep, on syntax) | 36, over 11 repositories |
| name gate | 13 |
| shape gate | 11 |
| body gate: **admitted** | **7** |
| emittable candidates (not private, concrete element) | 3 |
| **E**, after the hand-check | **2** |

### Where the name family fell out

- **`name: not a stem`, 22:** `distinct`, `unique`, `uniqueKey`, `removeDuplicates` (GRDB's observation
  reducer), `uniquifyIfNeeded`, and this repository's uniquifier helpers. Not dedupes, or not by this name.
  - **One real dedupe is excluded by name:** SwiftAssist's
    `KnowledgeGraphBuilder.distinct(_: [(String, String)])`. It is a filter-insert dedupe over a tuple, which
    is neither `Equatable` nor a generator the kit derives, so it could not have entered E.
- **`name: revoking tail`, 1:** ArgumentParser's `uniquingAdjacentElements()`, refused as #671 requires.
- **`shape`, 2:**
  - SwiftAssist's `uniqued(by:)` has a key closure and a generic `Element`;
  - SwiftUMLBridge's `ERModelExtractor.dedupe(explicit:implicit:)` takes two arrays.
- **`body: early return`, 1:** `dedupedByIdentity`, refused as #671 requires.
- **`body: unread form`, 3. These are real dedupes in forms the frozen gate does not list:**
  - ArgumentParser's `uniquing()` filters on `seen.insert($0).0`, not `.inserted`;
  - SwiftProjectLint's `dedupedByLocation` is `for x in xs where seen.insert(k).inserted { append }`;
  - this repository's `CardinalityWitnessDetector.deduplicateByPropertyName` is
    `for x in xs where !seen.contains(k) { insert; append }`.

  All three are private or generic, so none could have entered E, and the decision does not move. A shipped
  body gate should admit both forms.

### The 7 admitted rows, hand-checked

Every row's C1 and C2 were read true of today's code. Every element type is `Equatable`, so C2's equality form is
available on each.

| row | route | recognised today | candidate | E |
|---|---|---|---|---|
| SwiftUMLBridge `CoreDataModelExtractor.dedupe(relationships:)` | Set, keep-first | yes (`dedupe`) | yes | **yes**: C1/C2 measured in the kill arm, generator `.derivedComposite` |
| `dedupedByStateAndAction(_:)` (SwiftInferCLI) | Set, keep-first | no (`deduped`) | yes | **yes**: `swift-infer verify` holds idempotence over `[ReducerCandidate]`, 1000 + 1000 trials |
| `ConstructionUniverse.deduplicated(_:)` (SwiftInferCore) | dictionary, **not** keep-first | yes | yes | **no**: `verify` stops on *no generator could be derived for carrier type `[Member]`* |
| `EqualityBodyShape.deduplicated(_:)` | Set, keep-first | yes | private | no |
| SwiftLintRuleStudio `deduplicated(_:)` | Set, keep-first | yes | private | no |
| SwiftLintRuleStudio `deduplicatedByRule(_:)` | Set, keep-first | no | private | no |
| SwiftUMLBridge `StateMachineExtractor.uniqued(_:)` | Set, keep-first | no | private | no |

- **The emittable column is measured where it could be.**
  - `discover`'s *Generator:* line says "not derived" for both `[Member]` and `[ReducerCandidate]`. Yet
    `verify` derives one for `[ReducerCandidate]` (and did in the 2026-09-17 survey), so that line is not the
    test.
  - `verify` was run on both of this repository's candidates; SwiftUMLBridge's is the kill arm's.
- **No row is a gate defect.** The dictionary route's one row, `ConstructionUniverse.deduplicated`, keeps the
  smallest path per key and overwrites. The count laws hold of it, its equality and subsequence forms do not, and
  it is not keep-first, which the gate records. This is the canonical-representative case #671 names.
- **Unscored:** no function outside the name family passes both the shape and body gates. So a body-only signal
  would add nothing on this universe.

### The decision, against the frozen rule

- **E = 2**, below 5: not BUILD.
- **A = 1** (SwiftUMLBridge `dedupe`): **ATTACH**. #671 stays open, and a small build is filed: emit C1 and C2
  beside the idempotence law on rows a recognised dedupe name proposes and that pass the body gate.

**Predictions (scope §6):**
- step 1 held in every cell;
- name family 36 (under 40), held;
- admitted 7 (under 10), held;
- E = 2 (2 or 3), held;
- ATTACH with A = {`dedupe`}, held.

`ConstructionUniverse.deduplicated` was the "doubtful" third. It fell to a generator, as predicted, though for
`Member` as a whole, not for its `URL`, which the kit does derive.

## What this does not answer

- **The tier, beyond the attach.** BUILD would have put a dedupe-role template in
  `Refutability.roleEntailedTemplates`. ATTACH adds two laws to an existing row, whose tier stays the
  idempotence row's. Whether C1 and C2 should lift that row's tier (they are owed by any non-adjacent dedupe;
  idempotence is a conjecture) is for the build.
- **A wrong key.** `xs + xs` collides under any key, so neither law sees it.
- **The idempotence law on `ConstructionUniverse.deduplicated`.** Whether it is false of correct code (hash
  order) stays REASONED; it has no generator, so it cannot run.
- **`dedupedByStateAndAction`'s identity mutant.** It would pass the measured idempotence law, and C2 would kill
  it (REASONED). That row is in E, not A: `deduped` is not a recognised name, so the attach does not reach it.
  Widening the curated names is a separate question, and one row cannot answer it.

## Reproduce

```
python3 scripts/dedupe_count_law_kill_arm.py fixtures/dedupe-count-law/kill-arm-2026-11-11.json
python3 scripts/dedupe_count_law_census.py controls fixtures/dedupe-count-law/subjects-2026-11-11.json
(cd fixtures/dedupe-count-law/census-run && swift run -c release DedupeCensus run ../subjects-2026-11-11.json ../census-2026-11-11.json)
python3 scripts/dedupe_count_law_census.py report fixtures/dedupe-count-law/census-2026-11-11.json fixtures/dedupe-count-law/handcheck-2026-11-11.json
```

The funnel repositories stand on their current `main` and are recorded per subject, with three dirty
(`swiftlint-rule-studio`/SwiftLintRuleStudio and MacCloud_server). A re-run at another revision is a new
reading, not a reproduction.
