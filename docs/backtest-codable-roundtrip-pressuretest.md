# Pressure-test — should the coder-mediated round-trip boundary be crossed? (2026-07-20)

Review round 3 of the Apple-libraries backtest surfaced a real, in-scope
round-trip bug (swift-asn1 `a9a5efd`, `decode(encode(128)) == -128`) that the
tool MISSES on the real API because the round-trip is **coder-mediated** —
`serialize(into: inout Coder)` + `init(from: node)`, the ASN.1 analog of Swift's
`Codable` (`encode(to: Encoder)` / `init(from: Decoder)`). The tool deliberately
does not compose these. This doc pressure-tests that boundary: **should it stop
being a boundary?**

Answer: **Yes for `Codable` with a custom-conformance gate; no for framework
coders (DER, protobuf, …).** The Codable crossing is high-value, precision-safe,
and generically verifiable. The evidence below is empirical, not asserted.

> **SHIPPED** (`92da233` discover + `5146629` measured verify). The
> `codable-round-trip` template surfaces a custom-`Codable` type at Likely 50
> (validated on real code: 8 in swift-collections, 1 in swift-numerics, 0 in
> swift-asn1/algorithms — synthesized stays silent), and
> `CodableRoundTripStubEmitter` verifies `decode(encode(x)) == x` through JSON
> (corpus: `Temperature` bothPass, `ScaledRatio` — the asn1 scale-bug class —
> defaultFails). The recommendation below is the built design.

## The boundary is total today

`discover --include-possible` on a fixture with three Codable shapes — a
synthesized `Point`, a custom-but-faithful `Celsius`, and a custom-buggy `Ratio`
(an asn1-shaped scale bug: `encode` multiplies by 100, `init(from:)` divides by
1000) — surfaces **0 suggestions**. The tool never pairs `encode(to: Encoder)`
with `init(from: Decoder)`, so *every* Codable round-trip is invisible, including
the buggy one. The boundary is complete, not partial.

## Prevalence — Codable is everywhere; custom conformance is the bug-prone slice

`Codable` is ubiquitous. The valuable subset is **hand-written** `encode(to:)` /
`init(from:)`: a synthesized conformance round-trips *by construction* (the
compiler generates inverse code), whereas a custom codec is where a human can —
and does — get it wrong. The asn1 bug, unit/scale bugs (`Ratio`), and
version/migration drift all live in custom codecs.

## The precision gate — custom vs. synthesized — validated on real repos

Surfacing round-trip on *every* Codable type is the Daikon flood the conservative
posture forbids. The lever is a gate on **custom conformance**: only surface when
the type declares BOTH a hand-written `func encode(to:)` AND `init(from:)`. Real
first-party density (files with custom `encode(to:)` / `init(from:)` vs. total
Codable-conforming decls):

| repo | custom `encode(to:)` | custom `init(from:)` | Codable decls |
|---|---|---|---|
| swift-collections | 8 | 8 | 27 |
| swift-numerics | 1 | 1 | 4 |
| swift-algorithms | 0 | 0 | 0 |
| swift-asn1 | 0 | 0 | 0 (uses its own DER coder) |
| swift-argument-parser | 0 | 6 (decode-only) | — |

The gate surfaces the **8 bug-prone custom codecs** in swift-collections, not the
~19 synthesized ones — targeted, not a flood. It requires **both** halves custom
on the **same** type, so swift-argument-parser's 6 decode-only `init(from:)` (a
custom `Decoder` for CommandLine parsing, no encode) are correctly skipped. And
swift-asn1's 0 confirms a Codable extension would NOT reach asn1's real API — its
DER coder is a separate, narrower boundary that stays closed.

## Verify is generic and feasible — no framework harness needed

Unlike the DER case (which needs a library-specific serialize/parse harness), a
Codable round-trip verifies through a single generic harness:

```swift
func roundTrips<T: Codable & Equatable>(_ x: T) -> Bool {
    guard let data = try? JSONEncoder().encode(x),
          let back = try? JSONDecoder().decode(T.self, from: data) else { return false }
    return back == x
}
```

Run against the fixture: the faithful `Celsius` **bothPasses** on every generated
value; the buggy `Ratio` (asn1-shaped) is **disproven** (`1.0`, `2.5`, `3.14` all
fail; `0.0` incidentally round-trips). Requirements: `T: Codable & Equatable` +
strategist-generatable `T` — the standard measured-verify preconditions.

## Recommendation — build a gated `codable-round-trip` template

The boundary should be crossed for Codable. Proposed design (a real feature, not a
one-line recall fix — recommend owner sign-off per the PRD §3.5 calibration
discipline, as with the cycle-124/135 precision carve-outs):

- **Recognition.** A type conforming to `Codable`/`Encodable`+`Decodable` that
  declares BOTH a hand-written `func encode(to:)` AND `init(from:)`. Intra-type
  pairing (no cross-type search). Skip synthesized, decode-only, encode-only.
- **Tier: Likely, not Strong.** A custom codec is *intended* to round-trip but is
  not *definitionally* an inverse pair — it may be deliberately lossy, versioned,
  or migration-shaped. A candidate to verify, not a fact.
- **Explainability — "why this might be wrong":** custom codecs can be
  intentionally lossy/versioned; round-trip also depends on the concrete coder
  (JSON here), on `Date`/`Data`/float encoding strategies, and on key-decoding
  defaults.
- **Verify emitter:** the generic JSON harness above. Deterministic →
  `defaultFails` suppresses lossy/buggy codecs, `bothPass` promotes faithful ones.
- **Gates kept (conservative):** requires `Equatable` (a non-`Equatable` Codable
  type → unsupported, like the `inverse-pair` template's `EquatableResolver`
  gate); framework coders (DER/protobuf) stay a boundary; a non-generatable
  custom-Codable type still surfaces in discover but verify records
  `architectural-coverage-pending`.

### Honest caveats

- **NaN/Infinity** aren't JSON-representable → a `Double`/`Float` field carrying
  them would spuriously `defaultFails`; needs a finite-value generator guard or a
  documented caveat.
- **Equatable requirement** gates out many real Codable types (conservative — a
  clean miss, not a false positive).
- **Generatability:** a custom-`init(from:)` struct whose memberwise/`init` is
  internal hits the known strategist `.todo` caveats — verify skips, discover
  still surfaces.

### Why NOT the broader boundary

Framework coders (DER.Serializer, SwiftProtobuf, custom binary coders) have **no
generic harness** — each needs a library-specific serialize/parse pair, low ROI
per library. They stay a boundary. The Codable crossing captures the *same bug
class* wherever it appears behind the standard-library coder, which is the bulk of
real serialization code.
