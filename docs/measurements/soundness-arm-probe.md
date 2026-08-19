# Phase 0.5's soundness arm — does the sandbox separate the trip list from pure controls?

> **Status:** `measured` · **As of:** 2026-08-18

Re-derivable at any time — `SoundnessArmProbeMeasuredTests` *is* the harness, and
`make batch2` runs it. The probe is `Sources/soundness-probe`, built by `swift build`.

`docs/plans/declaration-claims-plan.md` §6.3 step 1, and its gate is stated as a
precondition rather than a result: *"if the sandbox cannot distinguish those nine from a
control set of genuinely pure functions, it does not work and nothing else matters."*

**It distinguishes them. 4 of 9 trip; 0 of 3 controls do.**

**And the arm's most useful finding is why the other five do not** — which is not that they
are pure.

---

## Provenance

| | |
|---|---|
| subjects | the **9 strictly-reachable** rows of the frozen 17-row trip list |
| controls | 3 functions with no I/O — a fingerprint, an identity hash, a string mapping |
| fixture | `fixtures/soundness-probe/` — a deliberately tiny package |
| detector | `sandbox-exec`, reads denied on the **fixture subpath only** |
| harness | `Tests/SwiftInferCoreTests/SoundnessArmProbeMeasuredTests.swift` (+`Support`) |

---

## The detector is differential, and it has to be

These subjects **swallow failure**. `KitEvidenceStore.load` returns an empty log whether
the file is absent or the read was denied, so a denial is invisible in the return value —
and `docs/measurements/sandbox-detector-mechanism.md` already measured that the errno often
does not name the policy, and that no log channel carries it.

What *is* visible is a **difference between two runs of the same binary**: a pure
function's result cannot depend on a resource that was denied. The probe prints one
fingerprint per subject; the harness diffs the runs.

**Reads are denied narrowly, on the fixture subpath.** A global read denial stops `dyld`
before the probe's first line, which measures the runtime rather than the subject.

---

## The measurement

| subject | unsandboxed | fixture reads denied | |
|---|---|---|---|
| `DrainedProcess.standardOutputViaEnv` | `bytes=6` | `bytes=-1` | **TRIP** |
| `KitEvidenceStore.load` | `outcomes=0` | **`outcomes=590`** | **TRIP** |
| `MetricsInteraction.loadDecisions` | `warnings=1` | `warnings=0` | **TRIP** |
| `SpeculativeRefactorRunner.scanRestricted` | `files=2` | `files=0` | **TRIP** |
| `DependencyTypeShapes.scan` | `shapes=0 roots=0` | same | — |
| `Metrics.loadAggregate` | `decisions=0` | same | — |
| `VerifierWorkdir.macOSPlatformLine` | `.macOS("14.0")` | same | — |
| `ViewModelArgumentGenerator.candidateValuesExpression` | `[0, 1, -1]` | same | — |
| `EffectResolver.resolve` | `summaries=0` | same | — |
| **3 controls** | — | **identical** | — |

**Every one of these nine is judged `.pure` by the inferrer.** Four of them demonstrably
depend on state the sandbox can take away.

### `KitEvidenceStore.load` finds MORE when denied, and that is the sharpest row

`outcomes=0` open, **`outcomes=590` denied.** Denying reads of the fixture did not stop it
— it made it **walk up out of the directory it was given** and read this repository's own
`.swiftinfer/kit-evidence.json` instead.

So its result depends on ambient filesystem state *outside its argument*. That is a
stronger impurity than "reads a file": the same call, with the same argument, returns
different evidence depending on what happens to sit in an ancestor directory. A law
generated over it would pass or fail on where the test process was launched from.

---

## Why the other five do not trip — and it is not purity

**A degenerate argument reaches a function without exercising it.** This is the reach
census's own caveat arriving as a measurement:
`docs/measurements/soundness-arm-reach.md` said *"a function reading a package manifest
under a temp URL returns `nil` rather than doing anything interesting; whether the probe
exercises the impure path is the sandbox's problem, not this census's."*

Read row by row:

- **`VerifierWorkdir.macOSPlatformLine(userPackage: nil)`** short-circuits on `nil` and
  never touches disk. The degenerate argument *is* the reason it looks pure.
- **`EffectResolver.resolve(summaries: [], …)`** has no work to do with an empty array.
- **`Metrics.loadAggregate`** and **`DependencyTypeShapes.scan`** find nothing in the
  fixture — the first wants a decisions file this fixture's shape does not satisfy, the
  second wants `.build/checkouts`.
- **`ViewModelArgumentGenerator.candidateValuesExpression(for: "Int")`** is a string
  mapping. It may genuinely be pure, and it is on the trip list only because it *calls*
  something the analyzer refutes.

**So the honest reading is 4 confirmed impure, 5 not-yet-exercised — not 4 impure and 5
pure.** Distinguishing those needs richer arguments, which is step 2's work, not a
conclusion available here.

**The first run made this vivid**: pointed at an *empty* temp directory, **eight of nine**
returned identical results and only the subprocess spawn tripped. The fixture moved the
count from 1 to 4 without changing a line of subject code.

---

## Do the findings have a consumer? Measured: NO, and no victims either

The Decisions stub in `open-threads.md` generalises the cluster's recurring lesson —
*"does this have a consumer?" has to be asked of the OUTPUT VALUE, not only of the report
that would carry it.* So it was asked here, on the day the arm produced its first output.

**Measured: 0 suggestions rest on any of the four confirmed-impure subjects.**

**The veto cannot catch them, structurally.** `TemplateRegistry.applyImpureSubjectVeto`
fires on **witness-refuted** subjects; these four are `.pure`, so nothing refutes them and
the veto never sees them. If a law did rest on one, it would ship.

**None does.** The four are not template-shaped: `load(startingFrom:explicitPath:diagnostic:)`
and `scanRestricted(under:diagnostic:)` match no template's signature. So the arm's first
findings are real and currently **inert** — a false `.pure` with no downstream victim.

**The zero has a non-vacuity control, and it needed one.** The same join, pointed at
`directoryExists` and `fileExists` — which `docs/measurements/purity-veto-precision.md`
measures as carrying laws — finds them. A dictionary built on the wrong key would have
reported *"no law rests on the arm's findings"* just as convincingly as the truth does,
which is this repo's confident zero arriving in the census whose entire output is a zero.

### What this costs Family A

§5.1 gates `@lint.purity refuted(_)` on *"the empirical arm discovered N false `.pure`"*.
**N is 4, so the gate is discharged** — and the same measurement says those 4 annotations
would move **0** suggestions.

That is the **fifth** time in this line of work that the reach half came back empty
(rows 31, 32, 33, 34, and now this). The pattern is not that the findings are wrong; it is
that a purity fact has no path to a law unless something gates on it, and the one thing
that does — the veto — gates on the *refuted* side, which is the side the arm is not
about.

---

## What this does NOT establish

**That the five are pure.** See above — they were not exercised.

**A base rate.** Nine hand-picked rows, chosen because a static census already suspected
them. §6.3's open question — *what is the base rate on rows no static refuter reaches* —
needs an unstratified population and is untouched here.

**That a trip means a bug.** `scanRestricted` reading source files is what it is *for*.
The finding is that the inferrer calls it `.pure`, not that it should not read.

**Anything about the 8 rows needing construction.** 14 of 17 are reachable once cheap
constructions are written; this is the 9 that need none.

---

## The verdict

**§6.3's precondition is discharged: the sandbox separates the trip list from pure
controls, on a real corpus, with the controls holding.**

**What to build next, in order:**

1. **Richer arguments for the five that did not trip.** The cheapest finding available —
   `macOSPlatformLine` given a real `UserPackageReference` and `resolve` given real
   summaries are two lines each, and both are predicted to trip.
2. **The `DiagnosticOutput` stub**, unblocking 2 more rows, with the reach census's warning
   attached: a stub that swallows output makes a probe silently uninformative.
3. **The three cheap constructions**, reaching 14 of 17.

**Do not widen to the full `.pure` population yet.** The trip list is the only part of it
with a hand-verified answer, and a sandbox scored against 2,396 functions with no key
produces a number nobody can check — which is the position the backtest arm was created to
escape.
