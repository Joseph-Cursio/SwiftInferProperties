# Cross-type insights (`swift-infer insights`, V1.143)

A read-only, on-demand **design pass** over `.swiftinfer/index.json`: surfaces
types that share an algebraic structure ("you have three monoids — consider
unifying them") as *author-facing* suggestions.

## The opposite end of the spectrum from `docc`

| | `docc` | `insights` |
|---|---|---|
| Audience | API **reader** | code **author** |
| Content | a **fact** ("verified idempotent") | a **question** ("consider a shared protocol?") |
| Gate | verified-only (measured `bothPass`) | Strong / Likely (inferred; a human reviews) |
| Tone | published guarantee | tentative nudge, dismissible |
| Cadence | generate for docs | pull, on-demand — *not* an every-build nag |

Because the audience is the author (who decides before acting), inferred rows
are fair game — but the tone stays tentative and every group ships a
`Why this might be wrong` line, since a shared *shape* is not a shared *purpose*.

## How structure is derived

Algebraic structure isn't one index row — it's composed per type from the
primitive `associativity` / `commutativity` / `identity-element` template rows:

| Templates a type has (Strong/Likely) | Structure |
|---|---|
| `associativity` | semigroup |
| `associativity` + `commutativity` | commutative semigroup |
| `associativity` + `identity-element` | monoid |
| all three | commutative monoid |

A type with no associative backbone (idempotence/monotonicity only) is not a
"structure to unify" and is skipped. **Semilattice is deliberately not claimed**
— the `idempotence` template is a unary `(T)->T` property, not binary-op
idempotence, so composing it would risk a false label. A structure's tier is the
**weakest** of its contributing properties (a monoid is only as sure as its
identity element).

## CLI

```
swift-infer insights [--directory <root>] [--index-path <p>]
                     [--min-types N] [--include-possible]
```

- Groups types by derived structure; reports groups with ≥ `--min-types` members
  (default 2), gated to Strong/Likely (`--include-possible` widens with a
  caveat — a shared Possible shape is often coincidence).
- Each group carries: the members (with operation name + tier + a `conforms`
  badge), a "consider a shared protocol" nudge, `Why` / `Why this might be
  wrong`, and — when it can see one — an **adoption-gap** note (some members
  already conform via `decision == acceptedAsConformance`, others share the
  shape but don't).

## Example

```
Cross-type structure  (.swiftinfer/index.json)

▸ 3 types share a commutative monoid shape
     Config   merge(_:_:)   [Strong · conforms]
     EventLog   combine(_:_:)   [Strong]
     FeatureFlags   merge(_:_:)   [Likely]
   → Consider a shared protocol so these compose through common code and their
     laws are checked once, on every CI run.
     Why: each exposes an associative, order-independent binary operation with an identity element.
     Why this might be wrong: the domains may be unrelated — a shared protocol
     only pays off if you actually fold/merge them through shared code.
     Note: Config already conforms to a protocol; EventLog, FeatureFlags have the same shape but no conformance.
```

## Deliberate scope

- **Call-site refactor hints are out of scope.** "This function would slot into
  your merge pipeline at Pipeline.swift:88" needs dataflow the index doesn't
  carry. The *adoption-gap* note is the index-derivable slice of that idea.
- **Read-only.** Never mutates source or writes files — it's a report.

## Files / tests

- `InsightsBuilder.swift` (pure: structure composition, grouping, render),
  `InsightsCommand.swift` (the subcommand).
- `InsightsBuilderTests` (9 — composition, grouping, tier gate, weakest-tier,
  adoption gap, render, sort order).
