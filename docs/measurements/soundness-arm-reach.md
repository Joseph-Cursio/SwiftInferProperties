# Can the soundness arm reach its own frozen prediction?

> **Status:** `measured` · **As of:** 2026-08-17

Re-derivable at any time — `SoundnessArmReachCensusMeasuredTests` *is* the harness,
and `make batch2` runs it.

Phase 0.5, step 1 of `plans/declaration-claims-plan.md`. **Measured: 14 of the 17
frozen rows are callable, 9 of them with nothing to construct at all.** The arm can
execute its own answer key, so the sandbox build is not blocked on reach.

---

## Why this had to be measured before the sandbox was built

§6.3's soundness arm sandboxes the `.pure` population and asks which functions trip a
deny-by-default policy. The plan review froze a prediction for it: the **17
hand-checked rows** from `purity-unrecognised-callee-census.md`, where a `.pure`
verdict calls a package function this same analyzer refutes with a witness — one of
them `DrainedProcess.standardOutputViaEnv`, which spawns a subprocess.

**A prediction the arm cannot execute is not a prediction.** §6.4 says the arm's
coverage *"must be estimated separately rather than inherited from 139-of-281"* — the
verify arm's carrier reach — because a purity probe needs only a **call**, not a
generator: one invocation that trips a denial refutes, so a degenerate argument
suffices where a law needs a domain. That estimate had never been taken.

Had the answer been "most of the key is unreachable", the arm would have been
unfalsifiable and the sandbox a waste. It is not.

---

## Provenance

| | |
|---|---|
| corpus | this repo's `Sources/`, the item 29 census's file enumeration |
| SEI pin | `3ea25f2` |
| harness | `Tests/SwiftInferCoreTests/SoundnessArmReachCensusMeasuredTests.swift` (+`Support`) |
| population | the frozen 17-row trip list, keyed by **file and name** |

Keyed by file *and* name because `resolve` and `load` each match several declarations
here — the name-collision hazard that has been the dominant defect in three
measurements at this seam.

---

## The measurement

**Reachable** means three things, all decidable from a parse: visibility is `public`
or `internal` (so `@testable` reaches it), no receiver needs constructing, and every
parameter is degenerate or defaulted.

| | rows |
|---|---|
| **reachable, nothing to construct** | **9** of 17 |
| **reachable, cheap construction only** | **14** of 17 |
| not reachable | 3 |

### Why two figures, and why the second is the real one

The strict rule counts *any* package type as blocking, and that understates the arm.
`WorkdirMode` is a `CaseIterable` enum — `.allCases.first!` is one expression, not a
construction problem. Reporting only the strict figure would decline the arm on a cost
that is not real.

So each blocking type is classified by what a probe would have to write:

| blocking type | rows | cost |
|---|---|---|
| `WorkdirMode` | 2 | **cheap** — `CaseIterable` enum |
| `any DiagnosticOutput` | 2 | **stub required** — a protocol existential |
| `ActionCaseInfo` | 1 | **cheap** — struct of degenerate fields |
| `Decisions` | 1 | **cheap** |
| `ExplicitOverrides` | 1 | **cheap** |
| `SpeculativeWidening.Candidate` | 1 | **expensive** |

**A protocol is counted as its own answer rather than folded into either side.** A
conforming stub is cheap in absolute terms, but it is code the harness owns and can get
wrong — a `DiagnosticOutput` stub that swallows output would make a probe silently
uninformative, which is the failure mode this whole line of work keeps meeting.

### The three that are out

- `MetricsCommand.loadImplicit` — **`private`**
- `TargetIsolation.dump` — **`private`**
- `SpeculativeRefactorRunner+Machinery.snapshotOrReport` — needs
  `SpeculativeWidening.Candidate`, which is not a struct of degenerate fields

**Nearly all of the trip list is `static`**, which is what makes the numbers this good:
no receiver to construct, which is the expensive half of the general problem and the
reason the verify arm's carrier reach is only 139 of 281.

---

## What this does NOT establish

**That calling them is informative.** A function reading a package manifest under a
temp URL returns `nil` rather than doing anything interesting; whether the *probe*
exercises the impure path is the sandbox's problem, not this census's. **Reach is a
precondition, not a result** — and conflating the two would be the same error as
reading a census's zero without its corpus list.

**That calling them is safe.** `standardOutputViaEnv` spawns a subprocess. That is the
point of sandboxing it, but it also means the arm cannot be run casually, and the
denial-reports-rather-than-kills constraint in §6.1 is load-bearing rather than polish.

**Anything about the other 2,379 `.pure` subjects.** This measures the answer key, not
the population. The arm's coverage over the full `.pure` set is a different and much
larger question — most of that population is *not* `static`, so the receiver problem
that this trip list happens to dodge applies there in full.

---

## The verdict

**The sandbox build is not blocked on reach.** 14 of 17 predicted trips are callable,
9 of them trivially, and the three that are out are out for legible reasons — two
`private`, one genuinely awkward type.

**What to build next, and in what order:**

1. **The probe harness for the 9 strictly-reachable rows.** No construction, no stubs,
   no judgement calls — if the sandbox cannot distinguish those nine from a control set
   of genuinely pure functions, it does not work and nothing else matters.
2. **A `DiagnosticOutput` stub that records rather than swallows**, unblocking 2 more.
   Its behaviour is a correctness question, not plumbing.
3. **The three cheap constructions**, unblocking 3 more, to reach 14.

**Do not start at the full `.pure` population.** The trip list is the only part of it
with a hand-verified answer, and a sandbox scored against 2,396 functions with no key
produces a number nobody can check — which is the position the backtest arm was
created to escape.
