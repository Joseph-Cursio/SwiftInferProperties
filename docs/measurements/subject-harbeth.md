# `Harbeth` — a fresh subject, a module-resolution defect, and a latent decode crash

> **Status:** `measured` · **As of:** 2026-09-29

The refutation hunt had stalled: the hand-check tally sat at 3–4 real of 42 since late August and
`candidate-screening-pass.md` recorded the local subject pool as nearly exhausted. This screens new
subjects by the method that pass settled on, runs the best one, and reads every failure and trap.

## 1. Screen

**Selection by querying the population** (`candidate-screening-pass.md` §8.1): GitHub code search for
hand-written `func encode(to encoder`, **182,272** files (136,192 when last run), ranked by hits per
repository, twice — once unrestricted and once scoped to `path:Sources` to favour SwiftPM packages.
Both rankings are dominated by generated SDKs (Google Cloud, FHIR, App Store Connect, openapi-generator
output), skipped by hand as the method requires. Eight hand-written candidates were cloned and run
through `scripts/screen_candidates.py`:

| candidate | revision | hand-written `Codable` ∩ `Equatable` | note |
|---|---|---:|---|
| **`yangKJ/Harbeth`** | `6c01592` | **13** | Metal image filters; 0 C files; macOS `.v12`; unspent |
| `ainame/swift-codex` | `47ca43f` | 3 | |
| `shiguredo/sora-ios-sdk` | `f7ccd8d` | 3 | iOS WebRTC wrapper |
| `SwiftDevJournal/JiraKit` | — | 1 | 556 `Codable`, 1 `Equatable` |
| `allotropeinc/StripeKit` | `4c39364` | 1 | |
| `sublabdev/scale-codec-swift` | `3a45c08` | 0 | its own codec protocol, not `Codable` |
| `OpenJelly/Open-Jellycore` | `e1ec31c` | 0 | |
| `nightscout/nocturne-swift` | `70503d9` | 607 | generated DTOs — the generated-code trap |

Harbeth's 13 are geometry and descriptor types (`C7Point2D`, `C7Size`, `Matrix4x5`, …), the shape of
`Euclid`, the best subject found by any method.

## 2. The pre-check failed on OUR side: 0 of 230 compiled

`scripts/corpus_funnel.py` on Harbeth: **1,249 seeds, 305 laws proposed (109 refutable), 230 stubs, 0
compiled.** Every stub imported `Basic`, `Compute` or `MPS` — subdirectories of Harbeth's single
target, `Harbeth`, declared at `path: "Sources"`. The accept path took the module from the file's
`Sources/<Module>/` path and ranked that above the manifest-resolved module the run already had: the
*target says what to build, sources says what to scan* trap, in the accept path.

**Fixed** (`SourceModuleResolver`): a file's module is the declared (non-test) target whose directory
contains it, longest directory first; the path convention remains the fallback for anything no target
contains (a nested package, an app, a fixture), so only a manifest answer can move a result. Used by
the stub's own import, `SendableShim` and `DeclaringModuleIndex`. **Harbeth: 0 → 88 compiled.**

**Same-code A/B over the 19 funnel repositories**: identical to census 18 on every bar — 1,176 stubs,
940 compiled, 773 passed (266 behaviour), 123 failed, 43 trapped, 1 unaccounted, and no repository moved.
The change can only move a stub where a manifest disagrees with the path convention, and no funnel
repository has that shape. A full `make test` stayed green with every batch unchanged.

## 3. Result — 88 compiled stubs

| | stubs |
|---|---:|
| passed | 66 (57 behaviour, 9 does-not-crash) |
| failed | 8 |
| trapped | 7 |
| unaccounted | 7 — documentation-only `consumer-producer` stubs that declare no `@Test` (`enqueueTexture_makeTexture.swift` and six like it), the funnel's known kind |

### 3.1 The eight failures — 0 real, every one read against the source

| law | verdict | why |
|---|---|---|
| `TextureAnalysisReadback.float16(bits:)` monotonicity | false law | decodes a bit pattern; the sign bit makes a larger input a smaller float |
| `Device.metalFunctionLookupFailureDescription` idempotence | false law | builds a message embedding its input — accumulating |
| `C7CMYKHalftone.conservativeSampleDisplacementFraction` idempotence | false law | clamp then scale by √2: not a projection |
| `TextureAnalysisValueRange.normalizedValue` idempotence | false law | rescales into `[0, 1]` by the held receiver's range; idempotent only if that range is `[0, 1]` |
| `C7Transform` / `RenderQuadRectifyTransform` / `RenderTransform3D` `.resize(input:)` idempotence | false law ×3 | each transforms a size; applying it twice transforms twice |
| `OutputSizePolicy.resolve(baseSize:)` idempotence | over-quantified domain | identity, constant or aspect-fit — plausibly idempotent at realistic sizes; refuted at width ~6×10¹⁸, where `Int` → `CGFloat` loses precision |

All mechanisms already named (`refutation-hand-check.md`): idempotence over a derivation or an
accumulation, and an over-quantified domain.

### 3.2 The seven traps — and what one of them pointed at

Five are `codable-round-trip` on `Matrix3x3`, `Matrix4x4`, `Matrix4x5`, `Vector3`, `Vector4`; the others
are `C7Rotate.resize` idempotence and `PipelineBinaryArchiveSnapshot.registeredPipelineCount`.

**The five traps are the generator's, not Harbeth's.** `Matrix3x3(values:)` requires exactly nine values
— `if values.count != 9 { HarbethError.failed(…) }`, and `HarbethError.failed` is `fatalError` in
DEBUG — while the derived generator draws `[Float]` of length 0–8. The kit did not decline the
initializer because its precondition detector does not follow a check routed through a helper: the
*init → helper* hop `criterion-a-swift-system.md` §8.5 sized and left unbuilt, here through a static
helper on another type.

**But reading the trap found a real, latent defect in Harbeth.** `init(values:)` checks the count;
**`init(from decoder:)` does not** — it decodes `[Float]` and stores it. The same holds for all five
types. And `to_factor()` indexes `values[0]` … `values[8]` unconditionally. **Verified by execution**
on the census tree (debug build): decoding `[1,2]` into a `Matrix3x3` succeeds with `values.count == 2`,
and `to_factor()` on it traps with *Index out of range* — an array bounds check, which Swift keeps in
optimised builds, unlike the DEBUG-only count check in `init(values:)`.

⚠ **LATENT, NOT LIVE**: nothing in Harbeth's `Sources/` decodes these types, and none of its 99 test
files does. They are `Codable` for clients (filter parameters such as `C7ColorMatrix4x5.matrix` are
`Matrix4x5`), so the crash is reachable by any client decoding one from outside data. **Not reported
upstream.**

⚠ **Not a law refutation, so not in the tally.** The `codable-round-trip` law would pass on every valid
value; a generator trap pointed at the invariant and a reader did the rest. It is recorded as surfaced by
the census, the same standing `swift-docc`'s latent `CatalogFeatureFlags` has, and the tally of
hand-checked refutations stays **3 real of 42**.

## 4. What this does not answer

One subject. The screen's first ranking and its `path:Sources` variant sampled at most 1,000 results
each from a relevance-ordered search, so the candidate list is what the search surfaced, not the pool.
