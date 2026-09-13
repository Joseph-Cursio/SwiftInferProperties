# Can the totality test reach the bugs totality is about? (2026-09-13)

`input-totality` and `predicate` state that a subject returns or throws for every
input its parameter type admits, and never traps. The emitter for that law shipped
today (#447), and S8 demonstrated one running and catching a planted trap.

**One planted bug is not a measurement, and it was the one I picked.** This is the
follow-through: six trap classes, predicted before the run, then measured.

## Why it was worth suspecting

`InputTotalityTemplate`'s own header says so:

> Refutable: any input that trips a trap. Hard: a generator drawing *realistic* text
> will essentially never produce one. The counterexamples live in malformed input —
> empty, invalid UTF-8, lone surrogates, unbalanced delimiters, pathological nesting
> — and they have to be generated on purpose. **A generator tuned for coverage of the
> *type* is silently mistuned for coverage of the *law*.**

So the template predicted its own emitter would under-reach. This tests that.

## Instrument

Subject `WikilinkParser.parse(_:)` on SwiftMarkdownWiki `46cb4a9`; the stub as
emitted, unedited. Each violator is a `precondition` at the top of `parse` — a real
totality bug, one class per run, 100 trials.

The generator the stub carries is `RawType.edgeBiasedGeneratorExpression`: ASCII
alphanumerics 0–8, plus 14 curated punctuation/whitespace tokens, doubled and
suffixed. Reachable domain: **ASCII only, length ≲ 16, no `[`, no `]`.**

## Prediction, written before the run

3 of 6 — the three whose triggering input happens to be a curated token.

## Result: 3 of 6, matching the prediction violator-for-violator

| # | trap fires on | predicted | measured |
|---|---|---|---|
| 1 | empty input | CAUGHT | **CAUGHT** |
| 2 | a newline | CAUGHT | **CAUGHT** |
| 3 | a tab | CAUGHT | **CAUGHT** |
| 4 | any non-ASCII scalar | missed | **missed** |
| 5 | `[[` in the source | missed | **missed** |
| 6 | length > 64 | missed | **missed** |

**Row 5 is the one that matters, and it is the worst possible miss for this subject.**
`WikilinkParser` exists to parse `[[…]]`. Its real trap bugs would live in bracket
handling, and **the generator cannot produce a single bracket.** The law is aimed at
the subject's hazardous inputs and the generator draws exclusively from the safe ones.

The three it catches are caught by coincidence rather than by design: `""`, `"\n"` and
`"\t"` are in `stringEdgeCases` because that list was curated for *structural string
laws* — YAML markers and heading prefixes — not for totality. A different curation with
equal claim to being "edge cases" would score 0 of 6.

## A hostile generator closes it: 6 of 6, with the control intact

Same six violators, same subject, generator replaced with one carrying the three
missing classes — the delimiters the subject actually parses (`[[`, `]]`, `[[a|b]]`,
`|`), `Gen<Character>.latin1` for non-ASCII, and `Gen<Character>.ascii.string(of: 0...120)`
for length:

| | current | hostile |
|---|---|---|
| violators caught | **3 of 6** | **6 of 6** |
| correct code | passes | **passes** |

The control row is load-bearing. A generator that failed everything would also score
6 of 6, and would be worthless. It still passes on unmodified `parse`.

## What this argues for, and what it does not

**It does not argue for widening `stringEdgeCases`.** That list feeds every string law,
and it was tuned for a different one — `edgeBiasedGeneratorExpression` exists because
`strippingHeadingMarkers` needed a *repetition* witness (SwiftPropertyLaws#42, measured
at 0 of 3 920 before the fix). Adding brackets and Latin-1 to it would re-tune a
generator that is currently correct for its own purpose, and would move every
idempotence golden.

**It argues that totality needs its own generator**, which is the template's own thesis
restated: the law, not the type, should pick the inputs. Two laws over `String` want
different draws, and the catalog currently gives them the same one.

⚠ **Single subject, single parameter type.** Six violators on one function is enough to
show the gap exists and that a hostile draw closes it; it is not a rate. The `[[` row
generalises least — it is specific to what this subject parses — and generalises most as
an argument, because *every* parser has delimiters and no curated list will contain all
of them.

---

## Shipped, and re-measured against the shipped code (2026-09-13)

The 6-of-6 above was a spike: a generator pasted into the stub by hand. This is
the same sweep against `RawType.hostileGeneratorExpression` as released in kit
**v4.6.1**, with the stub as the tool emitted it and no hand-editing.

| trap fires on | edge-biased | hostile (shipped) |
|---|---|---|
| empty input | caught | **caught** |
| a newline | caught | **caught** |
| a tab | caught | **caught** |
| any non-ASCII scalar | missed | **caught** |
| a `[[` delimiter | missed | **caught** |
| length > 64 | missed | **caught** |
| **score** | **3 of 6** | **6 of 6** |
| correct code | passes | **passes** |

⚠ **v4.6.0 shipped the generator with a bug, and the sweep is why v4.6.1 exists.**
`hostileTokens` carries `\u{0}` and `\u{7F}` — a parser trapping on NUL is exactly
what a totality law is for — and `swiftStringLiteral` escaped only `\`, `"`, `\n`
and `\t`, so those went into the generated `.swift` file as **raw bytes**. Every
test on that function compared strings, and a NUL inside a Swift string compares
equal to itself; it was found by reading the emitted file's bytes. The guard now
asserts on the emitted expression's *scalars*, the only form in which it is visible.

**Only totality stubs changed.** The idempotence and monotonicity arms keep
`edgeBiasedGeneratorExpression`, verified by re-emitting: the non-totality files are
byte-identical across the change. That was the point of a sibling rather than a
wider `stringEdgeCases`.
