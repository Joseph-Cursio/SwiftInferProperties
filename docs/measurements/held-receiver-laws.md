# Holding a configuration receiver fixed — what arity-bound laws did it free?

> **Status:** `measured` · **As of:** 2026-09-24

A template's arity counts the arguments its law applies, and for an instance method the receiver is
one of them (`StubApplicationArity`). So `codec.encode(_:)` needs two arguments while `round-trip`
applies one, and the accept path declined it with *"needs 2 arguments (a receiver plus 1)"*. The law
was never about the receiver: a codec, a formatter, a normaliser is configuration, and the law
quantifies over the value it is applied to. `HeldReceiver` now writes `codec.decode(codec.encode(x)) == x`
with the receiver spelled either as the package's own tests construct it, or as one draw of its derived
generator on a seed fixed by the suggestion.

## The answer

**Real movement, almost all of it in the teaching repositories.** Across the 19-repository funnel
corpus, same harness, census 11 (1.151.0) against census 13 (this branch, before the last fix below):

| | before | after |
|---|---:|---:|
| stubs | 967 | 1,160 |
| compiled | 699 | 834 |
| passed | 604 | 675 |
| — behaviour | 151 | **222** |
| — does not crash | 453 | **453** |
| failed | 68 | 116 |
| crashed | 26 | 42 |

**Quote the split, never the total.** The whole gain is behaviour laws; the does-not-crash half did not
move by one. **No repository lost ground on any bar.**

⚠ **Outside the `pbt-*` teaching repositories the gain is small: +67 stubs, +9 compiles, +4 passes.**
The teaching corpus is built out of exactly this shape — a protocol with a correct implementation and
several planted-bug implementations, each a separate object with one method — so it is the best case,
not a rate.

⚠ **The last fix withdraws 19 more stubs and moves nothing else.** Every generator-drawn receiver
outside the teaching repos had an underivable generator whose marker was a block comment, not the
`.todo` member the first version checked for; all 19 were set aside. This is COUNTED from census 13's
stubs, not re-run: stubs 1,160 → 1,141, compiled and passed unchanged.

## The population was 244, not 103

The figure this work started from, 103, undercounted. Re-counted from census 11's own decline notes:
**244 suggestions** declined for needing a receiver — `idempotence` 95, `round-trip` 63,
`monotonicity` 46, `associativity` 17, `commutativity` 17, `involution` 4, `inverse-pair` 2. **133 of
them are `pbt-workbook-corpus`**, and **76 are outside the teaching repositories**.

## What the teaching corpus says — each failure against its own control

`pbt-workbook-corpus` pairs a `Correct*` (or `Adding*`, `Max*`) implementation with planted-bug ones, so
every failure can be classified: a failure whose control passes is a bug caught; one whose control also
fails is a false law or an over-wide domain. Each held-template suite was re-run on its own, since one
trap aborts a `swift test` run.

- **25 planted-bug failures, each against a passing control.** Round-trip 8 (the CSV, run-length, two digit codecs, path codecs),
  idempotence 7 (`DropFirstKeeper`, `FlipSurvivorsKeeper`, `OnePassSorter`, `ShiftingCanonicalizer`,
  `DroppingLargestBuilder`, `DropsElementBuilder`, `DropsLastStack.pushAll`), associativity and
  commutativity 9 (subtracting, weighted, averaging, left-biased and right-only combiners, set
  difference), involution 1 (`DroppingReverser`).
- **Bugs a law passes, correctly:** `LeftBiasedCombiner` is associative and `AveragingAssociative`
  commutative, so both pass the law their bug does not break. `TieDroppingMerger` passes both — its bug
  needs two values to collide, the standing `measured-bothPass` caveat.
- **Controls that fail:** `CorrectDigits` round-trip on a negative `Int` (it is written for
  non-negatives — an over-quantified domain), and `CorrectPath` on `[""]`, which serialises to `""` and
  parses back as `[]`. The second is a real ambiguity in that path format, not a generator artefact.
- **False laws that now run instead of being declined:** idempotence of a reversal (`popAll`, fails on
  every stack including the correct one), of doubling, of delta encoding, of a hash, and monotonicity of
  `abs`. **These come from discovery proposing them, not from holding the receiver** — but holding it is
  what turns a decline into a stub that fails.
- **The new crashes are integer overflow** on full-range `Int` (`x * 2`, delta subtraction), not bugs in
  the subjects.

## Three defects the first census found in this change

Census 12 ran the first version. Three set-aside causes were the change's own, each fixed. ⚠ **Fixes 1
and 2 moved no compiles in census 13**: the stubs that showed those errors are also blocked by a
`private` subject or an underivable receiver, and two SwiftAssist stubs still report *consecutive
statements* with no receiver closure left in them, so that error has a second, undiagnosed source.

1. A closure literal opening a statement does not parse (`consecutive statements on a line`). The
   drawn receiver is now parenthesised, and a `Gen.always(X)` receiver is spelled as `X`.
2. An untyped receiver closure left the writers' `pair in` / `triple in` closures nothing to infer from.
   The closure now declares its return type.
3. `async` or `throws` subjects were spliced as bare calls. `ThrowingSubjectGate` covers `idempotence`
   only, and these rows had never reached the others because arity declined them first. **An effectful
   subject is not held**: 5 stubs withdrawn in census 13.

## What stops the rest outside the teaching repos

Of the new stubs outside the teaching repositories that do not compile, the leading causes existed
before this change: the compiler's type-check timeout (13, most on stubs whose receiver is a plain
construction and whose argument is a large literal-mixing `String` generator), `monotonicity` over a
parameter type nothing makes `Comparable` (12, SwiftSyntax's `Syntax`, which `UnorderedCarrierGate`
cannot see because it is not a scanned type), test-harvested constructions naming a type the generated
file cannot see (10), `private` subjects (6), and missing argument generators (7).

## Decisions

- **One receiver per stub, not one per trial.** A pass is a statement about that receiver. Drawing the
  configuration too would change every writer's quantifier.
- **A receiver of the parameter's own type is an operand, not configuration**, and is not held —
  `a.appending(b)` held at `a` is the accumulating-operand false-law mechanism already in the tally.
- **Not proposed: gating the false laws above.** They are discovery's conjectures and each is a named
  mechanism already recorded (`refutation-hand-check.md`); a filter here would be a filter on the
  receiver, which is the wrong layer.
