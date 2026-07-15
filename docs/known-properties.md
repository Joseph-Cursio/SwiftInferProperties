# Standard-library known-properties catalog (`swift-infer known-properties`, V1.145)

A built-in, provable **seed of ground truth**: a curated catalog of known-true
algebraic properties on standard-library types, plus the famous **caveats**
(properties that look plausible but do NOT hold).

## Why this is the *right* kind of seed

Standard-library types are the one class where properties are both **known-true
by contract** and **verifiable** — their carriers (`Int`, `Double`, `Bool`,
`String`, `[T]`, `Set`) are exactly the ones the generator can construct
(unlike, say, `BigUInt`, which gates as `unsupported-carrier`). So `--verify`
can *confirm* the catalog live rather than assert it.

It is **universal engine knowledge**, shipped built-in and versioned — it never
reads or writes a project's `.swiftinfer/`, which stays the user's own corpus.

## CLI

```
swift-infer known-properties [--type <T>] [--verify]
```

- default: list the catalog grouped by type, with a Caveats section.
- `--type Set`: filter to one type.
- `--verify`: generate a self-contained, stdlib-only Swift script that
  property-tests each law with a seeded RNG (64 sampled inputs), run it via the
  `swift` interpreter, and annotate each law ✓/✗ with a tally.

`--verify` spawns `swift` locally (no network) — an opt-in verify gesture, on
the §16 hard-guarantee `Process` allowlist alongside the verifier subprocess.

## What's in it (37 laws, 6 caveats)

- **Int** — additive commutative monoid; `max`/`min` semilattice; `abs`
  idempotent.
- **Double** — commutative `+`/`*` and identities, **for finite inputs only**
  (NaN/±∞ break them under `==`). Listed explicitly so the special-case status
  is visible rather than read as an oversight. `+` non-associativity is a caveat.
- **Bool** — `&&`/`||` commutative/associative/idempotent (as boolean *values*).
- **String** — concatenation monoid (not commutative) + identity; `uppercased`
  idempotent; `reversed` involution.
- **Array** — concatenation monoid; `reversed` involution; `sorted` idempotent.
- **Set** — `union`/`intersection` bounded semilattice; distributivity /
  absorption / relative De Morgan; `symmetricDifference` commutative +
  self-inverse.
- **Optional** — functor laws (identity + composition) + monad right identity.
- **Dictionary** — `mapValues` functor laws; `filter` idempotent;
  merge-with-self identity (keep first).

Caveats (documented, never asserted true): `String`/`Array` `+` not commutative;
`Double` `+` not associative; `Set.subtracting` not commutative;
`Dictionary.merging` not commutative on key collisions; and **`&&`/`||`
short-circuit** — the laws hold for boolean *values*, but not for *evaluation*
when operands have side effects (Swift does not evaluate the right operand when
the left decides the result, so `a && f()` and `f() && a` differ in what runs).

## Files / tests

- `StandardLibraryProperties.swift` (the catalog + model),
  `KnownPropertiesRenderer.swift` (pure: list render + verify-program generation
  + output parsing), `KnownPropertiesCommand.swift` (the subcommand + `swift`
  subprocess).
- Tests: `KnownPropertiesTests` (7). Verified end-to-end: `--verify` compiles +
  runs and reports 23/23 laws hold.
