# Calibration cycle 119 — value-generator path scoping + corpus payload survey

> **STATUS: SCOPING (no binary change — investigation + decision record).**
> Scopes the optional "value-generator path for associated-value Action
> cases" follow-up (CLAUDE.md "What's next" item 1), then measures the
> calibration corpus to size its actual payoff. **Finding: the corpus data
> recommends *against* building a general value-generator engine** — the
> dominant Action-payload shape (nested-action composition) is not
> promotable, and the promotable witness cases that carry payloads number
> only ~5 distinct shapes. Captured 2026-06-14. **No version bump** (ships
> documentation, not binary behavior — same posture as cycles 108 / 118).

## Why this was scoped

A1 is signed off (cycle 118) and the mechanism arc (110–117) is complete.
The remaining "What's next" items are optional. Item 1 — a value-generator
path for associated-value Action cases (`setColor(String)` et al.) — was the
candidate with apparent product value: it is the named prerequisite to widen
the measured survey toward the *literal* ~39 real-corpus identities, and to
move the measured-execution rate off its **50.5% (52/103), frozen since
cycle 66**.

Before committing engineering, this cycle answers the load-bearing unknown:
**how many real-corpus Action cases would the path actually unlock?**

## What breaks today (the mechanism)

`ActionSequenceStubEmitter` hardcodes one enumeration strategy
(`ActionSequenceStubEmitter.swift:125-128`):

```swift
let generator = ActionSequenceFactory.actionSequence(
    forCaseIterable: \(inputs.candidate.actionTypeName).self,
    length: \(inputs.lengthLowerBound)...\(inputs.lengthUpperBound)
)
```

`forCaseIterable:` requires `Action: CaseIterable`, which Swift synthesizes
only for **payload-free** enums. Add `case setColor(String)` and the enum
is no longer `CaseIterable` → `swift build` fails →
`InteractionVerifyOutcomeParser.parseBuildFailure`
(`InteractionVerifyOutcomeParser.swift:113-126`) emits
`.architecturalCoveragePending` with a generic stderr snippet — **no marker
distinguishes a payload case from any other build failure.**

## The machinery that already exists (this is not a from-scratch engine)

1. **The kit's primary entry already accepts a user-supplied generator.**
   `ActionSequenceFactory.actionSequence(from: Generator<Action,_>, length:,
   statefulGuards:)` exists alongside the `forCaseIterable:` convenience.
   The kit's own doc states: *"Consumers with payload-carrying actions must
   construct their own `Generator<Action, _>` and call the primary entry."*
   The intended division of labor *is* this feature — **no kit change
   strictly required.**
2. **Per-payload scalar generators already exist.** `DerivationStrategist` +
   `RawType.generatorExpression` (SwiftPropertyLaws
   `DerivationStrategy.swift:54-99`) emit `Gen<Int>.int()`,
   `Gen<Character>.letterOrNumber.string(of: 0...8)`, etc. for all 14 raw
   types. We delegate (PRD §11), not reimplement.
3. **Prior art for composing a value generator on the verify side.**
   `StrategistDispatchEmitter` already turns a strategy into an emission
   recipe, including `memberwiseRecipe` (zip-composed struct generators) and
   a shipped `.caseIterable` recipe (`StrategistDispatchEmitter.swift:194-199`).
   Composing a per-case `Gen<Action>` is the enum analog.

`DerivationStrategist` itself returns `.todo` for associated-value enums
(SwiftPropertyLaws `DerivationStrategistTests.swift:280-295`) — payload
enums aren't `CaseIterable`, so the strategist has no whole-enum path. The
composition (one-of over per-case constructors) must live on the
SwiftInferProperties side; the per-payload scalars delegate to the strategist.

## Corpus payload survey (the decision input)

Bucketed every payload-bearing Action case across both calibration corpora
(`~/xcode_projects/calibration-corpora/{tca-10,tca-25}-discovery`, 74 files
defining an Action enum). Counts are occurrences; the two trees overlap, so
distinct *shapes* are fewer.

| Payload bucket | Count | Value-generator-path reach |
|---|---|---|
| **Nested actions** (`X.Action`, `PresentationAction`, `BindingAction`, `StackActionOf`, `IdentifiedActionOf`) | **111** | ❌ recursive composition — large lift |
| **Raw** (Int/String/Bool/Double…) | **37** | ✅ tier 1 |
| **Result / TaskResult** | 18 | ❌ generic + error type |
| IndexSet / Data / CGPoint / Color / UUID? / TimeInterval / Tab / … | ~40 | mostly ❌ (CGPoint = struct tier; Tab = enum tier) |

### The decisive cut — payloads on *promotable* cases only

The table above counts every action, but only idempotence-witness-vocabulary
cases (`set*` / `select*` / `show*` / dismiss / close / hide / cancel) are
ever promoted. Filtered to those, the **entire** set of witness-named
payload cases is **5 distinct shapes**:

| Witness case | Payload | Tier |
|---|---|---|
| `setNavigation(isActive: Bool)` | labeled `Bool` | ✅ tier 1 (raw) |
| `setSheet(isPresented: Bool)` | labeled `Bool` | ✅ tier 1 (raw) |
| `selectTab(Tab)` | custom enum | ⚠️ tier 1.5 — reuses shipped `.caseIterable` recipe |
| `setNavigation(selection: UUID?)` | optional `UUID` | ❌ needs UUID gen + optional lifting |
| `setColor(Color)` | SwiftUI `Color` | ❌ not derivable |

Every other witness-named case already carries **no payload** (`showSheet`,
`showPopover`, `dismissButtonTapped`, `cancelButtonTapped`, …) — coverable
*today*. Note both tier-1 witness payloads are **labeled** `Bool`, so a
parser that only handled unlabeled payloads would unlock nothing — labeled
single-raw payloads are the minimum useful target.

## Decision

**Do not build a general value-generator engine.** The corpus says:

1. The dominant payload shape (111 nested-action composition cases) is the
   most expensive thing to generate (recursive) and is **not promotable** —
   `binding` / `delegate` / nested `X.Action` are never idempotence
   witnesses. Maximum effort, zero promotion payoff.
2. Tier 1 (raw payloads, incl. labeled) unlocks ~2 distinct witness shapes
   (`setNavigation(isActive:)`, `setSheet(isPresented:)`). Real but modest.
3. Adding the enum-payload tier is nearly free — it reuses the shipped
   `.caseIterable` recipe verbatim — and adds `selectTab`. Best
   effort-to-payoff ratio after raw.
4. `Color` / `UUID?` witnesses stay pending, correctly surfaced.

**Crucially: no Action-payload tier moves the 50.5% number meaningfully.**
The blocker on that metric is nested-action composition, which isn't
promotable. So the honest framing for any future work here is
*coverage-completeness / surfaced-not-dropped*, **not** a recall jump.

### Recommended posture (if revisited)

A deliberately narrow **"raw + CaseIterable-enum payload"** tier, scoped as
coverage-completeness, with eyes open about the small payoff:

1. **Capture** — add a payload-preserving `EnumCaseDecl { name;
   associatedValueTypes: [String] }` to `TypeDecl` (additive; keep
   `enumCaseNames` for the M14.1 consumer). Scanner parses **labeled**
   single raw/enum payloads; rejects the rest to pending.
2. **Compose** — emit a `Gen<Action>` as a one-of over per-case
   constructors (`Gen<String>.…map(Action.setColor)`); per-payload scalars
   from the strategist. Switch the stub from `forCaseIterable:` to
   `actionSequence(from:length:)` only when a payload case is present
   (payload-free enums keep the zero-risk existing path).
3. **Classify** — extend `architecturalPendingDetail`
   (`VerifyCommand+ArchitecturalPendingDetail.swift`) with an explicit
   `action-payload-type-not-derivable: <Type>` subcategory.
4. **Measure** — a verify-ready corpus reducer with a labeled-Bool witness
   payload, driven end-to-end via a `.subprocess` test (mirrors
   `IdempotenceSurveyCorpusMeasuredTests`).

Risks: associated-value-clause parsing (labels, multiple values, generics)
is the real work — start with single labeled raw/enum payloads only;
confirm the composed `Gen<Action>` co-operates with `statefulGuards` and the
`SWIFT_INFER_PIN_*` shrink-replay path (a short spike); re-run
`MeasuredPromotionDeterminismTests` to confirm the byte-stable seed survives
the richer generator.

**Default decision: shelve.** Revisit only if the calibration corpus shifts
away from TCA-composition shapes toward value-input actions.

## Verification

No binary change. Survey reproduction:

```sh
cd ~/xcode_projects/calibration-corpora
# payload buckets
grep -rhE "^[[:space:]]*case [a-zA-Z]" --include="*.swift" . | grep -E "case [a-zA-Z][A-Za-z0-9_]*\(" | ...
# witness-named payload cases
grep -rhE "^[[:space:]]*case (set|select|show|dismiss|close|hide|cancel)[A-Za-z0-9_]*\(" --include="*.swift" .
```

Suite green (3196; one verify-pipeline subprocess flake observed on a clean
build under contention, did not reproduce on rerun — not a regression).
