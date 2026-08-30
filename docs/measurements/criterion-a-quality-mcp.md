# A-quality on a short-chain subject — answered YES, by a real defect

> **Status:** `measured` · **As of:** 2026-08-23

**A-quality: YES.** An emitted law found a **real, pre-existing defect** in a subject the
toolchain had never met, and the subject's own **551-test suite misses it**.

Subject: **`mcp-swift-sdk` @ `a0ae212`** (the MCP Swift SDK). Left clean — the only artifact is
a gitignored `.swiftinfer/`.

**This is stronger than the bar asks for.** A-quality is phrased around a *planted* mutant
because planted evidence is guaranteed to be a defect. This needed no mutant: the law refuted
on the subject as shipped, and the adjudication is *is the refutation real*, answered below.

---

## 0. ⚠ ADDENDUM 2026-08-30 — this finding is the shape OpenAPIKit's maintainer ruled INTENDED

**Checked because `OpenAPIKit#509` came back *intended*** and its reasoning was general:
*"the OpenAPI documents are equivalent, the in-code constructions just aren't identical."*
`ToolChoice` was then examined against that same standard, reading the source at `a0ae212`
rather than our summary of it. **It fails the test the same way:**

| | `OpenAPI.XML` (ruled INTENDED) | `ToolChoice` |
|---|---|---|
| non-canonical in-code state | `.legacy(false, false)` | `mode: nil` |
| canonical state | `nil` | `.auto` |
| documents | **byte-identical** | **byte-identical** (`{}`) |
| decode canonicalises | yes | yes (`decodeIfPresent(…) ?? .auto`) |
| the two mean the same thing | yes — *no attribute, not wrapped* | **yes, and the type SAYS SO** |

The decisive line is `ToolChoice`'s own doc comment, and it is on the **Swift property**, not on
the JSON field:

```swift
/// The tool choice mode. If omitted, defaults to `.auto`.
public let mode: Mode?
```

**So the type documents `nil` and `.auto` as the same thing**, and the finding rests on demanding
value-identity where the type itself asserts value-equivalence. That is precisely the demand the
one maintainer who has ruled on it rejected.

⚠ **STATUS: CONTESTED, not withdrawn** — and the distinction is deliberate. **MCP's maintainers
have not been asked**, and *over-claiming contamination is not the safe direction*: a finding
wrongly marked false gets discarded and its work repeated. One project's ruling is evidence about
the *reasoning*, not authority over another project's type.

⚠ **And MCP's case differs in a way that arguably makes it MORE defensible as a defect than
OpenAPIKit's.** OpenAPIKit's maintainer had a stated policy reason for the non-canonical state —
*"I want to support explicitly representing the legacy combinations of properties."* **MCP claims
no such purpose for `nil`**; its doc says `nil` *means* `.auto`. So this is an unnormalised
initialiser (`init(mode: Mode? = .auto)` with no `?? .auto`) rather than a deliberate legacy
form, and the one-line lossless fix — `self.mode = mode ?? .auto` — takes nothing away. **That is
an argument, not a verdict.**

⚠ **CONSEQUENCE FOR CRITERION A-quality, which this document is the sole evidence for.** The bar
is *≥1 passing law kills a mutant the subject's existing tests miss*, and it was answered **yes**
here **by a real defect standing in for a planted mutant**. If this finding is not a defect, the
substitution fails and **A-quality reverts to its earlier, weaker basis**: the `swift-system`
planted NUL-guard mutant, *NO at the shipped budget, YES at N ≥ 500*. **The default budget is now
N=1000**, so that route plausibly still meets the bar — but the basis changes from *a real defect
on shipped code* to *a planted mutant at the shipped budget*, and `toolchain-exit-criteria.md`'s
headline claim of *by a REAL defect and NO planted mutant* does not survive as written.

**§1 onward is the original analysis. It describes the behaviour accurately; what is in question
is the verdict drawn from it.**

---

## 1. The finding

`CreateSamplingMessage.ToolChoice` (`Sources/MCP/Client/Sampling.swift:465`):

```swift
public let mode: Mode?                              // .auto | .required | .none
public init(mode: Mode? = .auto) { self.mode = mode }

public init(from decoder: Decoder) throws {
    mode = try container.decodeIfPresent(Mode.self, forKey: .mode) ?? .auto   // nil → .auto
}
public func encode(to encoder: Encoder) throws {
    if let mode, mode != .auto { try container.encode(mode, forKey: .mode) } // nil AND .auto → omitted
}
```

The type is `Hashable, Codable`. Independently reproduced against the package:

```
encode(nil)   : {}          encode(.auto) : {}        ← byte-identical
a == b        : false       hash equal    : false
round trip    : ToolChoice(mode: nil) → ToolChoice(mode: .auto)
```

**Two values the type documents as meaning the same thing** — the doc comment reads *"If
omitted, defaults to `.auto`"* — **encode identically, are not equal, and hash differently.**
`Codable` conflates them; the synthesized `Equatable`/`Hashable` distinguishes them.

Consequences: a `Set<ToolChoice>` can hold both; equality is not preserved across a JSON round
trip; `Hashable` and `Codable` disagree about identity.

**Reachability**: `init(mode: Mode? = .auto)` defaults to `.auto`, so `nil` requires an explicit
`ToolChoice(mode: nil)`. That is unusual but legal, public, and the type is `public`.

---

## 2. Their tests miss it

| | |
|---|---|
| suite at `a0ae212` | **551 tests in 40 suites, all passing** |
| occurrences of `ToolChoice` in `Tests/` | **0** |

The defect ships green. **That is the A-quality bar met: a law killed something the subject's
own tests miss.**

---

## 3. Why THIS template, and why that matters

The refuting template is **`codable-round-trip`**, and the distinction from everything before
it is structural rather than lucky.

`decode(encode(x)) == x` is a law the code **owes**: the type declares `Codable` and
`Equatable`, and those two conformances make the claim between them. Idempotence, by contrast,
is a **conjecture read off a shape** — the tool's own caveat says so, and every one of the 18
false laws hand-checked before today was one.

| | |
|---|---:|
| hand-checked refutations before today | **18, all false laws** |
| this one | **1 real** |
| **tally** | **1 real of 19** |

**The 18 were `idempotence` or its operand form. This one is `codable-round-trip`.** One data
point is not a rate, but it is the first evidence that *which template refutes* carries
information — a question `refutation-hand-check.md` measured as **NO** across a population that
contained no codable-round-trip refutations to measure.

---

## 4. The short-chain rule, validated

`toolchain-exit-criteria.md` §6.1 says select for **unmet AND short-chain**, and offers a
one-run pre-check: *how many rows reach the build stage*.

| | `swift-system` | `mcp-swift-sdk` |
|---|---|---|
| public struct/enum vs class | value types behind C interop | **173 vs 2** |
| C / header files | pervasive | **0** |
| target path vs name | `Sources/System` / `SystemPackage` ← a bug | `Sources/MCP` / `MCP` |
| discovery mix | 18 of 41 `idempotence` | **28 of 67 `codable-round-trip`** |
| **rows executing, FIRST run, zero fixes** | **0 of 41** | **10 of 67** |

swift-system needed four fixes across two days to reach 8 executing rows. **MCP reached 10 on
the first attempt.** The structural criteria predicted this before the run, which is what makes
§6.1 a rule rather than a story told afterwards.

Full pre-check: 27 `unsupported-carrier`, 20 `not-a-candidate`, 7 `unsupported-template`,
**9 `bothPass`**, **1 `defaultFails`**, 2 `build-failed`, 1 trap. Stream frozen at
`fixtures/mcp-swift-sdk/2026-08-23-precheck.jsonl`.

---

## 5. What this does NOT establish

**Not a rate.** One real defect, one subject, one template. `planted-defect-arm`'s rule holds:
this is an existence proof, and existence proofs do not estimate precision.

**Not a claim that the defect is severe.** It needs an explicit `ToolChoice(mode: nil)` to
observe. What it is unambiguously is an **inconsistency between two conformances the type
declares itself**, found without a mutant, in a subject the tool had never seen.

**Not a verdict on the catalogue.** 18 of 19 hand-checked refutations are still false laws, and
nothing here changes the standing advice to read `idempotence` refutations with suspicion.

**Not reported upstream.** Whether to file this with the MCP SDK maintainers is the
maintainer's call, not the tool's.

**The 2 `build-failed` and 1 trap are undiagnosed.** `UnitInterval.encode(to:)`,
`PKCE.makeChallenge(from:)` and `Heartbeat.rawValue(rawValue:)` — three rows this document
does not explain, recorded so the count is not read as clean.
