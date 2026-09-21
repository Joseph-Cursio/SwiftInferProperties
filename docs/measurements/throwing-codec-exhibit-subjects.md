# The throwing-codec shape, measured where the findings actually came from

> **Status:** `measured` · **As of:** 2026-09-21

[`throwing-codec-census.md`](throwing-codec-census.md) sized this shape over the 20-corpus
manifest, found Shape A **once in 172** hand-written encoders, and then recorded that **the corpus
could not answer the question** — none of the four subjects that ever produced a
`codable-round-trip` finding is in it. Its §4 names the next step exactly:

> **Run this census over the four exhibit subjects**, which is cheap and needs no manifest change.
> ⚠ **Do NOT add them to the manifest for this**: the corpus universe is the denominator of every
> other census.

This is that run. `scripts/throwing_codec_census.py` takes subjects as arguments and shares
`measurement.py`'s file walk, so `EXCLUDED_DIRS` still drops `Tests`.

Subjects at the SHAs their findings were taken on: `mcp-swift-sdk` `a0ae212`, `jwt-kit` `8189d7c`,
`swift-docc` `f160765`, `OpenAPIKit` `651cc55`.

## The reading

| subject | files | `encode(to:)` | `init(from:)` | Shape A | Shape B |
|---|---:|---:|---:|---:|---:|
| mcp-swift-sdk | 52 | 42 | 43 | 0 | 4 |
| jwt-kit | 84 | 13 | 16 | **1** | 0 |
| swift-docc | 584 | 83 | 97 | **1** | 3 |
| OpenAPIKit | 197 | 81 | 81 | **2** | 0 |
| **total** | **917** | **219** | **237** | **4** | **7** |
| *manifest, for comparison* | *2,498* | *172* | *191* | *1* | *0* |

✅ **The detector re-finds the known exhibit unaided.** jwt-kit's single Shape A hit is
`AppleIdentityToken.UserDetectionStatus` — the type `refutation-hand-check.md` recorded as a real
defect — found by a shape rule that names neither the type nor the subject.

## Shape A does NOT refute the original census, and the decomposition is why

§6 of that census set the refutation condition: *Shape A finding a substantial population on the
exhibit subjects*. **4 of 219 encoders is 1.8% against the manifest's 0.6% — three times denser and
still not substantial.** Read one by one, it is smaller than that:

| site | what it is | a defect? |
|---|---|---|
| `jwt-kit` `UserDetectionStatus` | the known exhibit | **yes**, already counted |
| `OpenAPIKit` `AnyCodable` | `Any` erasure; throws in a `default:` arm | **no** — irreducible |
| `swift-docc` `AnyMetadata` | `Any` erasure; throws in a `default:` arm | **no** — irreducible |
| `OpenAPIKit` `ComponentKey` | the `UserDetectionStatus` mechanism | **candidate** |

⚠ **Two of the four are `Any`-erasure wrappers, which cannot be anything else.** A type whose
stored value is `Any` cannot promise to serialise it; throwing in the `default:` arm is the only
honest option. They match the shape and are not the thing the shape was meant to find. **That is a
precision limit of Shape A, and it is new information** — the manifest's single hit was not of this
kind, so nothing said the rule had this failure mode.

✅ **So across four subjects hand-picked as the richest the toolchain has ever found, the shape
yields ONE new candidate site.** `ComponentKey` is the `UserDetectionStatus` mechanism exactly:
constructible through the type's own declared API into a state the encoder rejects. Its author
wrote the reason down:

```swift
// we check for consistency on encode because a string literal
// may result in an invalid component key being constructed.
guard Self(rawValue: rawValue) != nil else { throw GenericError(…) }
```

⚠ **And that comment cuts both ways.** It is the mechanism, stated by the maintainer — and it is
also evidence the behaviour is *intended*, which is exactly the ground on which OpenAPIKit's
maintainer ruled `OpenAPI.XML` not a defect. **Not adjudicated here**, and not added to the tally:
the tally moves on a hand-check, not on a shape match.

## Shape B went 0 → 6 and then to 0 on a hand-check

The shape the manifest could not witness appeared to exist here — 6 sites across two subjects
after two instrument fixes, 4 in mcp-swift-sdk and 2 in swift-docc. **Read one by one, none of
them is real.**

### Hand-checked: 6 of 6 FALSE, and Shape B is refuted as a detector

Every site was read. **Not one is an asymmetry any type has**, and a seventh — swift-docc's
`LinkDestinationSummary.platforms` — was an artifact of this census's own regex, found while
checking it. Four distinct false-positive modes, two of them beyond what a call-name proxy can
see:

| mode | sites | mechanism |
|---|---:|---|
| **cross-ARM in a discriminated union** | 3 | `Content` encodes `mimeType` required in `.image`/`.audio` and `encodeIfPresent` in `.resourceLink` — and decodes them `decode` and `decodeIfPresent` to match. **Every arm is internally consistent**; the proxy pairs keys across arms of one type |
| **`encodeIfPresent` on a NON-OPTIONAL value** | 3 | `Elicitation`'s `requestedSchema` is `RequestSchema`, `RenderAttribute`'s payloads are `String`. Swift promotes `T` to `T?` at the call site, so the key is **always** written |
| cross-TYPE in one file | 5 | fixed before publishing; `DocumentInfo.swift` declares `Contact`, `License` and `Info` together |
| a regex spanning a parenthesis | 1 | `decode(SourceLanguage.self)` and a later `decodeIfPresent(…, forKey: .platforms)` read as one call |

⚠ **The first two are the same missing capability the original census named**: *detecting that
needs the property's optionality, not just the call name*. It recorded this as a reason Shape B
would **undercount**; measured, it is why Shape B **overcounts**, and on this population it
overcounts to the point of being all it does.

**So Shape B has 0 real sites in 219 hand-written encoders across the four richest subjects
known** — a precision of 0 of 6 on the sites it reported, or 0 of 12 before two instrument fixes.

⚠ **This CORRECTS the reading published hours earlier in this same document**, which called Shape
B *the real movement* and *the one worth pursuing* on the strength of the count alone. A shape
census sizes a population; it was the hand-check that said what the population was, and the
answer is nothing.

### Rebuilt arm-aware, and it reproduces the hand-check unaided

Shape B was rebuilt to pair an encoder with a decoder on the **same type, the same arm**, and only
where the encoded value is **actually optional**. Arms are paired by the discriminator an encoder
arm *writes* (`encode("image", forKey: .type)`) against the literal a decoder arm is *labelled*
with (`case "image":`).

**It reports 0 across all four subjects** — the same answer the hand-check reached by reading, now
reached mechanically.

⚠ **A zero is only worth as much as the proof the detector can still say one**, which is the trap
`module-state-base-rate.md` shipped once and this census has now nearly repeated twice. Three
controls were added to separate *discriminating* from *blind*, and all three are asserted before
any subject figure is printed:

| control | asserts |
|---|---|
| **still fires when the arms are paired** | a union whose *own* arm omits a key that same arm's decoder requires → **1** |
| does not pair across arms of one union | the mcp-swift-sdk shape reduced → **0** |
| ignores `encodeIfPresent` on a non-optional | the `requestedSchema` / `RenderAttribute` shape → **0** |

⚠ **The count is now a FLOOR.** An arm whose discriminator cannot be read is skipped, because this
shape's measured failure mode is overcounting and the conservative direction is the one that keeps
a reported site worth reading. A real asymmetry in a union that discriminates some other way would
be missed.

## ⚠ An instrument error, caught by reading a hit rather than by the control

**The first run of this census read Shape B as 12.** The pairing was scoped to the *file*, so
`OpenAPIKit/Document/DocumentInfo.swift` — which declares `Contact`, `License` and `Info` together
— had one type's `encodeIfPresent(name,…)` paired with another type's `decode(…, forKey: .name)`
and reported as an asymmetry **neither type has**. Scoping the pairing to the enclosing type takes
it to **7**; both OpenAPIKit hits were artifacts.

**The control did not catch this**, because every control case held one type. A case with two types
in one file is now in the control and is asserted to read zero. The lesson is the one this
repository keeps paying for: *a control tests the cases you thought of*, and the hit list is what
tests the rest — which is why the hits are printed rather than only counted.

## What this changes

- **The template split stays unproposed.** Shape A yields one new candidate across the four richest
  subjects known, and two of its four matches are irreducible `Any` erasure. Splitting
  `codable-round-trip` on this would rest on a population of one.
- **Shape B's call-name proxy is refuted, 0 real of 6 — and the rebuilt detector agrees, reporting
  0 from the other direction.** A proxy cannot see an enum's arms or a payload's optionality, and
  both are needed before a match means anything. With both, the population on these four subjects
  is **zero**, which is a measurement rather than a limitation.
- ⚠ **Nothing here moves the tally**, which stays **3 real of 42**. A shape census sizes a
  population; only a hand-check makes a finding.

## What would refute this

- **A fifth exhibit subject with a dense Shape A population**, which would make the
  1-of-4-minus-2 reading here a property of these four subjects rather than of the shape.
- **A subject where the arm-aware detector fires.** It is now built and proven to discriminate, so
  a site it reports is worth reading; these four subjects simply have none.

## Reproducing

```
python3 scripts/throwing_codec_census.py <subject-dir>...
```

The control runs first and the run aborts if it fails, so no subject figure is printed from a
detector that has not proved it can see both shapes.
