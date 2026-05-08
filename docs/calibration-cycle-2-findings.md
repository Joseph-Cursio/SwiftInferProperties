# v1.5 Calibration Cycle 2 — Findings

Captured: 2026-05-08. swift-infer at `79ad26a` + the V1.5.0–V1.5.3 working copy. The second execution of PRD §17.3's empirical-tuning loop.

This document is the cycle-2 record: what we ran, what we learned, what shipped, what's deferred. Cycle 3 reads this to decide where to perturb next.

## Headline

**Cycle 2 shipped one structural rule: protocol-coverage suppression.** A curated `protocolName → [KnownProperty]` map (V1.5.1's `ProtocolCoverageMap`) drives a `protocolCoveredProperty` veto across the six algebraic templates (V1.5.2). The mechanism is op-class-aware where it matters: identity-element maps the (constant-name, op-name) pair to a single covered property; commutativity / associativity map the op name to additive / multiplicative / set-union variants; idempotence / inverse-pair / round-trip use a fixed candidate set per template.

| Tuning | Type | Where | Empirical effect |
|---|---|---|---|
| `protocolCoveredProperty` veto | structural | Idempotence + Commutativity + Associativity + Identity-Element + Inverse-Pair + Round-Trip | -5 of 358 surfaced (-1.4% aggregate); 100% of suppressions on swift-numerics/ComplexModule |

After v1.5: total `--include-possible` surface across the 4 corpora went **358 → 353** (-5, -1.4%). The suppression is *surgical and precise*: every suppressed suggestion is exactly the one whose property is published by the candidate type's declared kit-conformance. None of the suppressed cases overlapped with cycle-1's three FP / cross-type rules.

The smaller-than-expected aggregate effect is the headline limitation finding (see below): the textual-only conformance match (V1.5.1 documented limit) means the veto only fires on corpus-declared types, which is one of the four cycle-1 corpora.

## Corpus selection

Same four cycle-1 targets — re-running on the cycle-1 baseline lets the suppression delta attribute cleanly to v1.5's single new rule:

| Corpus | Target | Cycle-1 post-tune total | Cycle-2 post-rule total | Δ |
|---|---|---:|---:|---:|
| swift-numerics | ComplexModule | 175 | 170 | **−5** |
| swift-collections | OrderedCollections | 101 | 101 | 0 |
| swift-algorithms | Algorithms | 75 | 75 | 0 |
| SwiftPropertyLaws | PropertyLawKit | 7 | 7 | 0 |
| **Total** | | **358** | **353** | **−5 (−1.4%)** |

Per-corpus pre/post snapshots committed to `docs/calibration-cycle-2-data/post-rule-*.discover.txt`. Diff target is `docs/calibration-cycle-1-data/post-tune-*.discover.txt`.

## What v1.5 ships (the mechanism)

Three pieces, all in `Sources/SwiftInferCore/ProtocolCoverageMap.swift` (catalog) + the six templates' `protocolCoverageVeto(...)` helpers:

1. **`KnownProperty` enum (22 cases)** — closed vocabulary of property surfaces SwiftInfer's algebraic templates can emit (additive / multiplicative / set / equatable / hashable / codable / kit-monoid families).
2. **`protocolCoverage` table (13 keys)** — curated `protocolName → Set<KnownProperty>` for the stdlib + kit protocols whose laws PropertyLawKit publishes (`Equatable` / `Comparable` / `Hashable` / `AdditiveArithmetic` / `Numeric` / `SignedNumeric` / `SetAlgebra` / `Codable` plus kit `Semigroup` / `Monoid` / `CommutativeMonoid` / `Group` / `Semilattice`). Transitive coverage hand-baked into values (`Numeric ⊇ AdditiveArithmetic`'s set) so callers don't walk inheritance chains.
3. **Per-template `protocolCoverageVeto(...)` helpers** — each algebraic template (idempotence / commutativity / associativity / identity-element / inverse-pair / round-trip) builds its candidate property set from its emission shape, then calls `ProtocolCoverageMap.coverageVetoSignal(...)` to produce a `Signal.Kind.protocolCoveredProperty` veto when any conformance in the candidate type's `inheritedTypes` covers any candidate property.

The veto uses `Signal.vetoWeight` (full collapse, not heavy counter-signal) per the v1.5 plan's open decision #3 default: protocol coverage is authoritative when it matches — the kit's `check<Protocol>PropertyLaws` *does* verify the property — so the suggestion is genuinely redundant, not "probably noise."

## Per-protocol suppression breakdown

All 5 ComplexModule suppressions resolve through 2 of the 13 curated protocols:

| Protocol cited | Property | Suppressed suggestion | Template |
|---|---|---|---|
| `AdditiveArithmetic` | `additiveCommutative` | `+(z:w:)` | commutativity |
| `AdditiveArithmetic` | `additiveAssociative` | `+(z:w:)` | associativity |
| `AdditiveArithmetic` | `additiveIdentityZero` | `+(z:w:)` × `Complex.zero` | identity-element |
| `Numeric` | `multiplicativeCommutative` | `*(z:w:)` | commutativity |
| `Numeric` | `multiplicativeAssociative` | `*(z:w:)` | associativity |

Complex's declared conformances (per the SwiftSyntax scan of `Sources/ComplexModule/Complex+*.swift`):

```
Sendable, Decodable, Encodable, AdditiveArithmetic, AlgebraicField,
Hashable, Numeric, ExpressibleByIntegerLiteral, ElementaryFunctions
```

Of these, `AdditiveArithmetic` + `Numeric` are the two that map to PropertyLawKit's published-law surface. The other 7 are either non-algebraic (`Sendable`, `Hashable`, `Encodable`/`Decodable`, `ExpressibleByIntegerLiteral`) or not in the v1.5 curated table (`AlgebraicField` is a kit-side type that the curated table doesn't cover; `ElementaryFunctions` is a kit-side numeric protocol that doesn't publish the algebraic laws SwiftInfer's templates emit).

`Hashable` and `Codable` (via `Encodable`+`Decodable`) didn't drive any suppression because the corresponding templates (`hashableConsistency`, `codableRoundTrip`) didn't have qualifying candidates on Complex — no `hash(into:)` was surfaced as a candidate, and the round-trip template's curated `Encodable+Decodable` posture (V1.5.1 plan §"What NOT to save in memory" — neither alone covers `codableRoundTrip`) means split-conformance Complex doesn't qualify even though it could in principle round-trip via JSON.

## Operator-aware-pairing-as-fallout demonstration

The cycle-1 findings doc named **operator-aware identity-element pairing** as the cycle-2 priority #1, observing that the 6 default-tier ComplexModule identity-element suggestions had a 16.7% (1/6) acceptance rate. The expectation: cycle-2 should narrow the cross-product `(any constant) × (any op)` matching to per-class pairing.

The v1.5 plan reframed that priority as a *strict generalization*: protocol-coverage suppression handles operator-aware pairing as a special case, since `Numeric`'s covered-properties set distinguishes `additiveIdentityZero` (covered) from `multiplicativeIdentityOne` (also covered, but not when paired with `Complex.zero`).

What actually happened on the 6 ComplexModule identity-element hits:

| # | Cycle-1 fn × constant | Cycle-1 decision | (constant, op) → KnownProperty? | Cycle-2 outcome |
|---|---|:---:|---|:---:|
| 1 | `+(z:w:)` × `.zero` | **A** | `("zero", "+")` → `additiveIdentityZero` | **suppressed** (kit covers) |
| 2 | `-(z:w:)` × `.zero` | n | `("zero", "-")` → nil | preserved |
| 3 | `/(z:w:)` × `.zero` | n | `("zero", "/")` → nil | preserved |
| 4 | `rescaledDivide(_:_:)` × `.zero` | n | `("zero", "rescaledDivide")` → nil | preserved |
| 5 | `pow(_:_:)` × `.zero` | n | `("zero", "pow")` → nil | preserved |
| 6 | `*(z:w:)` × `.zero` | n | `("zero", "*")` → nil | preserved |

V1.5 takes a **complementary** position to cycle-1's hypothesis:

- **Cycle-1's hypothesis (op-class-aware pairing at pair-formation):** suppress 5 noise, keep 1 signal. Final triage: `1A / 0n` (already-correct).
- **V1.5's actual approach (coverage veto on the conformance-driven property):** suppress 1 redundant (already-kit-verified), keep 5 noise. Final triage: `0A / 5n` (all rejection — but the genuine `+ identity` is already covered by the kit's `checkAdditiveArithmeticPropertyLaws`, so the user's previously-accepted property is still tested, just not via SwiftInfer-emitted code).

The two approaches are independent and combinable. **Cycle-3 priority #1** (below) reinstates the original op-class-aware pairing at the pair-formation step, on top of v1.5's coverage veto. The combined effect on Complex would be: 0 identity-element suggestions emitted (5 vetoed at pair-formation, 1 vetoed by coverage), 0 user-visible noise to triage.

## The 0-delta finding on three corpora — the headline limitation

OrderedCollections + Algorithms + PropertyLawKit produced 0 suppressions despite having 175 surfaced suggestions across them (101 + 75 + 7). All three suffer the same constraint: **the candidate type's inheritance clauses are not in the corpus's `typeDecls`.**

V1.5.2's veto consults `inheritedTypesByName[strippedTypeName]`. The map is built by `ProtocolCoverageMap.inheritedTypesIndex(from: typeDecls)` from the SwiftSyntax-scanned `[TypeDecl]` of the corpus's source files. If the candidate type isn't *declared* in any source file the scanner walks (only *referenced*), there's no entry, no lookup hit, no veto.

Per-corpus diagnostics:

### OrderedCollections (0 of 101 suppressed)

The 10 commutativity / 10 associativity / 27 idempotence / 9 inverse-pair / 25 round-trip / 20 monotonicity surfaced suggestions land overwhelmingly on stdlib-typed parameters:

```
[Suggestion]
Template: commutativity
Why suggested:
  ✓ index(_:offsetBy:) (Int, Int) -> Int — …Sources/OrderedCollections/…
  ✓ Type-symmetry signature: (T, T) -> T (T = Int) (+30)
```

The candidate type is `Int`, which is in stdlib, not the swift-collections corpus. `inheritedTypesByName["Int"]` is `nil`. Even if the user added `: AdditiveArithmetic` somewhere, the textual-only matcher would still need a corpus-side `extension Int: AdditiveArithmetic { ... }` declaration to lift it — which doesn't exist (and shouldn't; the stdlib already provides it).

The corpus's set-shaped types (`OrderedSet`, `OrderedDictionary`) don't conform to stdlib `: SetAlgebra` either — they implement set-shaped *operations* (`union`, `intersection`, `formUnion`, `subtract`) without inheriting the protocol. This is a deliberate API-design choice in swift-collections (the protocol's contracts don't all hold for ordered variants), but it means SwiftInfer's `: SetAlgebra` curated coverage doesn't fire on them.

### Algorithms (0 of 75 suppressed)

Similar shape: 1 commutativity / 1 associativity / 44 idempotence / 6 inverse-pair / 20 round-trip / 3 monotonicity. The candidates are largely free functions with generic `Element` parameters. Generic types aren't declared in the corpus either.

### PropertyLawKit (0 of 7 suppressed)

1 idempotence + 6 monotonicity hits, all in protocol extensions where the candidate type is the protocol's `Self` (which strips to `"Self"` in our textual lookup but doesn't appear as a TypeDecl). The kit's own `Monoid` / `Group` / `Semilattice` *protocols* are in the corpus, but the candidates use them as constraints, not as the candidate type itself.

### What this tells us

**The textual-only protocol-coverage match works exactly where the cycle-1 findings doc predicted it would: on libraries that declare conformances via the textual `extension X: Numeric` / `extension X: AdditiveArithmetic` shape on user types** (ComplexModule's `Complex+AdditiveArithmetic.swift` is the canonical example). Three of cycle-1's four corpora don't have this shape — they implement algebraic ops on stdlib-typed (`Int`) or generic (`Element`) carriers without rewrapping them in a user struct.

This is the v1 textual-only limitation per the V1.5.1 type doc + v1.5 plan §"Out of scope". SemanticIndex (PRD §20) would resolve `Int: AdditiveArithmetic` authoritatively via Swift's `lookupConformance`, lifting suppression on these three corpora. **V1.5's surgical −5 on ComplexModule is the maximum effect achievable within textual-only semantics on the cycle-1 corpora.**

## Methodology gaps

**Smaller cycle-2 corpus impact than the cycle-1 findings doc projected.** The cycle-1 doc estimated that "most of the visible identity-element / commutativity / associativity / inverse-pair / round-trip hits on Complex / Float / Double / Decimal / collection types likely fall under some existing conformance." The corpus-level reality is more nuanced: only Complex (a user-defined struct in the corpus declaring `: AdditiveArithmetic` / `: Numeric`) hits the textual-match rule. `Float` / `Double` aren't *declared* in the swift-numerics corpus — they're stdlib types referenced by Complex's `RealType` constraint. The cycle-3 priority list adjusts accordingly — see below.

**Citation determinism.** The veto's `Signal.detail` field cites "the matching protocol" via `inheritedTypes.first { covers($0, property) }` where `inheritedTypes` is a `Set<String>` (non-deterministic iteration order across runs). Suppressed suggestions don't appear in stdout (so byte-stability of user-visible output holds), but Decisions records that introspect veto reasons may see different cited protocols across runs. Trivial fix for cycle 3: sort the inheritedTypes before scanning. Filed as a v1.5 follow-up below.

**Single-runner triage carryover.** The cycle-2 effect is structural (no new triage), so this gap from cycle-1 carries forward unchanged. No new accept/reject decisions in cycle 2.

**`surfacedAt` plumbing still pending.** Same as cycle-1; PRD §17.2's time-to-adoption metric still blocked.

**Possible-tier sampling on the post-v1.5 surface still pending.** With the surface now at 353 across 4 corpora, this is more tractable than cycle-1's pre-tune 1167 — but it's still cycle-3 work.

## Cycle-3 priority list (in expected impact order)

1. **Op-class-aware identity-element pairing at pair-formation step.** *(Reinstates cycle-1's original priority #1 hypothesis, complementary to v1.5's coverage veto.)*

   `IdentityElementPairing.candidates(...)` currently emits a pair for every binary op `(T, T) -> T` × every same-typed identity constant in the corpus. v1.5's coverage veto suppresses the 1-of-N that the kit already covers; this priority suppresses the (N-1)-of-N that are structurally mismatched.

   Implementation outline:
   - Lift V1.5.2's `IdentityElementTemplate.identityCoverageCandidate(identityName:opName:)` mapping table into `IdentityElementPairing` (or a shared utility).
   - Skip pair emission when the (constant-name, op-name) combo doesn't map to any `KnownProperty`.
   - Combined with v1.5's coverage veto: zero identity-element suggestions emitted on Complex.

   Estimated cycle-3 scope: ~half a day. Would close cycle-1's headline acceptance-rate concern (16.7%) by removing the noise *before* it reaches the scorer rather than after.

2. **Stdlib-conformance bake-in (curated table extension).** *(Closes the textual-only-coverage gap on cycle-1's three 0-delta corpora.)*

   The v1.5 textual-only matcher misses `Int: Numeric`, `Double: AdditiveArithmetic`, etc. because stdlib types aren't declared in the user's corpus. Mirror `EquatableResolver.curatedEquatableStdlib`'s posture: add a curated `[TypeName: Set<String>]` of stdlib types' known conformances to `inheritedTypesIndex(...)`'s output:

   ```swift
   private static let stdlibConformances: [String: Set<String>] = [
       "Int":    ["BinaryInteger", "FixedWidthInteger", "Numeric",
                  "AdditiveArithmetic", "Comparable", "Hashable", "Codable"],
       "Double": ["BinaryFloatingPoint", "FloatingPoint", "Numeric",
                  "AdditiveArithmetic", "SignedNumeric", "Comparable",
                  "Hashable", "Codable"],
       // … Int8/16/32/64, UInt*, Float, Float80, Bool, String, …
   ]
   ```

   Empirical-effect estimate: the 10 commutativity + 10 associativity OrderedCollections suggestions on `(Int, Int) -> Int` ops would fall into two buckets: stdlib operators (`+` / `*`) suppressed, user-named ops (`index`, `distance`) preserved. Combined with priority #1, OrderedCollections's surface would drop noticeably without changing the user-visible noise signal.

   Estimated cycle-3 scope: ~half a day. Same conservative-bias risk as `EquatableResolver.curatedEquatableStdlib` (false-positive suppression on shadowed names) — manageable per the v1.5 plan's curated-list precedent.

3. **Approximate-equality template arm for FP types.** *(Carried forward from cycle-1 priority #2 — still pending.)*

   Cycle 1 surfaces FP candidates with the kit-pointer advisory; cycle 3 ships a real `KitFloatingPointTemplate` emitting `checkFloatingPointPropertyLaws(for: T.self, using: gen)` stubs. Synergy with v1.5's protocol-coverage map: once `Numeric` / `AdditiveArithmetic`-covered suggestions are suppressed on FP types (via priority #2 above + the existing v1.5 rule), FP-conforming-but-not-kit-checked types are the natural target for the new template arm.

   Estimated cycle-3 scope: ~1 day.

4. **Possible-tier sampling on the post-v1.5 surface (353 suggestions, 4 corpora).** *(Carried forward from cycle-1 priority #3.)*

   With cycle-3 priorities #1 + #2 likely cutting another ~30-50 from the surface, the remaining ~300 is genuinely tractable for a 20-30 sample triage round. Highest-information samples (per the cycle-1 runbook): 10 round-trip Possible from Algorithms + 10 idempotence Possible from OrderedCollections + the FP commutativity/associativity survivors on ComplexModule.

5. **`surfacedAt` plumbing.** *(Carried forward from cycle-1 priority #4.)* Unblocks PRD §17.2's time-to-adoption metric. Still ~half a day.

6. **Citation-determinism fix.** *(New from cycle 2.)* Sort `inheritedTypes` before `firstCoveringProtocol` scans, so suppressed-suggestion Decisions records show stable protocol citations across runs. Trivial; ~30 min. Combine with priority #5's plumbing pass.

7. **SemanticIndex** *(Carried forward; multi-cycle effort. PRD §20 v1.1+.)* Resolves `Int: Numeric` etc. authoritatively, lifting the textual-only limitation that cycle-2 measured.

## Summary

Cycle 2 shipped one structural rule: a `protocolCoveredProperty` veto driven by a 13-protocol curated table mapping conformances to `KnownProperty` values. The empirical effect was −5 of 358 surfaced suggestions (−1.4%), all on swift-numerics/ComplexModule, which is the only one of the four cycle-1 corpora that *declares* algebraic conformances on user types (`Complex+AdditiveArithmetic.swift` etc.). The 5 suppressions are surgically precise: they remove exactly the suggestions whose property is published by `Complex`'s declared `: AdditiveArithmetic` and `: Numeric` conformances, leaving the noise (subtraction, division, `pow`, user-named variants) untouched.

The 0-delta on the other three corpora is the headline finding: the textual-only protocol-coverage map cannot reach into stdlib's conformance graph, so corpora that build on stdlib-typed (`Int`, `Element`) carriers can't be suppressed by v1.5 alone. Cycle-3 priority #2 (curated stdlib-conformance bake-in) and priority #7 (SemanticIndex, multi-cycle) close this gap.

The cycle-1 hypothesis on operator-aware identity-element pairing was *partially* addressed: v1.5 suppresses the kit-redundant `(zero, +)` pair via the coverage veto, but doesn't filter the cross-product `(zero, *)` / `(zero, -)` / `(zero, pow)` noise. Cycle-3 priority #1 reinstates the original cycle-1 hypothesis as a complementary pair-formation filter; combined with v1.5's coverage veto, identity-element suggestions on ComplexModule would drop to zero.

Cycle 3 has a concrete priority list with two ~half-day items (priorities #1 + #2) that should produce a measurably-larger empirical effect on the cycle-1 corpora than v1.5 did. Time to next cycle: aim for the v1.6 cut.
