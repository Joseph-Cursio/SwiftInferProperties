# Docstring corroboration — docstrings touch first-stage inference

**Status:** shipped — all six families (idempotence, involution, commutativity,
associativity, round-trip, monotonicity), 2026-07-18.
**Posture:** corroborate-only. A docstring can only *strengthen* a candidate the
shape already matched — never surface a law the shape didn't.

## What it does

The default-path templates now consult the function's own docstring. When a
template has already matched a candidate by **shape** (and possibly name), and the
prose **independently asserts the same property**, the candidate earns a positive
`Signal.docstringCorroboration` (**+15**), raising its tier.

The payoff is a documented-but-not-curated-name law surfacing **by default**:

```swift
/// Recomputes the derived cache. Calling it on already-current state is
/// idempotent — a second call has no further effect.
func refresh(_ s: State) -> State   // shape 30 + docstring 15 = 45 -> Likely (shown)
```

Without the docstring, `refresh` is a shape-only candidate at **30 (Possible,
hidden)**. The prose lifts it to **45 (Likely)**, shown by default. A curated-verb
candidate (`normalize`, 70) rises to **85 (Strong)** — three-signal agreement.

## Why corroborate-only (not "infer a law from prose")

This is deliberately narrower than the `--docstring-advice` channel
(`DocstringAdvisor`, `docs/docstring-generation` lineage), which surfaces a
documented reference definition as a *separate* advisory. Corroboration instead
feeds the **template inference itself**, but under a strict rule:

- **The shape still gates.** A docstring alone never conjures a candidate. A
  `(Model) -> Data` with "the operation is idempotent" in its docstring surfaces
  **nothing** — the `(T) -> T` shape didn't match. Involution stays name-required.
- **Refutability preserved.** The law is still the shape's law, checkable by
  `verify`; the prose only changes how prominently it's shown.
- Matches the baked-in conservative posture ("when in doubt, fewer suggestions").

## Precision discipline

`DocstringPropertyCorroborator` (Core, pure) carries a tight, **discriminating**
vocabulary per property — the bare word (`idempotent`), or a phrase unique to that
property (`self-inverse`, `twice returns the original`). Ambiguous prose shared
across properties (a bare "applying twice") corroborates **neither**. Every match
is **negation-gated**: a phrase preceded by a negator (`not`, `n't`, `non-`,
`never`, …) does not corroborate — "this is *not* idempotent" gives no boost.

## Calibration (+15)

| candidate | before | after | tier move |
|---|---|---|---|
| shape-only idempotence | 30 | 45 | Possible → **Likely** (surfaces) |
| curated-verb idempotence | 70 | 85 | Likely → **Strong** |
| name+shape involution | 70 | 85 | Likely → **Strong** |
| documented commutativity/associativity (shape-only) | suppressed (10) | 45 | **Likely** (see gating) |
| shape-only monotonicity | 25 | 40 | Possible → **Likely** |
| free-function round-trip pair | +15 on either half's docstring | | boost |
| negated / ambiguous prose | unchanged | | unchanged |

+15 sits between `fixedPointName` (+10, a fuzzy name hint) and `selfComposition`
(+20, body evidence): an explicit documented assertion is stronger than a fuzzy
name but weaker than an exact curated verb (+40) — prose can be aspirational.
Per `Tier`'s own note the weight is a tunable calibration constant.

## The unsupported-shape gate (commutativity / associativity)

Commutativity and associativity suppress a bare `(T,T)->T` shape-only candidate
with a −20 `unsupportedAlgebraicShape` counter (the B24 anti-flood rule): the
shape alone doesn't entail a monoid. A docstring that asserts the property **is**
exactly the corroboration that counter demands, so a docstring corroboration both
adds +15 **and gates the counter off** — a documented commutative op on a
non-curated name surfaces at 45 (Likely) instead of being suppressed. An
*undocumented* shape-only op stays suppressed, unchanged.

Round-trip is the one exception to "docstring boosts": it adds +15 but does **not**
override the structural `crossTypeRoundTripPair` (−25) counter — a documented
cross-type pair keeps its structural filter (the cycle-4 over-generation guard
dominates prose). The clean win there is a documented free-function / same-carrier
codec pair.

## Scope

All six families are shipped: `idempotence`, `involution`, `commutativity`,
`associativity`, `roundTrip`, `monotonicity`. Each is one `Property` case + a tight
negation-safe vocabulary + a `docstringCorroborationSignal` per template. Adding a
future property is the same three steps.

## Where

- `Sources/SwiftInferCore/DocstringPropertyCorroborator.swift` — the pure matcher
  (per-property vocabularies + negation gate).
- `Sources/SwiftInferCore/Signal.swift` — `Signal.Kind.docstringCorroboration`.
- Wiring: `IdempotenceTemplate+DocstringCorroboration.swift`, `InvolutionTemplate.swift`,
  `CommutativityTemplate+DocstringCorroboration.swift` (+ B24 gate in
  `CommutativityTemplate.swift`), `AssociativityTemplate+DocstringCorroboration.swift`
  (+ counter gate), `MonotonicityTemplate+DocstringCorroboration.swift`,
  `RoundTripTemplate+DocstringCorroboration.swift`.
- Tests: `DocstringPropertyCorroboratorTests` (Core — unary + binary suites),
  `IdempotenceDocstringCorroborationTests`, involution corroboration in
  `ApplicationShapeTemplateTests`, `AlgebraicDocstringCorroborationTests`
  (commutativity / associativity / monotonicity / round-trip tier movement).
