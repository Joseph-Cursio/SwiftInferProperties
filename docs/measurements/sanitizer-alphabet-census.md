# Do #672's per-character sanitizer laws have a population? Four emittable rows after the hand-check: DECLINE (#672)

> **Status:** `measured` · **As of:** 2026-11-11
>
> **Decision: DECLINE law 2 (count)** under `docs/plans/sanitizer-alphabet-census-scope.md` §7. E2 = 4,
> against the bar of 5. The reader admits exactly #672's six sanitizers. The hand-check removes one,
> SwiftProjectLint's `c99Identifier`, on which law 2 is **false**: its `map` re-joins grapheme clusters, so a
> replaced character can merge with a kept combining mark. **Law 1 stays HELD** at E1 = 2, against the line of ten
> that `docs/measurements/replacement-chain-idempotence-census.md` set. The kill arm turned #672's Python replica
> into a Swift run, and it held in every cell.

#672 shows that SwiftUMLBridge's `ERScript.sanitizeType` is a per-character keep-or-replace sanitizer that gets
only `idempotence`, and that F3's recorded `SwapTernary` survivor at L178 passes it. It proposes two laws read by
one shared reader:

- **Law 2, output alphabet:** every character of `f(x)` satisfies the keep predicate `P` or comes from an emitted
  literal. This would be a new `rewrite-postcondition` arm.
- **Law 1, fixed point:** `x ∈ Safe ⟹ f(x) == x`. It was already held on population.

#672's own gate was "build if the count is of the order of 6". Before the run, the user chose the house rule:
at least 5 emittable rows and no repository holding more than half, the rule #670 and #671 used. (#669's bar was
5 across at least 2 repositories.) The reader, universe, controls, predictions and decision were frozen in the
scope (`01d25759`) before the harness read any subject.

## Instrument

| piece | where |
|---|---|
| scope, frozen first | `docs/plans/sanitizer-alphabet-census-scope.md` (`01d25759`) |
| kill arm | `fixtures/sanitizer-alphabet/kill-arm/`, run by `scripts/sanitizer_alphabet_kill_arm.py` → `fixtures/sanitizer-alphabet/kill-arm-2026-11-11.json` |
| census harness | `fixtures/sanitizer-alphabet/census-run/` (committed at `f671d462`, before the run) → `fixtures/sanitizer-alphabet/census-2026-11-11.json` |
| universe, decision | `scripts/sanitizer_alphabet_census.py` (`controls` → `fixtures/sanitizer-alphabet/subjects-2026-11-11.json`; `report`) |
| hand-check | `fixtures/sanitizer-alphabet/handcheck-2026-11-11.json` |

- **The harness** reads every `(String) -> String` function in the universe with the reader `R` (scope §2.2). It
  folds operators with swift-syntax's `SwiftOperators`, so predicates such as `a || c == "_"` and ternaries are
  read as trees.
- **The recall pool** records, with `R`'s verdict, every shape-passing function whose body mentions
  `CharacterSet`, `isLetter`, `isNumber`, `isASCII` or `alphanumerics`.
- **The controls** are 13, all passing before the run. Five are #672's own subjects, read verbatim; eight are
  synthetic admits and refusals.
- **The verification pass.** After the first report, an adversarial pass of six independent checkers re-read:
  - every admitted row;
  - every refused pool row;
  - the universe, swept twice without the pool's tokens;
  - every number here against the JSON.

  It found the `c99Identifier` defect, now in the hand-check, and the smaller corrections recorded below. Neither
  sweep found a function the frozen grammar admits that the census missed.

## Step 1: the kill arm

`sanitizeType` is copied verbatim; its body is identical at SwiftUMLStudio `e36da59` and `9ad7631`. Each law runs
100 trials on one fixed seed:

| law | draws from |
|---|---|
| idempotence | the stub's edge-biased generator, with the literals `["_", "Unknown"]` |
| law 1 | `Safe`, drawn directly: non-empty ASCII letters, digits and `_` |
| law 2 | the edge-biased generator |

Toolchain: Swift 6.4.2, SwiftPropertyLaws 4.11.0, swift-property-based 2.0.1.

| mutant | idempotence | law 1 | law 2 |
|---|---|---|---|
| original | pass | pass | pass |
| L172 `NegateConditional` | **FAIL** | **FAIL** | **FAIL** |
| L172 `\|\|` → `&&` | **FAIL** | **FAIL** | pass |
| L172 `==` → `!=` | pass | pass | **FAIL** |
| L173 `RemoveSideEffects` | **FAIL** | **FAIL** | pass |
| L178 `SwapTernary` (F3's recorded survivor) | pass | **FAIL** | pass |

**#672's replica held in every cell.**
- **Idempotence** kills three. Two of them (`NegateConditional`, `||` → `&&`) need an empty draw. This seed
  draws 9 empty strings in 100; that count is indicative only (see the JSON's note).
- **Law 1** kills four, including the recorded survivor.
- **Law 2** is the only law that kills `==` → `!=`.
- **Together**, laws 1 and 2 kill all five.

The arm decides nothing.

## Step 2: the census

The census read 33,725 functions in 4,668 files over 40 subjects: #670's 39 roots plus this repository's
`Sources/`. That is the same universe as the #671 census.

**The reader admits exactly #672's six sanitizers, and nothing else in the universe.**

| row | core | law 2 | law 1 | emittable | in E2 |
|---|---|---|---|---|---|
| SwiftUMLBridge `ERScript.sanitizeType` | F1 loop over scalars, fallback `"Unknown"` | ✓ (per scalar) | ✓ (non-empty) | ✓ | **yes** |
| SwiftInferCLI `moduleIdentifier(from:)` | F2 map over a local `Set<Character>` | ✓ (per `Character`) | ✓ | ✓ | **yes** |
| SwiftProjectLint `NameListReader.normalize` | F3 filter after `lowercased()` | ✓ | — (pre-transform) | ✓ | **yes** |
| SwiftProjectLint `SecurityVisitor.alphanumericsOnly` | F3 filter after `lowercased()` | ✓ | — (pre-transform) | ✓ | **yes** |
| SwiftProjectLint `PackageManifest.c99Identifier` | F2 map + leading-digit `_` prefix | **✗ false** | — (prefix rule) | ✓ | no: a reader defect |
| SwiftInferCLI `sanitizeForFileName` | F2 map over a local `Set<Character>` | ✓ (per `Character`) | ✓ | private | no |

### Law 2 is false of `c99Identifier`

`String(name.map { P($0) ? $0 : "_" })` maps whole `Character`s, then `String(...)` joins them back together, and
adjacent clusters can merge. Take a control character followed by a combining `Alphabetic` scalar. In the input
they are two clusters. The control fails `P` and becomes `"_"`. The combining scalar passes `P`, because
`isLetter` reads it, so it is kept. In the output it attaches to the `"_"`, as one `Character`.

| input scalars | output scalars | output Characters | law 2 |
|---|---|---|---|
| `0A 345` | `5F 345` | 1 | fails |
| `61 0A 345` | `61 5F 345` | 2 | fails |
| `01 903` | `5F 903` | 1 | fails |

These were measured with a verbatim copy. The merged `Character` is not a letter, a number or `"_"`, so the
"identifier" holds a character outside the alphabet. This is a latent defect in `c99Identifier` itself, reachable
only from a target name that holds a control character, so it is recorded and not filed.

The filter rows cannot do this. A merged cluster there always begins with a kept character, so it still satisfies
`P`. Under scope §5 the row is a reader defect: named, and not counted.

A built reader would have to state law 2 per scalar, or refuse an F2 map whose replacement can be followed by a
kept combining mark.

### The other verdicts

- **No other reader defect.** The other five law-2 statements are true as read, and every `P` and literal was
  read right. All candidates are in library targets.
- **`moduleIdentifier` and `sanitizeForFileName`.** Law 2 holds at `Character` level, not as "the output is
  ASCII". `Set<Character>` membership is canonical equivalence, so U+212A KELVIN SIGN (NFC `K`) is kept verbatim.
- **No row needs `&&`.** Every `P` is written in #672's `||` form.

### Recall

The pool holds 22 functions: the 4 admitted rows whose bodies use a pool token, plus 18 refused.
(`moduleIdentifier` and `sanitizeForFileName` are admitted outside the pool: they use a local `Set` and no pool
token.)

Two of the 18 have a real per-character core, and both are private, so neither could enter E2:
- **SwiftLintRuleStudio's `ConfigBackupStore.readableName`** caps its result with `prefix(64)`.
- **SwiftAssist's `SwiftEvolutionCitationChecker.normalized`** collapses whitespace with a split/join.

Both map `.unicodeScalars` through `? Character($0) : LIT`, a spelling the frozen F2 clause does not list. That is
a gap in the scope, not the reader: over scalars it is F2's only compilable spelling.

The other 16 are not this shape:
- SwiftAssist's split/join slugs;
- `identifierSafe` and `suiteName`;
- two operator-name switch tables;
- GRDB's snake-case and SwiftProjectLint's kebab-case converters;
- name extractors.

### The decision, against the frozen rule

| | rows | by repository | without this repository |
|---|---|---|---|
| **E2** (law 2) | 4 | SwiftProjectLint 2, SwiftUMLStudio 1, SwiftInferProperties 1 | 3 |
| **E1** (law 1) | 2 | SwiftUMLStudio 1, SwiftInferProperties 1 | 1 |

- **Law 2: DECLINE**, because `|E2| = 4` is below 5. No repository holds more than half (SwiftProjectLint has 2
  of 4). Two of the four rows are SwiftProjectLint's identical one-line `lowercased().filter` body, in two files.
- **Law 1: stays HELD.** `|E1| = 2`, against a line of ten.

**Predictions (scope §6):**
- Step 1 held in every cell.
- E2 "≈ 5, SwiftProjectLint holds 3" was right before the hand-check and off by one after it: 4, with
  SwiftProjectLint holding 2.
- E1 ≤ 3 held: it is 2.
- "DECLINE law 2 on concentration" held as a decision, **not as a reason**: the decline is on count.

**#672's grep estimate matched the reader exactly.** The reader found the same six law-2 rows and the same three
law-1 rows. Unlike `rewrite-postcondition`'s text scan, which shrank from about 20 to 6, nothing dropped out at
the reader stage. What shrank this count was a law that is false of one subject.

## Recorded after the first report

The first report (`e3b5ac46`) counted `c99Identifier` in E2 and declined on concentration: E2 = 5,
SwiftProjectLint 3. The verification pass refuted that row's law 2, and the hand-check now records it as a
reader defect. The decision is unchanged, but its reason changed.

Smaller corrections:
- **The reader accepts a few spellings beyond §2.2.** It accepts `String.UnicodeScalarView(…)` around a map,
  inline `CharacterSet(charactersIn:)` and `.union` atoms, any `Set…`-named call with a literal, and a variadic
  `String...` parameter. None fired on an admitted row.

## What this does not answer

- **Whether the rule is right here.** Under #672's own gate, with no concentration test, 4 is still below "of
  the order of 6" taken as at least 5.
- **Split-then-join sanitizers**, which are outside the reader by design.
- **Injectivity of a sanitizer** (#674).
- **Whether one recorded kill earns law 1 below ten rows.** The kill arm now MEASURES that law 1 is the only law
  that kills the recorded survivor. Whether that earns a build is still the maintainer's call, as #672 says.
- **Unicode reach.** The kill arm draws ASCII.

## Reproduce

```
python3 scripts/sanitizer_alphabet_kill_arm.py fixtures/sanitizer-alphabet/kill-arm-2026-11-11.json
python3 scripts/sanitizer_alphabet_census.py controls fixtures/sanitizer-alphabet/subjects-2026-11-11.json
(cd fixtures/sanitizer-alphabet/census-run && swift run -c release SanitizerCensus run ../subjects-2026-11-11.json ../census-2026-11-11.json)
python3 scripts/sanitizer_alphabet_census.py report fixtures/sanitizer-alphabet/census-2026-11-11.json fixtures/sanitizer-alphabet/handcheck-2026-11-11.json
```

Every root stands at its current `main`, recorded per subject. Three subjects were dirty: the
`swiftlint-rule-studio` manifest corpus, and the SwiftLintRuleStudio and MacCloud_server funnel repositories.
