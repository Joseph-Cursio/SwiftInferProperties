# The measurement corpus

`manifest.json` is the committed registry of subject codebases the toolchain is measured
against: what each one is, where it comes from, at what revision each measurement was taken,
**why it is in the corpus at all**, and — for the members that are deliberately wrong — **what
the tool is supposed to find**.

Read by `swift-infer corpus`, `swift-infer prove-then-show --corpus <id>`, and
`CorpusManifestTests` / `CorpusCheckoutTests` / `CorpusRunPlanTests`.

```
swift-infer corpus                                  # the registry, with each checkout's pin
swift-infer corpus --apparatus kit-suite-backtest   # what one apparatus actually covers
swift-infer corpus --strict                         # non-zero if a checkout is off pin or dirty
make corpus-check                                   # the same gate, before a sweep

swift-infer prove-then-show --corpus grdb --budget small --max-parallel 4 \
    --retain-run fixtures/verify-runs/<date>-GRDB-native.json
```

## Why this exists — the other half of a problem `fixtures/verify-runs/` half-solved

That directory solved *a run must survive*. It did not solve **a run must be reproducible**, and
the four runs banked there are the evidence. Every one records its provenance as:

```
/tmp/claude-501/…/scratchpad/grdb-native @ b83108d10 (uncommitted changes)
```

The revision is real. The path is a scratchpad directory belonging to a session that ended, and
**nothing anywhere recorded that `b83108d10` is a commit of `groue/GRDB.swift`**. Three of the
four also say `(uncommitted changes)`, so even the revision does not fully name the code.

The artifact built expressly to outlive its session says *where* it ran, and that place is gone.
Those subjects are re-derivable today only because nobody has run `git pull` on the clones since
— which is luck, not provenance.

That is the fourth diagnosis of this class. `fixtures/whole-corpus-survey/` records a run that
overwrote the file it was compared against; `VerifyEvidence.corpusProvenance` exists because two
streams a week apart are not comparable without it; `RetainedSurveyRun` exists because the
streams kept being deleted. Each made a run more self-describing or more durable. **None made it
findable from outside.**

The same rot had already reached the prose. `docs/design-internal/glossary.md` states that
`1b5cd99f` is "no longer a reachable object" in the swift-syntax checkout; it is, and the census
that used it is registered here at that revision.

## The pinned revision belongs to the MEASUREMENT, not to the corpus

A `revision` is not *the version we intend to test*. It is **the version this measurement was
taken against** — a fact about work already done, in a repo whose standing rule is that
diagnoses do not expire and measurements do. A subject nobody has measured has no revision and
says so, rather than carrying an aspiration that reads like a pin.

That is what makes the drift check worth running. A checkout sitting off-pin does not mean
*update the manifest*. It means **a diff taken here will mix a change in the subject with a
change in the tool, and cannot tell you which moved** — the confound the whole retained-run
apparatus exists to separate. So `--corpus` warns and proceeds rather than refusing: surveying a
newer commit is exactly how a baseline gets re-based.

Only a `baseline` sets the pin. A `census` or `backtest` records the revision **it** was taken
at, which is a different claim — a backtest is pinned to a commit chosen *because* the code is
broken there, and treating that as the pin would report the subject as having "moved off" the
moment anyone checked out a working version.

## Cannot-check is a state, not a pass

The corpora live outside this repository and this project is worked from two machines, so a
clone present on one and absent on the other is the **ordinary case**, not an error.

The tempting shape — available *and* at pin, everything else off — would let a machine holding
none of the clones report a clean sweep. So there are three answers, and the third is the point:
at pin, off pin, or **could not be checked**. `--strict` fails on the first two and not the
third, and the summary always states its denominator:

```
21 corpora · 19 checked · 2 at pin and clean · 18 with no baseline · 2 COULD NOT BE CHECKED
```

Never "all corpora at pin" having read nineteen of twenty-one. That is `scanIsNotEmpty`
asserting a denominator, `make docs-drift` reporting a behind-by-N clone as its own fact, and
`DeferralFalsifierTests` answering `unavailable` rather than "absent" — the same rule in a
fourth place.

### The failure mode the three states do NOT separate — present, at the wrong path

`could not be checked` means *no directory at `localPath`*. It does **not** distinguish a clone
this machine genuinely lacks from one it **has, at a path the manifest gets wrong** — and the
second is worse, because the fix is a one-line edit rather than a clone and the state reads as
the benign case.

**Both of the registry's first-day entries for `~/GitHub_projects/swift-numerics` and
`~/GitHub_projects/swift-algorithms` were this** (corrected 2026-08-15 to `~/calibration/…`).
Both checkouts were present, both carry the matching `origin` remote, and swift-numerics sat at
**exactly its pinned `899af71`** while being reported as uncheckable. The involution measurement
in `swiftorg-property-test-study-findings.md` §10.5 is taken from that corpus, and it is the
witness that a census called dead — so the wrong path was hiding a checkout that refutes a
finding.

**A cheap partial check exists and is not built:** the manifest already carries `remote`, so a
present-but-elsewhere clone is detectable by matching `git remote get-url origin` across
candidate roots, and a pin is verifiable with `git cat-file -t <rev>` without checking anything
out. **`cat-file` alone is not enough** — an unreachable pin usually means *the clone is behind*,
not *the pin is wrong*: **five of seven** unreachable pins here resolved after a plain
`git fetch` (`swift-syntax` `1b5cd99`, `swift-argument-parser` `2f77f2f`, `swift-foundation`
`96d4094`, `swift-algorithms` `ff223da`, and **`swiftlang-swift` `408632e`**). **Fetch before
reporting a pin as lost**, which is `make docs-drift`'s rule arriving in a fifth place.

> **This said "four of six" until 2026-08-15 and the missing one is the consequential one.**
> `swiftlang-swift` `408632e` is the swift.org Q2 corpus — *the only registry member with an
> answer key frozen before the tool ran*, so it is the one pin whose loss would cost a recall
> number rather than a re-clone. It was still unreachable when the sentence was written and
> resolved on the next fetch, which is the rule working and the count not keeping up.
>
> **The manifest's own note is why it looked lost**: that revision was *"re-pinned off the local
> PR branch, which was 1,894 commits behind AND had edited a corpus file."* A pin whose
> provenance mentions a local branch invites the reading that it was never pushed. It was; the
> clone was simply behind. **Do not infer a lost commit from a pin's history — fetch and look.**

Two pins did **not** resolve after fetching and are recorded as open rather than diagnosed:
`swift-nio` `590dd7b` and `SwiftLintRuleStudio` `6ffc755`. A revision that no longer exists in
its origin is a genuinely different state from a stale clone, and neither `--strict` nor this
README currently names it.

> **BOTH RESOLVED 2026-08-15, and they turned out to be different problems with different
> fixes.** The paragraph above treated them as one residue; they are not.
>
> **`swift-nio` `590dd7b` was a CLONE defect, and the pin was always right.** The commit is on
> `origin/main` (a 2026-07-17 Windows build PR). The clone's fetch refspec was
> `+refs/tags/2.79.0:refs/tags/2.79.0` — a single-tag clone sitting on a local branch — so
> `git fetch origin` legitimately brought nothing, twice, and looked like a lost commit both
> times. Adding `+refs/heads/*:refs/remotes/origin/*` and fetching resolves it. **No manifest
> change was needed. A fetch that succeeds is not a fetch that fetched anything** — check the
> refspec before concluding a commit is gone.
>
> **`SwiftLintRuleStudio` `6ffc755` was a RECORD defect and is not recoverable.** GitHub answers
> HTTP 422, and the object is absent from the local store, the reflog and the sibling
> `SwiftLintRuleStudioTeam` clone. The road test it cites never captured a subject revision at
> all: every SHA in that document (`748dd81`, `9e1e066`, `3bf23e0`, …) is a **SwiftInferProperties
> fix commit**. So the registry's revision had no source in the record it points at, and its
> `takenOn` (2026-08-12) was the day the registry was written, not the day of the measurement
> (the doc is dated 2026-07-22).
>
> It is now recorded as `"revision": null`. **Substituting a working SHA was rejected outright** —
> this file's own rule is that a revision names the version a measurement *was taken against*, so
> inventing one falsifies the record the registry exists to preserve. See *An unrecoverable
> revision* below.

### An unrecoverable revision is a fourth state, and it is not "no baseline"

`revision` is optional. `null` means **the measurement happened and the version it was taken
against cannot be established** — which was previously unrepresentable, so it was written as a
SHA-shaped string resolving nowhere. That is the worst available option: it is indistinguishable
from a stale clone, so it sends every reader to `git fetch`, forever, for a commit that does not
exist. `swift-nio` and `SwiftLintRuleStudio` sat in the same paragraph of this file for exactly
that reason, and only one of them was a fetch problem.

**`null` is not a weaker pin; it is a different fact.** Off-pin says *a diff here mixes a change
in the subject with a change in the tool*. `null` says *no diff is possible at all, and no amount
of fetching will change that*. The only remedy is to re-run the measurement and record the
revision — which is why `CorpusPin.revisionUnrecoverable` refuses to fold into `noBaseline`
(*enqueued, never swept* — invites a sweep that would silently produce an incomparable run) or
into `movedOff` (*check out the pin* — a pin that does not exist).

Two decisions worth keeping:

- **The summary counts it from the MEASUREMENTS, not from the pin verdict.** A lost revision on a
  `census` leaves the pin correctly at `noBaseline`, because there is genuinely no baseline — so
  counting the pin would file a permanent loss inside a bucket that a single sweep clears. The
  defect is a property of the record, so it is counted there and named in capitals.
- **`--strict` does NOT fail on it**, and that is deliberate rather than lenient. Strict fails on
  what the person running it can fix before the sweep they are about to start: check out the pin,
  clean the tree. A record defect is identical on every machine and unfixable at gate time, so
  failing would hold the gate red until someone re-runs a road test — and a permanently red gate
  is one people route around, costing the off-pin detection strict exists for. The pressure lives
  in the summary line.

`CorpusManifestTests` requires an absent revision to say `REVISION UNRECOVERABLE` in its `arm`,
**and asserts that at least one entry does** — without the denominator arm, `null` becomes cheaper
than a real pin and the field for recording a known loss turns into the field for recording that
nobody looked.

### The wider problem this exposed, and it is NOT fixed

A commit cannot postdate the measurement taken against it. **Five entries have exactly that**, so
their recorded revision is provably not the one the measurement used:

| corpus | revision | `takenOn` | commit date |
|---|---|---|---|
| `swift-project-lint` | `e06e39f` | 2026-08-12 | 2026-08-14 |
| `swift-effect-inference` | `50c5d3a` | 2026-08-01 | 2026-08-07 |
| `planted-defect-arm` | `ecaa66f` | 2026-08-13 | 2026-08-14 |
| `cycle27-surface` | `ecaa66f` | 2026-08-05 | 2026-08-14 |
| `leaderboard-sort` | `ecaa66f` | 2026-07-31 | 2026-08-14 |

The last three share one revision — this repository's HEAD around the day the registry was
written — which is the same failure as `SwiftLintRuleStudio`, caught earlier: **a revision filled
in from what was checked out at registration time rather than read off the measurement.** With
`6ffc755` that produced a SHA belonging to nothing; here it produces SHAs that resolve, which is
worse, because they look right.

**Deliberately left as found.** Correcting them means recovering what each measurement actually
ran against, and that is a per-measurement investigation, not an edit. Recorded here so the next
reader does not take a resolving SHA as a verified one — and it is a cheap mechanical check
(`git log -1 --format=%cs <rev>` against `takenOn`) that no test performs yet.

## The four kinds of subject

The registry covers more than "third-party SwiftPM library", because the corpus always did and
each shape used to be set up by hand and left unrecorded.

| kind | reached by | why it is its own kind |
|---|---|---|
| `package` | `target` | the ordinary case |
| `sibling` | `target` | same mechanics, but the cross-repo seam is the thing nothing else checks, and the remote is ours |
| `app` | `sources` | no SwiftPM target exists. `prove-then-show --corpus` **refuses** these by name rather than resolving a target that is not there — an empty scan reports *nothing to suggest*, which is indistinguishable from a clean result |
| `mutant` | `target` | code that is deliberately wrong. See below |

## Known-wrong members are the recall denominator

Every other member is code believed **correct**, so a clean sweep is the weak-but-correct
outcome and there is no way to tell a thorough instrument from a blind one. This is the gap
CLAUDE.md keeps recording — *planted evidence has no base rate*, *absence of refutation over a
generated domain is not proof*.

A `backtest` measurement must carry `expectedOutcome`, and `CorpusManifestTests` fails without
it: a backtest with no recorded expectation is just a run. Four are registered, and **two of
them are registered because they are MISSES**:

- **swift-collections `876177db^`** — HIT. Both `symmetricDifference` laws must fail at trial 1.
- **swift-collections `c8080d05` + three projection mutants** — MISS. 26 emitted tests come back
  verdict-for-verdict identical to correct code. Narrowing only the generator makes
  `Hashable.equalityConsistency` refute all three, so the failure is the generator domain and
  this repo owns it. The baseline is not green either: 6 of 26 fail on *correct* code.
- **`fixtures/planted-defect-arm`** — one refutation that is a real defect and one that is a
  false law about correct code, which killed both readings of the template hypothesis at once.
- **`fixtures/leaderboard-sort`** — the mutant × law matrix that separates a weak generator from
  a weak law.

Backtest at `<fix>^`, **never at HEAD**: these libraries are correct at HEAD, so an all-green
run cannot be told apart from the tool being blind.

Where a frozen answer key exists it is cited by path rather than copied — `answerKey` points at
`fixtures/swiftorg-study/q2-answer-key.json`, committed *before* any `discover` run so the tool
could not grade its own homework. Re-encoding it here would create a second copy to drift.

## One list, four apparatuses

`measurements` is deliberately not a list of retained survey runs. `prove-then-show` is one of
several things pointed at these subjects — the others being the census scripts, the kit-suite
backtest, the swift.org study and the road tests — and **each kept its own disjoint corpus
list**, so "the corpus" meant something different depending on which tool you had run. Modelling
only survey runs would have re-created that split inside the fix.

A measurement therefore names its `apparatus` and points at its `record`, whether that record is
a retained JSON stream or the findings doc that is the only place a census survives. `record` is
required: a measurement with nowhere to point is one whose result was discarded.

`--apparatus <name>` answers what each private list used to. An unknown name is an **error that
lists the real ones**, not an empty report — `--apparatus censsus` printing "0 corpora matched"
reads as a coverage gap and would send someone to measure what is already measured.

## Fields

| field | meaning |
|---|---|
| `id` | stable slug; the handle `--corpus` takes. Never renamed once a measurement cites it |
| `subject` | the repository, as a human names it |
| `kind` | `package` · `sibling` · `app` · `mutant` |
| `target` / `sources` | exactly one. `sources` is a path *within* the checkout |
| `remote` | the authority for where the subject comes from |
| `localPath` | a resolution *hint*, `~`- or repo-relative. Deliberately not authoritative |
| `role` | `control` (home turf) or `unfamiliar`. Free text; nothing branches on it |
| `why` | **what this subject is for.** Not decoration — see below |
| `measurements[].apparatus` | which machinery produced this |
| `measurements[].kind` | `baseline` (sets the pin) · `frozen` · `backtest` · `census` |
| `measurements[].revision` | full 40-character SHA. A short one cannot be resolved in a clone that does not already hold the object |
| `measurements[].record` | **required** — where the result actually lives |
| `measurements[].frozenBecause` | required on `frozen`: what re-running would destroy |
| `measurements[].expectedOutcome` | required on `backtest`: what the tool is supposed to find |
| `measurements[].answerKey` | a frozen key committed before the measurement, cited not copied |

### `why` is load-bearing

A corpus that cannot say what each member is for grows by accretion, and then nobody can tell a
subject that earns its runtime from one added on a whim. Most entries here are in it because
each exposed something no other subject could:

- **swift-format** declares macOS 13.0, below the kit's 14.0, so every pick failed to build. An
  entirely ordinary deployment target — invisible on a corpus that agrees with the kit, as this
  repo does by construction.
- **GRDB** declares `path: "GRDB"`, so its sources sit at repo root. Unreachable outright.
- **SwiftFormatRuleStudio** sets `.defaultIsolation(MainActor.self)`: 64 laws emitted, 132
  errors, 0 compiled.
- **Harmonize** alone contributed 38 of the whole-to-parts census's dominant false-positive
  class, and its `tokens(startingWith:)` is the witness that rejected a rule at 50%.
- **MacCloud_client_iOS** is the only app, and five commands rejected it with an argument error
  while the same files in a shim produced 4 findings. The gate never rejected the code.

And the control earns its place by being the ceiling: 87 of 159 picks execute on
`SwiftInferCore` against 1 of 129 and 5 of 307 on the other two. **That gap is invisible from
any single-corpus run**, which is the argument for having a corpus rather than a subject.

## The guards, and which direction matters

`CorpusManifestTests` checks the manifest against the tree **in both directions**, because they
fail differently:

- A measurement naming a record that is not there is a dangling pointer, and is loud the first
  time anyone follows it.
- A retained run that **no entry names** is silent. It sits in `fixtures/verify-runs/` looking
  like a baseline, gets diffed against, and carries no remote, no revision binding and no reason
  for existing.

The second is the one that needed a guard — the same asymmetry `SubprocessBatchCoverageTests`
records for the Makefile batches.

Also asserted: the population is non-empty (every other arm is vacuous over an empty manifest),
at least two apparatuses are represented and each selects a non-empty set, ids are unique,
revisions are full-length hex, a retained stream really is a run of the target its entry claims,
an in-repo corpus names a target its own `Package.swift` declares (this caught a wrong target
the day it was written), at most one baseline per corpus, and `frozen` / `backtest` carry their
required explanations.

`CorpusCheckoutTests` and `CorpusRunPlanTests` cover resolution, and most arms are **negative**:
a missing clone resolves `uncheckable` and never `atPin`, a dirty tree at the pin is not
comparable, a `frozen` measurement is not a baseline, an unreadable checkout outranks a missing
baseline, an app-shaped corpus is refused even when its checkout is present, and a filtered
empty report names the filter that emptied it.

## Adding a corpus

1. Add an entry with `remote`, `localPath`, `kind`, `target` *or* `sources`, `role`, `why`, and
   `measurements: []`. An entry with no measurement is legal and means *registered, never
   measured* — that is how you enqueue a subject.
2. `swift-infer corpus` to confirm it resolves on this machine.
3. `prove-then-show --corpus <id> --retain-run fixtures/verify-runs/<date>-<subject>.json`.
4. Add the measurement with the **full** SHA it was taken at and a `record` that exists.

The label is derived, so do not pass `--retain-label` unless the arm is unusual enough to need
naming beyond subject-target-revision. That is the point: a hand-typed label is free text nobody
validates, and it is what dated every artifact in `fixtures/verify-runs/`.
