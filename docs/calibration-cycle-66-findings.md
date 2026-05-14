# v1.69 Calibration Cycle 66 — Findings (monotonicity-emitter rework: +10, past 50%)

Captured: 2026-05-14. swift-infer at v1.69.

## Headline

**A measurement cycle — the first since cycle 60.** v1.69 reworks the
monotonicity verify-stub composer for OrderedCollections carriers and
adds three nested-OC carrier scaffolds, closing the 10 monotonicity
picks the cycle-60 investigation
(`docs/calibration-cycle-60-monotonicity-investigation.md`) had
identified and then recommended **"defer indefinitely."**

Measured-execution: **42/103 = 40.8% → 52/103 = 50.5%.** 28 → 38
`.bothPass`, 61 → 51 `.architectural-coverage-pending`; `.defaultFails`
(6) and `.edgeCaseAdvisory` (8) unchanged. The frozen cycle-27 surface
crosses the half-measured line.

## What the cycle-60 investigation got right — and wrong

The investigation correctly diagnosed **two co-occurring bugs** in the
v1.48 monotonicity composer, and was right that a "Comparable-aware
composer" alone closes **zero** picks:

- **Bug A** — the composer ordered two trial values with global
  `min`/`max`, forcing the *carrier* to be `Comparable`.
  `OrderedSet<Int>` isn't.
- **Bug B** — it emitted a static-call shape `Carrier.index(value)`.
  `index(after:)` is an *instance method* needing a receiver collection
  and a labeled index argument.

Where it was wrong: it framed the rework as a "weak trade" and said
"defer indefinitely." Two facts overturn that:

1. **No index-schema change is needed.** The investigation implied the
   emitter would have to *generally* infer instance-method-ness and
   argument labels. It doesn't: `primaryFunctionName` literally carries
   the label (`"index(after:)"` / `"index(before:)"`), and the fix is
   the same curated-carrier methodology v1.59–v1.63 already used for
   `curatedOCRecipe` / `mutatingInstanceCarriers` / `curatedBindings`.
2. **The work is bounded, and +10 picks crosses 50%.** One new composer,
   one reshaped expression-builder, three curated-table entries — no
   architectural change. The "diminishing returns" framing (cycle 62
   closed 8, cycle 63 closed 1) was real but over-weighted: this rework
   is a single bounded change, not a grind.

## The fix

### V1.69.A — instance-method monotonicity composer

`composeInstanceMethodMonotonicityPass` (gated on a new
`monotonicityInstanceCarriers` set) emits, per trial: draw a receiver
collection from the curated OC generator, draw two valid indices from
the receiver's *own* index range (`Gen<Int>.int(in:)` over
`startIndex ... endIndex-1` for `index(after:)`, shifted for
`index(before:)`), order the **indices** with `min`/`max` (they're
`Int` — `Comparable` by construction; Bug A dissolves because we order
indices, not the carrier), then assert
`receiver.index(after: lo) <= receiver.index(after: hi)` (Bug B fixed —
real instance-method call shape with the recovered labeled argument).

The labeled-arg name reaches the composer because
`resolveFunctionCalls` now threads `primaryFunctionName` as a second
`functionCalls` element for monotonicity; the Int/String value-
monotonicity path reads only `functionCalls.first` and is byte-identical.

### V1.69.B — three nested-OC carrier scaffolds

The 3-edit scaffold (binding + recipe + `monotonicityInstanceCarriers`
entry) for `OrderedSet<Int>.SubSequence`,
`OrderedDictionary<Int, Int>.Values`, and
`OrderedDictionary<Int, Int>.Elements.SubSequence`. Each is a
`RandomAccessCollection` with `Index == Int`, so V1.69.A's
receiver-and-index shape applies unchanged. All three binding keys
appear as `typeName` values in the cycle-27 fixture, so the V1.58.B
methodology guard passes without an escape-hatch entry.

`curatedOCRecipe` was extracted to
`StrategistDispatchEmitter+OCRecipes.swift` and reshaped from a `switch`
into a lookup table over two shared expression builders — the three new
entries pushed the switch over SwiftLint's function-body cap, and the
extraction also cleared two pre-existing file-length / type-body
overflows.

### fix(V1.69.B) — type-checker break-up

Subprocess verify against the fixture surfaced a compile failure on the
`OrderedDictionary<Int, Int>.Elements.SubSequence` picks: *"the compiler
is unable to type-check this expression in reasonable time."* The
single-expression `OrderedDictionary(uniqueKeysWithValues: [4-tuple
literal]).elements[...]` form overloads inference once the
`.elements[...]` slice layer is added. `ocDictExpression` now binds the
dictionary to a concretely-typed local before projecting the view.

## What shipped

| Workstream | Summary |
|---|---|
| **V1.69.A** | `composeInstanceMethodMonotonicityPass` + `monotonicityInstanceCarriers`; `resolveFunctionCalls` threads `primaryFunctionName`. Monotonicity composers extracted to `StrategistDispatchEmitter+Monotonicity.swift`. `MonotonicityOCEmitterTests` pins the emit shape. |
| **V1.69.B** | 3 nested-OC scaffolds; `curatedOCRecipe` → lookup table in `StrategistDispatchEmitter+OCRecipes.swift`. |
| **fix(V1.69.B)** | `ocDictExpression` binds the dictionary to a typed local — the `.elements[...]` form overloaded the type-checker. |
| **V1.69.C** | Version bump 1.67.0 → 1.69.0, refreshed `fixtures/cycle27-surface/.swiftinfer/verify-evidence.json` (10 records re-stamped), this findings doc + `docs/calibration-cycle-65-findings.md`, CLAUDE.md update. |

## The 10 closed picks

All verified `.bothPass` (100 default trials, integer carrier — no edge
pass), confirmed via `swift-infer verify --suggestion <hash>
--index-path fixtures/cycle27-surface/.swiftinfer/index.json`:

| Carrier | `index(after:)` | `index(before:)` |
|---|---|---|
| `OrderedSet<Int>` | `5F9B…` | `4B1E…` |
| `OrderedSet<Int>.SubSequence` | `D641…` | `8DC4…` |
| `OrderedDictionary<Int, Int>.Elements` | `CD6F…` | `A6E6…` |
| `OrderedDictionary<Int, Int>.Values` | `59D6…` | `DD74…` |
| `OrderedDictionary<Int, Int>.Elements.SubSequence` | `4935…` | `D73F…` |

The property — `i ≤ j ⟹ c.index(after: i) ≤ c.index(after: j)` — holds
trivially for these contiguous-`Int`-index collections, but these are
genuine *measured* passes: the stub constructs a real receiver, draws
real indices from its index range, and runs 100 trials each.

## Methodology note

The refreshed `verify-evidence.json` briefly got swept into the
`fix(V1.69.B)` commit by `git add -A`, bundling a regenerated data file
with a code fix. It was untangled before the V1.69.C cut and re-stamped
at v1.69.0. Lesson, in the same family as cycle 60's "findings doc not
cross-checked against the machine survey": **stage generated-data-file
regeneration explicitly, never via `git add -A` alongside code.**

## Test count

**2490 → 2498 (+8)** — `MonotonicityOCEmitterTests` (emit-shape per
carrier, `index(before:)` domain, Int-path non-regression, the
nested-OC scaffolds, and the `monotonicityInstanceCarriers` ⊆ recipes
methodology guard). §13 budgets unchanged — the composer is pure
string emission.

## What's next (post-v1.69)

The pick-closing surface is now genuinely near-exhausted: the residual
`architectural-coverage-pending` (51) is dominated by internal-API dead
ends (`_HashTable*`) and discover-layer false positives the cycle-60
investigation already catalogued. Remaining roadmap:

1. **`metrics` per-corpus evidence join** — extend V1.64.D to an
   explicit `--decisions` aggregation mode.
2. **V1.42.C.5 deferred** — implicit reindex on demand (carried from
   v1.42).

## Artifacts

- v1.69 source: `Sources/SwiftInferCLI/StrategistDispatchEmitter+Monotonicity.swift`
  (the composer), `StrategistDispatchEmitter+OCRecipes.swift` (the
  recipe table + the type-checker fix), `GenericBindingResolver.swift`
  (3 bindings), `VerifyCommand+TemplateDispatch.swift` (label
  threading).
- Investigation this cycle overturns:
  `docs/calibration-cycle-60-monotonicity-investigation.md`.
- Prior cycle: `docs/calibration-cycle-65-findings.md` (v1.68 verify
  evidence reaches its last two consumers).
