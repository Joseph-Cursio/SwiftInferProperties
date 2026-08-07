# Road-test — ReplayIdempotenceTemplate against MacCloud_server (2026-08-06)

> **Status:** `measured` · **As of:** 2026-08-06


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

## Broadened to the public trial corpus (2026-08-06) — and the precision blowup it caught

MacCloud is one app with two genuine handlers. Two handlers validate *recall*; they cannot
validate *precision*. So the finished template (M1+M2+M3) was swept across **8 public repos**
— the upstreams of SwiftIdempotency's own package trials (HelloVapor, luka-vapor, penny-bot,
VernissageServer, plc-handle-tracker, parse-server-swift, wallet, HomeAutomation), each pinned
to the trial's commit, each written by strangers who never saw this tool. (AmpFin excluded:
the `swiftdata-sample` fixture was modelled on it, so it grades its own homework. vreader failed
to clone at its pin.) Syntax-only `discover --sources … --include-possible`, no builds.

**First sweep: 12 hits, mostly false positives.** The 2-handler MacCloud pass had looked clean;
the breadth pass did not. Two false-positive classes, verified against source:

- **`isCancelled` fired on cooperative cancellation.** penny-bot's three hits were all
  `if Task.isCancelled { return }` in background `run()` loops — the single most common idiom
  in async Swift, nothing to do with dedup. `isCancelled`/`isCanceled` never belonged in the
  state-flag set.
- **The pre-fetched reader fired on pure getters.** `getReblogStatus`,
  `getRegisteredExternalUser` (Vernissage), a mock middleware (HelloVapor) — `let x =
  query().first(); if let x { return x }`, reads with **no insert or effect at all**. The
  detector never checked that an effect *followed* the gate, so "fetch-then-**insert**" was a
  misnomer for "fetch-then-return", which every nullable getter matches.

**And a recall gap the same sweep exposed.** penny's *real* dedup —
`guard await cache.canGiveCoin(…) else { return }`, keyed on `(sender, message)` — is a
`guard` with a domain-named method, and the template handles neither. So on penny it fired
three times on cancellation noise and stayed silent on the one genuine handler. The worst
pairing, and only a broad corpus shows it.

## Fix — M4 precision pass (licensed by the same external oracle)

- **Tightened `stateFlags`** — dropped `isCancelled`/`isCanceled` and the ambiguous lifecycle
  flags (`isComplete`/`isDone`/`isFinished`/`isClosed`/`isExpired`); kept the set that reads
  "this key was already handled" (`isDeleted`, `isHandled`, `isProcessed`, …).
- **Required a guarded effect** — `classify` now returns a shape only if the body performs an
  effect-verb call (`insert`/`save`/`create`/`delete`/`publish`/…). A gate that guards nothing
  is a getter's early return, not a dedup gate. (Effect-*dominance* — the effect sits on the
  path the gate skips — is a finer check left to a later slice; "the body has an effect at all"
  removes the getters without it.)
- **Deferred, and named honestly:** `guard`-form gates and domain-named dedup methods
  (`canGiveCoin`) remain uncaught. No verb list covers them; that is the fundamental
  spell-checker-dictionary boundary, not a bug M4 can close.

## Re-sweep: 12 → 5, and the 5 are real

| repo | first sweep | after M4 |
|---|---|---|
| penny-bot | 3 (all `isCancelled`) | **0** |
| HelloVapor | 1 (mock middleware) | **0** |
| VernissageServer | 8 (getters + upserts) | **5** |
| the other 5 | 0 | 0 |

The five survivors are all in VernissageServer, and every one verified against source is a
**genuine fetch-or-create dedup handler** where replaying matters:

- `follow` — return the existing follow or create one (no duplicate follows on retry)
- `getTwoFactorToken` — return the existing token or generate+save (no duplicate 2FA tokens)
- `mute` — fetch-and-update or create (no duplicate mutes)
- `update` — settings upsert
- **`flag`** — the **ActivityPub inbox `Flag`** handler, dedup-gated on `activity.id`
  (`if let report = Report.query().filter(activityPubId == activity.id).first() { return }`).
  This is the *exact* handler the Vernissage trial's answer key identified by hand
  (`IdempotencyKey(fromAuditedString: "ap-inbox:\(activity.id)")`) — surfaced here **from its
  shape alone**, independently of that key.

MacCloud's two true positives are unchanged (both carry `save`). False-positive rate on the
corpus: ~10/12 → **0/5**.

## Net

The broad oracle did what the narrow one couldn't: it refuted a green self-assessment (M3
looked clean on two handlers, over-fired on real code), and the fix it licensed left the
template surfacing **real replay-idempotency handlers in real public servers from their shape**
— up to and including one a careful adopter had already flagged by hand. The ledger's honest
entry is not "it works" but "it over-fired, an external corpus caught it, the fix held, and
what survives is true." The recall boundary (guard-form, domain-named dedup) is written down,
not papered over.

## Closing the guard-form recall gap (M5)

The M4 boundary named a real miss: penny-bot's *actual* dedup is
`guard await cache.canGiveCoin(sender, message) else { return }` — a `guard`, which the
classifier only handled as an `if`, and a domain-named capability verb (`canGiveCoin`), which
no curated dedup-verb list covers. Two changes close it:

- **`guard`-form gates** — `guard <claim> else { return }`, with `guard`'s inverted polarity
  handled: it returns when the condition is *false*, so a dedup reads as a positive claim-once
  capability (`canGive…`, `shouldProcess`) or a negated dedup check (`!hasHandled`). The
  else-block must **return** (not `throw`), which excludes the `guard permission else { throw }`
  authorisation shape; the capability prefixes deliberately exclude the *permission* family
  (`canWrite`/`canAccess`/`canRead`/…), which is authorisation, not dedup.
- **Prefix-matched effect verbs** — M4's exact-match `effectVerbs` missed penny's effect,
  `postCoin` (not a bare `post`). Effects are now prefix-matched (`postCoin`→`post`,
  `createMessage`→`create`, `markAsDeleted`→`mark`), so the M4 effect requirement still gates
  but recognises real-world spellings.

The precision risk was real — a broad capability heuristic plus a weakened effect filter is
exactly the shape that over-fired at M3 — so it was **re-swept across all 8 repos before
shipping**:

| repo | M4 | M5 |
|---|---|---|
| penny-bot | 0 | **1** — `ReactionHandler.handle()`, the real `canGiveCoin` dedup |
| VernissageServer | 5 | 5 (unchanged, all genuine) |
| the other 6 | 0 | 0 |

**6 hits, all genuine; zero new false positives.** The guard-form detection added exactly the
one real handler the M4 write-up had named as missed — the handler this whole broadening was
prompted by — and the prefix-effect weakening did not reintroduce the getter false positives
(the M3 getters call no mutation-prefix verb). MacCloud's two are unchanged.

What remains outside is now genuinely narrow: a dedup whose *only* signal is a domain verb the
capability prefixes don't reach, with no `guard`/`if`/flag/fetch shape to corroborate it. That
is the irreducible spell-checker-dictionary floor, not a shape left on the table.
