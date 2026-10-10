# Scope: should `unknown-action-is-no-op` require evidence that the alphabet is open?

> **Status:** `proposed` · **As of:** 2026-10-10

#661 stopped the family firing on a closed enum: discovery now resolves each reducer's Action type
(`ActionTypeKind`) over the scanned sources, and an `enum` closes the alphabet. Everything not proven
closed still fires — a protocol, a struct, and any type declared outside the scan. On the manifest
that is 269 rows. This scope asks whether the family should instead require evidence that the
alphabet is open, and finds the question is smaller than the flood it sits in.

## 1. What is already measured

Re-tabulated from #661's before/after runs of `discover-reducers` (2026-10-10, same trees). No row has
been hand-checked yet.

| | reducer-shaped functions | `determinism` rows | `unknown-action-is-no-op` rows |
|---|---|---|---|
| manifest, 18 of 21 subjects (21 scan roots) | 274 | **274** | **269**: 179 unresolved · 73 struct · 17 protocol |
| in-repo reducer fixtures (`Tests/Fixtures/`) | 95, of which 65 TCA | 30 | **2**, both protocol: the family's own corpus |

- **The 179 unresolved:** 86 stdlib or Foundation value types (`String`, `Int`, `Decimal`, …), 44
  collections, tuples, optionals and function types, 31 generic types, 12 other named types, 6 `Self`
  in a protocol extension.
- **The 17 protocol rows are all `some P` generic parameters**: 11 `some SQLExpressible` (GRDB), 2
  `some AttributedStringProtocol`, 2 `some Sequence<Element>`, 1 `some RangeReplaceableCollection<Element>`,
  1 `some _RowLayout`.
- **Carriers:** 258 `generic`, 10 `elm-style`, 1 `reswift`. The `reswift` row is
  `Bundle.preferredLocalizations([String], [String]?) -> [String]`.

## 2. What the measured check can reach

The verifier declares `struct __UnknownActionProbe: <ActionType> {}` and applies it
(`ActionSequenceStubEmitter+UnknownAction.swift`). That compiles only when the Action type is a protocol
an empty struct can satisfy, spelled bare or `any P`. It cannot compile for an enum, struct, class,
stdlib value type, tuple or function type, and `some P` is not legal in an inheritance clause at all.
A failed build is recorded as `architectural-coverage-pending`, not as a verdict.

Every such row still costs a build: `verify-interaction --all` surveys every discovered identity with
no tier cut (`VerifyInteractionSurvey.collectEntries` filters by family only).

**By inspection, not by measurement, none of the 269 manifest rows is measurable.** The 17 protocol
rows are `some P` over protocols with requirements, and the rest are not protocols. Prediction 2
tests this.

## 3. The flood the gate would sit on

`determinism` fires on all 274 manifest rows, and most of them are not reducers:

- operators (`AssociationAggregate.<`) and combinators (`Anchor.strongest`);
- protocol requirements read as free functions — `Semigroup.combine` and `Ring.add` render as
  `elm-style`, because discovery never pushes a protocol onto its type stack (**fixed after this
  scope was written**: see §8);
- shape matches — `Bundle.preferredLocalizations` is labelled `reswift` without the file importing
  ReSwift, where the TCA walk requires `import ComposableArchitecture`.

An alphabet gate removes one of the two rows each such function carries and leaves `determinism`'s.
That is the [Daikon trap](../design-internal/glossary.md#daikon-trap)'s "filter on top of a flood". The
bigger lever is whether `discover-reducers` recognises reducers in library code at all. That question
is out of scope here except as arm 1's by-product.

## 4. Options

| | Admits | Manifest rows | Fixture rows | What it costs |
|---|---|---|---|---|
| **A. Status quo** (#661) | anything not proven closed | 269 | 2 | Every manifest row is unmeasurable; the caveat says so, and the survey still builds each one |
| **B. Positive evidence** | `.protocol` only | 17 | 2 | Keeps the 17 unmeasurable `some P` rows. Drops ReSwift's imported `Action` (unresolved), the family's motivating case, unless that is special-cased |
| **C. Measurability** | a protocol the probe can conform to: spelled bare or `any P`, declared in the scanned sources with no unmet requirements, or the `.reSwift` carrier's `Action` in a file that imports ReSwift | 0 by inspection | 2 | Drops an open alphabet declared in another module, and retires the doc's "String/opaque dispatch" clause |
| **D. Threshold** (the PRD's remedy) | everything, scored below 20 unless protocol | 269, hidden in `discover-interaction` | 2 | `discover-reducers`' render shows every candidate regardless of score, and the survey has no tier cut, so nothing stops being built |

**Recommendation: C, after the arms below.** Its whole cost is on the recall side, which no registered
corpus can measure.

**Why C is not a filter on a flood.** C does not hide rows for being numerous. It makes the family's
eligibility equal its instrument's precondition. A row C removes has no refutation path in this tool,
and this repo scores refutability, not suggestion count.

**What C gives up, named.** A String-dispatch reducer's `reduce(s, unknown) == s` is a real property
that this instrument cannot state. C drops it rather than proposing it unmeasurable.

**What building C involves:**
- record, per declared protocol, whether an empty struct can conform: no requirements of its own, and
  only protocols the compiler synthesises for an empty struct (`Equatable`, `Hashable`, `Sendable`,
  `Codable`) inherited;
- tell `some P` apart from `any P` and a bare name, which `ActionTypeKind` currently folds together;
- add the ReSwift case, with an import check like the TCA walk's;
- gate both consumers on the result, and update the rationale text.

Reading requirements is the only real design question.

## 5. Measurement

- **Arm 1, precision.** Hand-classify all 269 manifest rows: (i) not a reducer, (ii) a reducer with a
  closed alphabet, (iii) a reducer with an open alphabet. Freeze the key before C is built. The 30
  fixture rows need no hand-check, because their corpora were written to a design.
- **Arm 2, verify reach.** `verify-interaction --all --family unknown-action-is-no-op` on GRDB, whose
  40 rows span all three kinds (9 unresolved, 12 protocol, 19 struct). The control is the in-repo
  `unknown-action-corpus`, already run by `make batch7`.
- **Arm 3, recall.** No registered corpus contains an open-alphabet reducer, and a zero from an
  unscreened pool is not evidence. Screen ReSwift and apps built on it: count reducers over an open
  alphabet, and how many declare that alphabet outside the module `--target` scans
  (`DiscoverInteractionCommand+MultiModule` resolves per root).

## 6. Predictions

Written before any arm runs.

| # | prediction |
|---|---|
| 1 | arm 1: **≥ 95%** of the 269 manifest rows are not reducers, and **0** are reducers over an open alphabet |
| 2 | arm 2: **0 of 40** GRDB rows reach a verdict, every one a build failure; the corpus control still splits 1 bothPass + 1 defaultFails |
| 3 | arm 3: at least one screened subject carries **≥ 3** reducers taking ReSwift's `Action`, and C keeps all of them |
| 4 | arm 3: **< 10%** of the open-alphabet reducers found declare their alphabet outside the scanned module |
| 5 | C built: manifest **269 → 0**, fixtures **2 → 2**, every `make test` batch baseline unchanged |

## 7. What would change the recommendation

- Arm 1 finds open-alphabet reducers among the unresolved or struct rows. C then costs recall that A and
  D do not.
- Arm 2 finds a non-protocol row that reaches a verdict. The measurability premise in §2 is then wrong.
- Arm 3 finds alphabets usually declared in another module. C then needs cross-module resolution first.
- Arm 1 confirms the rows are non-reducers. C is still right for this family, but the larger fix is
  recognition (§3), and it should come first.

## 8. Not answered here

- **Reducer recognition precision on library code** (§3): both redux families fire on every match.
- **Protocol requirements discovered as free reducers**: a discovery defect, recorded separately.
  **Fixed 2026-10-10** (`ReducerDiscoveryVisitor.protocolDepth`). Over the same manifest trees,
  10 requirements left the scan, each taking both of its rows: reducer-shaped functions 274 → 264,
  `determinism` 274 → 264, `unknown-action-is-no-op` 269 → 259. Fixtures did not move. The figures
  and predictions above are left as written; arm 1's population is now 259 rows.
- **String-dispatch reducers**: their property is real, and stating it needs a different probe
  (an unrecognised value of the dispatch type), not a different gate.
