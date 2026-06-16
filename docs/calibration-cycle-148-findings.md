# Calibration cycle 148 — Lever A: non-public / SPI discovery filter

**Captured 2026-06-16.** First build cycle of the v1-algebraic-rate epic
(cycle 147). Lever A: stop indexing the non-public / SPI declarations an
external verifier can never call, so they don't enter the cycle27-surface
index as `architectural-coverage-pending` false positives inflating the
measured-execution denominator.

## The change

`FunctionScanner.visit(FunctionDeclSyntax)` (SwiftInferCore) — extend the
cycle-54 access filter (which drops `private`/`fileprivate` at scan time) to
also skip:

- **explicit `internal` modifier** — e.g. swift-numerics
  `internal static func rescaledDivide`, swift-collections `internal
  mutating func _ensureUnique`. **Safe**: Swift's default access carries NO
  token, so internal-*by-default* code (incl. our internal test-fixture
  reducers) is untouched; only deliberately-marked internal SPI is dropped.
- **`_`-prefixed enclosing type / extension** — e.g. `_HashTable`,
  `_UnsafeHashTable`. The carrier itself is a private stdlib internal.

This reverses cycle-54's deliberate "keep explicit-internal, mark pending at
verify" stance: an externally-uncallable symbol is noise (PRD §3.5 high
precision), not a deferred verdict.

## The dead end that shaped it (access modifier, not the `_` prefix)

The first attempt also filtered `_`-prefixed **function names**. That was
**wrong**: it dropped *measured* picks — swift-numerics ships
`public static func _relaxedAdd` / `_relaxedMul`, underscore-named but
PUBLIC SPI that genuinely verifies (4 measured bothPass). The reliable
signal is the **access modifier**, not the underscore. Removed the
function-name signal; kept access-modifier + `_`-enclosing-type. (Caught at
the index-rebuild step before any commit — 103→72 with the bad filter vs
103→82 with the correct one.)

## The two `Double.log` shims (a precision fix, not a recall loss)

The corrected filter drops 2 picks that were `measured-bothPass` in the
baseline: `Double.log(_:)` / `log(onePlus:)` (monotonicity). These were
discovered from swift-algorithms' **`internal static func log`** shim
(`RandomSample.swift` — a fallback for when RealModule is absent). Their
"measured" status was a **cross-symbol artifact**: the verify stub's
`Double.log(x)` resolved to swift-numerics' *public* `log` (a different
symbol than discovered). So filtering the internal-shim discovery removes a
precision false positive; the lost "measured" count was never genuine recall
(the discovered symbol is internal to Algorithms and uncallable by its
consumers).

## Result

| | before | after Lever A |
|---|---|---|
| index entries (denominator) | 103 | **82** (−21: 19 unverifiable FPs + 2 internal shims) |
| measured | 52 | **50** |
| measured-execution rate | 50.5% | **61.0%** |

**Survey-confirmed** (re-ran `verify --all-from-index` over the 82-entry
index): 36 measured-bothPass + 6 measured-defaultFails + 8
measured-edgeCaseAdvisory = **50 measured / 82 = 61.0%**; 32
architectural-coverage-pending remain (the addressable tail for Levers B–D).

(Precision also improves: 21 non-public/SPI suggestions no longer surfaced.)

## Verification

- `FunctionScannerTests` — updated `nonPublicAccessLevelsAreSkipped`
  (explicit-internal/private/fileprivate dropped; public + default-internal
  kept), `underscoreNamedPublicSPIIsKept` (public `_relaxedAdd`-style SPI
  kept, explicit-internal dropped), `underscoreEnclosingTypesAreSkipped`.
- `make test-fast` green (no regression — fixtures use internal-by-default,
  untouched).
- cycle27 index rebuilt (82 entries) + re-surveyed to confirm the rate.

## Notes

- The committed `index.json` is the baseline minus exactly the 21 dropped
  entries (original `firstSeenAt`/`lastSeenAt` preserved — a full rebuild
  would have churned all 82 timestamps). The committed `verify-evidence.json`
  is left at the pre-Lever-A 103-record snapshot (the index is the canonical
  denominator; the 50/82 rate is survey-confirmed from the run log). A clean
  `rm verify-evidence.json && verify --all-from-index` would refresh it to 82
  records — deferred to avoid churn.
- `fixtures/cycle27-surface/build-index.sh` uses `declare -A` (bash 4+);
  macOS ships bash 3.2, so it aborts. Indexed the four corpora directly this
  cycle. A `bash`-3.2-compatible rewrite (or a Swift driver) is a cheap
  follow-up.
- Next: **Lever B** — the instance/mutating-method emitter (20 picks, the
  dominant lever) → projected ~85%.
