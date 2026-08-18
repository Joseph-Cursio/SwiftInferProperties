# Can the soundness arm's sandbox be built from what the toolchain already has?

> **Status:** `measured` · **As of:** 2026-08-18

Re-derivable at any time — `SandboxDetectorMechanismMeasuredTests` *is* the harness, and
`make batch2` runs it.

Phase 0.5 of `docs/plans/declaration-claims-plan.md`, measured **before** the arm was
built rather than discovered inside it. **The plan's cost premise is false and its
recommendation survives anyway** — §6.5 claims an interposition hook this package does
not contain, and the detector turns out not to need one.

**The two costs the plan does not price are the finding.** Report-rather-than-kill is
free; *report which policy fired* is not, and an allow-list is partial inside the very
directory it names.

---

## Provenance

| | |
|---|---|
| host | macOS 26.6.2 (25G83) |
| detector | `/usr/bin/sandbox-exec` — present, and the profile language rejects `(with report)` on `deny` |
| harness | `Tests/SwiftInferCoreTests/SandboxDetectorMechanismMeasuredTests.swift` (+`Support`) |
| subject | a purpose-built probe, compiled by the harness — **not** the `.pure` corpus |
| corpus scan | `Sources/` + `Tests/`, this suite's own two files excluded by name |

**This measures the instrument, not the population.** `docs/measurements/soundness-arm-reach.md`
draws the same line one step earlier: reach is a precondition, not a result. Nothing here
says anything about the 2,396 `.pure` subjects.

---

## 1 · §6.5's premise, checked

> *"`VerifierSubprocess` already runs each law as its own process with `DYLD_*`
> injection — process isolation exists and **the interposition hook is in place**, which
> is what makes report-rather-than-kill cheap."*

**Process isolation exists. The hook does not.** What `VerifierSubprocess` sets is
`DYLD_LIBRARY_PATH` and `DYLD_FRAMEWORK_PATH`, to *locate* `libTesting.dylib`. That is a
search path. An interposition hook is `DYLD_INSERT_LIBRARIES` plus a dylib carrying a
`__DATA,__interpose` section, and none of it is here:

| spelling | occurrences in `Sources/` + `Tests/` |
|---|---|
| `DYLD_LIBRARY_PATH` — **the control** | **> 0** |
| `DYLD_INSERT_LIBRARIES` | 0 |
| `__interpose` | 0 |
| `dlopen(` / `dlsym(` | 0 |
| non-Swift compilable source files under `Sources/` | **0** |

The last row is the decisive one: an interposing dylib needs a C or Objective-C
translation unit, and this package has **no non-Swift source at all**. The only hit for
"interposition" anywhere in the repository is the sentence claiming it exists.

**The control is what makes the zeros readable.** A scan that reaches nothing reports the
same four zeros, and `docs/measurements/module-state-base-rate.md` published a zero from
exactly such a detector before it was caught. `DYLD_LIBRARY_PATH` must be found or the
test fails.

**Fourth time a premise in this line of work reads plausibly and measures false** — after
items 30, 33 and 47. The first three each erred toward claiming more purity than the
evidence supports. **This one errs toward understating a cost**, which is a different
direction and worth separating: the earlier three would have shipped a wrong answer, this
one would have shipped a right answer over budget.

---

## 2 · The detector works, and report-rather-than-kill is free

§6.1's hard constraint is not a preference:

> *"The denial must **report which policy fired**, not kill the process: a trapping
> `precondition` in `#assertIdempotent` destroys the counterexample and leaves no output,
> and a sandbox that refutes by SIGKILL reproduces that one layer down."*

Measured, one probe binary, three runs:

| operation | no profile (**control**) | deny-all | deny-all + workdir allow |
|---|---|---|---|
| write inside workdir, atomic | ALLOWED | DENIED | **DENIED** |
| write inside workdir, plain | ALLOWED | DENIED | ALLOWED |
| `FileManager.createFile` inside | ALLOWED | DENIED | **DENIED** |
| write outside workdir | ALLOWED | DENIED | DENIED |
| subprocess spawn | ALLOWED | DENIED | DENIED |
| loopback `connect` | ALLOWED | DENIED | DENIED |
| **process reached its last line** | yes | **yes** | yes |

**The probe survives every denial and exits 0.** Each denial arrives as a catchable
Swift error, so §6.1's constraint is satisfied by the mechanism itself — **no interposing
dylib is required**, and §6.5's conclusion holds despite its premise.

**The no-profile column is the control, not a warm-up.** Every sandboxed expectation is a
*denial*, and a denial is indistinguishable from a probe that never ran. Which is not
hypothetical: see §5.

**`ECONNREFUSED` counts as ALLOWED**, deliberately. The policy permitted the `connect`
and nothing was listening on port 1. Only `EPERM` is a denial. The first spike used an
outbound HTTP fetch; a test suite that makes outbound requests measures the network, and
the loopback substitute was adopted once the two errnos were shown to separate the cases.

---

## 3 · Cost the plan does not price: the errno names the policy twice in three

| class | unsandboxed | denied | does the error name the policy? |
|---|---|---|---|
| file-write | writes | `NSPOSIXErrorDomain` **1** (`EPERM`) | **yes** |
| network | `errno 61` (`ECONNREFUSED`) | `errno` **1** (`EPERM`) | **yes** |
| `process-exec` | runs | `NSCocoaErrorDomain` **4** — *"The file "echo" doesn't exist"* | **no** |

A denied `process-exec` is reported to the process as **ENOENT**. A probe reading only
the thrown error would file a blocked subprocess spawn as a missing binary.

**It lies in exactly the class the answer key needs most.** The sharpest of the 17 frozen
rows is `DrainedProcess.standardOutputViaEnv`, whose whole defect is that it **spawns a
subprocess** and is judged `.pure`. The arm's best single finding is the one the errno
misattributes.

### The fix is differential profiles, not a dylib

Log attribution is **unavailable**, checked three ways plus `/var/log/system.log`:
`(with report)` is rejected outright by this seatbelt version — *"report modifier does
not apply to deny action"* — and `subsystem == "com.apple.sandbox"`,
`senderImagePath CONTAINS "sandbox"` and `process == <probe>` each return **0 lines**.

So attribute by **differencing** instead: run each subject under profiles that deny one
class each, and the policy that fired is the profile whose run differs. Three cheap
processes per subject, no C target, no log scraping, and the attribution becomes a
measurement rather than a string parsed out of a system log. **It also degrades
honestly** — a subject tripping two classes shows up as two differing runs rather than as
whichever denial happened to be reported first.

---

## 4 · Cost the plan does not price: an allow-list is partial inside its own subpath

With `(allow file-write* (subpath "<workdir>"))` explicitly granted, in that exact
directory:

| write | verdict |
|---|---|
| `String.write(toFile:atomically: false)` | **ALLOWED** |
| `String.write(toFile:atomically: true)` | **DENIED** |
| `FileManager.createFile(atPath:contents:)` | **DENIED** |

Same directory, same rule, three spellings, two denied. The cause is not diagnosed here
and is not needed to act on: **a probe's own plumbing can trip the detector**, so a false
trip is reachable without any impurity being involved.

**This is why the plan's control set is load-bearing rather than a formality.** §6.3's
step 1 already says *"if the sandbox cannot distinguish those nine from a control set of
genuinely pure functions, it does not work and nothing else matters."* That sentence was
written as a methodological precaution. It is now a measured hazard with a named
mechanism, and the control set has to include **how the harness writes its own results**,
not only functions believed pure.

---

## 5 · Two defects in the harness, both kept

Neither is incidental — both are instances of failure modes this repo has already paid
for, arriving inside a suite written to measure something else.

**The self-describing scan.** §1's first run reported four hits, all of them in this
suite's own two files, which spell every needle in their prose. `DocCitationTests` solved
the identical problem the identical way and says why: a guard for an absence has to quote
the thing that is absent, so it reports itself forever. Excluded by **name**, not by an
"is it inside a comment" rule.

**The uncanonical path, which produced a perfect false positive.** The probe was built
under `NSTemporaryDirectory()` — `/var/folders/…`, a symlink — while seatbelt matches
`(literal …)` against the **canonical** path. The profile's own allow missed the probe,
the exec was denied, and the run came back with no output at all. Read naively that is
*six denials and a sandbox working perfectly*.

`Foundation`'s `resolvingSymlinksInPath()` is the wrong tool and was tried first: it
special-cases the `/private` prefix and **strips** it, producing precisely the spelling
seatbelt will not match. `realpath(3)` goes the other way.

**The guard that now exists because of it**: a run parsing zero step lines throws a
harness error rather than returning six denials. That is the confident zero in its most
dangerous form here — it would have read as the detector working, in the document
recommending the detector.

---

## What this does NOT establish

**That a trip is informative.** Whether calling one of the 17 exercises its impure path
is the arm's problem, not this document's.

**That the `.pure` population is reachable under a profile.** The probe was written to be
sandboxed. Most of the 2,396 are not `static` and the receiver problem applies to them in
full — `docs/measurements/soundness-arm-reach.md` measures that for the answer key only.

**Any base rate.** No subject from the corpus was run.

**That `sandbox-exec` will keep working.** It is deprecated. The harness fails loudly if
it stops behaving, which is the most this document can offer.

---

## The verdict

**Build the arm on `sandbox-exec`, with differential profiles for attribution.** §6.5's
recommendation stands; its stated reason does not, and the corrected reason is better —
the mechanism gives report-rather-than-kill for free, so the arm never needed the hook
the plan credited it with.

**Price it with the two costs above**, which is what the plan is missing:

1. Attribution is **three runs per subject**, not one, and is a measurement rather than a
   read.
2. The control set must cover the **harness's own writes**, because those trip the
   detector inside a directory it was explicitly granted.

**Do not add a C target.** Both costs are payable in Swift and shell, and a build
dependency in a parse-only toolchain is the change open item 38 declines to start with.

## What would reverse this

- **`sandbox-exec` stops denying, or starts killing.** §2's table is the guard.
- **A denied `process-exec` starts reporting `EPERM`.** Then attribution is a read again
  and differential profiles are unnecessary complexity. Pinned, and it fails on the
  improvement.
- **An interposition hook lands in the package.** §6.5 becomes true, and this document's
  §1 must be re-read before its recommendation is followed. Pinned in both directions.
