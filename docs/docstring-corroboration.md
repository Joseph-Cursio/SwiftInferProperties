# Docstring corroboration — docstrings touch first-stage inference

**Status:** shipped (first slice: idempotence + involution), 2026-07-18.
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
| negated / ambiguous prose | 30 / 70 | 30 / 70 | unchanged |

+15 sits between `fixedPointName` (+10, a fuzzy name hint) and `selfComposition`
(+20, body evidence): an explicit documented assertion is stronger than a fuzzy
name but weaker than an exact curated verb (+40) — prose can be aspirational.
Per `Tier`'s own note the weight is a tunable calibration constant.

## Scope

- **Shipped:** `idempotence`, `involution`.
- **Obvious extension (same pattern, one `Property` case + vocabulary + signal per
  template):** `commutativity` ("commutative", "order doesn't matter"),
  `associativity`, `round-trip` ("recovers the original", "losslessly"),
  `monotonicity` ("monotone", "order-preserving"). The binary-op vocabularies are
  more prone to ambiguous matches, so each deserves its own tight vocabulary +
  negation review before wiring.

## Where

- `Sources/SwiftInferCore/DocstringPropertyCorroborator.swift` — the pure matcher.
- `Sources/SwiftInferCore/Signal.swift` — `Signal.Kind.docstringCorroboration`.
- `Sources/SwiftInferTemplates/IdempotenceTemplate+DocstringCorroboration.swift`,
  `InvolutionTemplate.swift` — the wiring.
- Tests: `DocstringPropertyCorroboratorTests` (Core, 13),
  `IdempotenceDocstringCorroborationTests` (5), involution corroboration in
  `ApplicationShapeTemplateTests` (2).
