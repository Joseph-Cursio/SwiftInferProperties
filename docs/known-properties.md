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

## Anchor vs reference (the `role` field)

Every entry carries a `role`, derived from whether it has a `template` the
`discover` confidence-anchor can match:

- **`anchor`** — feeds `StdlibAnchor`: a law becomes a "proven analog" line, a
  caveat (a **trap**) becomes a "known counter-example" line on a matching
  discovered candidate. These pull weight in `discover` (e.g. `Set.union`
  commutativity; the `Set.subtracting` non-commutativity trap).
- **`reference`** — true and self-verified under `--verify`, but invisible to
  `discover` because no template names its shape (functor / stack / queue laws).
  Documentation + a portability self-check, not enforcement.

The listing tags reference laws `[reference]` and trap caveats `[trap]` so a
reader can tell the weight-bearing rows from the documentation. The role is
derived, so it can't drift: the day a shape gets a template, its entries stop
being reference and start anchoring — as the `reversed` involution rows did the
day the `InvolutionTemplate` shipped (`template: "involution"`), and the
`op(x, x) == x` rows (`Set.union`, `Int.max`, `Bool.&&`) did with the
`BinaryIdempotenceTemplate` (`template: "binary-idempotence"`).

## CLI

```
swift-infer known-properties [--type <T>] [--verify]
```

- default: list the catalog grouped by type, with a Caveats section.
- `--type Set`: filter to one type.
- `--verify`: property-test each law with a seeded RNG (64 sampled inputs) and
  annotate each ✓/✗ with a tally. Two paths, partitioned automatically:
  - **stdlib + `Foundation` laws** → a self-contained script run via the `swift`
    interpreter (fast, no package).
  - **external Apple-package laws** (swift-numerics / swift-collections /
    swift-algorithms) → compiled as a temp SwiftPM package's `main.swift`, built
    against the **real** package releases and run. The package build fires only
    when an external-library law is in scope (so `--type Int --verify` stays on
    the fast path), and reuses a warm workdir keyed by the imported-module set.

`--verify` spawns `swift` locally — an opt-in verify gesture, on the §16
hard-guarantee `Process` allowlist alongside the verifier subprocess. The
package path additionally lets SwiftPM **fetch** the declared Apple packages on
first run (inherent to verifying against a real external package).

## Adding a library

An external-library law carries `imports: ["<Module>"]`; the module → package
mapping lives in `KnownPropertiesPackages.byModule`. A `checkBody` constructs the
external type inline from the stdlib `rand*` helpers (`Deque(randArr())`,
`Complex(randDouble(), randDouble())`), so no new generator is needed — just the
import + a mapping entry. A catalog-consistency test guards that every imported
module is mapped.

## What's in it (71 laws, 6 caveats)

- **Int** — additive commutative monoid; `max`/`min` semilattice; `abs`
  idempotent; `abs`/`signum` multiplicative (`h(a·b) == h(a)·h(b)`).
- **Double** — commutative `+`/`*` and identities, **for finite inputs only**
  (NaN/±∞ break them under `==`). Listed explicitly so the special-case status
  is visible rather than read as an oversight. `+` non-associativity is a caveat.
- **Bool** — `&&`/`||` commutative/associative/idempotent (as boolean *values*).
- **String** — concatenation monoid (not commutative) + identity; `uppercased`
  idempotent; `reversed` involution.
- **Array** — concatenation monoid; `reversed` involution; `sorted` idempotent;
  `count` additive over concatenation (a monoid homomorphism).
- **Set** — `union`/`intersection` bounded semilattice; distributivity /
  absorption / relative De Morgan; `symmetricDifference` commutative +
  self-inverse.
- **Optional** — functor laws (identity + composition) + monad right identity.
- **Dictionary** — `mapValues` functor laws; `filter` idempotent;
  merge-with-self identity (keep first).
- **Stack / Queue** — the LIFO and FIFO contracts, realized on `Array`
  (`append`/`removeLast`, `append`/`removeFirst`).

**External Apple first-party packages** (verified against the real releases):

- **swift-numerics** — `Complex<Double>`: `+`/`×` commutative (finite inputs),
  additive identity, `conjugate` involution. Not a `Monoid` (inherits Double's
  non-associativity), mirroring the `Double` rows.
- **swift-collections** — `Deque` (reverse involution, count-additive,
  prepend/removeFirst double-ended symmetry); `OrderedSet` (union idempotent;
  membership-commutative but order-preserving — the "commutative under *which*
  equality" lesson); `OrderedDictionary` / `TreeDictionary` (`mapValues` functor
  identity); `BitSet` (full SetAlgebra — union/intersection commutative,
  idempotent, absorption); `TreeSet` (union commutative + persistent-CHAMP value
  semantics); `Heap` (model-based — `popMin` drains sorted, `min`/`max` agree
  with the array model, since no protocol row applies).
- **swift-algorithms** — `uniqued` idempotent; `chunks` then flatten is the
  identity; `min(count:)` agrees with the sorted prefix.
- **Foundation** — `Data` (base64 round-trip, count-additive over append) and
  `IndexSet` (SetAlgebra: union commutative + idempotent). Run on the fast path
  (Foundation is available to the interpreter).

Caveats (documented, never asserted true): `String`/`Array` `+` not commutative;
`Double` `+` not associative; `Set.subtracting` not commutative;
`Dictionary.merging` not commutative on key collisions; and **`&&`/`||`
short-circuit** — the laws hold for boolean *values*, but not for *evaluation*
when operands have side effects (Swift does not evaluate the right operand when
the left decides the result, so `a && f()` and `f() && a` differ in what runs).

## Files / tests

- `StandardLibraryProperties.swift` (the catalog + model) + per-library
  extensions (`+Numerics` / `+Collections` / `+Algorithms` / `+Foundation` /
  `+Containers`); `KnownPropertiesRenderer.swift` (pure: list render +
  verify-program generation + output parsing); `KnownPropertiesCommand.swift`
  (the subcommand + interpreter subprocess + stdlib/package partition);
  `KnownPropertiesPackages.swift` (module → package mapping);
  `KnownPropertiesPackageVerify.swift` (temp-package build + run).
- Tests: `KnownPropertiesTests` (10) + `KnownPropertiesPackageTests` (7, incl.
  the every-imported-module-is-mapped consistency guard). Verified end-to-end:
  `--verify` reports **71/71** laws hold (stdlib + Foundation on the fast path;
  swift-numerics / swift-collections / swift-algorithms built against the real
  releases).
