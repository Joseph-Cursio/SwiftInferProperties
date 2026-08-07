# `ReplayIdempotenceTemplate` — match-rule sketch

*A discovery template for effectful replay-safe handlers. Design source: SwiftIdempotency's
[replay-idempotency shape catalog](../../../SwiftIdempotency/docs/replay-idempotency-shape-catalog.md)
and its four fixtures. Status: **shipped (M1–M5, 2026-08-06)** — this document is the original
plan; see the "As built" note below for where reality diverged, and
[`roadtest-maccloud-server-replay.md`](../measurements/roadtest-maccloud-server-replay.md) for the validation
journey.*

## As built (M1–M5) — plan vs reality

The template shipped. The sections below are preserved as the design thinking, but the
implementation diverged in a few load-bearing ways — recorded here rather than edited into each
section, so the plan stays legible next to what it became.

| Plan (this doc) | As built | Where |
|---|---|---|
| A **third witnessed family** (`HandlerCandidate` / `ReplayIdempotenceWitness` / `…Detector`) modelled on `IdempotenceInteractionTemplate` | A **Constraint-Engine template** (`ReplayIdempotenceTemplate.suggest → ConstraintRunner`), like the value templates. Simpler; no witness/candidate/detector types were needed. | M1 |
| `BodySignals.dedupGate` walker (§5) | Shipped as `BodySignals.dedupGateShape` + `DedupGateClassifier`, gated to `throws`/`async` functions. | M2 |
| Branches A (annotation) + B (`IdempotencyKey` param) | Shipped as-designed. `+35` / `+25`; both → `.likely`, either alone → `.possible`. | M1 |
| Branch C shapes: early-return dedup, fetch-then-insert | Shipped, **plus two the fixtures didn't show** and the external corpus did: `stateFlagGuard` (`if file.isDeleted { return }`, M3) and `guardDedup` (`guard canGiveCoin() else { return }`, M5). Fetch-then-insert also learned a **pre-fetched** form (M3). | M2/M3/M5 |
| Branch B′ `keyFromEntity` (the pure builder, `StripeWebhookHandler`) | Shipped (M6) via a `BodySignals.buildsIdempotencyKey` marker (`IdempotencyKey(…)` construction — precise, SwiftIdempotency-specific). Being a **pure value builder** it bypasses M4's effect requirement and emits the **value** form (`#assertIdempotent`), not the effect form. **Uniquely has no external oracle:** no public repo adopts `IdempotencyKey`, so recall is confirmed only on the fixture and precision is by-construction (the type name), not measured. | M6 |
| The four vetoes — `unkeyedEffectVeto` as the load-bearing refutation | Shipped `declaredNonIdempotentVeto`; `nonStableKey` stayed a **soft counter**, not a hard veto. `unkeyedEffectVeto` was replaced by M4's simpler **effect requirement** (a gate must guard an actual effect-verb call, or it is a getter) — forced by the public-corpus sweep, where effect-less getters were the dominant false positive. `mutatingAccumulatorVeto` not built. | M4 |
| Emit a filled-in `assertIdempotentEffects` | Emits a **`.todo` scaffold** that fails via `Issue.record` until completed — the effect recorder can't be synthesized, as §4 anticipated. | M1 |
| `.possible` band, promotion gated on external evidence | Held at `.possible` through M1–M8, then **promoted (M9, 2026-08-07)**: the annotation (a *claim*) and the structural gate (which cleared the ≥70%×3 external gate, 8/8 across M5/M7/M8) each reach `.likely` alone, so genuine findings surface by default. The two weak signals (key parameter, key builder) stay `.possible`. | M1–M9 |
| Effect requirement: an effect must *exist* (M4) | **Sharpened to effect-*dominance* (M7):** the effect must sit at or after the gate, so an effect that ran *before* a too-late gate no longer qualifies (`insert(order); if hasHandled { return }` is now rejected). Left corpus results unchanged (all genuine gates dominate their effect); closes a latent false-positive class. | M7 |
| `mutatingAccumulatorVeto` (one of the four proposed vetoes) | **Shipped (M8):** a member compound-assign (`self.count += 1`) or member `.append` in the statements *before* the gate vetoes it — an ungated accumulation runs on every replay, so the handler is not idempotent despite the gate. Member-scoped (a local accumulator resets each call and doesn't count). Corpus unchanged; closes a latent false-positive class M7's call-based dominance can't see. | M8 |
| **Deferred, still open** | The irreducible floor — a dedup whose only tell is a domain verb no capability prefix reaches, with no `guard`/`if`/flag/fetch/key-builder shape to corroborate. | — |

**Validation went further than the plan's single-oracle §6.** MacCloud_server (M3) caught two real
handlers; an 8-repo **public trial corpus** (M4) then caught the template *over-firing* (~10/12 false
— a precision blowup a two-handler oracle had hidden), whose fix cut it to 0 false; the M5 guard-form
close was re-swept on that corpus *before* shipping. The honest ledger is in the road-test doc.

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

## Build order — as shipped

- **M1** — Constraint-Engine template; Branches A+B (annotation + `IdempotencyKey` param); `.possible`
  band; `assertIdempotentEffects` `.todo`-scaffold emitter; fixtures as regression set.
- **M2** — `BodySignals.dedupGateShape` walker + `DedupGateClassifier` + Branch C (early-return dedup,
  fetch-then-insert). Refutation is structural: no gate → no proposal, so `BuggyOrderHandler` needs no
  veto.
- **M3** — `MacCloud_server` road test (external oracle). Its confident zero, investigated, exposed two
  missed idioms → added `stateFlagGuard` and the pre-fetched fetch-then-insert form; both handlers then
  surfaced.
- **M4** — 8-repo public trial-corpus sweep caught the template over-firing (~10/12 false: `isCancelled`
  cancellation + effect-less getters). Fix: tightened the state-flag set and **required a guarded
  effect**. Re-sweep 12 → 5, all genuine.
- **M5** — closed the guard-form recall gap: `guardDedup` (`guard canGiveCoin() else { return }`) +
  prefix-matched effects. Re-swept before shipping: 6 hits, all genuine, penny's real handler caught,
  zero new false positives.
- **M6** — the key-from-entity builder (`StripeWebhookHandler`, catalog Shape 1): a
  `buildsIdempotencyKey` marker (`IdempotencyKey(…)` construction) + a value-form (`#assertIdempotent`)
  emitter, bypassing M4's effect requirement since the builder is pure. The one branch with no
  external oracle — no public repo adopts `IdempotencyKey` — so it added zero corpus hits (confirming
  its by-construction precision) and its recall is confirmed only on the fixture.
- **M7** — sharpened M4's effect requirement to effect-**dominance**: the effect must sit at or after
  the gate. Rejects `insert(order); if hasHandled { return }` (effect before a too-late gate); left all
  corpus + MacCloud hits unchanged (every genuine gate already dominates its effect).
- **M8** — the `mutatingAccumulatorVeto`: a member `+=`/`.append` *before* the gate (an ungated
  accumulation that runs on every replay) vetoes it. Member-scoped so a local accumulator doesn't
  false-veto; corpus unchanged, closes the accumulation false-positive dominance can't see.

- **M9** — the band promotion, on the terms the project set. Two signals reach `.likely` alone:
  the **annotation** (Branch A, +35→+40) — a *claim*, not inference, so the "gate promotion on
  external evidence" rule doesn't apply (it exists to check the tool's guesses, not the author's
  declaration); and the **structural gate** (Branch C, +30→+40) — inference, so it had to clear the
  external gate, which it did (8/8 accepted across the M5/M7/M8 re-sweeps, meeting PRD §3.5 ≥70%×3).
  The two weak signals — key parameter (+25) and key builder (+25) — stay `.possible`. Effect: the
  genuine findings (MacCloud's two handlers, penny's `canGiveCoin`, Vernissage's five) now surface at
  `.likely` **by default**, not behind `--include-possible`.

  **The one honest caveat, kept in view:** the structural-gate calibration is n=8, far smaller than the
  reducer-idempotence family's n=39. The ≥70%×3 *rate* is met, but the *sample* is thin — so this
  promotion is provisional: if a larger external corpus surfaces a structural false positive, Branch C
  drops back to `.possible`. `.likely` is still discovery, not a verdict — a human writes the recorder
  and confirms the law. Promotion is never gated on the fixtures.

Three of the sketch's four proposed vetoes are now built as classifier checks —
`declaredNonIdempotentVeto` (M1), the effect requirement/dominance that subsumes `unkeyedEffectVeto`
(M4/M7), and `mutatingAccumulatorVeto` (M8); `nonStableKeyVeto` remains M1's soft non-determinism
counter. The only genuinely open item is the irreducible vocabulary floor.
