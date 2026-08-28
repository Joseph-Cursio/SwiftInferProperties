# `swift-docc` — the strongest subject yet, and a real defect of a NEW kind

> **Status:** `measured` · **As of:** 2026-08-28

**Subject: `swift-docc` @ `f160765`, target `SwiftDocC`** (the vended library product). Left
clean — the only artifact was a gitignored `.swiftinfer/`, since removed.

**49 verdicts — ten times any previous subject** — from 267 index rows, with **13 refutations**.
Selected by the amended §6.1 screen at 46 hand-written `Codable` ∩ `Equatable` carriers, 0 C
files, 0 prior mentions.

**One refutation is a REAL DEFECT IN THE SUBJECT'S SHIPPED SOURCE, and it is not the mechanism
the first three shared.** `CatalogFeatureFlags`'s own encoder produces JSON its own decoder
**throws** on. The previous three real defects were all *`Equatable` finer than `Codable`* —
values that differ but encode identically. This one is a **failed decode**, which the same law
catches for a different reason.

---

## 1. The reading

| | |
|---|---|
| revision | `f160765` |
| target | `SwiftDocC` — the vended library product |
| host build | clean, 56s |
| in manifest / prior mentions | no / **0** on five tokens |
| source files · C files | 552 · **0** |
| hand-written `Codable` ∩ `Equatable` | **46** (of 118 in the intersection) |
| index rows | **267** |
| rows reaching the build stage | 77 |
| rows that ERRORED at the build stage | 28 |
| **rows reaching a VERDICT** | **49** |
| verdicts | **36 pass · 13 refutations** |
| `codable-round-trip` rows | 59 |
| their own suite | **1,644 XCTest (1 skipped, 0 failures) + 452 swift-testing — green** |

**Both readings are quoted, per the rule that cost this project a correction last pass.**

| subject | rows | reach build stage | verdicts | refutations |
|---|---:|---:|---:|---:|
| **`swift-docc`** | **267** | **77** | **49** | **13** |
| `SymbolKit` | 27 | 21 | 5 | 0 |
| `OpenAPIKit` | 97 | 15 | 5 | 1 |

Decline causes across the 190 pending rows: `unsupported-carrier` **115**, `not-a-candidate`
**44**, `unsupported-template` **22**, `instance-method-shape-not-supported` **8**,
`carrier-not-equatable` **1**.

---

## 2. The real defect — `CatalogFeatureFlags`

`Sources/SwiftDocC/Infrastructure/Workspace/FeatureFlags+Info.swift`,
`DocumentationContext.Inputs.Info.CatalogFeatureFlags`. **The defect is in the subject's own
shipped source.**

### 2.1 The mechanism

```swift
public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(experimentalOverloadedSymbolPresentation, forKey: …)  // Bool?
    try container.encode(experimentalCodeBlockAnnotations, forKey: …)          // Bool?
}
```

`container.encode` on an `Optional` writes **JSON `null`**; `encodeIfPresent` is what omits the
key. The decoder then iterates `values.allKeys`, finds the key **present**, and calls
`try values.decode(Bool.self, forKey:)` on a null.

### 2.2 Reproduced by executing their code

A probe against the package (written, run, deleted):

```
json: {"ExperimentalCodeBlockAnnotations":null,"ExperimentalOverloadedSymbolPresentation":true}
decode THREW: DecodingError.typeMismatch — Expected to decode Bool but found null instead
```

**Any value with one flag set and the other `nil` — the ordinary case, since both default to
`nil` — encodes to JSON its own decoder rejects.**

### 2.3 A second defect in the same type

`unknownFeatureFlags` is populated on decode and **never encoded**:

```
decode {"SomeUnknownFlag": true}  →  unknownFeatureFlags: ["SomeUnknownFlag"]
re-encode                          →  {"ExperimentalOverloadedSymbolPresentation":null,
                                       "ExperimentalCodeBlockAnnotations":null}
```

The unknown flag is **silently dropped**, and the re-encoded JSON now has *two* nulls, so it
fails to decode as well. The field exists to preserve forward-compatibility information, and
encoding discards exactly that.

### 2.4 What it costs today — stated, because it bounds the claim

**Nothing in `SwiftDocC` encodes this type.** A grep for encode sites finds none; the type is
decoded from catalog `Info.plist`. **So this is a real defect on PUBLIC API that the package
itself never exercises — latent, not live.** It cannot be reported as *DocC is broken*.

**Their suite misses it, and the coverage is zero rather than thin**: across 1,644 + 452 tests,
**no test names `CatalogFeatureFlags` at all**.

⚠ **A maintainer could reasonably answer *the encode path is not meant to be used*.** That
would make it a latent defect rather than an active one; it would not make the round trip hold.

---

## 3. It is NOT the mechanism the first three shared, and that corrects a generalisation

The three earlier real defects — `ToolChoice`, `UserDetectionStatus`, `OpenAPI.XML` — were all
one shape: **`Equatable` finer than `Codable`**, two distinct values with one encoding. After
the third it was tempting to say the mechanism *is* the finding.

**`CatalogFeatureFlags` refutes that at n=4.** `==` is never reached: `decode` throws. The law
`decode(encode(x)) == x` catches it because a **thrown decode is a failed round trip**, which is
a second, independent way for the same law to earn its keep.

**Read this as widening the template's value, not narrowing it.** `codable-round-trip` is not a
detector for one asymmetry; it is a detector for *the encoder and decoder disagreeing*, and
they can disagree by throwing.

---

## 4. The other twelve refutations, triaged

**10 of 13 resolved. Three are NOT resolved and are recorded as open rather than guessed at.**

### 4.1 Five `idempotence` refutations — all already-named false mechanisms

| subject | why false | named mechanism |
|---|---|---|
| `String.appendingHashedIdentifier(_:)` | `appending("-\(hash)")` — twice appends twice | accumulating operand |
| `JSONPointer.removingFirstPathComponent()` | `pathComponents.dropFirst()` — twice drops two | one-shot stripper (`removingLastComponent`'s shape) |
| `String.stableHashString` | hash of a hash | idempotence over a **derivation** |
| `SymbolInformation.hash(uniqueSymbolID:)` | as above | idempotence over a **derivation** |
| `FileServer.mimeType(for:)` | mime type of a mime type | idempotence over a **derivation** |

**`idempotence` moves 0 real of 18 → 0 real of 23.** Five more instances, no new mechanism, and
nothing that would end the template comparison.

### 4.2 Four `codable-round-trip` refutations that are over-quantified

**`PlatformName` is the mechanism and it is a FIFTH named false-law shape**: `encode` writes
only `displayName`; `init(from:)` calls `init(operatingSystemName:)`, which rebuilds `rawValue`
and `aliases` from a **canonical lookup**. A value whose fields do not agree with that table is
not constructible through the intended API, and the generator invented one
(`rawValue: "i", aliases: [7 random strings], displayName: "17"`).

> **New named mechanism — *round trip over a type whose fields are DERIVED from a canonical
> table, so only canonical values are constructible*.** Distinct from the undeclared
> cross-field invariant shape: there the invariant is unstated, here the canonical form is
> stated by an initializer the generator does not use.

`DefaultAvailability` and `ModuleAvailability` **embed `PlatformName`**, so they are the same
mechanism, not independent evidence. `CodeColors` is over-quantified too — its counterexample
carries `alpha: 877527.7`.

### 4.3 Three UNRESOLVED

- **`String.replacingWhitespaceAndPunctuation(with:)`** (idempotence, trial 456). Splits on
  whitespace ∪ punctuation and rejoins with a separator. Idempotent for the separators a caller
  would pass; the failing operand is not recovered from the counterexample. **Two copies of this
  function exist** (`SwiftDocC` and `DocCTestUtilities`), and which one was measured is not
  established.
- **`JSONPointer.encode(to:)`** (trial 6, empty counterexample). Encodes `description`, decodes
  via `Self.unescaped(_:)`. Plausibly an empty-pointer edge — `[]` vs `[""]` — unconfirmed.
- **`DownloadReference.encode(to:)`** (trial 0). `encode` **rewrites the URL** through
  `renderURL(for:prefixComponent:)` and never encodes `encodeUrlVerbatim` at all. That is
  asymmetric by construction, and whether it is a defect or a deliberate render-output encoder
  is a maintainer's question.

---

## 5. The tally

**40 hand-checked · 4 real.**

| template | hand-checked | real |
|---|---:|---:|
| `idempotence` (+ operand forms) | **23** | **0** |
| `codable-round-trip` | **17** | **4** |

**`idempotence` is now 0 for 23** across four codebases. **All four real defects are
`codable-round-trip`, on four independent unmet subjects, each missed by the subject's own
suite.**

⚠ **Still not a rate, and the reason is unchanged.** Nine of the seventeen codable checks remain
one mechanism from one generated codebase, and three of this subject's four over-quantified ones
share `PlatformName`. Deduplicated by mechanism it is nearer **4 real of 7 distinct
mechanisms** — the largest denominator yet and still too small to quote as a precision.

⚠ **Depth of check, stated per finding.** `CatalogFeatureFlags` was traced in full and
**executed**. `PlatformName` was traced in full and its two embedders pattern-matched. The five
`idempotence` subjects were read at their implementations. The three in §4.3 were **not
resolved**.

---

## 6. What this does NOT claim

- **Not that DocC is broken.** §2.4 — nothing in the package encodes the type.
- **Not that 49 verdicts is a rate of anything.** It is one subject's reach, and it is the
  reach number, not a quality number.
- **Not that the 28 build-stage errors are diagnosed.** They are not looked at here.
- **Not that §4.3's three are false.** They are unresolved, which is a different claim.

## 7. What would refute this

- **A maintainer stating the `CatalogFeatureFlags` encode path is deliberately unused**, which
  would make it latent rather than active — and would still leave the round trip broken.
- **Resolving any of §4.3 as REAL**, which for `replacingWhitespaceAndPunctuation` would end the
  `idempotence` comparison outright.
- **A fifth real defect that is NOT `codable-round-trip`**, which would break the one pattern
  that has held across four subjects.
