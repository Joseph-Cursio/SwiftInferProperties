# StatefulRoleDiscoverer — generalizing architecture-aware discovery

Status: **design sketch** (no code landed). Author note: grounds every claim in
the existing `ReducerDiscoverer` / `ViewModelDiscoverer` implementations.

## Motivation

SwiftInferProperties has two architecture-aware discovery tracks:

- **TCA** — `ReducerDiscoverer` (`Sources/SwiftInferCore/ReducerDiscoverer.swift`
  + `+TCAWalk`), producing `ReducerCandidate`.
- **MVVM** — `ViewModelDiscoveryVisitor` / `ViewModelDiscoverer`, producing
  `ViewModelCandidate`.

Every other SwiftUI/UIKit state architecture — **Redux/Elm, VIPER, MVP, MVC** —
currently falls back to the architecture-neutral function-level templates
(idempotence, commutativity, round-trip, …). That misses the architecture's
*distinctive* contracts (e.g. "a Redux reducer is pure and total", "an MVP
presenter's view updates are a deterministic function of model + event").

This note proposes folding the two existing tracks — and the four missing ones —
into a single **`StatefulRoleDiscoverer`** parameterized by a pluggable
**`RolePolicy`**. The thesis: this is mostly a **refactor that exposes a seam**,
not new machinery, because the codebase already models the commonality.

## Two facts that make this a lift, not a rewrite

1. **A viewmodel is already modelled as a reducer.** `ViewModelCandidate`'s
   doc-comment (`Sources/SwiftInferCore/ViewModelCandidate.swift`) states it
   verbatim:

   | Reducer | ViewModel |
   |---|---|
   | `State` | the stored properties (`stateFields`) |
   | `Action` alphabet | the state-mutating methods (`actions`) |
   | `reduce(into:_:)` | each method body mutating `self` |

2. **`ReducerDiscoverer` already recognizes multiple frameworks by signature**
   (`ReducerDiscoverer.swift` header + `ReducerSignatureShape`):
   - `(S, A) -> S` — Elm-style / hand-rolled / free-function reducers
   - `(inout S, A) -> Void` — TCA `Reduce` closures
   - `(S, A) -> (S, Effect<A>)` — TCA pre-2022, **ReSwift with thunks**
   - Square **Workflow** `apply(toState:)`
   - TCA `var body: some ReducerOf<Self>` via the conformance walk

   So **Redux (ReSwift) and Elm are already partially discovered** — they simply
   lack a paradigm label and collaborator-mocking.

Consequently `ReducerCandidate` and `ViewModelCandidate` are near-isomorphic
(location, type name, state surface, action alphabet, construction recipe), and
`ViewModelMethodBodyWalker` / `ViewModelMethodSignals` (assignedRoots,
mutatorCallReceivers, same-object action calls) is a **paradigm-agnostic
mutation detector** already.

## The unified shape — `StatefulRole`

Lift the common fields of `ReducerCandidate` + `ViewModelCandidate` into one
type. The only material differences between a reducer and a viewmodel are *how
you obtain an instance to drive* and *what you mock*.

```swift
/// A type/function that owns state and exposes mutation entry points — the
/// unit every state architecture (TCA, MVVM, Redux, VIPER, MVP, MVC) reduces
/// to. Replaces ReducerCandidate + ViewModelCandidate.
public struct StatefulRole: Sendable, Equatable {
    public let location: String
    public let typeName: String
    public let paradigm: Paradigm            // tca | mvvm | redux | viper | mvp | mvc
    public let recognizedBy: RecognitionKind // signatureShape | conformance | macro | convention

    public let state: StateSurface            // named `State` type  OR  stored fields
    public let actions: [RoleAction]          // unifies ActionCaseInfo + ViewModelAction
    public let construction: Construction      // how the harness gets an instance to drive
    public let collaborators: [Collaborator]   // protocols to fake (the View, the Output, …)
    public let effect: Effect                  // SEI lattice — `.pure` reducers fuzz directly
}

public enum Construction: Sendable, Equatable {
    case freeFunction(name: String)                     // reducer: just call it
    case instance(initParameters: [RoleInitParameter],  // viewmodel / presenter / interactor:
                  fakedCollaborators: [Collaborator])     //   build it, injecting fakes
}

/// A collaborator the role calls *out* to, recognized as a protocol so it can
/// be mocked. Reuses ViewModelProtocolScanner / ProtocolFaker.
public struct Collaborator: Sendable, Equatable {
    public let propertyName: String     // "view", "output", "presenter"
    public let protocolType: String     // "LoginViewProtocol"
    public let role: CollaboratorRole    // .dependency(noop:) | .output(assertable:)
}
```

The pivotal generalization is `CollaboratorRole`: a **dependency** (inject a
no-op fake — what MVVM does today) vs an **output sink** (inject a *recording*
fake so the property can assert what the role pushed to it). The recording
output fake is the one genuinely new capability, and it is exactly what makes
MVP/VIPER's contracts testable.

## The pluggable seam — `RolePolicy`

Everything paradigm-specific collapses to one protocol. The engine owns the
walk + the shared mutation analysis; the policy owns recognition and the two
facts that differ (state surface, construction) plus collaborators and
distinctive properties.

```swift
public protocol RolePolicy: Sendable {
    var paradigm: Paradigm { get }

    /// Cheap structural check against the declaration + file context
    /// (imports, inheritance, attributes, name). Returns nil if not my role.
    func recognize(_ decl: DeclSyntax, in ctx: FileContext) -> RoleMatch?

    func extractState(_ match: RoleMatch) -> StateSurface
    func construction(_ match: RoleMatch) -> Construction
    func collaborators(_ match: RoleMatch) -> [Collaborator]

    /// Paradigm-specific invariants layered on the shared interaction families.
    var distinctiveProperties: [PropertyKind] { get }
}
```

## The engine

```swift
public struct StatefulRoleDiscoverer {
    let policies: [RolePolicy]   // ordered: specific (macro/signature) → generic (convention)

    public func discover(in tree: SourceFileSyntax, file: String) -> [StatefulRole] {
        var roles: [StatefulRole] = []
        for decl in tree.statements.declarations {
            guard let (policy, match) = firstMatch(decl, file) else { continue }

            // SHARED, paradigm-agnostic: the mutation analysis that already
            // lives in ViewModelMethodBodyWalker, lifted verbatim.
            let actions = MutationAnalyzer.actions(in: decl, state: policy.extractState(match))

            roles.append(StatefulRole(
                location: "\(file):\(decl.line)",
                typeName: match.typeName,
                paradigm: policy.paradigm,
                recognizedBy: match.kind,
                state: policy.extractState(match),
                actions: actions,
                construction: policy.construction(match),
                collaborators: policy.collaborators(match),
                effect: SoundPurity.inferredEffect(for: decl) ?? .nonIdempotent
            ))
        }
        return roles
    }
}
```

`SoundPurity` (the Idea #4 step-2 oracle) is the effect classifier here: a
`.pure` reducer can be fuzzed as a free function with no harness; an effectful
role needs the instance + mock path.

## The existing two become policies (proof it lifts)

```swift
struct TCAReducerPolicy: RolePolicy {
    let paradigm = Paradigm.tca
    func recognize(_ d, _ ctx) -> RoleMatch? {
        // EXISTING ReducerDiscoverer logic: signature shapes (S,A)->S,
        // (inout S,A)->Void, … OR ctx.imports("ComposableArchitecture")
        // && (inherits "Reducer" || hasAttr "@Reducer")
    }
    func construction(_ m) -> Construction { .freeFunction(name: m.functionName) }
    func collaborators(_ m) -> [Collaborator] { [] }   // pure reduce; nothing to mock
    var distinctiveProperties { [.actionSequence, .idempotence, .interactionInvariants] }
}

struct MVVMPolicy: RolePolicy {
    let paradigm = Paradigm.mvvm
    func recognize(_ d, _ ctx) -> RoleMatch? {
        // EXISTING ViewModelDiscoveryVisitor: @Observable macro || : ObservableObject
    }
    func extractState(_ m) -> StateSurface { .storedFields(m.observableFields) }       // existing
    func construction(_ m) -> Construction {
        .instance(initParameters: m.initParams, fakedCollaborators: m.protocolDeps)     // existing
    }
    var distinctiveProperties { [.idempotence, .interactionInvariants] }
}
```

Both bodies are **code that already exists** — moved behind the seam, not
rewritten.

## The four new paradigms — thin policies

| Paradigm | Recognize | Collaborators to fake | Distinctive properties | Value / Effort |
|---|---|---|---|---|
| **Redux** (ReSwift / Elm) | already-matched `(S,A)->S` + thunk shapes; add ReSwift `Reducer` typealias / `Middleware`; label `redux` | none (pure reducer) | `determinism` (`reduce(s,a)==reduce(s,a)`), `unknownActionIsNoOp`, `actionSequence` | **High / Low** |
| **VIPER** | conforms to `*InteractorInput` / named `*Interactor` (convention) | the `presenter`/`output` protocol → **recording** fake | `outputDeterminism`, `noUIKitImport`, `interactionInvariants` | **Med / Med** |
| **MVP** | `*Presenter` / `*Presenting`, holds `weak var view: SomeViewProtocol` (convention) | the `view` protocol → **recording** fake | `viewUpdateDeterminism`, `idempotence` | **Med / Med** |
| **MVC** | `*Model` class, no UIKit import (convention); a `UIViewController` subclass is low-value | none (or model deps) | `idempotence`, `interactionInvariants` | **Low / Low–Med** |

VIPER/MVP/MVC have no language-level marker, so their `recognize` is
**data-driven from config** — a `[roles.*]` block compiles to a generic
`ConventionPolicy`, reusing the existing `Vocabulary` / `[discover]` config
plumbing, so a project's house naming convention needs no new code:

```toml
[roles.presenter]
nameSuffix  = ["Presenter"]
conformsTo  = ["Presenting"]
outputCollaborator = "view"     # → recording fake, assertable output
```

```swift
ConventionPolicy(paradigm: .mvp, nameSuffix: ["Presenter"],
                 conformsTo: ["Presenting"], outputCollaborator: "view")
```

## Distinctive properties worth generating

Beyond the shared interaction-invariant families, each paradigm has a contract
that is *its* reason to exist as a separate policy:

- **Redux:** the reducer is pure & total — `reduce(s, a) == reduce(s, a)`;
  unknown/irrelevant actions are a no-op; state invariants hold under any fuzzed
  action sequence; middleware idempotence. (Most directly fuzzable of all — no
  effects to strip; `SoundPurity` gates it.)
- **VIPER:** given the same input + the same mocked-service responses, the
  interactor's calls to its output protocol are deterministic; the interactor
  never imports UIKit (a testability invariant); the router fires ≤ once per
  terminal action.
- **MVP:** the presenter's `view.show(Y)` is a function of (model, event)
  (asserted via the recording view fake); re-rendering from the same model is
  idempotent.
- **MVC:** model-mutation invariants; controller→model is the only mutation
  path.

## Migration path (land without disturbing the suite)

- **Phase 0 (done)** — introduce `StatefulRole` + the adapters
  (`asStatefulRole`) *alongside* the existing discoverers, plus an exploratory
  per-declaration `RolePolicy` engine. Zero behavior change.
- **Phase 1 (done)** — see the revision below. Wrap the existing discoverers at
  the corpus level (`UnifiedRoleDiscoverer`) rather than reimplementing them.
- **Phase 2 (recognition + distinctive candidates: done for Redux)** — Redux was
  the first slice. Recognition was already there: `ReducerCandidate.carrierKind`
  spans the `tca` *and* `redux` families, and `carrierKind.paradigm` (the single
  source of truth, shared with `asStatefulRole()`) folds Elm / ReSwift / Mobius /
  Workflow / generic into `.redux`. The slice added the two paradigm-distinctive
  candidate invariants — `ReducerInteractionAnalyzer` surfaces `determinism`
  (`reduce(s,a) == reduce(s,a)`, for every redux reducer — the static purity
  analyzer doesn't check `Date()`/`UUID()`/`random()`, so it's genuinely
  unsettled) and `unknownActionIsNoOp` (`reduce(s, unknown) == s`, only for *open*
  action alphabets — a closed enum is exhaustive, so the claim would be a
  tautology). TCA is excluded by design (its own richer story).
- **Phase 2 (measured-verify: done for `determinism` AND `unknownActionIsNoOp`)** —
  both are now first-class `InteractionInvariantFamily` cases (the 6th + 7th).
  The template engine emits one determinism `InteractionInvariantSuggestion` per
  redux reducer (`DeterminismInteractionTemplate` — the first *witness-free*
  family), and `ActionSequenceStubEmitter.makeDeterminismCheck` runs it as a
  **per-step two-call comparison** (`reduce(s, a) == reduce(s, a)` on the loop's
  current `(state, action)` — distinct from idempotence's post-loop
  single-witness double-apply, since determinism must hold for every action). A
  `bothPass` folds +50 → `.verified` through the existing M9 evidence→tier join;
  determinism carries no Finding-G deferral, so the fold isn't clamped. The
  measured baseline (`Tests/Fixtures/determinism-verify-corpus/`) proves it
  catches an `Int.random` reducer the static purity analyzer labels `.pure`.
  `unknownActionIsNoOp` **measured-verify shipped** (commit `d4a4fc7`): the
  verifier mints a fresh probe type conforming to the reducer's open `Action`
  protocol (`ActionSequenceStubEmitter+UnknownAction`) and asserts
  `reduce(s, unknown) == s` over an empty sequence — measured baseline
  `Tests/Fixtures/unknown-action-corpus/` (`NoOpCounter` → Verified,
  `LeakyReducer` → suppressed).
- **Phase 2 (VIPER/MVP: SHIPPED)** — convention roles now have the complete
  discover → surface → verify → promote loop. **Slice A:** `ConventionRule`
  (built-in `*Presenter`/`*Interactor` defaults; name-or-conformance match) +
  `ConventionRoleDiscoverer` reuses the MVVM scan (visitor / `classifyExclusion`
  / `resolveActions`) to emit a `StatefulRole` per matched class, flagging the
  named output collaborator as `.output(assertable:)`; registered as
  `ConventionParadigm` and surfaced in `discover-reducers`. **Slice B (the
  genuinely-new capability — recording output fakes, the design's risk #4):**
  `RecordingFakeEmitter` synthesizes a `Recording_<P>` that logs each output call
  (name + args) to `callLog`, and `OutputDeterminismVerifierEmitter` constructs
  the role twice (recording fake for the output, no-op fakes for other deps),
  drives the same actions, and compares the two logs — a hidden `UUID()`/`Date()`
  in the output path makes them differ. Measured corpus
  (`Tests/Fixtures/output-determinism-corpus/`): `SafePresenter` → bothPass,
  `LeakyPresenter` → defaultFails. **Productionized:** new 8th
  `InteractionInvariantFamily.outputDeterminism` (no Finding-G deferral →
  promotable); `ConventionRoleInteractionAnalyzer` surfaces it in
  `discover-interaction` at `.possible`; `OutputDeterminismVerify` +
  `OutputDeterminismVerifyEvidence` close the verify-evidence join so a verified
  role promotes to `.verified` (`OutputDeterminismJoinMeasuredTests`). Still open
  in Phase 2: **MVC** (flagged low-value — confirm it beats the generic
  function-level templates before building; the doc's own §6.5 caution).
- The stub emitters generalize by dispatching on `construction` (free-fn vs
  instance) instead of on candidate type — the one real consumer-side refactor.

### Phase 1 finding — the seam is corpus-level, not per-declaration

The Phase 0 engine offered each declaration to a policy and built a role from
*that decl alone*. Reading the discoverers showed this is the wrong granularity:

- `ReducerDiscoverer` is single-pass per file — a per-decl fit.
- **`ViewModelDiscoverer` is corpus-level and two-phase.** A view model's methods
  routinely live in `extension VM {}` blocks in *other files*; the discoverer
  *accumulates* `RawTypeInfo` per type name across all files, then *assembles*
  candidates from the merged table, with a fixed-point transitive-action
  resolution that needs the type's full method set. A per-decl
  `buildRole(classDecl)` cannot see the class's extensions — even in the same
  file — so it cannot reproduce that.

So reimplementing the discoverers as per-decl policies was the wrong move. Phase 1
instead places the seam at the **corpus level** and has each paradigm **wrap its
existing, heavily-tested discoverer**, adapting the output to `StatefulRole`:

```swift
public protocol ParadigmDiscoverer: Sendable {
    var name: String { get }
    func discover(source: String, file: String) -> [StatefulRole]
    func discover(directory: URL) throws -> [StatefulRole]
}

struct MVVMParadigm: ParadigmDiscoverer {        // wraps ViewModelDiscoverer
    func discover(source: String, file: String) -> [StatefulRole] {
        ViewModelDiscoverer.discover(source: source, file: file).map { $0.asStatefulRole() }
    }
    // directory variant delegates to ViewModelDiscoverer.discover(directory:),
    // which already does the cross-file accumulate/assemble.
}

struct UnifiedRoleDiscoverer { let paradigms: [any ParadigmDiscoverer]; … }   // runs all, concatenates
```

This **reuses the recognition + extraction + cross-file machinery wholesale**
(the design's "reuse" column) and makes parity with the legacy discoverers true
*by construction* — there is no reimplemented extraction to keep byte-identical.
Tests cover both paradigms through one seam and, critically, a view model whose
methods span two files assembling into one role.

The Phase 0 per-declaration `RolePolicy` / `StatefulRoleDiscoverer` is retained
as a building block (its `FileContext` / recognition shape will serve the
convention-based VIPER/MVP/MVC recognizers in Phase 2), but it is **not** the
top-level discovery path — `UnifiedRoleDiscoverer` is.

## What's reuse vs. genuinely new

| Piece | Status |
|---|---|
| Mutation analysis (`MutationAnalyzer`) | **Reuse** `ViewModelMethodBodyWalker` verbatim |
| Instance construction + dependency faking | **Reuse** `ViewModelDependencyConstructor` + `ProtocolFaker` |
| Reducer signature recognition (incl. Redux/Elm) | **Reuse** `ReducerDiscoverer` shapes |
| `RolePolicy` seam + engine | New, small |
| **Recording** (assertable) output fakes | **New** — the capability MVP/VIPER need that MVVM didn't |
| `ConventionPolicy` (config-driven recognition) | New — reuses `Vocabulary` / config plumbing |
| Per-paradigm distinctive properties | New stub emitters, incremental |

## Risks & open questions

1. **Candidate-type churn.** `ReducerCandidate` / `ViewModelCandidate` are
   `Codable` and persisted (baseline / index / decisions). Phase 0 must keep
   their wire shape stable via adapters, or a schema migration is required.
2. **Recognition precedence.** When a TCA reducer also matches a generic
   convention, the specific policy must win. Engine resolves by ordering
   (macro/signature policies before convention policies) — needs a deterministic
   tie-break and a test.
3. **Convention false positives.** Name-suffix recognition (`*Presenter`) is
   weaker than a macro; surface every match's `recognizedBy` so a human can see
   *why* a type was treated as a presenter, mirroring `ViewModelExcludedField`'s
   transparency posture.
4. **Recording-fake semantics.** Asserting "output is deterministic" requires
   capturing the *sequence and arguments* of output-protocol calls across two
   runs — a new fake kind beyond the current no-op `ProtocolFaker`. Scope this
   before committing to MVP/VIPER.
5. **MVC honesty.** Resist testing `UIViewController` subclasses; the realistic
   deliverable is a `*Model`-role discoverer, which overlaps the generic
   function-level templates — confirm it adds signal over the status quo before
   building it. **RESOLVED: do NOT build MVC.** The status-quo check was run (a
   scan of every `*Model` class across the owner's projects) and came back
   negative: (a) MVC adds **no new invariant type** — its distinctive properties
   are `idempotence` + the five families, which `ViewModelInteractionAnalyzer`
   already runs, so it would only *extend recognition* to plain `*Model` classes;
   (b) **86% of `*Model` classes (59/69) are already caught** as observable by
   `ViewModelDiscoverer`, and the naming is dominated by `*ViewModel` (MVVM), so
   `*Model` is a Daikon-trap recognition signal; (c) the genuinely-missed set —
   plain non-observable `*Model` classes — is **10 files, all noise** (9 test
   fixtures for other tools' lint rules + 1 SwiftLint rule-example), with **zero
   real MVC state-models**. Modern Swift stateful UI is SwiftUI MVVM (`@Observable`)
   or TCA, both already covered; the classic UIKit MVC "Model class" is effectively
   absent. Building `*Model` recognition would trade a clean miss of ~nothing for a
   low-precision flood — against the conservative posture. MVC stays unbuilt.

## Recommended first step

Phase 0 + `ReduxPolicy`: the lowest-risk, highest-signal slice, because Redux
recognition is already mostly implemented and a pure reducer is the most
directly fuzzable target in the whole taxonomy.
