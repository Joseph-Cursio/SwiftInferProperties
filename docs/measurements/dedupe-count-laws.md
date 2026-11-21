# #671's count laws, carried beside idempotence on a gated dedupe

> **Status:** `measured` · **As of:** 2026-11-21

**Verdict: built (#711), in the accept stub and in `verify`.** An `idempotence` row on a recognised dedupe (`dedupe`,
`deduplicate`, `deduplicated`) whose body passes #671's gate now carries the body's route as
`TemplateMatch.dedupeCount`. Its accepted stub writes two more laws over the same generator and seed:
**C1**, a singleton survives, and **C2**, a duplicate of everything adds nothing. On SwiftUMLBridge's
`dedupe(relationships:)`, **the emitted stub fails all three mutants that idempotence passes, and
passes the original.** Over 22 manifest corpora plus two extra trees, **no row moved and no score
changed**. The route line reached exactly the 4 dedupes #711 named. Quote it as **one emittable row,
three mutants killed by an emitted law**, never as laws gained.

⚠ **The first gate admitted false laws, and an adversarial review caught them before merge (§5).**
Its dictionary route took any skip that mentioned `d[k]`, and its loops waved every `let` through
unread. On correct code, both made C1 or C2 false. The fixed gate refuses every reproduced
counterexample, and §3 and §4 are re-taken on it.

**`verify` checks them too, as companion laws (§6).** They run inside the idempotence entry after
idempotence passes, are reported beside its verdict and never as it, and a failure withholds
`Verified` without vetoing. On the kill arm, `verify` holds with C1 and C2 held on the original. On
each mutant, a plain `verify` runs no companions: each mutation also breaks the body shape the gate
admits. `accept-check`, which re-checks the laws the user accepted, reports all three mutants as
now-fails.

---

## 1. What changed

Census decision **ATTACH** (`dedupe-count-law-census.md`, under the frozen scope
`docs/plans/dedupe-count-law-census-scope.md` §7): E = 2 emittable dedupes in 33,725 functions,
against a bar of 5, so no new template. A = 1 is a row a curated name already proposes, so the laws
ride on it.

| piece | where |
|---|---|
| the body gate, from the scope's §2.4 plus #711's two forms (`insert(k).0`, a `for … where` that inserts or tests `!contains`) | `DedupeBodyReader` (`SwiftInferCore`), read into `BodySignals.dedupeBody` only for the three names and shape `[T] -> [T]` |
| the match, so no writer re-reads the body | `TemplateMatch.dedupeCount(DedupeBody)` |
| "why suggested" names the route; "why this might be wrong" says a wrong key is invisible | `IdempotenceTemplate+DedupeCount.swift` |
| C1 and C2 in the accepted stub, same generator and seed | `LiftedTestEmitter.dedupeCountLaws`, called by `InteractiveTriage.idempotentStub` |
| on the dictionary route, idempotence stated without order (§5) | `LiftedTestEmitter.idempotentIgnoringOrder` |

**C2's form depends on the route.** On the Set route (keep-first), and under strict equality, C2 is
`f(value + value) == f(value)`, since the row already needs `==`. On the dictionary route it compares
counts only. `Array(d.values)` is in hash order, so equality may be false of correct code there.

The gate is written from the scope, not copied from the census harness. Its tests are the scope's §4
controls, with real subjects quoted verbatim (`DedupeBodyReaderTests`,
`DedupeBodyReaderRefusalTests`). Two refinements beyond the scope, both toward refusal:
- in `if !s.contains(k) { s.insert(k) … }`, the two keys must be the same text;
- on the dictionary route, every write and every guarded read must use one key.

## 2. The tier: unchanged, decided explicitly

#711 asked for an explicit answer. **The row keeps idempotence's score and tier.** C1 and C2 are owed
by any dedupe the gate admits, while idempotence is a conjecture, so the laws could argue for more.
But the census found one emittable row, and one row cannot calibrate a tier.
`DedupeCountLawTemplateTests.scoreUnmoved` pins this, and the A/B (§4) found no rescored row. The verify half (§6) only ever takes away: a companion failure withholds `Verified`, and it never
promotes or vetoes.

## 3. The kill arm, on the EMITTED stub

`scripts/dedupe_count_laws_kill_arm.py` copies `fixtures/dedupe-count-law/kill-arm/` and drops the
hand-written laws. It accepts every suggestion with `discover --interactive`, then runs `swift test`
on the original and on each of F3's mutants. The stub runs 100 trials, the generator is
`.derivedComposite`, and all three tests share one seed.

| variant | becomes | C1 `keepsASingleton` | C2 `ignoresADuplicateOfEverything` | `isIdempotent` |
|---|---|---|---|---|
| original | — | pass | pass | pass |
| L162 `seen.insert` deleted | identity | pass | **FAIL** | pass |
| L161 `!seen.contains` negated | `[]` | **FAIL** | pass | pass |
| L163 `result.append` deleted | `[]` | **FAIL** | pass | pass |
| *control: `main`'s binary* | | *not written* | *not written* | *pass ×4* |

Each cell matches the hand-written kill arm (`kill-arm-2026-11-11.json`). C2 here is the equality
form, which the hand-written arm did not run. It failed exactly where the count form did.

## 4. The A/B

`scripts/dedupe_count_laws_ab.py` ran a `swift-infer` built at `main` `0c02caab` against one built from
this change. It used the same flags (`discover --sources <dir> --include-possible`), the same day, and an
empty working directory. It covered the 22 manifest corpora (28 directories), `main`'s own `Sources/` and
SwiftUMLStudio's `SwiftUMLBridge/Sources` at `ef6d77f`. **Every row is the control**: the change adds a
match, a line and a caveat, and nothing else.

| | before | after |
|---|---|---|
| rows printed | 7,879 | 7,879 |
| rows gained / lost / rescored | — | **0 / 0 / 0** |
| rows carrying the route line | 0 | 6 |
| directories void (tree moved) | — | 0 |

Re-taken on the fixed gate (§5). The first run, on the first gate, read 7,877 → 7,877 with the same
6 route lines. The 2 rows between the runs are this branch's own new code: the `swift-infer-core`
corpus is the working tree, and both binaries scanned the same tree each time.

The 6 are **4 functions**. This repository's two are scanned twice, once as the `swift-infer-core`
manifest corpus and once in `main`'s `Sources/`.

| function | route | tier | stub runs? |
|---|---|---|---|
| SwiftUMLBridge `CoreDataModelExtractor.dedupe(relationships:)` | Set | 45 Likely | **yes**: the kill arm, §3 |
| `ConstructionUniverse.deduplicated(_:)` | dictionary | 75 Strong | no: `[Member]` derives no generator, as #711 predicted |
| `EqualityBodyShape.deduplicated(_:)` | Set (filter) | 75 Advisory | no: `private` |
| SwiftLintRuleStudio `YAMLConfigurationEngine.deduplicated(_:)` | Set | 75 Advisory | no: `private` |

These are exactly #711's population table. The census's other admitted rows are not reached, by
design: `dedupedByStateAndAction` and `deduplicateByPropertyName` carry names no template recognises,
and widening the names is out of scope.

## 5. The adversarial review, and what it changed

Four reviewers read the PR through four lenses: false admission, scope fidelity, the emitted stub,
and the claims. Each finding then went to three skeptics told to refute it, by execution where they
could. **11 findings were upheld 3 to 0, and 2 were refuted.** The 11 reduce to six defects. Every
reproduced counterexample is now a test (`DedupeBodyReaderReviewTests`).

| defect | class | reproduced | fix |
|---|---|---|---|
| The dictionary route admitted any `if … { continue }` whose condition **mentioned** `d[k]`, so `d[k] != nil \|\| x < 0`, `x % 2 == 0, d[k] == nil` and `d[k] == nil` passed. C1 is false of each: they filter | **false law** | emitted C1 failed on `NonNegative.dedupe` | the first condition must be a presence test on the written key (`let v = d[k]` or `d[k] != nil`); later conditions are conjuncts and may not name `d` |
| Every `let` in a loop was skipped unread, so `let _ = seen.insert(x)`, `let _ = result.append(x)` and `let _ = id == nil ? seen.remove(nil) : nil` passed. C1 or C2 is false of each | **false law** | emitted C1 failed on `PreBlocked.dedupe`, and C2 on a pass-through | a `let` may not name the set, the result or the dictionary; an insert or `contains` must name the set once, as receiver, and never the result |
| The dictionary "why" line said *written once per key*. The scope (§2.4) refined that wording away, because the route admits a write per element | misleading | — | reworded |
| For an actor's callee the stub dropped C1 and C2 without a word, while the row promised them | misleading | the stub held idempotence alone | written as statements, each call awaited; on the review's actor subject all three laws compile and pass |
| `DedupeBody`'s doc said both laws compare counts, but on the Set route C2 is `==` | misleading | — | doc corrected |
| **Pre-existing, made visible:** a dictionary-route dedupe's idempotence, `f(f(v)) == f(v)`, is false of correct code, because the second call lists the values in another dictionary's hash order. #671 had this REASONED, and the change stated the hash-order reason beside the law | false law (pre-existing) | `byKey[word.lowercased()] = word` failed it in 4 of 4 runs, at an input with no duplicates | on that route the stub states idempotence **without order**: equal counts, and every element of `f(f(v))` is in `f(v)`. It passes now |

Refuted, and fixed anyway because the fix was one line: two appends behind one insert were admitted,
and C1 would see two elements. **A gate now admits one append per element.**

**The review's false-law subjects, run through the fixed binary:** all six still get the idempotence
row they get on `main`, and none gets the route line or the count laws. The control, a clean filter
form, is admitted.

Left as nits:
- the failure label hard-codes `(_:)`, as idempotence's does;
- `Array<T>()` and a filter closure with an explicit `return` are refused although the scope's
  wording admits them. That costs recall, never soundness.

## 6. `verify`: the count laws as companion laws

**The problem.** `verify` reads a `SemanticIndexEntry`, not a `Suggestion`, so the route never
reached it. Its stub states one law per entry, and every consumer keys the verdict by identity. Had
the laws been added to the idempotence pass, a C2 failure would have been filed as
`measured-defaultFails`. Idempotence would then read as refuted, the row would be vetoed, an
idempotence regression test would be banked, and the replay corpus would hold a counterexample
idempotence passes.

**Three designs were weighed, and the user chose companion verdicts.**
- *Verify-only template names* were rejected: discover never proposes those identities, so their
  verdicts would show nowhere.
- *Order-free idempotence only* would have left #711 open.

### 6.1 What was built

| piece | where |
|---|---|
| the route in the index, required on the exhaustive init, from the re-scan in `updated(from:)` | `SemanticIndexEntry.dedupeBody` |
| the route folded into the evidence fingerprint, so a verdict recorded before verify knew it reads as unvalidatable | `SubjectFingerprint.stamped(…, dedupeBody:)` |
| idempotence order-free on the dictionary route, in the main loop and the collision sweep; every other row's stub byte-identical | `StrategistDispatchEmitter.dedupeMismatch` |
| C1 and C2 run once, last, after both of idempotence's passes printed their verdicts, on the default generator as the accepted stub draws: their own RNG stream, a `_BEGIN` per law so a trap is named, never an `exit` | `StrategistDispatchEmitter+DedupeCountLaws.swift` |
| read apart from the exit code; `parse`'s verdict untouched, and a trap inside a companion after both PASS markers keeps `.bothPass` | `VerifyResultParser.companionLaws` |
| carried on the run, the survey record and the evidence, absent from the encoded form when none ran | `CompanionLawOutcome` |
| a default-pass failure withholds the +50 and `Verified`, adds a weight-0 caveat, and never vetoes | `VerifyEvidenceScoring`, `Signal.Kind.verifyCompanionRefuted` |
| accept-check reports it as now-fails; the refactor runner stops calling the run "held"; the regression bridge banks no strict idempotence test on the dictionary route | `AcceptCheck.classify(run:)`, `SpeculativeRefactorRunner`, `emitRegressionTest` |
| the decision record keeps the accepted route, and accept-check re-checks with it | `DecisionRecord.dedupeBody`, `Verify.withAcceptedRoute` |

### 6.2 Why accept-check needs the accepted route

The census's mutants are exactly what a body gate refuses:
- deleting the insert leaves a `contains` with no insert;
- negating the check leaves a test that is not an absence test;
- deleting the append appends nothing.

So `verify` on mutated code finds no route, and correctly stops owing C1 and C2: that code no longer
reads as a dedupe. But a user who accepted the stub banked those laws, and that edit is the
regression they exist to catch. **A gate-driven re-scan cannot follow an accepted law into code the
gate no longer admits**, so the decision record keeps the route, and accept-check re-checks with
it. A route the re-scan finds still wins. Evidence that accept-check stamps with the accepted
route does not match discover's current fingerprint, so discover reads it as unvalidatable.

### 6.3 The kill arm, through the CLI

`scripts/dedupe_count_laws_verify_kill_arm.py` copies the kill arm and adds the library product
`verify` links against (the fixture declares only a target). It then runs `index` and accepts the
row with `discover --interactive`, which records route `set`. For each variant it runs `verify`,
then `accept-check`.

| variant | `verify` verdict | companions (`verify`) | evidence | `accept-check` |
|---|---|---|---|---|
| original | holds (strong), idempotence 1000 + 1000 trials | C1, C2 held | `measured-bothPass`, 2 companions held | still-passes |
| L162 `seen.insert` deleted (identity) | holds | not run: the gate refuses the body | `measured-bothPass` | **now-fails (companion law C2 failed)** |
| L161 `!seen.contains` negated (`[]`) | holds | not run | `measured-bothPass` | **now-fails (companion law C1 failed)** |
| L163 `result.append` deleted (`[]`) | holds | not run | `measured-bothPass` | **now-fails (companion law C1 failed)** |

`VerifyPipelineDedupeCountLawsTests` builds and runs the stub with the route given directly, so it
also covers the case where the gate does admit a buggy body:
- the identity fails C2;
- `{ _ in [] }` fails C1;
- a correct dedupe holds both;
- a dictionary-route dedupe holds the order-free idempotence.

In every case idempotence's verdict stays `.bothPass`.

### 6.4 A second adversarial review, and what it changed

The same panel ran on the verify half: four lenses, three refuting skeptics per finding. **7 findings
were upheld 3 to 0, and 5 were refuted.** The 7 reduce to three defects, all now fixed and tested:

| defect | reproduced | fix |
|---|---|---|
| The first version ran the companions inside the composer, so the edge pass re-ran them. A trap there, for example an edge-only `Negative count` on the doubled input, turned idempotence's PASS + PASS into `measured-error`. An "advisory" law replaced a verdict the run had produced | `bins/before` held; the change gave `measured-error` | the companions run once, last, after both passes. The parser keeps `.bothPass` when both PASS markers are followed by a trap inside a companion. The accepted stub has no edge pass, so agreement needs none |
| accept-check stamped its evidence with the accepted route, so discover's fingerprint never matched. Fresh evidence read as stale, with a false *different body* caveat, and the companion refutation never showed | the caveat claimed a body change that never happened | the evidence is stamped with the re-scanned entry's fingerprint; the run uses the accepted route. On the identity mutant, discover now shows *the primary law held, but C2 FAILED*, at score 45 and not `Verified` |
| A route the re-scan found overrode the accepted one. A keep-first stub states C2 and idempotence with `==`, so a body edited into the dictionary route fails it, while accept-check checked the count form and reported still-passes | still-passes over a failing accepted test | in accept-check the accepted route wins |

Also fixed: the staleness caveat now says a dedupe row's fingerprint can move because of the route
it is verified by, not only its body. Two doc comments I had inserted inside existing ones are
moved.

Refuted:
- docc, `report` and `metrics` reading the bare outcome. These were judged not misleading at this
  population, and they are not changed.
- A default-pass companion trap skipping idempotence's edge pass. This is no longer possible: the
  companions run after it.

**Known limitation.** When idempotence's own edge pass fails, the run exits before the companions.
That outcome is `.edgeCaseAdvisory`, which promotes nothing, so no row gains `Verified` from it. But
accept-check then reports still-passes without having checked C1 or C2.

**Population.** One row reaches a verify verdict on the corpus, SwiftUMLBridge's `dedupe`. Quote
this as one row whose verify run now checks the two laws its accepted stub writes, not as laws
gained.

## 7. Not done, on purpose

- **Widening the names** (`deduped`, `uniqued`, `By<Key>`) and **a dedupe-role template** stay out
  of scope, as #711 says.
- **A receiver form** (`extension Array { func deduplicated() … }`) is not read. Its element is
  unconstrained, so no stub can draw it (#493).
- **A wrong key is invisible** to both laws, and the row says so.

## 8. Reproduce

```
python3 scripts/dedupe_count_laws_kill_arm.py <swift-infer>
python3 scripts/dedupe_count_laws_verify_kill_arm.py <swift-infer>
python3 scripts/dedupe_count_laws_ab.py <before swift-infer> <after swift-infer> <main's Sources> \
  ~/xcode_projects/SwiftUMLStudio/SwiftUMLBridge/Sources
```

Build both binaries with `swift-6.4.1-RELEASE`. The A/B voids a directory whose checkout moves
during the run.
