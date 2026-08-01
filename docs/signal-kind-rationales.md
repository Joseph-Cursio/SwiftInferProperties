# Signal-kind rationales — the overflow file

`Signal.Kind` is one enum, and Swift will not let its cases be split across files, so
`Sources/SwiftInferCore/Signal+Kind.swift` grows monotonically with the catalogue and
hit its 400-line SwiftLint cap on 2026-08-01.

**This file is the pressure valve, and it is deliberately narrow.** Only the three
longest rationales moved — they were 99 of the file's 327 doc lines between them. The
other 40 cases keep their reasoning inline, because this repo's standing norm is that
the rationale travels with the decision (`GeneratorRecipe.rationale` exists for exactly
that reason). Moving prose out is a cost, taken here only where the alternative was a
lint failure landing on somebody else's unrelated change.

**If you add a signal and the file will not fit, move the next-longest rationale here
rather than trimming a new one.** The doc comments that remain are load-bearing: every
one records a measurement or a corpus finding, and several are the only surviving record
of why a veto exists.

---

## `unsupportedComparatorShape`

Fires on a `comparator` candidate that matched on the `(T, T) -> Bool`
**shape alone**, with no ordering name to corroborate that this relation is
meant to *order* its operands.

The inconsistency this fixes was visible in the catalog: the sibling
`equivalence-relation` template, which makes the *weaker* claim, was already
name-gated. `comparator` asserted a strict weak ordering from shape alone.

Measured on this repo: of 22 shape matches, **11 were false** — and the three
already on the default surface (`areComplementary`, `isCanonicalInversePair`,
`initializerPairAdmissible`, all internal or public) were false at `Likely`, so
this was shipping rather than latent. Two failure modes, neither visible to a
shape test:

- **symmetric relations** — `sameType(_ lhs:, _ rhs:)` is
  `lhs.trimmed == rhs.trimmed`; `areComplementary`'s docstring says
  *"Order-insensitive"*. A **correct** implementation fails asymmetry.
- **role-carrying operands** — `matches(_ name:, _ stem:)` is positional but not
  interchangeable. The label test claims to catch this and does not; `_ x: T,
  _ y: T` has no labels. That hole is **not** closed by this signal.

Weight `-25` drops 40 → 15, below the `.possible` floor, so a shape-only
candidate is suppressed rather than downgraded. Any ordering name prevents it.

**A suppressed candidate earns NO law, not a weaker one** —
`PredicateTemplate.isPredicate` excludes anything matching `isComparator`, and
that gate reads the shape, which still matches. Whether these should become
predicates is a separate calibration decision.

---

## `endomorphismRoundTripPair`

Fires on a `round-trip` pair where **both halves are endomorphisms** —
`T -> T` paired with `T -> T` — and no inverse *name* corroborates them.

Two endomorphisms are not an inverse pair. A round-trip needs opposite
directions, `A -> B` against `B -> A`; same-type-both-sides is just two
functions over one type, and the `g(f(x)) == x` law is false for almost
every such couple. The bare type-symmetry signal cannot tell them apart,
which makes it combinatorial: every `(String) -> String` helper in a corpus
pairs with every other.

Measured as an outcome, per corpus, with a systematic sample read at each
step:

| corpus | round-trip before → after |
|---|---|
| SwiftInferProperties, private seeded | 438 → **92** |
| SwiftInferProperties, baseline | 53 → **1** |
| FoundationEssentials | 142 → **53**, keeping all 5 Strong + 5 Likely |

Every same-type pair sampled was false, on **both** corpora —
`sanitizeForFileName` × `stripGenericParameters` here;
`index(afterUnicodeScalar:)` × `index(afterRun:)` (both *after*) and
`deletingLastPathComponent()` × `deletingPathExtension()` (both *deleting*) on
Foundation, 14 of 14 in the dropped sample. Every surviving Foundation
Strong/Likely claim was real:
`Date(timeIntervalSinceReferenceDate: t).timeIntervalSinceReferenceDate == t`
and `Locale(identifier: s).identifier == s`, where canonicalisation is exactly
the bug the law would find. So this raises precision on the corpus where
round-trip already worked, not only on the one where it did not.

*Method note.* A first pass tabulated same-type-vs-opposite-type shares by
regex over rendered signatures and got them wrong, reading `() -> TimeInterval`
as opposite-typed. A zero-parameter instance method's domain is its
**receiver** — `FunctionPairing.transformationDomain`, which this signal uses
and that script did not. The counts above are outcomes of the shipped code
instead, which cannot drift from it.

**Name evidence overrides it.** A base64 `encode: String -> String` /
`decode: String -> String` IS a same-type round-trip, and the curated
inverse-name pair earns +40 on its own — so this fires only when *nothing
but the shape* matched, mirroring `unsupportedAlgebraicShape`.

---

## `preconditionElidingVariant`

Fires on a `differential-equivalence` pair whose variant only
**elides a precondition** (`load`/`unsafeLoad`,
`append`/`uncheckedAppend`) rather than being a second
implementation of the same computation.

Vetoed on **unrefutability**, not falsity. The law is true — that is
the contract — but nothing can execute it: where the precondition
holds the two agree trivially, because the reference is normally the
checked wrapper around the variant or both bottom out in the same
builtin; where it does not, the variant traps or is UB, and a trap is
not a refutation. So no generator can reject any plausible
implementation, which is what "score refutability, not suggestion
count" forbids shipping.

Measured, and the reason this is a veto rather than a penalty: the
subclass has produced **zero** true positives on every corpus tried.
9 `unchecked*` pairs on swift-collections were rejected only
incidentally (`mutating`/`Void` on unsafe-handle carriers), and
`stdlib/public/core` — where the same shape returns a value on a
resolvable carrier, so the incidental gates do not fire — produced
**57 Likely-tier claims, all of this class** (32 ×
`loadUnaligned`/`unsafeLoadUnaligned`, 24 × `load`/`unsafeLoad`,
1 × `bitCast`/`unsafeBitCast`) and none of the law the family exists
for. The incidental gates were hiding a wrong marker class, which is
the "a refuter that fires first hides every refuter behind it"
hazard read from the other side.

Scored-then-filtered rather than dropped at the pairing stage, on the
`protocolCoveredProperty` precedent, so `metrics` can still answer
"how many pairs did this veto suppress?".

## `kitEqualityOracleRefuted`

**Fires when PropertyLawKit has *measured* the carrier's `==` to be broken, and the
suggestion's law is stated with it.**

Almost every property `discover` proposes is an `==` between two expressions —
`f(f(x)) == f(x)`, `a • b == b • a`, `decode(encode(x)) == x`. All of them use the carrier's
`==` as the oracle. When the kit has executed the Equatable/Hashable laws and one of them
**failed at `Strict` tier**, those proposals are not so much wrong as **unusable**: they
will be checked with a comparison that does not work, and a green run means nothing.

**Why this signal exists at all.** Before it, the toolchain was one-way — `discover`
proposed, a human wrote tests, the kit ran them, and nothing came back. The kit's verdicts
are the only *executed* evidence anywhere in the pipeline and they influenced no later
inference. That is the same quarantine as two other findings from 2026-08-01: the curated
catalog contributes zero to scoring, and `ProtocolCoverageMap` vetoes a template on the
*assumption* the kit covers a law without checking whether the kit ever ran.

**Why it demotes rather than vetoes.** The law may be perfectly true and worth stating; what
is broken is the ability to check it. The useful output is a diagnosis with a prerequisite —
*fix `==`, then these become checkable* — not silence. `ProtocolCoverageMap`'s full veto is
the wrong precedent: it fires on **coverage**, this fires on **refutation**, and a reader
whose equality is broken needs to be told, not to be shown an empty run.

**Three exclusions, each measured rather than argued.**

- **`Heuristic`-tier failures do not fire it.** `fixtures/toolchain-coverage` measured a
  *correct* type failing `Hashable.distribution` purely because the generator had been
  narrowed to hunt a collision bug — the projection bug needs collisions to be visible and
  the distribution law needs their absence, and one generator cannot serve both. Demoting on
  that basis would punish a reader for aiming their generator well.
- **`.expectedViolation` does not fire it.** The author used the kit's own
  `.intentionalViolation` suppression to say the failure is the documented design.
- **`Comparable.totalOrder` is not in the trigger set.** A broken `<` invalidates *ordering*
  laws, not equality-shaped ones. Conflating them would suppress far more than the evidence
  supports.

The witness is `fixtures/toolchain-coverage`: a projecting `==` beside a synthesized
`hash(into:)`, rejected by the kit at `Strict` in 17 trials, while all four Equatable laws
pass — because a projection *is* an equivalence relation. A tool that kept proposing
`==`-shaped laws for that type after the kit said so would be ignoring the best evidence it
has.
