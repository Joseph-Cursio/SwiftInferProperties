# Road-test — ReplayIdempotenceTemplate against MacCloud_server (2026-08-06)

The external-oracle validation the M1/M2 sketch demanded. `ReplayIdempotenceTemplate`
(M1 annotation + key parameter, M2 dedup-gate walker) was pointed at `MacCloud_server`
— real, unplanted, and **written before the SwiftIdempotency grammar existed**. The
frozen-answer-key rule is satisfied by that provenance: the handlers' own docstrings and
the §26.8 field report are an answer key that predates the template and was written by
someone who never heard of it.

Outcome: **0 replay-idempotence suggestions.** Per the road-test discipline a confident
zero is investigated, not accepted — and the investigation splits it into legitimate
silence and **two real misses of docstring-declared idempotent handlers**. This is the
same boundary the book documents (Appendix C's spell-checker-missing-`intersection`
story), reached now from the template's own side.

## Setup

```
swift-infer discover --sources MacCloud_server/Sources/MacCloudServer --include-possible
```

`--include-possible` is required: replay-idempotence lands at `.possible` (a single
signal) and is hidden by default. The run surfaced 4 suggestions (1 value-idempotence,
3 predicate), all noise, and **zero replay-idempotence**.

## The zero, investigated

### Legitimately silent (correct)

- **No `@ExternallyIdempotent` / `IdempotencyKey` anywhere.** MacCloud_server predates the
  grammar, so Branches A and B have nothing to match. Correct silence, not a miss.
- **`uploadFile` / `createFolder` reject duplicates by *throwing*** (`if fileExists { throw
  .fileAlreadyExists }`). Not idempotent as written — a retry errors rather than
  succeeding — so proposing idempotency would be wrong. Correct.

### Two real misses

Both are `async throws` handlers whose **own docstrings declare them replay-idempotent**,
squarely the template's target population, both missed.

**1. `deleteFile`** — `Routes/FileRoutes.swift`. Docstring: *"Replayed DELETE … must be
idempotent … a repeat is acknowledged without double-decrementing"* (§26.8's
double-decrement bug lived on these routes). Textbook early-return dedup gate:

```swift
if file.isDeleted { return .ok }
```

Missed because the gate condition is a **state property** (`file.isDeleted`), not a
dedup-verb **method call** (`dedup.hasHandled(...)`). The M2 detector's `CallVerbFinder`
only looks for a call — because the fixture it was built from (`OrderCreatedHandler`)
guards with `if await dedup.hasHandled(orderID:) { return }`. The property form is the
same *semantic* gate in a different *syntactic* dress, and the detector never took it up.

**2. `restoreFileVersion`** — `Routes/FileRoutes.swift`. Docstring: *"a replay must not
stack another identical version … if the latest version already carries the source's
content, acknowledge without creating a new row."* Content-addressed dedup:

```swift
let latest = try await FileVersion.query(on: req.db)...first()   // fetch is a PRIOR statement
if let latest, latest.hash == version.hash, latest.storagePath == version.storagePath {
    return FileResponse(from: file)
}
```

Missed on two counts, both harder than deleteFile: the fetch is a **separate upstream
statement** (not inside the `if let` binding `fetchThenInsert` inspects), and the dedup is
a **content-hash equality**, not a binding-whose-initializer-is-a-fetch.

## Verdict — the boundary, mapped honestly

The template graded its own homework perfectly on the fixtures (M1 + M2, every test green).
But the fixtures are its author's own. Pointed at code it was never tuned against, it is
blind to two genuine handlers, because MacCloud expresses the *same* replay-idempotency in
*different idioms*: a **state-property guard** and a **content-addressed, pre-fetched
dedup**, versus the fixtures' method-call-and-inline-fetch. The confident zero was ~half
legitimate silence and ~half a real recall gap — and the only reason that is knowable is
that the oracle predates and is independent of the template. An internal benchmark could
not have surfaced it; the fixtures agreed with the detector by construction.

This is not the exercise failing. It is the exercise doing the one thing an external oracle
is for: refuting a green self-assessment.

## Fix — licensed, and taken (M3)

Extending the detector until it catches these two is **licensed** by the same rule that
licensed the swift-collections `symmetricDifference` fix: the oracle is external, so the
change responds to MacCloud's docstrings, not to the template's own fixtures. Two
miss-classes, added as M3 (`DedupGateShape` gains a `.stateFlagGuard` case; the fetch-then-
insert reader learns the pre-fetched form):

1. **State-property early-return gate** — `if <handledFlag> { return }` where the property
   reads as handled-state (`isDeleted`, `isHandled`, `isProcessed`, `isCancelled`, …), with
   a precision guard so `if x.isEmpty { return }` does not false-fire.
2. **Pre-fetched / content-addressed dedup** — a fetch bound in an upstream statement, then
   an `if let latest, <equality> { return … }` gate.

Re-validation after M3 is recorded at the foot of this file.

## Still out of scope (honest boundary, not a miss to fix)

`uploadFile`/`createFolder`'s reject-on-duplicate is a *different* retry-safety shape
(reject, not resume) and is genuinely not idempotent; the template is correct to stay
silent. The natural idempotence of an operation with no gate at all (a pure overwrite)
remains outside every shape in the catalog, by design.

## Re-validation after M3 (2026-08-06)

Same command, same `--sources`, after M3 shipped (`DedupGateShape.stateFlagGuard` +
the pre-fetched fetch-then-insert form):

```
Template: replay-idempotence · Score 30 (Possible)
  ✓ deleteFile(req:)         FileRoutes.swift:184
    Body has a dedup gate (an early return on an already-handled state flag on `isDeleted`)
  ✓ restoreFileVersion(req:) FileRoutes.swift:374
    Body has a dedup gate (a fetch-existing-then-insert branch)
```

**Both misses now surface — and exactly those two.** `uploadFile`/`createFolder` stay
silent (they throw rather than return, so `blockReturns` is false and the gate never
fires): the recall gain did not cost the precision. The loop is closed end to end —
validate → confident zero → investigate → two real misses → licensed fix → re-validate,
both caught, nothing spurious.

The honest ceiling, restated: the score is `.possible`, not a verdict. The template
proposes the right property on the right two handlers *from their shape*; a human still
writes the effect recorder and confirms the law holds. Band promotion past `.possible`
stays gated on this same external evidence, never the fixtures.
