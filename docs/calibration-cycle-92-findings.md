# v1.95 Calibration Cycle 92 — Findings (RefInt + IdentifiedArrayOf)

Captured: 2026-05-17. swift-infer at v1.95.

## Headline

**Second family-pattern-calibration sub-cycle ships, with an
expected-but-instructive null result.** v1.95 closes sub-item #2
of cycle-87 finding #5 — `ReferentialIntegrityWitnessDetector`
now recognizes `IdentifiedArrayOf<T>` and the two-arg
`IdentifiedArray<ID, T>` form alongside the array literal `[T]`.
Modern TCA uses `IdentifiedArrayOf<X>` everywhere; the v1.94
detector matched only `[X]` and missed all of them.

**TCA 1.25.5 interaction count: 23 → 23 (no delta).** The detector
*does* recognize the IdentifiedArrayOf collections correctly — but
TCA 1.25.5 has **zero `selected*` properties** anywhere in its
seven example apps. The referential-integrity pairing rule
(`selected<X>: T.ID?` × any collection) doesn't fire because the
first half of the pair is absent.

This is **another legitimate calibration signal**, similar to
cycle-91's modern-TCA-prefers-enum-destination finding. The
detector is correctly extended; the pattern just doesn't fire on
real TCA because of naming conventions. The IdentifiedArrayOf
recognition still ships — it's correct, it's tested, and it'll
fire on any codebase mixing TCA-style collections with the
`selected*` naming convention. Hand-rolled corpus stays at 18
interactions (regression check passes).

After v1.95, two sub-items of cycle-87 finding #5 remain queued:
(c) Idempotence TCA action-name conventions and (d) Biconditional
Effect/Task pairs. Both target patterns more likely to actually
fire on TCA's naming conventions.

## What landed

### A — `collectionElementType(_:)` umbrella + `identifiedArrayElementType(_:)` helper

New dispatch in `ReferentialIntegrityExtractor`:

```swift
static func collectionElementType(_ type: String) -> String? {
    if let element = arrayElementType(type) {
        return element
    }
    return identifiedArrayElementType(type)
}
```

`arrayElementType(_:)` (the existing `[T]` parser) is tried first;
on miss, `identifiedArrayElementType(_:)` is tried for the TCA
shapes. Both shapes flow into the same `collections` bucket in
`classify(_:)`, so downstream Cartesian-product pairing treats
them identically.

`identifiedArrayElementType(_:)` handles two TCA shapes:

- **`IdentifiedArrayOf<T>`** — TCA's canonical typealias for
  `IdentifiedArray<T.ID, T>`. Element type is the sole generic
  argument.
- **`IdentifiedArray<ID, T>`** — explicit two-argument form.
  Element type is the *second* generic argument (the first is the
  ID type). Implemented via a depth-counting comma split
  (`secondGenericArgument(in:)`).

Both forms accept module-prefixed variants
(`IdentifiedCollections.IdentifiedArrayOf<X>`) for robustness
against fully-qualified imports.

### B — 8 new tests

In a sibling file `ReferentialIntegrityIdentifiedArrayTests`
(separate suite to keep both files under SwiftLint's type-body
length cap):

- `IdentifiedArrayOf<X>` paired with `selectedID` fires witness.
- Element type with dotted path (`Todo.State`) preserved.
- Two-arg `IdentifiedArray<UUID, Item>` returns the second arg.
- Module-prefixed `IdentifiedCollections.IdentifiedArrayOf<X>` matches.
- Mixed `IdentifiedArrayOf<X>` + `[Y]` produces both witnesses
  via Cartesian product.
- `IdentifiedArrayOf<X>` alone (no `selected*`) produces nothing.
- One-arg `IdentifiedArray<UUID>` rejected (canonical form is two-arg).
- Pure-function check: `identifiedArrayElementType(_:)` returns
  nil for `[T]` / `Dictionary<K, V>` / scalars / empty inner.

Test count: 3030 → 3038 (+8). RefInt suites: 2 → 3.

## Measured delta

### TCA 1.25.5 corpus

| Example | Interactions (c4 → c5) | Per-family delta |
|---|---|---|
| CaseStudies (SwiftUI) | 18 → 18 | unchanged |
| UIKitCaseStudies | 4 → 4 | unchanged |
| Search | 0 → 0 | unchanged |
| SpeechRecognition | 0 → 0 | unchanged |
| SyncUps | 0 → 0 | unchanged |
| Todos | 0 → 0 | unchanged |
| VoiceMemos | 1 → 1 | unchanged |
| **Subtotal** | **23 → 23** (0) | |

### Hand-rolled + TCA 1.0.0 corpora

Unchanged. Hand-rolled fixtures use `[T]` arrays (no
`IdentifiedArrayOf`); TCA 1.0.0 predates `IdentifiedArrayOf`. The
existing array-literal path still works (regression check).

### Corpus-wide cycle-5 baseline

| Cycle | Reducers | Interactions |
|---|---|---|
| 0 (v1.89) | 29 | 114 |
| 1 (v1.91) | 29 | 34 |
| 2 (v1.92) | 42 | 35 |
| 3 (v1.93) | 92 | 56 |
| 4 (v1.94) | 92 | 57 |
| **5 (v1.95)** | **92** | **57** |

## Calibration finding — modern TCA doesn't name selection slots `selected*`

Confirmed via grep across all of `/tmp/tca-25-discovery/Sources/`:

```
$ grep -rni "selected" /tmp/tca-25-discovery/Sources/
(zero results)
```

Modern TCA's selection mechanism is `@Presents var destination:
Destination.State?` where `Destination` is an `@Reducer enum`
carrying case variants. Drilling into a row of an
`IdentifiedArrayOf<Item>` happens via `.ifLet(\.$destination,
action: \.destination)` and similar Scope chains — never via a
`selected<X>: T.ID?` Optional in State.

This is **another modern-TCA-prefers-enum-X-over-name-Y** pattern,
parallel to cycle-91's enum-destination-over-multi-Presents
finding. The Cardinality and Referential Integrity families both
fundamentally fit legacy TCA shapes; modern TCA encodes the same
semantics differently.

Both findings inform PRD §5.4 calibration — Cardinality and
Referential Integrity may stay default-`.possible` longer than
Idempotence (which fires straightforwardly on modern TCA via the
existing curated action-name set), since the modern-TCA fire
rates for these two families are fundamentally bounded by API
convention rather than detector capability.

The IdentifiedArrayOf recognition still ships because:

1. It's correct, tested, and zero-risk to the existing array-
   literal path.
2. Mixed-codebase or transitional projects (older code with
   `selected*` + new code with `IdentifiedArrayOf`) would fire
   the witness.
3. The hand-rolled corpus could add a fixture exercising this
   pattern; the kit could ship a documentation page on the
   `selected<X>: T.ID?` + `IdentifiedArrayOf<X>` pairing as a
   recommended invariant. Both follow-ups out of scope for this
   cycle.

## What's next

Two sub-items of cycle-87 finding #5 remain queued:

1. **Idempotence: TCA action-name conventions** — extend M4.C's
   curated set with `task` / `delegate(...)` / `binding(.set(...))`.
   Most likely to actually fire on modern TCA (Action names are
   ubiquitous across all 7 examples). Smallest scope.
2. **Biconditional: Effect/Task pairs** — extend the
   Bool/Optional pairing rules to recognize TCA's `Effect<X>?` /
   Task-style state pairs. More design-heavy.

Given the cycle-91 + cycle-92 pattern (detector extensions land
correctly but produce small or zero interaction-count deltas
because TCA's naming conventions don't fire the existing pairing
rules), sub-item (c) is the highest-value remaining since
Idempotence's pairing rule is action-case-name only — no
companion-pattern needed. The expected unlock is more concrete:
every TCA reducer has Action cases, and `task` /
`delegate(...)` / `binding(.set(...))` appear in essentially
every modern-TCA Action enum.
