# What does the uniquifier template propose over the census's population, and do its stubs hold and refute where they should? — 10 of the census's 13 gated rows proposed, the 2 it measured declined, nothing outside them; a real defect refuted, a correct allocator held (#692, #669)

> **Status:** `measured` · **As of:** 2026-11-11
>
> **Built:** `UniquifierTemplate` (#692), on branch `uniquifier-template`. It proposes #669's law at the
> Possible tier, behind `--include-possible`. Run over the census universe it proposes **10 of the 13 rows the
> census gated, all 10 owing the law by the census's verdicts**, declines the **2** the census measured
> (a setup call and a recycling pool), and proposes **nothing outside the census's gated rows**. On real code
> its stub **refutes** SwiftPlantUML's defective `uniqName` and passes once the defect is fixed, and **holds**
> on SwiftUMLStudio's `NodeIdAllocator` while killing a planted mutant. The run found three defects in the
> template before this doc was written, all fixed (§3).

#669 asked for a law the catalogue could not state: a **uniquifier**, state that hands out names and remembers
them, owes *one receiver, n calls, n distinct results*. A **memoizing** one owes *equal keys give equal ids,
distinct keys distinct ids*. The census (`docs/measurements/uniquifier-law-census.md`) decided BUILD, and #692
is that build, carrying the seven conditions the census measured. This doc reports what the built template does
over the census's own population, and what its stubs do when run.

## 1. What was built

| piece | where | what it does |
|---|---|---|
| body reader | `Sources/SwiftInferCore/UniquifierShapeReader.swift`, `UniquifierBody*.swift` | #669's criteria 2 and 3: a syntax-tree port of the census's cues (scope §1.2), TEST ∧ (TIED ∨ RETEST) ∧ WRITE. It also reads the decoration's spelling, the guard's sentinel and the memoizing early return. |
| sibling facts | `StateWrites`, recorded per method | the stored chains each non-static method writes and removes from |
| template | `Sources/SwiftInferTemplates/UniquifierTemplate.swift` | criterion 1 (a class method, a `mutating` method or an `inout` collection), the two declines, the Possible tier |
| stub writer | `LiftedTestEmitter+Uniquifier.swift`, `InteractiveTriage+AcceptUniquifier.swift` | one receiver per trial, colliding draws, a failure naming the two calls that collided |
| witness | `Tests/SwiftInferCLITests/UniquifierStubCompiledWitness.swift` | the stubs accept writes, compiled and run in the fast suite (§4) |

How #692's seven conditions were met:

1. **Setup calls: declined.** A sibling method that writes a chain the function tests, and is not itself a
   uniquifier, is read as a setup call (SwiftUMLStudio's `reserveIdentifiers` beside `uniqName`). Declining
   was chosen over stating the law after the call, because the call's arguments cannot be filled mechanically.
   Two issuers over one state (MermaidKit's `registerCluster` and `openSubgraph`) are not each other's setup call.
2. **Access: not declined.** The existing pipeline's access caveat applies, as for every template. `uniqueCaseName`
   is proposed with its `private` caveat. Whether that caveat names its visible caller, `emit`, was not checked.
3. **Colliding draws: yes.** Half the trials draw 1–16 names over `a` and `b`, bare or with the body's
   decoration (`0`, `1`, `2`, `10`, `11` for a counter, `_0`… for an underscore prefix, `_`, `__` for appended
   text). Half draw a dense 11–24 over `a`, `a1`, `b`, `b1`, so a counter reaches 10 within one trial.
4. **The memoizing form: yes.** An early return of a lookup on a tested base, bare or inside what is returned,
   takes the memoizing law.
5. **A dependent domain: yes, for a reserving initializer.** When the owner has an initializer whose every
   parameter is a collection of `String`, the stub builds the receiver from the drawn names
   (`NodeIdAllocator(reserving: names)`). This was found by running the stub (§3).
6. **Counter-only generators: outside the gate, as measured.** swift-foundation's `addCapture` is not proposed.
7. **One receiver per trial: yes.** It is bound once with `let` or `var`, never through `HeldReceiver`.
   **Hand-built arguments: a placeholder.** When the name does not enter through one `String` parameter, each
   argument is left as `<#T built from `name`#>`, and the stub does not compile until a reader fills it.

**Also declined for now:** `async`, `throws` and actor methods, since the stub calls the subject synchronously,
and a subject isolated to a global actor (no stub is written).

**Declines are silent.** Like every template's gate, a declined subject produces no suggestion and no output.
The reason is available as `UniquifierTemplate.declineReason(for:siblings:)`, which the run below records.

## 2. The template over the census universe

`fixtures/uniquifier-law/template-run/` is a harness that walks each of the census's 126 subjects with the
census's skip rules (scope §2) and records, for every function the reader shapes, whether the template proposes
it, declines it, or finds no state kept across calls. It also records whether `TemplateRegistry.discover` keeps
the suggestion after the pipeline's own vetoes. Output: `fixtures/uniquifier-law/template-run-2026-11-11.json`.

**The universe is not the census's exactly.** Read it as today's checkouts:

- **70 subjects are at revisions other than the census's.** Each record carries both revisions.
- **4 subjects were remapped.** `swift-infer-core` and three fixture subjects lived in a `SwiftInferProperties-669`
  worktree that no longer exists, so they were read from this checkout.
- **8 wide directories are gone** and read as zero files: aider, Checkout, Hudson_ProSwiftUI_1_1, Hummingbird,
  IdempotencySpike, muter-upstream, Sitrep and swift-aws-lambda-runtime.
- **The run predates one fix.** It was taken at `614daddd`, before the reserving-initializer fix (§3). That fix
  changes what a stub builds, not which rows are proposed.

**Every row the reader shaped** (14). All 13 of the census's GATED rows are among them; `uniqueCaseName` has moved
from line 158 to 157:

| group | subject | function | census | template | form | runnable name |
|---|---|---|---|---|---|---|
| decision | swift-syntax | `PluginMacroExpansionContext.makeUniqueName` | GATED, UNIQUIFIER | **proposed** (35) | instance | yes |
| decision | swift-syntax | `BasicMacroExpansionContext.makeUniqueName` | GATED, UNIQUIFIER | **proposed** (35) | instance | yes |
| decision | swift-package-manager | `DOTManifestSerializer.label` | GATED, UNIQUIFIER | **proposed** (25) | mutating | no |
| decision | swiftlang-swift | `PropertyListSerializer.id(of:)` | GATED, MEMOIZING | **proposed**, memoizing (25) | instance | no |
| decision | SwiftUMLStudio | `DiagramIdentifiers.id` | GATED, MEMOIZING | **proposed**, memoizing (25) | mutating | no |
| decision | SwiftUMLStudio | `NodeIdAllocator.issue` | GATED, UNIQUIFIER | **proposed** (25) | mutating | yes |
| decision | this repository | `ViewModelActionEnumEmitter.uniqueCaseName` | GATED, UNIQUIFIER | **proposed** (35) | inout | no |
| decision | SwiftUMLStudio | `DiagramContext.uniqName` | GATED, SETUP | **declined**: SETUP, `reserveIdentifiers` | — | — |
| decision | swift-foundation | `AutoDictionary.insert` | GATED, NOT-UNIQUIFIER | **declined**: RECYCLING, `remove` | — | — |
| decision | swiftlang-swift | `Code.withCompletionTokensReplaced` | candidate, not gated | no state | — | — |
| wide | SwiftPlantUML | `PlantUMLContext.uniqName` | GATED, owes | **proposed** (35) | instance | no |
| wide | swift-crypto | `ARC.PresentationState.update` | GATED, owes | no state: it `throws` | — | — |
| layout | MermaidKit | `DOTParserImpl.registerCluster` | GATED, owes | **proposed** (25) | instance | yes |
| layout | MermaidKit | `MermaidParser.openSubgraph` | GATED, owes | **proposed** (25) | inout | no |

**In short:**

- **Proposed: 10 rows, and the census says all 10 owe the law.** Both memoizing rows take the memoizing law. All
  10 survive `discover`'s own vetoes.
- **Declined: 2 rows, both as the census measured.** The census marked `uniqName` SETUP and `AutoDictionary.insert`
  NOT-UNIQUIFIER (the census gate's one miss).
- **Missed: 1 gated row, by design.** swift-crypto's `update` owes the law but `throws`, which v1 leaves out.
- **Outside the census's gated rows, nothing is proposed.** The one other shaped row keeps no state.
- **4 of the 10 proposals get a stub that runs as written**: the two `makeUniqueName`s, `NodeIdAllocator.issue`
  and `registerCluster`. The other 6 take their name through something other than one `String`, so their stubs
  carry a placeholder.

Since the template proposes no row the census did not gate, and declines the census gate's one false row, its
precision over this universe is the census's judged precision on the rows it keeps: **10 of 10**. That is
measured against the census's judged verdicts. It is not a fresh hand-check.

## 3. What running the template found in itself

Each of these was found by running the template over real code, not by reading it. Each is fixed in this
branch, with a test from the real body.

- **A false setup decline (`614daddd`).** swift-syntax's `BasicMacroExpansionContext.makeUniqueName` tests
  `sharedState.uniqueNames`, and its sibling `detach` writes `sharedState.detachedNodes`. Comparing *bases*
  (`sharedState`) read two members of one shared object as one state and declined a uniquifier the census judged
  EXPRESSIBLE. Sibling writes are now compared by *chain*: a write overlaps a test when one chain is, holds or
  lies inside the other.
- **A memoizing body given the plain law (`614daddd`).** swiftlang's `PropertyListSerializer.id(of:)` returns its
  stored id inside a literal (`return "\"\(id)\""`), so the memoizing early return was missed. The plain law is
  false on a memoizing body: the same key twice returns one id. A return that names the bound id now counts.
- **A stub false on correct code (`1505e848`).** SwiftUMLStudio's `NodeIdAllocator`, built with nothing reserved,
  issued `a_1` twice for `a`, `a`, `a_1`. This is #692's condition 5. Its contract owes distinct results only over
  the names it reserved, so the stub now builds the receiver from the drawn names.

## 4. The stubs, run

**In the fast suite (`UniquifierStubCompiledWitness`).** The stubs accept writes for five subjects are held byte
for byte in a compiled test file. Four are correct, and their stubs compile and pass:

- a class;
- a `mutating` memoizing struct;
- an `inout` function;
- a reserving allocator.

The fifth is #669's defect, and its stub, run under `withKnownIssue`, fails with `uniqName(_:) issued one result
twice: calls 4 and 6, on b and b1, both returned b1`.

**On real code.** Both runs used the stub text accept writes, inside the subject's own test target, against
PropertyLawKit 4.10.0. That is the last kit on swift-syntax 602, which SwiftUMLBridge requires. The trial files
and manifest changes are in `fixtures/uniquifier-law/template-run/trials/`.

| subject | revision | expected | result |
|---|---|---|---|
| SwiftPlantUML `PlantUMLContext.uniqName`, placeholders filled as the census's repro builds them | `0f5875e` | refute | **refuted**: `calls 3 and 15, on a1 and a, both returned a10`. The dense stratum's two-digit counter collides `a1` + `0` with `a` + `10`. |
| the same, with the census's fix (`upstream-repro/swiftplantuml/uniqName-distinct-aliases.patch`) | `0f5875e` + patch | hold | **held** |
| SwiftUMLStudio `NodeIdAllocator.issue`, as first written | `9ad7631` | hold | **failed on correct code** (§3), fixed |
| the same, reserving the drawn names | `9ad7631` | hold | **held** |
| the same, with `taken.insert(nodeId)` removed | `9ad7631` + mutant | refute | **refuted**: `calls 4 and 7, on a and a, both returned a_2` |

**Not run on real code:**

- swift-syntax's `makeUniqueName`, because no one package resolves both the kit and that checkout's swift-syntax;
  the witness's class form stands in for it;
- `registerCluster`;
- the 6 placeholder stubs, among them SwiftPM's `label(for:)`, whose defect #691 tracks as latent;
- Yams's `uniqueAlias`, which the census found refutable, but which is outside the gate: a caller's names beside
  generated ones.

## 5. So what

- **#692's build is done to its stated tier.** The template proposes only rows the census gated, declines the two
  the census measured, and its stub refutes a real defect and holds on real correct code.
- **It stays at Possible.** #692 asks for the template's own output to be hand-checked before it rises. The
  10 rows above are checked here only against the census's verdicts, not against a fresh reading of each body.
- **The runnable share is the lever left.** 4 of 10 proposals run as written; the rest need an argument built
  from a drawn name, which no machinery here spells. That is the next piece of work if the tier is to rise,
  together with `throws` and `async` subjects (swift-crypto's `update`).
- **Disposition (scope §8):** with the build merged, #669 and #692 can close as completed.

## Reproducing

```
cd fixtures/uniquifier-law/template-run
swift run -c release UniquifierTemplateRun ../census-2026-10-28.json ../template-run-<date>.json
```

The run takes about 7 minutes on an M5 Pro. Subjects whose `root` no longer exists read as zero files. Remap a
moved root in a copy of the census JSON, as this run did for `SwiftInferProperties-669`.
