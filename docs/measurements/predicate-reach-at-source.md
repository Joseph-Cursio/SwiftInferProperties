# Does reach at the source move predicate stubs to BOTH?

> **Status:** `measured` · **As of:** 2026-11-13

**Yes. Both levers SHIP, and together they move net +81 rows to BOTH against the old behaviour** (89 up, 8 down),
taking G, the share of passing predicate rows in the non-teaching repositories (R) whose own 100 draws reach both
answers, **from 41.1% to 58.9%**. The
scope froze the arms, metric and decision rules before any code ran
(`docs/plans/predicate-reach-at-source-scope.md`, #684).
- **Lever 1 ships as `seeded`: net +65** (A2 against A0). A stub's seeds admit up to 8 matching snippets from past
  the 300-snippet cap and bias its draws. Lifting the cap altogether (`uncapped`) netted 19 more, +84 against +65, but
  cost 2.64× seeded's build-and-run seconds on SwiftProjectLint, and §6 ships the whole corpus only at 1.5× or less.
- **Lever 2 ships as pairing: net +16 on top of seeded** (A3 against A2). A drawn `String` sometimes takes a name
  from a drawn syntax node, a `String` collection sometimes holds a drawn `String`, and an equal-typed argument
  sometimes copies an earlier one.
- **No stub that passed before fails, crashes or hangs in the shipped arm.**
- **§6's reopen condition for #665's reach check is met:** under the shipped arm G is 58.9% and G_loo 58.8%, both at
  or above #665's W floor of 0.50. Building the check is a follow-up issue, not this one.

A row reaching BOTH is not a law gained, and no kill is measured: the claim is only that a passing law's draws now
exercise both outcomes, so its pass says more. The population is this corpus, never a rate.

## The arms

One binary (`62f10aa8`), one hidden switch, `SWIFT_INFER_REACH_ARM`, now removed. Every arm ran the same 19
repositories at the same pins through `scripts/reach_arms.py`, each repository with the same kit and toolchain in every
arm: kit 4.11.0 except SwiftUMLStudio's 4.10.0; swift.org's swift-6.4.1, and Xcode's `swiftlang-6.4.2.1.9` for the six
repositories the funnel builds with Xcode (amendment A2).
SwiftFormatRuleStudio is at `61cfea1`, its tokenizer fix, in every arm (amendment A5).

| arm | switch | what it does |
|---|---|---|
| A0 | `baseline` | the first 300 harvested snippets, drawn uniformly; no pairing |
| A1 | `uncapped` | every harvested snippet, drawn with the seed bias |
| A2 | `seeded` | the 300, plus up to 8 seed-matching snippets per stub from past the cap, drawn with the seed bias |
| A3 | `seeded+paired` | A2, plus relational pairing of drawn arguments |

**A3 withholds one law** (amendment A6, user-approved): SwiftLintRuleStudio's `SystemXcodeLauncher.open(_:)` calls
`NSWorkspace.shared.open(url)` on every trial, about 4,500 calls across A0–A2. It is ONLY-TRUE in A0, A1 and A2, at
100 and 1,000 draws, so it cannot move to BOTH, and in A2 → A3 it shows as disappeared, which never enters the net.

## Results

| pair | net to BOTH | up | down | G before → after | decided |
|---|---|---|---|---|---|
| A1 against A0 | **+84** | 94 | 10 | 41.1% → 59.6% | not shipped (cost) |
| A2 against A0 | **+65** | 72 | 7 | 41.1% → 55.4% | **lever 1: seeded** |
| A3 against A2 | **+16** | 17 | 1 | 55.4% → 58.9% | **lever 2: ships** |
| A3 against A0 | +81 | 89 | 8 | 41.1% → 58.9% | the shipped whole |

**The lever-1 rule (§6).** Both arms clear +10, so one ships. `uncapped` ships only if it moves at least 10 more rows
than `seeded` (it moves 19 more) **and** costs at most 1.5× seeded's SwiftProjectLint build-plus-run seconds. It
cost 176.6 s (20.4 + 156.2) against 66.8 s (22.8 + 44.0), 2.64×, so seeded ships. The whole corpus is about 11×
the snippets: 3,226 per SwiftProjectLint corpus file against seeded's 320 to 598.

**The lever-2 rule (§6).** It ships at +5; it moved +16. All 17 up rows and the 1 down row are relational:
- 11 net in SwiftProjectLint;
- 3 in SwiftUMLStudio;
- 1 each in SwiftEffectInference and SwiftPropertyLaws.

The down row is SwiftProjectLint's `StringReceiverEvidence.isString(_:at:)`. Pairing changed its draws: at the
100-draw metric it now reaches only `false`, though at 1,000 draws it still reaches both.

**Where lever 1 moved.** 63 of seeded's net +65 are SwiftProjectLint's (97%), and 64 are syntax-corpus rows. The
rows that appeared in R, 8 in every lever-1 arm, are stubs that only now compile. Their node types (`SwitchExprSyntax`,
`IfExprSyntax`, `CatchClauseSyntax`, `IfConfigDeclSyntax`) occur only past the cap, so the old corpus could not draw
them. They never enter the net.

**The funnel.** 1,649 stubs in A0 to A2, 1,648 in A3 (the withheld law):

| arm | compiled | passed | failed | crashed | hung |
|---|---|---|---|---|---|
| A0 | 986 | 816 | 127 | 42 | 0 |
| A1 | 996 | 826 | 127 | 42 | 0 |
| A2 | 994 | 824 | 127 | 42 | 0 |
| A3 | 993 | 823 | 127 | 42 | 0 |

**New failures, hand-checked: none to check.** No stub that passes in A0, or in A2, fails, crashes or hangs in A3.
The memory guard killed nothing in any census, nor in any funnel after A5's re-run. Before that re-run it killed
SwiftFormatRuleStudio's tokenizer totality test at `5cea6a7` in A0, A1 and A2; that is the defect A5 moved the pin
past.

**At 1,000 draws**, the scope's second reading, rows of R reaching BOTH are 241 of 467 (A0), 333 of 475 (A1), 315 of
475 (A2) and 332 of 474 (A3). They rank the arms the same way as the 100-draw metric.

### The frozen predictions (§7)

| # | prediction | result | held? |
|---|---|---|---|
| P1 | `net(A1, A0)` in [40, 90] | +84 | yes |
| P2 | `net(A2, A0)` in [40, 90], and within 15 of A1 | +65, 19 apart | **no**: the gap is 19 |
| P3 | lever 1 decides `seeded` | seeded | yes, on the cost clause |
| P4 | `net(A3, A_w)` in [8, 20], and lever 2 ships | +16, ships | yes |
| P5 | G under the shipped arms in [0.50, 0.60]; G_loo ≥ G | G 58.9%; G_loo 58.8% | **half**: G_loo is 0.1 point below G |
| P6 | at least 70% of lever 1's net is SwiftProjectLint's | 63 of 65 | yes |
| P7 | new real failures 0–3, new false failures 0 | 0 and 0 | yes |
| P8 | A1's SwiftProjectLint corpus ≥ 8× A0's; A2's ≤ 3× | 10.8×; at most 2.0× | yes |
| P9 | funnel compiles within ±5 of A0 in every arm | +10, +8, +7 | **no**: every extra compile has a node type only past the cap |

**P9 missed by design, not disturbance.** The scope expected lever 1 to leave compiles alone. But a stub whose node
type occurs only past the cap compiles once its type is in the corpus, and every such stub passes:
- A2's +8 are the 8 predicate stubs that appeared in R;
- A3's +7 are the same 8, less the withheld law;
- A1's +10 are those 8 plus 2 non-predicate stubs that only the whole corpus reaches: a `guard-domain` stub on
  `SameTypeRequirementSyntax` and a `measure-non-negativity` stub on `GenericArgumentClauseSyntax`.

## What shipped (the cleanup commit)

The switch and the losing modes are gone (`ReachArm` deleted). `SyntaxCorpusSource` always works as `seeded`:
- the 300 base snippets;
- seeded admission past the cap, at most 8 per stub, first matches in file order;
- the draw bias;
- the merge that keeps earlier processes' admissions.

Every corpus file carries the reach machinery. `totalityStub` always applies `DrawPairing.plan`, leaving `inout`
arguments unpaired. `SyntaxCorpusSeededDrawTests` pins both defaults.

**Checked byte for byte.** The cleaned binary, with no switch set, ran the funnel over SwiftEffectInference at its
pin. It wrote the same 42 generated files as A3's tree, with a diff of 0 lines, and 15 of them use the seed bias or
a pairing. The funnel line matched too: 60 stubs, 40 compiled, 38 passed, 1 crashed.

**`scripts/reach_arms.py` still sets the switch, and now refuses a binary that cannot read it.** A later binary runs
`seeded+paired` whatever it is told, so the script stops rather than record another arm's label on those rows. To
reproduce an arm, use binary `62f10aa8` and CLI `6a231cda`, which `decisions.log` records with each fixture's sha256.

## Ledger

`fixtures/predicate-reach-at-source/`:
- `A0.jsonl`–`A3.jsonl` are the reach census per arm, 491, 499, 499 and 498 rows;
- `decisions.log` holds the two DECISION lines.

`python3 scripts/predicate_outcome_reach.py compare <A> <B>` prints every moved row; the A2 → A3 up rows are:

<details><summary>The 17 rows lever 2 moved up, and the 1 it moved down</summary>

| repo | subject |
|---|---|
| SwiftEffectInference | `ConstructionFacts.isShadowed(_:at:)` |
| SwiftProjectLint | `BooleanControlCouplingVisitor.assignsAsFinalStatement(_:to:)` |
| SwiftProjectLint | `CatchWithoutHandlingVisitor.containsReference(to:in:)` |
| SwiftProjectLint | `DemeterChainFilter.isNonExemptChain` |
| SwiftProjectLint | `DirectInstantiationVisitor.isExemptDefinitionSite(_:on:)` |
| SwiftProjectLint | `MainActorMissingVisitorBase.hasAttribute(_:named:)` |
| SwiftProjectLint | `MainActorTypeTable.hasAttribute(_:named:)` |
| SwiftProjectLint | `NonInjectedNondeterminismVisitor.isWriteBack(_:to:in:)` |
| SwiftProjectLint | `PureMutatorCandidateVisitor.reachesImpureCallee` |
| SwiftProjectLint | `URLSessionUnhandledErrorVisitor.containsReference(to:in:)` |
| SwiftProjectLint | `VariableShadowingVisitor.initializerReferences(name:in:)` |
| SwiftProjectLint | `VariableShadowingVisitor.sequenceReferences(name:in:)` |
| SwiftProjectLint | `conformsToAny(_:protocols:)` |
| SwiftPropertyLaws | `EnvironmentRelaxation.matches(expected:actual:)` |
| SwiftUMLStudio | `ERModelExtractor.hasAttribute(_:named:)` |
| SwiftUMLStudio | `String.isMatching(searchPattern:)` |
| SwiftUMLStudio | `TypeSyntax.names(_:bareOrIn:)` |
| *down* SwiftProjectLint | `StringReceiverEvidence.isString(_:at:)` |

</details>

## Not answered

- **Receiver state** (#665 §6.1): a constructed receiver is fresh, so a predicate reading accumulated state stays
  constant. No lever here touches it.
- **Single-line literals**, which the harvester skips by design; SwiftEffectInference's needed tokens sit there.
- **The reach check itself.** Its reopen condition is met (above); building it is a separate issue.
- **The trial budget, and verify's predicate composer.**
