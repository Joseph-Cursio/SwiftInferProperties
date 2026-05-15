# v1.86 Calibration Cycle 83 — Findings (V2.0.M9: InteractionInvariantBridge)

Captured: 2026-05-15. swift-infer at v1.86, SwiftPropertyLaws at v2.3.0 (local tag).

## Headline

**V2.0.M9 ships — InteractionInvariantBridge is wired end-to-end.**
Second cross-repo cycle after M2 (cycle 73). Two halves in one push:

- **Kit-side (M9.A):** SwiftPropertyLaws v2.3.0 adds 6 new protocols
  in `Sources/PropertyLawKit/Public/InteractionInvariant.swift`.
- **Repo-side (M9.B):** three new types — `BridgeSuggestion`,
  `InteractionInvariantBridge` (aggregator), `InteractionBridgeWriter`
  (conformance-stub emitter).

**Test count 2910 → 2928 (+18)** in the repo; **460 → 467 (+7)** in
the kit. No §13 budget regression.

The Bridge is the v2.0 analog of v1's RefactorBridge: when a
reducer accumulates ≥ 3 Strong-tier interaction invariants, propose
conformance to the kit's family-specific protocols. Same writeout
path as v1 (`Tests/Generated/SwiftInferRefactors/`).

## Kit side — M9.A

PRD §9.2's protocol family lands in v2.3.0:

| Protocol | Refines | Adds |
|---|---|---|
| `InteractionInvariant` | — | `associatedtype State` + `static func invariantHolds(in:) -> Bool` |
| `CardinalityInvariant` | `InteractionInvariant` | nothing (state predicate) |
| `ReferentialIntegrityInvariant` | `InteractionInvariant` | nothing |
| `BiconditionalInvariant` | `InteractionInvariant` | nothing |
| `ConservationInvariant` | `InteractionInvariant` | nothing |
| `ActionIdempotenceInvariant` | `InteractionInvariant` (with `State: Equatable`) | `associatedtype Action: Hashable` + `static var idempotentActions: Set<Action> { get }` |

**Why no hierarchy among the families.** PRD §9.4 explicitly settles
that the five families are mutually independent — no protocol
subsumes another. When ≥ 2 fire as Strong on the same reducer they
surface as **peer proposals**, not nested choices. Unlike v1's
`Semigroup → Monoid → CommutativeMonoid → Semilattice` chain, M9's
protocols don't form a DAG.

**Why ActionIdempotence has a different shape.** The other four
families assert "a state-level predicate holds after every action
sequence step." ActionIdempotence asserts "applying a from
`idempotentActions` twice equals applying it once" — an action-
applicative property, not a state-level one. So the protocol carries
the action set rather than implementing the predicate. The inherited
`invariantHolds(in:)` defaults to `true` so conformers don't have
to provide a trivial implementation.

**Deferred to a future kit minor.**
1. `checkInteractionInvariantPropertyLaws` harness function. The
   property check is currently done by SwiftInferProperties' M3.E
   `verify-interaction` subcommand; an in-kit harness would let the
   conformance run on every CI invocation via PropertyLawMacro
   discovery, mirroring how Semigroup/Monoid/Group surface.
2. PropertyLawMacro discovery integration — so a `: CardinalityInvariant`
   conformer auto-emits its property test through the kit's macro
   plugin.

Both are layered concerns that don't block M9's Bridge writeout — the
protocols are the load-bearing scaffolding that lets the user-side
conformance stub compile.

## Repo side — M9.B

### `BridgeSuggestion` data model

Carries the per-reducer Bridge proposal:

```swift
public struct BridgeSuggestion {
    public let identity: SuggestionIdentity
    public let reducerQualifiedName: String
    public let stateTypeName: String
    public let peers: [PeerProposal]           // one per distinct family
    public let firstSeenAt: Date
}
```

Identity is derived from `(reducerQualifiedName, sorted family
rawValues)`, so the same set of fires produces the same identity
across runs **and across input orderings**. The order-independence
test exercises this with `Array.reversed()`.

### `InteractionInvariantBridge` aggregator

```swift
public static func bridges(
    from suggestions: [InteractionInvariantSuggestion],
    strongThreshold: Int = 3,
    now: Date = Date()
) -> [BridgeSuggestion]
```

The aggregator filters to `.strong` / `.verified` tier (both count
as Strong+, matching v1.65's promotion rule), groups by reducer
qualified name, drops groups below threshold, and emits one
`BridgeSuggestion` per surviving reducer with peer proposals sorted
by family `rawValue` for byte-stable output.

**Trigger threshold.** PRD §9.1's "≥ 3 Strong-tier suggestions on
the same reducer." `.possible` / `.likely` / `.suppressed` are
excluded. The threshold is a parameter (default 3) so tests can
exercise the boundary without inflating fixture data.

### `InteractionBridgeWriter` conformance-stub emit

Writeout path: `Tests/Generated/SwiftInferRefactors/<stateRoot>/<StubName>.swift`
per PRD §9.3 — reuses v1's RefactorBridge layout. `<stateRoot>` is
the State type's leftmost segment (`Inbox.State` → `Inbox`), so all
M9 stubs for one reducer cluster under one directory.

**State-predicate stub (Cardinality / Conservation / Refint /
Biconditional):**

```swift
struct InboxCardinality: CardinalityInvariant {
    typealias State = Inbox.State
    static func invariantHolds(in state: State) -> Bool {
        <conjoined predicate>
    }
}
```

When a peer carries multiple member invariants in the same family,
the body is `p1 && p2 && ...`. Member predicates are alphabetically
sorted for byte-stable rendering.

**ActionIdempotence stub:**

```swift
struct InboxIdempotence: ActionIdempotenceInvariant {
    typealias State = Inbox.State
    typealias Action = Inbox.Action
    static let idempotentActions: Set<Inbox.Action> = [.clearAll, .refresh, .reset]
}
```

The kit's protocol provides a default `invariantHolds` (returning
`true`), so the stub omits it.

## Strong-tier gating in production

PRD §3.5 corollary keeps every new family at default-`.possible`
visibility until three calibration cycles of stable acceptance
promote it to `.likely` then `.strong`. **No invariants reach
Strong tier yet.** The Bridge therefore doesn't fire in production
on real-world corpora — but the wiring is ready for when promotion
happens.

Tests construct synthetic Strong-tier inputs directly to exercise
the aggregator and writer. The unit tests don't depend on
calibration state.

## Kit publication gap was already closed

Cycle-82's CLAUDE.md note about `git push origin v2.2.0` being
pending was **stale**. `v2.2.0` has been on origin since at least
the v1.83 (cycle 80) push — verified via `git ls-remote --tags
origin` against `../SwiftPropertyLaws`. The repo's `Package.swift`
pin (`from: "2.2.0"`) has been resolving cleanly the whole time;
synthesized interaction workdirs have been building against the
real published kit.

M9 adds a new pending tag: kit `v2.3.0` is local-only this cycle
(matching cycle 73's M2 pattern). The repo's `Package.swift` pin
stays at `from: "2.2.0"` because the repo doesn't import the v2.3.0
protocols directly — only user-side generated stubs do, via the
user's own kit pin. Once you push the kit, users can bump their
own pin.

## What's deferred / queued

**M9 follow-ups:**
- **`checkInteractionInvariantPropertyLaws` harness** in the kit.
  Adds the kit-side property-check loop that PropertyLawMacro
  discovery can drive on every CI invocation. Layered concern;
  doesn't block the writeout.
- **PropertyLawMacro discovery integration** for the v2.3.0
  protocols. Same shape as v1.8's Semigroup/Monoid/Group rollout —
  the macro plugin needs to recognize the new `KnownProtocol`
  cases.
- **N-arm extended triage prompt** for peer proposals (PRD §9.4 —
  `[A/B/B'/B''/.../s/n/?]`). The interactive UI layer. M9.B ships
  the data model; the prompt itself is a separate concern.

**M8 follow-up still queued:**
- `accept-check`-shaped post-acceptance flow for interaction
  invariants — analog of v1.72's PRD §17.2 5th metric, keyed on
  trace-replay regressions.

## What's next — M10

PRD §5.8's last v2.0 milestone:

- **M10 — Drift mode** for interaction invariants. Per-baseline
  warning on new Strong-tier interaction suggestions added since
  baseline. Mirrors v1's drift mechanism — non-fatal, advisory
  signal so developers can review new candidates without breaking
  the build.

After M10, the v2.0 PRD §5.8 arc is complete. The empirical work
(calibration cycles → tier promotion → real Bridge fires) is
ongoing across all 5 families.

## Test count breakdown

**Repo: 2910 → 2928 (+18).**

- **Aggregator (10):** threshold gating (below / exactly 3 /
  non-Strong excluded / verified counts); peer-proposal shape
  (single-family multi-invariant → 1 peer; multi-family sort
  stability); multi-reducer isolation + sorting; identity
  stability + order-independence; kitProtocolName mapping.
- **Writer (7):** header marker, kit import, state-predicate stub
  shape, multi-member `&&`-conjunction, ActionIdempotence Set
  shape, path layout, disk round-trip.
- **Skipped:** end-to-end persist tests against a real workdir
  (covered by `VerifyPipelineIntegrationTests` when v2.3.0
  publishes).

**Kit: 460 → 467 (+7).** Conformance shape per family + the
mutual-independence type-level assertion.

§13 budgets unchanged — no scan-perf surface touched.

## Artifacts

- v2.3.0 kit sources (`../SwiftPropertyLaws/`):
  - `Sources/PropertyLawKit/Public/InteractionInvariant.swift`
  - `Tests/PropertyLawKitTests/InteractionInvariantTests.swift`
  - `CLAUDE.md` (v2.3.0 entry)
  - Tag `v2.3.0` (local, awaiting push)
- v1.86 repo sources:
  - `Sources/SwiftInferCore/BridgeSuggestion.swift`
  - `Sources/SwiftInferCore/InteractionInvariantBridge.swift`
  - `Sources/SwiftInferCLI/InteractionBridgeWriter.swift`
- Prior cycle: `docs/calibration-cycle-82-findings.md` (M8.D.4 —
  drop-prefix shrinking).
- v2.0 PRD: `docs/SwiftInferProperties PRD v2.0.md` (§9 specifies
  the Bridge).
