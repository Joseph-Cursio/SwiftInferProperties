# Falsifier naming — measured failure modes of the deferral convention

> **Status:** `measured` · **As of:** 2026-08-10

The convention is `(falsifier: ``Symbol``)` beside a deferral, and `DeferralFalsifierTests`
fails the day `Symbol` resolves in the tree. It was built because prose could not be guarded —
four text detectors were measured and declined (`stale-summary-guard-declined.md`), all beaten
by the same structural fact: this repo corrects by annotation, so a fixed doc keeps the wrong
sentence and a text detector fires on it forever. A falsifier is checked against the **tree**,
not another sentence.

**That reasoning is still right. This records the failure mode it does not cover.**

## 1. The guard can only fail in one direction

`DeferralFalsifierTests` fails when a falsifier **resolves**. There is no state in which it
fails because a falsifier will *never* resolve. So:

| falsifier | guard says | reality |
|---|---|---|
| names a symbol the fix will create | green until the fix lands, then red | works |
| names a symbol nobody will ever create | **green forever** | **inert** |

The two are indistinguishable from the guard's output, which is the same shape as every site
the 2026-08-09 silent-swallow sweep changed: an empty result a reader cannot tell from a real
one.

## 2. Measured: two went inert the same week

**`nestedCarrierImportResolution`** — written beside *"the per-entry `@testable import` does
not reach a nested carrier — the cheapest open item left"*. The fix shipped as
`VerifyCommand+NestedCarrier.swift` + `NestedCarrierQualificationTests` (`e5731a9`, PR #206).
Nothing was ever named `nestedCarrierImportResolution`, so the falsifier resolved to nothing
and the guard stayed green while the deferral read as open. It survived in CLAUDE.md — the
index everyone reads — until 2026-08-10, by which point **all three parts of the gap were
closed and `build-failed` was zero**.

**`IndexedTypeShape.accessLevel`** — written beside a deferred schema change. The investigation
then found the change unnecessary (§9.7: the verdict already existed one stage upstream, as
prose). The falsifier is *correctly* unresolved, but for a reason it cannot express: the
deferral was not pending, it was **void**.

## 3. The split that predicts it

Population at 2026-08-10, after retiring the inert `nestedCarrierImportResolution` — **10
occurrences over 8 distinct symbols**, two sibling ones being cited from two docs each. Both
counts are given because they differ and the guard reports occurrences:

| kind | occurrences | distinct | examples | fails how |
|---|---|---|---|---|
| **sibling-scoped** | 5 | 3 | `SwiftPropertyLaws/checkGroupActionPropertyLaws`, `SwiftProjectLint/DuplicateImplementationRule` | reliably |
| **local** | 5 | 5 | `perSlotBoundaryRotation`, `composeInvariantPreservationPass`, `Pairing.permuted` | may never |

**Both of the inert ones were local, and every sibling one is sound.** The mechanism is not
luck: a sibling falsifier names **another repo's published API**, a name that repo will
actually use if it ships the thing. A local falsifier names **an internal symbol nobody is
obliged to create** — the author is predicting the shape of a fix that has not been designed,
and any competent implementation is free to call it something else.

## 4. The rule this supports

**Name what the fix must expose, not what you imagine calling it.**

* **Best** — a sibling repo's public API (`SwiftPropertyLaws/checkRingPropertyLaws`). Stable,
  published, and the other repo has no reason to pick a different name.
* **Good** — an *existing* local symbol whose presence or behaviour the fix must change, so the
  falsifier is checked against something that already exists.
* **Fragile** — a new local symbol invented at deferral time. `perSlotBoundaryRotation`,
  `composeInvariantPreservationPass` and `VerifierWorkdir.dependencyProductEdge` are all this
  shape today and are all one naming decision away from going inert.
* **Wrong** — a symbol for a change that might turn out unnecessary. `IndexedTypeShape.accessLevel`
  was this: the deferral needed a *witness* (does the situation still arise?), not a symbol.

**Where no symbol fits, defer on a witness instead.** §9.8 declined ambiguous nested-carrier
resolution on measurement — zero rows decline for that reason, 27 ambiguous leaf names, none
ever a carrier — and reopens on *a row that declines because of ambiguity, on any corpus*. That
is checkable, cannot go inert, and does not require guessing an implementation's name.

## 5. What is NOT built, and why

**No detector for "this falsifier will never fire."** It would have to know what a future fix
will be called, which is the thing the author could not know either. A text detector over the
surrounding prose is the arm `stale-summary-guard-declined.md` already measured at **0/11
precision at HEAD**, for the reason that applies here too: the correcting annotation sits
beside the stale claim forever.

**What is built is smaller and sound**: `DeferralFalsifierTests` now reports the pending
population — count, and the local/sibling split — so an inert falsifier is *visible in the
output* rather than silently green. It does not change the verdict. That is the same remedy the
silent-swallow sweep applied eleven times: when a check cannot distinguish two states, make the
state legible rather than guessing.

## 6. What would falsify this document

A **sibling-scoped** falsifier going inert, or a local one surviving a fix that renamed around
it. Either would mean the split in §3 is coincidence rather than mechanism. Two data points are
two data points; the argument in §3 is why they should generalise, not evidence that they do.
