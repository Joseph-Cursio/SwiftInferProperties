# TestStore Trace Mining — Build Plan / Scope

**Status:** Slices 1–2 SHIPPED (2026-07-21); Slice 3 scoped, not started. Grounds the `docs/ideas/TestStore Trace Mining Proposal.md` direction against the current code.
**Target:** SwiftInferProperties (this repo). New extractor in `SwiftInferTestLifter`; additive threading into the interaction verify path. **No kit change for the default (payload-free replay) slice.**
**One-line goal:** seed the interaction verifier's action sequences from the orderings a repo's own TCA `TestStore` tests already contain, instead of random generation alone.

---

## 1. Why (recap, one paragraph)

`ActionSequenceStubEmitter` today drives verify by generating **random** bounded action sequences — `ActionSequenceFactory.actionSequence(forCaseIterable: Action.self, length: lower...upper)`, looped `defaultSequenceCount = 1_024` times (`ActionSequenceStubEmitter.swift:19`, `:289`). Random sampling over a k-case enum with length 0…16 spends most of its budget on orderings that never set up the precondition that makes an invariant violable. A repo's existing `TestStore` suite already ships hand-curated, meaningful orderings — every `await store.send(.foo)` is a developer asserting "this ordering matters." Mining those and checking them **first** (then continuing random) is strictly-additive coverage with short, readable counterexamples.

## 2. What already exists (so we don't rebuild it)

| Piece | Where | Reuse |
|---|---|---|
| Test-body parser (XCTest + Swift Testing → `TestMethodSummary` with `body: CodeBlockSyntax`) | `TestSuiteParser.swift` | **As-is.** The trace extractor consumes `TestMethodSummary.body`, same input the `Slicer` uses. |
| Directory scan (deterministic sorted order) | `TestSuiteParser.scanTests(directory:)` → `SwiftSourceFiles.sorted(in:)` | **As-is.** |
| Call-site walker pattern over a sliced/whole body | `DomainCallSiteExtractor.swift` (`CallSiteVisitor`) | **Template to copy.** Same `FunctionCallExprSyntax` + `trailingIdentifierName` matching idiom. |
| Reducer model (Action cases + payload types, enclosing type) | `ReducerCandidate` (`actionCases: [ActionCaseInfo]`, `enclosingTypeName`) | **Join key.** Mined trace → candidate by `enclosingTypeName`. |
| Verifier stub emit + seeded generator + per-sequence loop | `ActionSequenceStubEmitter.makeGeneratorBlock` / `makeIterationBody` | **Injection point** for replay-then-extend. |
| Single-sequence pin/replay primitive (env-var driven) | `pinSequenceEnvVar` etc. + `InteractionShrinker` | Precedent that the loop already supports externally-supplied sequence selection. |

**Nothing mentions `TestStore` anywhere in the codebase yet** — this is greenfield on top of proven parsing infra.

## 3. The one constraint that shapes the whole plan: **argument concreteness**

The interaction verifier is a **standalone `main.swift`** that imports the user module and constructs Action values itself. A mined action splits cleanly into two classes:

- **Payload-free** — `.dismiss`, `.close`, `store.send(.refresh)`. Emittable verbatim as `.dismiss` in the stub. **Fully reconstructible.**
- **Payload-bearing** — `store.send(.select(a.id))`. The arg `a.id` references a **local binding from the test body** that does not exist in the verifier. **Not verbatim-emittable** (proposal open-Q #2). Generalizing to "the `.select` case with a *generated* id" is exactly Phase-B constructibility work (`+PayloadConstructibility.swift`) and overlaps the shelved value-generator epic.

This bifurcation is the spine of the plan: **the extractor captures everything; the verify-side consumer ships payload-free first and defers payload generalization.** It mirrors the repo's recurring posture — *recognition is the cheap, reusable asset; the harder consumption rides behind it* (cf. the rule-visitor recognizer, the MVVM discoverer slices).

## 4. Phased slices

### Slice 1 — `TestStoreTraceExtractor` (the reusable asset) — ✅ SHIPPED

Pure parsing, self-contained, zero verify/kit dependency, fully unit-testable offline. Shipped as `MinedActionTrace.swift` (types) + `TestStoreTraceExtractor.swift` (extractor + `TestStoreTraceVisitor`) in `SwiftInferTestLifter`, with `TestStoreTraceExtractorTests` (11 tests: payload-free ordering, payload-bearing arg capture, `receive`-separation, reducer-through-modifier / `reducer:`-arg / trailing-mutation-closure forms, plus the four precision guards — unrelated-object, non-literal-action, multi-store separation, bare-`store` fallback). Lint silent, fast suite green. The as-built surface matches the sketch below.

**New types (`SwiftInferTestLifter`):**

```swift
public struct MinedAction: Equatable, Sendable {
    public enum Kind: Sendable { case send, receive }
    public let kind: Kind
    public let caseName: String          // "select", "dismiss"
    public let argumentTexts: [String]   // ["a.id"]; empty == payload-free
    public var isPayloadFree: Bool { argumentTexts.isEmpty }
}

public struct MinedActionTrace: Equatable, Sendable {
    public let reducerTypeName: String?  // "Feature" from `TestStore { Feature() }`
    public let initialStateExpr: String? // verbatim `TestStore(initialState:)` arg text (Slice 3 fodder)
    public let sent: [MinedAction]       // .send actions in source order
    public let received: [MinedAction]   // .receive, recorded separately (proposal open-Q #1)
    public let location: SourceLocation
}

public enum TestStoreTraceExtractor {
    public static func extract(from summary: TestMethodSummary) -> [MinedActionTrace]
    public static func extract(fromTestsDirectory: URL) throws -> [MinedActionTrace]  // scans via TestSuiteParser
}
```

**Recognition rules (SwiftSyntax visitor, `viewMode: .sourceAccurate`):**
1. Find `TestStore(...)` constructions in the body; bind their result variable name (`let store = TestStore(...)`) and capture:
   - the trailing-closure return type identifier → `reducerTypeName` (`TestStore(initialState:) { Feature() }` → `"Feature"`);
   - the `initialState:` argument's verbatim text → `initialStateExpr`.
2. Match `FunctionCallExprSyntax` where callee is `<receiver>.send` / `<receiver>.receive` and `<receiver>` is a bound `TestStore` var (fallback: bare name `store`, the overwhelming convention — accept it even if the binding walk misses, flagged low-confidence).
3. Classify the single action argument:
   - `MemberAccessExprSyntax` (`.dismiss`) → payload-free, `caseName = declName`.
   - `FunctionCallExprSyntax` whose callee is a member access (`.select(a.id)`) → `caseName = member declName`, `argumentTexts = args.map { $0.expression.trimmedDescription }`.
4. `send` → `sent`, `receive` → `received`. **Mine `send` for the user-action corpus; keep `receive` separate** (a `receive` is an effect *output*, replaying it as a user action is wrong — proposal open-Q #1).

**Hard contract:** never throws (PRD §15). No `TestStore` in a body → empty result.

**Tests (`Tests/SwiftInferTestLifterTests/TestStoreTraceExtractorTests.swift`):**
- payload-free trace (`.send(.dismiss)` × N) → correct ordered `sent`, `isPayloadFree`.
- payload-bearing (`.send(.select(a.id))`) → `caseName == "select"`, `argumentTexts == ["a.id"]`.
- `receive` routed to `received`, not `sent`.
- `reducerTypeName` extracted from the trailing closure; `initialStateExpr` captured.
- precision guards: a non-`TestStore` `.send(...)` on an unrelated object is **not** mined; a body with no `TestStore` yields `[]`; multiple `TestStore`s in one body keep their sequences separate.

**Risk:** low. Pure AST, offline, deterministic. No kit coordination.

### Slice 2 — payload-free replay-then-extend in the verifier — ✅ SHIPPED

Threads mined **payload-free** traces for a candidate into `ActionSequenceStubEmitter` and checks them **before** the random loop. As built:
- `Inputs.seedTraces: [[String]]` (default `[]`); the replay block (`ActionSequenceStubEmitter+TraceMining.swift`) emits `let minedTraces: [[Action]] = [[.dismiss, .refresh], …]` and runs each through the **same** apply + per-step + post-loop check as a generated sequence, guarded by `if pinSequence == nil` (a shrink pin skips mined runs). Empty `seedTraces` → **byte-identical** output (golden test enforces it).
- `MinedTraceSelector` (`.tca`-only for now — that's where the Action alphabet is captured): join by reducer type, payload-free only, stale-case guard. `VerifyInteractionPipeline.resolveEmitAndSeed` (`+Resolve.swift`) mines `<workingDir>/Tests` best-effort, selects, threads, and reports the count.
- Explainability: `foldSeedTraceDisclosure` appends `replay-then-extend: checked N developer-authored trace(s) before random generation` to the verdict detail (rides into evidence + render).
- Tests: `TraceMiningReplayTests` (10 — emitter golden/replay-block/shrink-pin, selector filters, and an end-to-end `resolveEmitAndSeed` proof: discover a real `@Reducer` + mine a sibling `TestStore` test → `[.close, .refresh]` injected). Lint silent; fast suite green (4027); a measured survey confirms the refactored emitter still builds+runs and the no-seed path is byte-preserved.

**Deliberately OUT (as planned):** payload-bearing traces (recorded, not emitted), generic-carrier injection (needs alphabet capture — Slice 3), initial-state mining, prefix/Markov biasing. **Hard rule held: mined traces only prepend; random generation stays the coverage floor.** A dedicated measured proof that a mined ordering is checked *first* on a purpose-built corpus is the one remaining verification (the wiring + emit are proven; a subprocess run would only reconfirm the trivially-valid `.case` literals compile).

_Original sketch:_

Thread mined **payload-free** traces for a candidate into `ActionSequenceStubEmitter` and check them **before** the random loop.

- Discovery/pipeline: on the interaction verify path, run the extractor over the project's tests root, join traces to the candidate by `enclosingTypeName == reducerTypeName`, keep only all-payload-free `sent` traces whose case names are all in the candidate's Action alphabet (stale-case guard — proposal open-Q #5; a renamed case is simply dropped).
- Emitter: add an optional `seedTraces: [[String]]` input (arrays of payload-free case names). Emit `let minedTraces: [[Action]] = [[.dismiss, .close], …]` and iterate them through the **same** per-sequence body (`state = init; for action in trace { applyStep; perStepCheck }; postLoopCheck`) ahead of the `for sequenceIndex in 0..<count` random loop. Default empty → byte-identical to today's output (golden stability, the repo's standing invariant).
- Explainability (PRD §4.5): verdict detail gains `checked N developer-authored traces + M generated` (mirrors the Phase-B `explored M of N` disclosure).

**Deliberately scoped OUT of Slice 2:** payload-bearing traces (recorded by the extractor, **not** emitted), initial-state mining, prefix-biasing (mode b), Markov weighting (mode c). **Hard design rule from the proposal (§6 #3): mined traces only ever *prepend*; random generation stays the coverage floor. Never replace.**

**Proof:** a verify-corpus reducer with a payload-free `TestStore` test whose ordering exercises an invariant the random pass reaches late → confirm the trace is checked first (subprocess measured test).

**Risk:** medium — golden-output stability (guarded by the empty-default), and the join heuristic.

### Slice 3 (optional, later) — payload generalization + initial-state mining

- Generalize payload-bearing mined actions to `case + generated args` by routing through the existing `+PayloadConstructibility` machinery (raw scalars + `CaseIterable` enum recipe already exist). This is where mode (b) prefix-biasing becomes real, and it re-opens the value-generator question the corpus data shelved (cycle 119) — **gate on demand.**
- Consume `initialStateExpr` as a seed starting state — needs the verifier to reconstruct a non-default `State`, same concreteness wall. Defer with Slice 3.
- Mode (c) Markov transition weighting — behind a flag, overfitting risk (proposal §6 #3); lowest priority.

## 5. Pipeline-impact table (as-built check of the proposal's §4)

| Stage | Change |
|---|---|
| `SwiftInferTestLifter` | **New** `TestStoreTraceExtractor` + `MinedActionTrace`/`MinedAction`. The bulk of Slice 1. |
| `ActionSequenceStubEmitter` | **Additive** `seedTraces` input, default empty → byte-identical. Slice 2. |
| `VerifyInteractionPipeline` / survey | **Minor** — run extractor, join to candidate, thread payload-free traces. Slice 2. |
| Interaction templates / scoring | **None.** |
| Explainability | **Minor** — "checked N authored traces + M generated." Slice 2. |
| Kit (`DerivationStrategist` / `ActionSequenceFactory`) | **None** for Slices 1–2. Mode (b)/(c) would want an additive `seedPrefixes:` overload — Slice 3 only. |

## 6. Open decisions (carried from the proposal, with a recommendation)

1. **`send` vs `receive`** → mine `send` only for the corpus; record `receive` separately, unused in v1. *(Baked into the data model.)*
2. **Argument concreteness** → payload-free verbatim in Slice 2; generalize in Slice 3. *(The spine of §3.)*
3. **Overfitting** → replay-then-extend only; random is always the floor. *(Hard rule.)*
4. **Non-TCA carriers** → TCA `TestStore` is the uniform, high-density starting syntax; Elm/hand-rolled `reduce(&s, a)` call mining generalizes on demand, not now.
5. **Stale traces** → drop any mined action whose case isn't in the candidate's current Action alphabet (the host suite is self-validating; if it compiles the cases are current).

## 7. Recommendation

**Build Slice 1 alone first and stop there for review.** It is the reusable asset (a clean extractor with a full offline unit-test suite), carries no golden-output or kit risk, and is independently valuable — the mined traces are inspectable data even before the verifier consumes them. Slice 2 is a small, honest MVP of the actual payoff (payload-free replay-then-extend) that proves the discover→verify loop end-to-end; take it as a second, separately-reviewed step. Slice 3 is real value but re-opens the shelved value-generator precision question — gate it on demand, don't front-load it.

Sequencing mirrors the repo's proven "recognition first, consumption behind it" posture and keeps every step independently shippable with the standing byte-identical-output guarantee intact.
