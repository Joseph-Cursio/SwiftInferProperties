# Calibration cycle 151 — Lever D: scan-time filter of the last 9 false positives → 100%

**Captured 2026-06-17.** Fourth and final build cycle of the v1-algebraic-rate
epic (cycle 147). Lever D filters the remaining `architectural-coverage-pending`
false positives at scan time, taking the measured-execution rate to **53/53 =
100% of the legitimate denominator**.

## The 9 remaining ACP picks — all false positives, three shapes

After Levers A/B/C-1 the index held 62 picks, 9 still ACP. Joined against the
live index they are three clean groups, every one a discovery false positive:

| group | picks | what they are |
|---|---|---|
| `@_spi(Testing)` capacity shims | 6 | `OrderedSet._minimumCapacity` / `_maximumCapacity` / `_scale` (round-trip ×2 + monotonicity ×4) — swift-collections `OrderedSet+Testing.swift`, marked `@_spi(Testing) public static` |
| nested local function | 2 | swift-algorithms `binomial(n:k:)` (commutativity + associativity) — declared **inside** the `count` computed property, not an API member; and binomial isn't commutative anyway |
| explicit-`internal` enclosing type | 1 | SwiftPropertyLaws `internal enum ViolationFormatter.format(_:)` (monotonicity) — a presentation helper |

None can be called by an external verifier; all stalled at verify as ACP,
inflating the denominator (PRD §3.5 — high precision, fewer suggestions). The
fix is a discovery filter, extending Lever A's non-public/SPI family.

## The change — three `FunctionScanner` filters

`FunctionScannerVisitor.visit(FunctionDeclSyntax)` skips three more shapes:

1. **`@_spi(...)` attribute** (`hasSPIAttribute`) — SPI is "less public than
   public"; an external module can't import it. Distinct from the plain
   `public _relaxedAdd` Lever A deliberately keeps (no `@_spi`).
2. **Nested local function** (`isNestedLocalFunction`) — walks ancestors: a
   member func reaches a `MemberBlock` (or the file root) first; a local func
   hits an enclosing `CodeBlock` / closure / accessor first. Removes a whole
   class of "helper declared in a property/closure body" FPs, not just
   `binomial`.
3. **Explicitly non-public enclosing type** (`enclosingTypeNonPublic`, a stack
   parallel to `typeStack`) — a func inside an `internal`/`private`/`fileprivate`
   *type* is externally uncallable even with no modifier of its own. Extends
   the explicit-`internal` function rule to the type level. **SAFE** — Swift's
   default (token-less) access is untouched, so internal-BY-default fixtures are
   kept, matching Lever A's reasoning.

## Result

| | before (C-1) | after Lever D |
|---|---|---|
| index entries (denominator) | 62 | **53** (−9 false positives) |
| measured | 53 | 53 |
| ACP | 9 | **0** |
| measured-execution rate | 85.5% | **100.0%** |

**Empirically confirmed by a clean index rebuild** (not derived): a fresh
per-corpus `swift-infer index` with Lever D active yields ComplexModule 18 +
Algorithms 0 + OrderedCollections 35 + PropertyLawKit 0 = **53** — the 9 drop as
predicted (Algorithms 2→0, PropertyLawKit 1→0, OrderedCollections 41→35).
Re-survey: **39 bothPass + 6 defaultFails + 8 edgeCaseAdvisory = 53 measured /
53 = 100.0%**, 0 ACP. Evidence regenerated to 53 records at v1.134.0.

Cumulative arc: 50.5% (frozen since cycle 66) → A 61.0% → B 80.6% → C-1 85.5%
→ **D 100.0%**. The epic is complete: the v1 algebraic corpus is now 100%
measured, every surfaced pick is either verified or a measured-disproven
true-negative, and zero false positives remain.

## Verification

- Clean per-corpus index rebuild (bash-3.2 worked around — replicated
  `build-index.sh`'s steps without its `declare -A`, with deleted per-checkout
  indexes to force a fresh scan) → exactly 53 entries; none of the 9 dropped
  symbols present.
- Clean-discovery check: `discover` on `OrderedSet+Testing.swift`,
  `Combinations.swift`, `ViolationFormatter.swift` now yields 0 of the dropped
  picks (end-to-end, not just the unit).
- Re-survey `verify --all-from-index` → 53/53 = 100%, evidence at v1.134.0.
- Unit: `FunctionScannerAccessFilterTests` — `@_spi` dropped / plain-public
  kept; nested-local dropped / member + top-level kept; explicit-internal type
  dropped / public + default-internal type kept.
- `V1.51.D` count guard updated 62 → 53. `make test-fast` green (3213).
- swiftlint silent (extracted the access-filter tests to
  `FunctionScannerAccessFilterTests.swift` for the type_body_length cap).

## Notes

- **The epic's two axes.** A and D raised the rate by removing false positives
  (precision; index shrank 103→82→…→53); B is the same in spirit (signature
  FPs). C-1 was the lone genuine recall gain (+3 OrderedDictionary picks). The
  honest headline: the frozen 50.5% was **half false-positive denominator**,
  half a real carrier gap — both now closed.
- **No remaining v1-algebraic levers.** 100% of the legitimate denominator is
  measured. Future movement requires *new* corpus surface (more public
  algebraic API), not filtering or recipes. The epic (cycles 147–151) is done.
