# Can the tool name the caller a `private`-subject law should be lifted to?

> **Status:** `measured` · **As of:** 2026-08-19

Re-derivable at any time — `LiftCallerReachMeasuredTests` *is* the harness, and
`make batch2` runs it.

**Measured YES, and higher than the estimate that nearly parked it: 260 of 373
visibility-declined suggestions can name a visible caller — 70%.**

---

## The design was settled eleven days before it was buildable

`docs/measurements/roadtest-self-dogfood-2026-08-08.md` §2 decided *what* to build and
could not build it:

> *"What would help is a caveat that names the nearest reachable caller, turning 'you
> cannot test this' into 'state it on `lookupSuggestion`'."* — **not a gate, not a
> demotion, not a veto.**

That is why `subjectNotVisibleToTests` carries **weight 0**: the row is correct and useful,
it says *there is a law near here*, and it is merely under-explained.

**It sat because callers were unresolvable.** Open item 38: no IndexStore in any of the
five packages, so `swift-syntax` cannot answer who calls what.

**`calledFreeFunctionNames` changed that on 2026-08-18** — added for `PackagePurityJoin`,
and inverting it gives a caller index. The feature became measurable as a side effect of an
unrelated build, which is worth recording: the blocker moved without anyone aiming at it.

---

## Why same-file is SOUND here, not a heuristic

`private` and `fileprivate` are **file-scoped in Swift**. A caller of one of these subjects
*must* be in the same file — a consequence of the language, not a guess.

That is what makes a reverse **name** index safe here, and it was the largest risk when
this was scoped: a `normalize` in another type cannot be a caller of this `normalize`, so
the collision hazard that has been the dominant defect at this seam in four measurements
does not arise. The restriction is doing real work rather than bounding an error.

---

## Provenance

| | |
|---|---|
| corpus | this repo's `Sources/` |
| population | `AccessRestriction.notVisibleToTests` only |
| caller index | `FunctionSummary.calledFreeFunctionNames`, inverted, bucketed by file |
| harness | `Tests/SwiftInferCoreTests/LiftCallerReachMeasuredTests.swift` (+`Support`) |

**`internalOrSPI` and `nestedLocal` are excluded**, per `AccessRestriction`'s own doc:
`@testable` genuinely reaches the first, and the second is a different problem left out
until measured.

---

## The measurement

| | count |
|---|---|
| restricted (`private` / `fileprivate`) functions | **934** |
| …with ≥1 same-file caller found | **842** (90%) |
| …of those, ≥1 caller **visible to tests** | **561** |
| …**unambiguous** — exactly one visible caller | **534** |
| no caller found at all | 92 (10%) |
| **reachable only by walking the chain** | **+267** — depths 2:198, 3:62, 4:7 |
| | |
| **suggestions declined for visibility** | **373** |
| …**that could name a visible caller** | **260 (70%)** |

### The estimate that nearly parked this was wrong, and worth recording

The scoping question was *"how much does the member-call blind spot cost?"* — the collector
takes **free-shape** callees only, so `self.foo()` and `x.foo()` are invisible, and the
worry was that private helpers are normally reached through a receiver. The stated
threshold was: *if it is 20, item 38's call-graph cap is the real answer and this parks
with a number attached.*

**It is 260, because the premise was wrong.** An unqualified call to a member of the
enclosing type **is** free shape, and that is how private helpers are normally called. 90%
of subjects resolved a caller.

### What the gaps are

**842 → 561 was subjects whose only callers are *also* private — chains of private
helpers. Transitive lifting was built the same day and reaches 267 of them**, taking the
total from 561 to **828 of 934**. The chains are shallow — 198 at depth 2, 62 at depth 3,
7 at depth 4 — which is why a bounded walk suffices and no call graph is needed.

**The whole chain stays in one file, and that is a consequence rather than a restriction.**
Each link is a call to a `private` declaration and `private` is file-scoped, so if A is
private and B calls it, B is in A's file; if B is private too, so is its caller. The walk
cannot leave the file until it reaches something visible, which is exactly where it stops.

**The caveat states the hop count when it is not 1.** A reader told to state the law on
something that does not call the subject directly would look for the call, fail to find it,
and distrust the advice. End to end this took the rendered rows on `SwiftInferCLI` from
**102 to 120**, 29 of them indirect.

**The 92 with no caller** are the genuine member-call blind spot plus helpers nothing calls
in-file.

### "Nearest" barely needs defining

**534 of 561 have exactly one visible caller.** The tie-break rule this was expected to
need applies to 27 rows, so the design decision it was blocking is close to moot: name the
single caller, and decide the rest later or list them.

---

## What this does NOT establish

**That it moves any row.** A caveat is explainability, not a law — **all 373 stay
declined**, by construction. Scoring this as throughput would be the error; PRD §4.5 makes
explainability a first-class output and this is that. Reading 260 as *260 new laws* is the
specific misreading to avoid.

**That the named caller is the RIGHT one to state the law on.** The road test's worked
example shows lifting produced a *different* law — `idempotence(normalize)` became
metamorphic spelling-insensitivity of `lookupSuggestion`, catching a mutant the
helper-level law is structurally blind to. **That is judgement, not a mechanical
transform**, and naming the caller is where the tool's contribution stops.

**Anything about another corpus.** 934 restricted functions is a fact about a package that
uses `private` heavily for helpers.

---

## The verdict

**Build the caveat.** 260 of 373, an unambiguous caller in 534 of 561 cases, and the
same-file rule is sound rather than approximate.

**Do not build auto-lifting.** The law the caller should carry is not a rewrite of the law
the helper carried, and inventing law statements is a larger claim than this catalog makes
anywhere else.

## What would reverse this

- **The visible-caller share falling below the population it explains.** Pinned by the
  control, which asserts the caller index is populated at all — a zero from an
  unpopulated `calledFreeFunctionNames` would read exactly like a corpus with no callers.
- **An index landing** (item 38), which would make the free-shape restriction unnecessary
  and the same-file rule redundant rather than sound.
