# The throwing-codec shape — sized, and the corpus cannot answer it

> **Status:** `measured` · **As of:** 2026-08-31

**Why this was run.** `refutation-hand-check.md` split `codable-round-trip`'s refutations into two
mechanisms with opposite track records:

| mechanism | survived scrutiny |
|---|---|
| **value promotion** — `Equatable` finer than the wire form | **0** — one ruled INTENDED by its maintainer, one contested, nine false |
| **throwing** — a codec fails on a value the type's own API produces | **2 of 2** |

If the throwing shape has a population, splitting the template's assertion would let the
refutation rate be read per mechanism instead of pooling a 0-for-11 arm with a 2-for-2 one.
**Sizing it first is the whole point** — five proposals this cycle were exact on one subject and
had no population.

## 1. The reading

| | |
|---|---:|
| Swift files scanned (`EXCLUDED_DIRS` applied) | 2,498 |
| mentioning `Encoder` / `Decoder` | 186 |
| **hand-written `encode(to:)`** | **172** |
| **hand-written `init(from:)`** | **191** |
| **Shape A — an encoder that can `throw`** | **1** |
| **Shape B — `encodeIfPresent` on a key `decode` requires** | **0** |

The single Shape A hit is `PredicateExpressions.KeyPath` in `swift-foundation`.

**Shape A is the sharp signal, and the asymmetry is deliberate.** A *decoder* throws on malformed
input by design — an explicit `throw` in `init(from:)` is ordinary validation. An *encoder*
receives a value that already exists, so **an encoder that can throw is a type admitting values it
cannot serialise.** That is exactly `UserDetectionStatus`. `throw` in `init(from:)` is therefore
not counted: a claim, not an oversight.

## 2. ⚠ THE CORPUS CANNOT ANSWER THIS QUESTION, AND THAT IS THE FINDING

**None of the four subjects that produced a `codable-round-trip` finding is in the manifest.**

| subject | finding | in the 22 corpora? |
|---|---|---|
| `mcp-swift-sdk` | `ToolChoice` | **no** |
| `jwt-kit` | `UserDetectionStatus` — Shape A | **no** |
| `swift-docc` | `CatalogFeatureFlags` — Shape B family | **no** |
| `OpenAPIKit` | `OpenAPI.XML` | **no** |

So this counted 172 hand-written encoders across a corpus list holding **zero of the exhibits**.
The manifest is Apple-adjacent library code — syntax, collections, foundation, NIO, the package
manager — and every exhibit came from **schema and API-client code**, which is where hand-written
`Codable` with validation actually lives.

**This is the fifth payment of *a census is only as wide as its corpus list*, and the second time
the manifest has been unable to answer a question about a shape it contains none of** — after
`module-qualified-leaf-spelling.md`, where the manifest held no generated-code subject.

## 3. What the reading DOES support

**1 throwing encoder in 172 is a real number about this kind of code.** A codec that refuses its
own values is not a general Swift pattern; it is close to absent from general-purpose libraries.

**So the template split is NOT proposed.** It would rest on a mechanism whose population is
unmeasured where it matters and near-zero where it was measured. ⚠ **And 2 of 2 was never a rate**
— it is two findings on two subjects, and the split would have been reading a shape into a sample
of two.

## 4. What would answer it

**Run this census over the four exhibit subjects**, which is cheap and needs no manifest change.
⚠ **Do NOT add them to the manifest for this**: the corpus universe is the denominator of every
other census, and `census-universe-17-to-20.md` records what moving it costs — every figure has to
be re-taken from one run. A shape census over named subjects is a different instrument from the
manifest census and should stay one.

## 5. The control, and why Shape B needed it more

**Both shapes are asserted detectable on synthetic sources** before either number is read. Shape A
came back 1 and Shape B came back **0**, and a detector that finds nothing prints the same figure
as a population that holds nothing — a mistake this project has shipped before, in
`module-state-base-rate.md`, whose home arm reported a zero from a detector blind to the syntax it
was looking for.

The control's two types are the exhibits reduced: an encoder that refuses one of its own values,
and a key the encoder may omit while the decoder demands it. Both are found.

⚠ **Both shapes are FLOORS.** Neither reaches a codec that throws through a helper, and Shape B's
proxy misses the `encode`-writes-null form its own exhibit (`CatalogFeatureFlags`) actually uses —
detecting that needs the property's optionality, not just the call name.

## 6. What would refute this

- **Shape A finding a substantial population on the exhibit subjects**, which would mean §2's
  caveat is the whole story and the shape is common where it matters.
- **A hand-written codec that throws through a helper**, which would make §5's floor materially
  low rather than usefully conservative.
