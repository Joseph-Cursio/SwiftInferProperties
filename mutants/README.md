# Mutation / regression corpus (private)

A hand-authored mutant corpus for **sharpening the inference engine itself**
(Chapter 30 §30.4.4). Three families:

- **Idempotence witnesses.** Mutants in the `IdempotenceWitnessDetector`'s pure
  name-classifier — the logic that decides whether an action name (`reset`, `setColor`,
  `increment`, …) is an idempotence witness.
- **Name-only positions.** Each mutant undoes one guard that keeps a key-path
  component's name (`\.name`) or a member's name (`job.name`, `.red`) from being read
  as a test-local binding (`DeclReferenceExprSyntax+NameOnlyPosition`).
- **Construction facts.** Each mutant undoes one piece of wiring SEI's `ConstructionFacts`
  into the scan — the table, the trees it was built from, the getter path, the universe rule
  and its shared-spec amendments, the scans that must build no table, the census replica's
  construction witness.

Each is killed by its own code's unit tests, which pin both what it *should* do and what
it *should not*. Not a scored benchmark — no frozen answer key.

Each mutant is a reversible patch (`patches/<id>.patch`). The runner applies one,
builds, runs its named killer test via `swift test --filter`, checks the outcome,
and reverts.

## Run

```sh
mutants/run-mutants.sh                    # all mutants
mutants/run-mutants.sh witness-drops-reset
```

Requires a clean working tree.

## The corpus (`manifest.json`)

| id | shape | expected | killer |
|---|---|---|---|
| `witness-drops-reset` | witness-recall | killed | `classifyExactNames` |
| `witness-admits-increment` | witness-precision | killed | `classifyNonMatching` |
| `witness-prefix-drops-set` | witness-recall | killed | `classifyPrefixes` |

Dropping `reset` makes the detector miss a real idempotence witness; adding
`increment` makes it claim a non-idempotent action as one (a false witness would
seed a property that can't hold); dropping the `set` prefix loses the `setX`
assignment family. Recall on two sides, precision on the third. All three verified
killed.

| id | shape | expected | killer |
|---|---|---|---|
| `harvester-keypath-name-is-local` | name-only-position | killed | `keyPathComponentNameIsNotALocal` |
| `harvester-inlines-keypath-name` | name-only-position | killed | `keyPathComponentNameIsNotInlined` |
| `slicer-collects-name-only-positions` | name-only-position | killed | `SlicerNameOnlyPositionTests` |
| `binding-rewriter-substitutes-keypath-name` | name-only-position | killed | `bindingNamedLikeAKeyPathComponentIsNotSubstituted` |
| `trace-initial-state-counts-name-only-positions` | name-only-position | killed | `keyPathAndMemberNamesAreNotLocals` |
| `trace-skips-every-member-name` | name-only-position | killed | `testTargetMembersAreLocals` |
| `trace-self-is-not-local` | name-only-position | killed | `testTargetMembersAreLocals` |
| `binding-rewriter-skips-subscript-arguments` | name-only-position | killed | `subscriptArgumentSubstitutedSelfMemberNot` |
| `harvester-skips-subscript-arguments` | name-only-position | killed | `keyPathSubscriptArgumentIsInlined` |

Each puts back one site's old reading. The first `ReceiverConstructionHarvester`
mutant refuses `Sorter(by: \.name)`; the second copies
`Pager(sortedBy: \.10, pageSize: 10)`. The `Slicer` pulls an unrelated `let id = 7` into
the property region through `.map(\.id)` and `{ $0.id }`. `LocalBindingResolver` builds
`\.makeID()`, a key-path component whose `declName` slot holds a call.
`MinedTraceSelector` drops `Feature.State(color: .red)`.

The last four guard the other direction, the over-correction. A selector that skips
every member name keeps `Feature.State(items: Self.fixtureItems)`, a static only the
test target declares, and the verifier stub it is pasted into fails to build; one that
reads `Self` as a type keeps `Self.Fixture()`. A rewriter that skips everything inside
a key path stops substituting `\.[id]`, whose argument is evaluated. All nine verified
killed.

| id | shape | expected | killer |
|---|---|---|---|
| `scan-drops-construction-facts` | construction-facts | killed | `siblingTargetConstructionRefutes` · `ConstructionFactsPipelineTests` |
| `scan-reparses-universe-trees` | construction-facts | killed | `scanJudgesOnTheFactsOwnNodes` |
| `universe-admits-tests` | construction-universe | killed | `testFileNamesakeDoesNotRefute` |
| `test-dir-scan-walks-up` | construction-universe | killed | `testDirectoryScanIsSelfContained` |
| `census-replica-blind-to-construction` | census-replica | killed | `classificationAgreesWithSEIWitness` |

The construction-facts family (2026-10-06) undoes one piece of the wiring each. The first
builds the project's table and hands the visitor the unconfigured oracle anyway — a table
built and dropped, which no type checker objects to. The second re-parses every judged file;
SEI types an assignment by node identity, so `reset` in one target is refuted by another
target's same-named `A`. The third lets a test target's `Item` into the production table; the
fourth walks a `Tests/Fixtures/X` scan up to the package, whose rule drops the fixture's own
files. The last blinds the census replica to SEI's construction witness: 0 verdicts move on
`Sources/`, so `verdictAgreesWithSoundPurity` stays green, and only the classification guard
sees the 2 re-witnessed rows filed as ignorance. All five verified killed (the first three
re-anchored after the universe rule changed).

| id | shape | expected | killer |
|---|---|---|---|
| `getter-ignores-construction-facts` | construction-facts | killed | `getterConstructingASiblingTypeIsRefuted` · `constructionFacts_refuteEveryAnswer` |
| `universe-order-not-string-lt` | construction-universe | killed | `universeOrderIsStringLessThan` · `buildOrderIsTheSharedOrder` |
| `universe-takes-every-nested-package` | construction-universe | killed | `unreferencedNestedPackageIsOutside` · `nearestManifestDecides` |
| `nested-doubt-includes-nothing` | construction-universe | killed | `doubtIncludesAll` · `doubtfulRootIncludesEveryNestedPackage` |
| `nested-closure-stops-at-one-hop` | construction-universe | killed | `transitiveClosure` · `referencedNestedPackageIsInside` |
| `manifest-reader-reads-every-path-argument` | construction-universe | killed | `manifestCasesHold` |
| `universe-dedup-keeps-first-seen` | construction-universe | killed | `deduplicationKeepsTheSmallestPath` |
| `universe-admits-non-utf8` | construction-universe | killed | `nonUTF8FileIsNotInTheUniverse` |
| `universe-root-found-resolved` | construction-universe | killed | `symlinkedTargetSeesItsRealSiblings` · `linkIntoAnotherPackageIsJudgedWhereTheLinkIs` |
| `purity-built-for-empty-judged-set` | construction-facts | killed | `purityIsBuiltOnlyForAJudgedSet` |
| `declarations-scan-skips-cross-file-hop` | construction-facts | killed | `declarationsOnlyScanMatchesTheFullScan` |
| `staleness-ignores-universe-manifests` | construction-facts | killed | `unreferencedNestedPackageIsNotWatched` |
| `speculative-snapshot-copies-sources-only` | construction-facts | killed | `customPathTargetStaysInTheSnapshot` · `examplesNamesakeStaysInTheSnapshot` |

The second construction batch (2026-10-06, after the adversarial review) adds one mutant per
fix the review asked for. The getter mutant is the review's own: the getter path judged with a
fresh unconfigured inferrer survived every test, fast and batch, because every fixture subject
was a function. The order mutant is the review's too: `localizedStandardCompare` instead of
`String <` stayed green while the fixtures' paths sorted alike under both. Six undo one clause
of the shared spec's amendments — the nested-package bound, its doubt rule and its
transitivity, the manifest reader, smallest-path dedup, strict UTF-8 — and one finds the root
from the resolved path, which judged a symlinked target at its destination. The rest undo the
scope fixes: a purity built for an empty scan, a declarations-only scan that drops the
cross-file precondition hop, a staleness probe blind to the manifests that decide the bound,
and a speculative snapshot that copies `Sources/` alone. `scan-reparses-universe-trees` now
also names `scanReusesTheFactsTrees`, which kills it on its own since it was given the
node-identity subject.

## Adding a mutant

1. Make the buggy edit; 2. `git diff -- <file> > mutants/patches/<id>.patch`;
3. `git checkout -- <file>`; 4. add an entry to `manifest.json`.
