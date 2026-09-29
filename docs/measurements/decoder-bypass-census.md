# Do decoders skip the validation their own initializers make? — only in Harbeth

> **Status:** `measured` · **As of:** 2026-09-29

`subject-harbeth.md` found a real, latent defect by reading a generator trap: five Harbeth types check their
element count in `init(values:)` and not in `init(from decoder:)`. That shape can be read statically, so
this asked whether it has a population — a route to encode/decode defects that does not depend on choosing
the right subject. Plan, shape and predictions in `docs/plans/decoder-bypass-census-scope.md`, committed
before the instrument; the instrument is `scripts/decoder_bypass_census.py`; the 38 flagged types were
frozen before any was read (`fixtures/decoder-bypass-census.json`) and every judgement is recorded with its
reason (`fixtures/decoder-bypass-judgements.json`).

## Result

| group | types with `init(from:)` | flagged |
|---|---:|---:|
| 20 manifest corpora (scanned through `measurement.source_dirs`) | 157 | 17 |
| 19 funnel repositories | 19 | 0 |
| unmet subjects (Euclid, swift-docc, OpenAPIKit, jwt-kit, swift-system, Harbeth, 7 screened) | 2,508 | 21 |

**Hand-checked, all 38: 4 TRUE, 2 BENIGN, 32 FALSE — and all four TRUE are Harbeth's** (`Matrix3x3`,
`Matrix4x4`, `Vector3`, `Vector4`; all four verified by execution — decode `[1,2]`, then `to_factor()` traps). The two BENIGN: swift-foundation's `ExpressionStructure`, whose decoder
skips the type allowlist but whose identifiers fail at resolution, and swift-docc's `InterfaceLanguage`,
whose initializer takes a bit *index* restricted to 3–7 while the decoder must admit the built-in *masks*.

| why FALSE | rows |
|---|---:|
| the initializer's check concerns something the decoder does not produce (a parse, a raw pointer, a stdlib primitive's string form) | 13 |
| ⚠ instrument: an `.init(…)` **call** read as a declaration | 8 |
| ⚠ instrument: two types sharing a **bare name** merged (`Range`, `Weekday`, `Location`, …) | 6 |
| the decoder validates in a form the rule cannot see (a throwing construction, a nested type, the validating inits) | 4 |
| ⚠ instrument: `guard … else` that is control flow, not rejection | 1 |

## The predictions, scored

| # | prediction | result | |
|---|---|---|---|
| 1 | controls hold; all five Harbeth types flagged | yes, plus `C7Size` | ✅ |
| 2 | manifest corpora flag ≤ 30 | **17** | ✅ |
| 3 | ≥ 30% TRUE | **11%** (4 of 38) | ❌ |
| 4 | ≥ 1 TRUE outside Harbeth | **0** | ❌ |

## So what

**The shape has no population outside the subject it came from.** Fifteen of the 38 flags are artefacts of
this instrument — the bare-name collision is the same defect `bare-name-pairing.md` just removed from
`round-trip`, arriving in a script — but correcting all of them leaves 4 TRUE of 23, still all Harbeth.
Library code that validates in an initializer almost always either decodes through it, validates in the
decoder, or validates something the decoder never produces. **Not a route to a template, and not worth
fixing the instrument for.** Harbeth's defect stands as a finding about Harbeth.

## What this does not answer

A text census: a rejection hidden in a helper the initializer calls is invisible to it except by the
failure-name rule.
