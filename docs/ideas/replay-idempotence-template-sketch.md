# `ReplayIdempotenceTemplate` — match-rule sketch

*A discovery template for effectful replay-safe handlers. Design source: SwiftIdempotency's
[replay-idempotency shape catalog](../../../SwiftIdempotency/docs/replay-idempotency-shape-catalog.md)
and its four fixtures. Status: **proposal**, not built.*

## Where it fits in the two existing mechanisms

swift-infer has two template mechanisms, and replay-idempotency belongs to **neither as-is**:

- **Algebraic / value templates** (`TemplateName`, the `verifiable` set). `IdempotenceTemplate`
  lives here and proves `f(f(x)) == f(x)` for a *pure* function. A replay handler is not pure
  and its law is not over return values, so this path can't carry it.
- **Interaction-invariant families** (`InteractionInvariantFamily`, `InteractionTemplateFamily`).
  `IdempotenceInteractionTemplate` lives here — but its subject is a **reducer** (`State`, `Action`),
  witnessed by an *action-case name*, and its own caveat is that it never inspects the body. A
  replay handler has no `Action` enum and its idempotence is a fact about its *body and key
  parameter*, not a name.

So the proposal is a **third witnessed family**, modelled structurally on
`IdempotenceInteractionTemplate` but with its own witness and its own candidate:

| Existing | Proposed analogue |
|---|---|
| `ReducerCandidate` | **`HandlerCandidate`** — a `FunctionSummary` that passes the pre-filter below |
| `IdempotenceWitness` (action-case name) | **`ReplayIdempotenceWitness`** (shape + key parameter) |
| `IdempotenceWitnessDetector` | **`ReplayIdempotenceWitnessDetector`** |
| emits `InteractionInvariantSuggestion` (algebraic stub) | emits a suggestion whose stub is `assertIdempotentEffects` (SwiftIdempotencyPropertyBased) |

The good news is that almost every signal the match rules need is **already on `FunctionSummary`**:
`parameters` (label + `typeText`), `isAsync`, `isThrows`, `returnTypeText`, `docComment`,
`declaredEffect: Effect?` (parsed on the default path), `inferredEffect: Effect?` (opt-in
`--resolve-effects`), and `bodySignals`. Exactly one new body signal has to be built; it is called
out explicitly in §5.

---

## 1 · The pre-filter — is this a `HandlerCandidate` at all?

Cheap gate that runs before witness detection, to keep the template off pure functions and getters
(which the value templates already own). A `FunctionSummary` is a candidate if **all** hold:

```
summary.returnTypeText != "Bool-only trivia is fine here"   // return type is NOT disqualifying
&& !summary.isInferredPure                                    // pure → value idempotence owns it
&& (summary.isAsync || summary.isThrows                       // an effect boundary is plausible …
    || summary.declaredEffect.isExternallyIdempotent          // … or an explicit retry-safety claim
    || summary.parameters.contains { $0.typeText == "IdempotencyKey" })
&& !summary.isComputedProperty && !summary.isInitializer
```

Rationale: replay handlers are effectful (`async`/`throws`), or they *announce* themselves with an
`IdempotencyKey` parameter or an `@ExternallyIdempotent` annotation. A pure `Int`-returning function
is not a replay candidate no matter what its name is — that's the `.possible`-band mistake the
reducer template's name-only matching makes, and this pre-filter is how we avoid inheriting it.

---

## 2 · The witness detector — the four shapes as gates

Each shape from the catalog becomes one branch. A branch fires a `ReplayIdempotenceWitness`
carrying the shape and the **key parameter to hold fixed** (the single most important payload —
it's what the emitted property quantifies over). Branches are ordered strongest-signal-first; the
first to fire wins.

```swift
public struct ReplayIdempotenceWitness: Sendable, Equatable, Codable {
    public enum Shape: String, Sendable, Codable, CaseIterable {
        case keyFromEntity        // catalog Shape 1
        case dedupGate            // catalog Shape 2
        case fetchOrInsert        // catalog Shape 3
        case routeThroughKey      // catalog Shape 4
    }
    public let shape: Shape
    public let keyParameterLabel: String?   // the param to hold fixed; nil ⇒ derived internally
    public let evidence: Evidence           // .annotation / .keyParameter / .bodyStructure / .docstring
}
```

### Branch A — annotation-driven (Shapes 3 & 4, matches **today**)

The strongest signal, and it needs no new machinery because `EffectAnnotationParser` already
populates `declaredEffect` on the default path:

```swift
if case let .externallyIdempotent(keyParameter) = summary.declaredEffect {
    // @ExternallyIdempotent(by: "idempotencyKey") — the author has claimed it.
    // Distinguish Shape 3 (returns a persisted row) from Shape 4 (effect via a
    // closure/boundary parameter) by the return type + a boundary param.
    let shape: Shape = summary.hasEffectBoundaryParameter ? .routeThroughKey : .fetchOrInsert
    return Witness(shape: shape, keyParameterLabel: keyParameter, evidence: .annotation)
}
```

`Effect.externallyIdempotent(keyParameter:)` hands us the exact parameter label to quantify over —
`OfflineManager.download`'s `"idempotencyKey"`, `AcronymService.notifyCache`'s `"idempotencyKey"`.
That is a gift: the property doesn't have to *guess* the key, the annotation names it.

> Note this branch discovers a property for a handler the author already *annotated* but may not have
> *tested*. That is the missing direction of the annotate-once-enforced-twice loop: the linter enforces
> the claim, this template proposes the property that would actually exercise it.

### Branch B — key-parameter builder (Shape 1, matches **today**)

```swift
if let key = summary.parameters.first(where: { $0.typeText == "IdempotencyKey" }),
   summary.isInferredPure == false,
   summary.bodySignals.hasNonDeterministicCall == false {
    // A handler taking a stable key but no gate/annotation — the pure builder shape.
    return Witness(shape: .keyFromEntity, keyParameterLabel: key.label, evidence: .keyParameter)
}
```

Also fires the degenerate form: a function whose body calls `IdempotencyKey(fromEntity:)` /
`IdempotencyKey(fromFluentModel:)` on an `Identifiable`/`Model` parameter (needs a lightweight body
signal — see §5, cheaper than the gate one). `StripeWebhookHandler.makeChargeRequest` matches here.

### Branch C — structural gate (Shapes 2 & 3 **unannotated** — needs the new signal in §5)

This is the branch that earns the template its keep, because it finds handlers **nobody claimed**:

```swift
if let gate = summary.bodySignals.dedupGate {      // ← NEW signal, see §5
    let shape: Shape = gate.kind == .fetchThenInsert ? .fetchOrInsert : .dedupGate
    return Witness(shape: shape, keyParameterLabel: gate.keyExpressionRoot, evidence: .bodyStructure)
}
```

`dedupGate` recognises the two body structures the catalog names:
- **early-return dedup** — `if <dedupCheck>(<keyExpr>) { return }` before an effect
  (`OrderCreatedHandler`: `if await dedup.hasHandled(orderID: order.id) { return false }`).
- **fetch-then-conditional-insert** — a fetch keyed on `<keyExpr>`, an early return of the hit, an
  insert only on the miss (`OfflineManager.download`).

### Branch D — docstring corroboration (evidence booster, never a sole trigger)

Reuse the existing `DocstringAdvisor` / round-trip docstring-corroboration machinery. If the doc
comment says "idempotent", "retry", "safe to run twice", "same key … same row", raise the witness's
score band but **never** let it be the only evidence — a sentence is corroboration, not a gate. This
mirrors `RoundTripTemplate+DocstringCorroboration`.

---

## 3 · Vetoes — the false-positive killers

Mirror the `IdempotenceTemplate+*Veto` family: each veto is a `Signal(kind:, weight: Signal.vetoWeight)`
composed into the witness's score. The replay shapes have their own failure modes:

| Veto | Fires when | Why |
|---|---|---|
| **`nonStableKeyVeto`** | the key expression roots in `UUID()` / `Date()` / an RNG (reuse `bodySignals.hasNonDeterministicCall` + `nonDeterministicAPIsDetected`) | a per-invocation "key" makes the claim a lie — the exact twin the catalog names for every shape |
| **`mutatingAccumulatorVeto`** | body increments a counter / appends to unbounded storage *outside* the gate | the reducer template's stated blind spot; here we can actually see it via body signals |
| **`unkeyedEffectVeto`** | an effect statement exists on a path the gate/key does not dominate | the effect isn't actually guarded by the key — Shape 2's `BuggyOrderHandler` with the gate deleted must land here |
| **`declaredNonIdempotentVeto`** | `declaredEffect == .nonIdempotent` or `inferredEffect == .nonIdempotent` | the author (or `EffectResolver`) denied the law; respect the denial, same posture as the value template's declared-effect handling |

`unkeyedEffectVeto` is the load-bearing one: it is what makes Branch C **refutable rather than
credulous**. Pointed at `BuggyOrderHandler` (gate removed, unconditional `repo.insert`), the effect no
longer sits behind a dedup check, the veto fires, and the handler is correctly *not* proposed as
idempotent. That is the fixture-level acceptance test for the whole template (see §6).

---

## 4 · Scoring, tiering, and what it emits

Follow `IdempotenceInteractionTemplate`'s calibration discipline exactly:

- **Start at `.possible` (score 30).** Do **not** ship at `.likely`. The reducer idempotence family
  earned promotion to 40 only after 100% acceptance across three calibration cycles (the PRD §3.5
  ≥70%×3 gate). Replay idempotence starts unproven and earns its band the same way.
- **Tier by evidence.** Branch A (annotation) is inherently higher-confidence than Branch C (inferred
  structure); let the `evidence` field bias the initial score so an author's own `@ExternallyIdempotent`
  outranks a body-structure guess.
- **Emit an effect property, not an algebraic law.** The stub is `assertIdempotentEffects`, not
  `#expect(once == twice)`:

```swift
// Emitted stub for a .dedupGate / .fetchOrInsert / .routeThroughKey witness:
try await assertIdempotentEffects(recorders: [/* inject at the effect boundary */]) {
    _ = try await <handler>(<fixed args, key held constant at witness.keyParameterLabel>)
}
// For a .keyFromEntity (pure) witness, the value form is enough:
#assertIdempotent { <handler>(<fixed entity>) }
```

  This is why replay idempotence can't ride the existing emitters: three of its four shapes state the
  property over **effects**, which the algebraic-law stub emitter has no vocabulary for. It needs the
  `SwiftIdempotencyPropertyBased` product as the emit target.

**`whySuggested` / `whyMightBeWrong`** (the honest pair every template ships):

- *why suggested* — `"Handler carries @ExternallyIdempotent(by: \"idempotencyKey\") and an effect
  boundary; two calls under the same key should produce the same observable effect."` (Branch A) /
  `"Body has a dedup gate (early return on hasHandled(order.id)) before its only effect."` (Branch C).
- *why might be wrong* — `"Idempotence holds only if the key is stable across retries; a key derived
  from UUID()/Date() breaks it."` · `"The effect boundary must be fully observed by the injected
  recorder — an unrecorded side effect (log line, metric) is invisible to the property."` ·
  `"Structural gate detection assumes the gate dominates every effect path; a second effect outside
  the guarded branch is not covered."`

---

## 5 · The one thing that has to be built: `BodySignals.dedupGate`

Honest boundary. `BodySignals` today carries `hasNonDeterministicCall`, `hasSelfComposition`,
`reducerOpsReferenced`, `equalityBodyShape`, `idempotenceReturnShape` — all aimed at *value*
idempotence. **None recognises a dedup gate.** So:

- **Branches A and B match today** — annotation-driven and key-parameter detection use
  `declaredEffect` and `parameters`, both already populated.
- **Branch C requires a new signal.** Add `dedupGate: DedupGateSignal?` to `BodySignals`, computed by
  a small body walker that recognises the two structures in §2 (early-return-on-dedup-check;
  fetch-then-conditional-insert) and records the key expression's root identifier. Model the walker on
  the existing body-signal detectors (the ones that populate `hasNonDeterministicCall` /
  `idempotenceReturnShape`).

This staging matters for a first cut: **ship Branches A+B first** (zero new body analysis, immediately
finds the *annotated-but-untested* handlers — a real, useful population), and add Branch C's
`dedupGate` walker as a second milestone once A+B's precision is calibrated. That also keeps the risky
part (structural inference of an unannotated gate) behind the safe part (reading a claim the author
already wrote).

---

## 6 · Validation — the fixtures are the dev set, never the evidence

The four fixtures (`StripeWebhookHandler`, `OrderCreatedHandler`, `OfflineManager.download`,
`AcronymService`) plus `BuggyOrderHandler` are the **regression/acceptance set**:

- All four handlers must be **proposed** (one witness each, correct shape + key parameter).
- `BuggyOrderHandler` must be **rejected** by `unkeyedEffectVeto` — the refutability check.
- A key derived from `UUID()` must be **rejected** by `nonStableKeyVeto`.

But — the same rule the catalog and Appendix C insist on — these fixtures were written by
SwiftIdempotency's author. Tuning the template against them and reporting "it finds them" is the
*grade-your-own-homework* trap; the frozen-answer-key discipline forbids counting it as evidence the
template works. The evidence has to come from an **external oracle**: point the calibrated template at
`MacCloud_server`, whose retry-safety bugs on the file and version-restore routes were real and
unplanted (§26.8), and ask whether it proposes the effect property on the handlers that carried those
bugs *before* looking at the fixes. That is the same posture that licensed the swift-collections
`symmetricDifference` catch — an oracle that predates the tool.

---

## Build order, in one line

**M1** Branches A+B (annotation + key-parameter), `.possible` band, `assertIdempotentEffects` emitter,
fixtures as regression set. → **M2** `BodySignals.dedupGate` walker + Branch C + the four vetoes. →
**M3** calibrate on `MacCloud_server`; promote the band only after the ≥70%×3 gate on an external corpus.
