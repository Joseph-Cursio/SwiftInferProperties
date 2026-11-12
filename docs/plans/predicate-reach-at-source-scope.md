# Reach at the source for predicate stubs (#684): scope, frozen before the build and the runs

> **Status:** `proposed` · **As of:** 2026-11-12

**Issue:** Joseph-Cursio/SwiftInferProperties#684. Two generator levers for `predicate` stubs, each scored as
**rows moved to BOTH** by `scripts/predicate_outcome_reach.py` on fresh funnels. **Lever 1** changes which
syntax-corpus snippets a stub draws from, in two forms A/B'd apart: uncapped, and seeded. **Lever 2** pairs two
drawn arguments. Four arms share one binary. **The predicted outcome is that the seeded form ships, along with
pairing, moving 50–110 rows to BOTH in all.** Below are the frozen rules that decide what ships.

## 0. How this scope is held to its text

- **It is committed alone, before any lever code, the tooling, or any run.** The build commits follow it.
  The first arm runs only after the binary is built from the tooling commit and passes §5's baseline check.
- **A change after the freeze is an amendment in §9,** with its reason and the commit it lands in. An amendment
  never changes §6's rules or §7's predictions once any arm has started.
- **Arms run in the order A0, A1, A2, then A3.** A3 waits for the lever-1 DECISION line.

## 1. Why, and what #665 left

#665 measured how often a `predicate` stub's own 100 draws return both `true` and `false`
(`docs/measurements/predicate-outcome-reach.md`). **G was 42.8% (204 of 477), so the reach check was not
emitted (NONE).** Both of the scope's Direction-2 triggers fired (`docs/plans/predicate-outcome-reach-scope.md`
§8):
- **172 red syntax-corpus rows,** 161 of them in SwiftProjectLint;
- **47 red relational rows.**

Reading the reds before this scope found three causes:

- **The corpus is capped at 300 snippets, cut in file order.** `SyntaxSnippetHarvester.harvest` defaults to
  `limit: 300` (`07803176`, "so the emitted file stays reviewable"; never measured).
  - SwiftProjectLint's tests hold about 3,200 candidate literals, so about 90% never reach a stub.
  - The 300 that do are mostly SwiftUI accessibility and animation views. The tokens its predicates need sit in
    the rest of the tests, for example `ObservableObject` (39 snippets), `@Published` (37), and `Task {` or
    `withTaskGroup` (56).
- **Dilution.** Where the token is in the corpus, a broad type such as `Syntax` or `AttributeListSyntax` has
  thousands of nodes to draw among. In a 41-row sample, 5 found-but-never-true rows are this case.
- **Relational draws.** A drawn `String` must equal a name inside a drawn node, or two drawn values must line
  up. About 18–22 of the 47 relational reds look reachable by one derivation.

**Where the needed tokens live,** in the 41-row sample (an exploration read, not a frozen measurement):
- in the predicate's own body: 14 as string literals, 5 as `.keyword(.x)`;
- one hop away, in a same-file `Set<String>` constant: 7;
- 8 need a node kind (`.is(X.self)`, `.as(X.self)`);
- about 8 are out of any lever's reach: receiver state, structural shapes.

## 2. The levers

### 2.1 Seeds (shared by both forms of lever 1)

`SyntaxSeeds.of(suggestion)` reads the subject's declaration, found by `DeclarationFinder` as `SubjectLiterals`
finds it, and returns:
- **tokens:**
  - every plain, non-interpolated string literal in the body, including array and set elements, at most 40
    characters long;
  - `x` for each `.keyword(.x)`;
  - one hop: for each identifier in the body that names a `let` or `static let` declared in the same file whose
    initializer is an array or set literal of plain strings, those strings.
- **kinds:** `X` for each `.is(X.self)`, `.as(X.self)` or `.cast(X.self)` whose `X` ends in `Syntax`.

Each list is deduplicated, kept in source order, and capped at 16. Seeds are computed only for the totality
family (`predicate`, `input-totality`, `measure-non-negativity`), and only when an argument draws from the
syntax corpus.

### 2.2 Matching and the draw bias (both forms of lever 1)

- **When a node matches:** one of its own tokens (`tokens(viewMode: .sourceAccurate)`) has text equal to a seed
  token, or the node or one of its ancestors has a kind named in the seed kinds.
- **The generator:** a stub with seeds draws through `SwiftInferSyntaxCorpus.gen(T.self, preferring: [...],
  kinds: [...])`. It takes a matching node with weight 1 and any node with weight 1, and falls back to any node
  when none match.
- **No seeds:** a stub without seeds still emits `gen(T.self)`, unchanged.

### 2.3 The two harvest forms

- **uncapped (A1):** every candidate snippet, meaning every multi-line, interpolation-free literal that parses
  cleanly, up to 1,500 characters, deduplicated, with no count limit. The draw bias applies.
- **seeded (A2):** the first 300 candidates, as today, plus, for each stub with seeds, up to 8 more candidates
  past the cap that contain a matching node of the requested type, the first 8 in file order. All admitted
  snippets go in the one corpus file per package. The draw bias applies.

### 2.4 Lever 2: relational pairing (A3)

This applies to stubs with two or more drawn arguments. A constructed receiver is never drawn, so it is never
paired. Each drawn argument j is checked against earlier arguments i < j, and the first rule that applies wins:

1. **`nameFrom(i)`:** j is `String`, `[String]` or `Set<String>`, and i draws from the syntax corpus.
   - Half the time, j takes a name from `SwiftInferSyntaxCorpus.name(near: arg_i)`: an identifier or keyword
     token of i's subtree, or, 1 time in 3, of i's root.
   - A `String` j is replaced by the name. A `[String]` gets it appended, and a `Set<String>` gets it inserted.
2. **`memberOf(i)`:** j is `[String]` or `Set<String>`, and i is `String`. Half the time, `arg_i` is appended or
   inserted.
3. **`copyOf(i)`:** j has the same spelled type as i. 1 time in 4, j is `arg_i`.

Otherwise j is drawn as before. Pairing is off in A0, A1 and A2.

## 3. Arms, pins and population

**One binary serves all four arms.** The arm is chosen by `SWIFT_INFER_REACH_ARM`, read where `discover` builds
its syntax corpus source.

| Arm | `SWIFT_INFER_REACH_ARM` | Lever 1 | Lever 2 |
|---|---|---|---|
| A0 | unset or `baseline` | none (today's behaviour) | off |
| A1 | `uncapped` | uncapped + bias | off |
| A2 | `seeded` | seeded + bias | off |
| A3 | `<w>+paired` | the lever-1 winner `w` (`baseline` if neither ships) | on |

**The binary:**
- built from this branch at the tooling commit, the last commit before the first run;
- `swift-infer --version` and the commit SHA are recorded in `decisions.log` and on every census row.
- Its own `Package.resolved` is copied into the run directory.

**The seed CLI** is SwiftProjectLint's CLI, built at `6a231cda`.

**Toolchains are as #665's:** swift.org `swift-6.4.1-RELEASE`, and Xcode's toolchain for the funnel's
`XCODE_REPOS`. Each funnel runs under `env -u SWIFT_DETERMINISTIC_HASHING`.

**The 19 repositories,** recorded 2026-11-12 before any lever code. These are #665's 19, from
`git -C ../<repo> rev-parse --short HEAD`.

| repository | SHA | | repository | SHA |
|---|---|---|---|---|
| SwiftMarkdownWiki | `51b789e` | | SwiftLintRuleStudioTeam | `7789bde` |
| SwiftProjectLint | `6a231cda` | | MacCloud_client_MacOS | `9424f4f` |
| SwiftAssist | `8e1bc8d` | | SwiftCloneDetector | `e03e865` |
| SwiftPropertyLaws | `b45d1bf` | | pbt-workbook-sampler (teaching) | `0e07795` |
| SwiftUMLStudio | `9ad7631` | | LintStudioUI | `abcff42` |
| SwiftLintRuleStudio | `77cc792` | | MacCloud_server | `b0a1495` |
| pbt-workbook-corpus (teaching) | `6df2650` | | SwiftIdempotency | `adf8d18` |
| pbt-book (teaching) | `3e76194` | | pbt-workbook (teaching) | `959937e` |
| SwiftFormatRuleStudio | `5cea6a7` | | pbt-workbook-grader (teaching) | `79e6c81` |
| SwiftEffectInference | `5e981ca` | | | |

**How each run uses these SHAs:**
- Each arm's run directory gets `trees/<repo>` as detached worktrees at these SHAs, created before
  `corpus_funnel.py` runs. The funnel reuses an existing tree.
- Several siblings are on feature branches, and some have uncommitted files. A worktree is cut from the commit,
  so neither matters.

**The population, per arm,** is defined exactly as #665's (that scope's §2 and §3):
- every compiled `predicate` stub;
- R is the readable rows of the non-teaching repositories.

## 4. The metric

- **Rows are keyed by `(repo, stub, label, line)`.** A stub path can carry two rows, as `String.isMatching` did
  in #665, so the label and line are part of the key.
- **Primary: net rows moved to BOTH against a reference arm.**
  - It is counted over rows in R in both arms: (red → BOTH) − (BOTH → red), where red is ONLY-FALSE or
    ONLY-TRUE.
  - Rows present in only one arm are reported apart (appeared, disappeared) and never enter the net.
- **Also reported per arm:**
  - G and G_loo, as #665 defined them;
  - the per-repository table;
  - the moves split by the row's `primary_kind` and `row_kind`;
  - rows reaching BOTH at 1,000 draws.
- **Funnel deltas against A0,** over every stub, not only predicates: stubs, compiled, passed (behaviour and
  does-not-crash), failed, crashed and hung, per repository.
- **Cost:**
  - each package's corpus file, in bytes and snippets;
  - the census's `package_build_seconds`, and the funnel's per-package `run_seconds`;
  - SwiftProjectLint is reported on its own.

## 5. Checks before the first arm

- **V1, the baseline is unchanged.** With `SWIFT_INFER_REACH_ARM` unset, the branch binary writes stubs and a
  corpus file byte-identical to a binary built from `main` at the branch point (`9942ec32`). This is checked
  over `discover --interactive` on SwiftUMLStudio and SwiftEffectInference at the pinned SHAs.
- **V2, the census self-tests pass:** `predicate_outcome_reach.py --self-test` with the new `compare`
  subcommand's cases, in `make measurement-selftest`.
- **V3, unit tests:** seeds, selection, the emitted generator compiles, and pairing goldens, in
  `make test-fast`.

## 6. What the result decides (frozen)

**Lever 1:**
- `net(A1, A0) < 10` and `net(A2, A0) < 10` → **ship neither**.
- Otherwise ship **A2 (seeded)**, unless both of these hold, in which case ship **A1 (uncapped)**:
  - `net(A1, A0) ≥ net(A2, A0) + 10`;
  - A1's SwiftProjectLint build seconds plus run seconds are at most 1.5× A2's.
- The DECISION line goes to `fixtures/predicate-reach-at-source/decisions.log` before A3 starts.

**Lever 2:** ship it if `net(A3, A_w) ≥ 5`, where `A_w` is the shipped lever-1 arm, or A0 if none shipped.

**New failures:**
- Every stub that passes in A0 and fails, crashes or hangs in a shipped arm is hand-checked. The verdict is
  either:
  - **real**, a defect in the subject on an input its type admits;
  - **false**, the generator built an input the subject's contract excludes, or the harness failed.
- A **false** failure blocks its lever until it is fixed and that arm is re-run. The fix and the re-run are
  recorded as an amendment.
- **Real** failures are recorded in the write-up, and filed upstream only with the user's approval.

**The reach check stays unbuilt here.** If G and G_loo under the shipped arms are both at least 0.50,
#665's W floor, the write-up says that the check's reopen condition is met, for a follow-up issue.

**What ships:**
- the chosen modes as the default;
- the switch removed;
- the losing modes deleted;
- a test pinning the default to the measured arm's behaviour.

## 7. Predictions (frozen)

| # | Prediction |
|---|---|
| P1 | `net(A1, A0)` is in [40, 90] |
| P2 | `net(A2, A0)` is in [40, 90], and `|net(A1, A0) − net(A2, A0)| ≤ 15` |
| P3 | The lever-1 DECISION is **seeded** |
| P4 | `net(A3, A_w)` is in [8, 20], and lever 2 ships |
| P5 | G under the shipped arms is in [0.50, 0.60]; G_loo ≥ G |
| P6 | Most of lever 1's moves are SwiftProjectLint's: at least 70% of `net(A_w, A0)` |
| P7 | New real failures in the shipped arms: 0–3. New false failures: 0 |
| P8 | A1's SwiftProjectLint corpus file has at least 8× A0's snippets; A2's has at most 3× |
| P9 | Funnel compiles move by at most ±5 in any arm against A0 |

## 8. Not answered here

- **Receiver state** (#665 §6.1): a constructed receiver is fresh, so a predicate reading accumulated state is
  constant. No lever here touches it.
- **Single-line literals:** SwiftEffectInference's needed tokens appear only there, and the harvester skips
  them by design. They are not admitted.
- **The trial budget, and verify's predicate composer** (`composePredicatePass`).
- **A reach claim is not a law.** Rows moved to BOTH are not laws gained, and no kill is measured. The
  population is this corpus, never a rate.

## 9. Amendments

Both amendments were recorded before any arm ran, and neither changes §6 or §7.

**A1: how the build reads §2 (with the lever commits).**
- **Seeded admission (§2.3) is tested per snippet, not per node.** A snippet past the cap is admitted when it
  holds a node of the requested type and, anywhere in it, a seed token or a node of a seed kind
  (`SnippetIndex.matching`). The draw bias (§2.2) still matches per node. A loose admission costs a few extra
  snippets in the file and nothing in the draw.
- **A node also matches through a descendant of a seed kind (§2.2),** not only through itself or an ancestor.
  `analyzeInitializer` tests `initializer?.value.is(ClosureExprSyntax.self)` on a child.
- **The corpus file is rewritten whenever seeds admit a snippet,** not only at the end of the run. It holds the
  base, then every admitted snippet, in admission order.
- **The switch is read in two places:**
  - lever 1, once, where `discover` builds its `SyntaxCorpusSource`;
  - lever 2, by `totalityStub`.
  An unknown spelling stops the process with exit 64, so an arm cannot be mislabelled.
- **Pairing (§2.4) looks at every other argument, either side:** "earlier arguments i < j" becomes "every
  other argument i ≠ j" for `nameFrom` and `memberOf`. `copyOf` still copies only from an earlier argument.
  `containsReference(to:in:)` draws the name before the node, so the pairing has to look both ways.
  - Every argument is drawn first, exactly as without pairing.
  - The pairings are then applied in argument order, so an unpaired draw keeps its place in the random stream.
  - An `inout` argument is never paired.

**A2: toolchains.**
- **swift.org `swift-6.4.1-RELEASE` was missing here when this scope was frozen.** It was installed on
  2026-11-12, at the user's request, from swift.org's notarized package
  (`Apple Swift version 6.4.1 (swift-6.4.1-RELEASE)`). So every arm keeps #665's swift.org toolchain, and the
  funnel's default path is unchanged.
- **Xcode is now 27.2, and its toolchain is `swiftlang-6.4.2.1.9`.** That is the toolchain for the funnel's
  `XCODE_REPOS`; #665 used `swiftlang-6.4.0.34.1`.
- **The binaries and the seed CLI are built with swift.org 6.4.1.**
- **Effect on the comparison:** all four arms share both toolchains, so the A/B holds. Against #665, figures
  differ by Xcode toolchain as well as by SHA, so #665's G is context, never an arm.

**A3: three fixes before the first arm, from an adversarial review and a two-repository smoke run.**
- **The biased draw's result type is spelled `Generator<Node, Shrink.None<Node>>`, not `some`.** A stub with a
  long draw line hoists its generator into a `static let`, which cannot infer another declaration's opaque
  type. In the smoke run, SwiftEffectInference's compiles fell from 40 to 25 under `seeded+paired` for this
  reason alone. The biased draw does not shrink; totality never shrinks a passing draw.
- **Seeded admissions accumulate.** The funnel runs one `discover` per source target, and those processes share
  one corpus file per test target. Each process now keeps the snippets already in the file, and when the funnel
  consolidates a package's generated directories, the corpus files are merged rather than all but the first
  dropped. Under the baseline arm both merges are no-ops: the files are identical.
- **Pairing takes a name only from a draw of the argument's own node type.** A composed draw such as
  `gen(ExprSyntax.self).optional` is not a node, and `name(near:)` on it does not compile. Admission takes the
  first 8 matches in file order, so asking twice admits nothing new. `compare` counts classes, as §4 says, and
  reports instability apart. Category kinds (`ExprSyntax` and the like) and tokens holding control characters
  are not seeds.

**Found in passing, before any arm:** SwiftUMLStudio's corpus file failed to compile under every arm, `main`
included, with "unprintable ASCII character found in source file". So every syntax-corpus stub in that
repository was set aside. That was a baseline defect, not a lever. It was fixed on `main` by #719 (A4).

**A4: the first attempt crashed the machine; the baseline moves to `main` at `7e4d8e5e`.**
- **What happened.** The first A0 run started at 09:03 on 2026-11-12, at `f8865952`. About 30–45 minutes in,
  `swiftpm-testing-helper` processes running the funnel's stubs held 35 GB, then 212 GB across five. macOS ran
  out of swap and rebooted at 09:50 (`JetsamEvent-2026-11-12-094707.ips`).
  - A0 is `main`'s behaviour, so no lever was involved.
  - The reboot wiped the run directory, so no arm row was ever recorded and nothing was read. The law that
    allocated is not identified.
  - The cause in the harness: a timed-out `swift test` left its helper running, and each resume could add one
    more.
- **What changed on `main` before any arm runs:**
  - **#720** (`7e4d8e5e`) holds every test process of the funnel and the census under an 8 GB limit
    (`scripts/memory_guard.py`), and kills a timed-out run's leftovers. A kill is recorded on the
    repository's result as `memory_guard_kills`. It reads as a crash of the running law, so a guard kill in
    any arm is reported by name.
  - **#719** (`eb2d292c`) escapes control characters in the corpus file, so SwiftUMLStudio's syntax-corpus
    stubs now compile in every arm.
- **This branch is rebased onto `7e4d8e5e`.** A0 is that `main`, and §5's V1 is re-taken against a binary built
  from it. §3's sibling pins, §6's rules and §7's predictions are unchanged.
  - P9 now reads against the new A0, so SwiftUMLStudio's recovered compiles are not a lever's.
  - Under `seeded`, a corpus file's escaped snippets read back as themselves (`SyntaxCorpusReachArmTests`).
