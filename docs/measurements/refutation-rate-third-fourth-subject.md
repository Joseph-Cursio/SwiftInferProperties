# The rate, attempt two — a second real defect, and a THIRD verdict category

> **Status:** `measured` · **As of:** 2026-08-25

**Still not a rate. But the template comparison is now corroborated across independent
codebases rather than resting on one subject**, and `codable-round-trip` has found a second
real, test-missed defect.

Two more unmet subjects, both selected by the **amended** §6.1 — including its new clauses that
a template's population is `Codable` ∩ `Equatable` on one type and that the conformance must be
**hand-written**, since a synthesized one is symmetric by construction and cannot refute.

---

## 1. What was measured

| | `jwt-kit` | `swift-openapi-runtime` |
|---|---|---|
| revision | `8189d7c` | `643f3d6` |
| in the manifest / prior mentions | no / **0** | no / **0** |
| source files · C files | 74 · **0** | 71 · **0** |
| `Codable` ∩ `Equatable`, all hand-written | **6** | **5** |
| their own suite | **124 tests, green** | **229 tests, green** |
| index rows | 35 | 51 |
| **rows reaching a verdict** | **17 of 35** | **7 of 51** |
| `codable-round-trip` rows | 12 → 6 pass, **1 refutation**, 5 pending | 5 → 2 pass, **0 refutations**, 3 pending |

**`jwt-kit` is the best pre-check reading yet — 17 of 35, against `mcp-swift-sdk`'s 10 of 67.**
The amended §6.1 selected it, and this time the pre-check was run *before* committing rather
than discovered afterwards.

Both subjects left clean; the only artifact is a gitignored `.swiftinfer/`.

---

## 2. The refutation, hand-checked — and it is neither of the existing categories

`AppleIdentityToken.UserDetectionStatus` (`Sources/JWTKit/Vendor/AppleIdentityToken.swift:97`):

```swift
public struct UserDetectionStatus: OptionSet, Codable, Sendable {
    private enum Status: Int, Codable { case unsupported, unknown, likelyReal }
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }        // accepts ANY Int
    public func encode(to encoder: Encoder) throws {
        switch self {
        case .unsupported: …; case .unknown: …; case .likelyReal: …
        default: throw EncodingError.invalidValue(self, context)   // THROWS
        }
    }
}
```

**The tool's counterexample over-quantifies.** It drew
`UserDetectionStatus(rawValue: 6348581922313170543)` — a random `Int` nobody constructs. Read
only that far, this is the same over-quantification as the nine `anyOf` wrappers.

**But the defect it points at is real, and reachable three ways through the type's OWN declared
API.** Verified by executing against the package as shipped:

```
.unknown.union(.likelyReal)   rawValue=3  -> THREW: EncodingError
[.unknown, .likelyReal]       rawValue=3  -> THREW: EncodingError
insert(.likelyReal)           rawValue=3  -> THREW: EncodingError
```

`OptionSet` is a **declared conformance**, and `union` / array-literal init / `insert` are its
defining operations. The type promises they produce valid values; its own encoder rejects them.
**That is a contradiction between two conformances the type declares itself** — the `ToolChoice`
shape, not the undeclared-invariant shape.

**Their tests miss it.** `UserDetectionStatus` appears in **zero** test files by name; the two
sites that use it both pass `.likelyReal`. The defect ships green under 124 tests.

### 2.1 The stated design goal is not achieved either

The type's own comment reads *"With slight modification to make adding new cases
non-breaking."* That is why it is an `OptionSet` rather than an `enum`. **It does not achieve
that goal**: `init(from:)` decodes the private three-case `Status: Int`, so a fourth status
value throws on decode. The `OptionSet` modelling buys the non-breaking property for the *type*
and for neither half of its `Codable`.

So the modelling admits meaningless combinations that break the encoder, **and** does not
deliver the openness it was chosen for.

---

## 3. A third verdict category, and why forcing a binary would lose information

| category | example | the law | the defect |
|---|---|---|---|
| **Real** | `ToolChoice` (`mcp-swift-sdk`) | quantified over the real domain | real — contradiction inside the type's own stated semantics |
| **False** | 9 `anyOf` wrappers (`MacPaw/OpenAI`) | over-quantified | none — the invariant is undeclared but genuine |
| **NEW: over-quantified law, real defect** | `UserDetectionStatus` (`jwt-kit`) | over-quantified — a random `Int` | **real** — reachable by the type's own declared `OptionSet` API |

**The counterexample's quality and the finding's reality are independent axes**, and the first
28 hand-checks never separated them because every real one happened to have a meaningful
counterexample and every false one did not. Recording this as simply *real* would overstate the
tool; recording it as *false* would discard a reproduced, test-missed defect.

**What it costs the reader:** a refutation in this category needs a human to ask *is there a
meaningful value nearby* — which is exactly the adjudication `criterion-a-quality-mcp.md` said a
found defect moves onto the reader. Here the answer was yes, and it took one probe.

---

## 4. The tally, and what it does and does not support

**Hand-checked refutations: 29. Real defects: 2** — both `codable-round-trip`, on two
independent unmet subjects, both missed by the subject's own suite.

| template | hand-checked | real | subjects |
|---|---|---|---|
| `idempotence` (+ operand forms) | 18 | **0** | home, swift-system |
| `codable-round-trip` | 11 | **2** | home 0/10 · mcp **1**/4 · OpenAI 0/15 (9 false, one mechanism) · jwt-kit **1**/7 · openapi-runtime 0/2 |
| `predicate` / totality | 0 refutations of 102 | — | three corpora |

**What this supports.** The 2026-08-23 hypothesis — *`idempotence` is a conjecture read off a
shape, `codable-round-trip` is a law the code owes* — is no longer resting on one data point.
Two real defects, two independent codebases, both found where two declared conformances
disagree. `idempotence` remains 0 for 18.

**What it does NOT support.** Not a rate, and the arithmetic says why: the 11
`codable-round-trip` hand-checks include nine instances of **one mechanism from one generated
codebase**, so the denominator is not eleven independent trials. Deduplicated by mechanism it is
closer to **2 real of 4 distinct mechanisms**, on a sample far too small to quote as a
precision.

**Not a claim about either subject's quality.** `swift-openapi-runtime` produced no refutation
at all, and that is a fact about a 7-verdict sample, not a bill of health.

---

## 5. What would move it, and what would refute this

- **More hand-written `Codable` ∩ `Equatable` subjects.** The local pool is now exhausted: after
  excluding the manifest and every subject recorded across `docs/`, the best remaining unmet
  candidates carry 3–6 such types each. Reaching a denominator worth calling a rate means
  cloning subjects deliberately, not screening what is already on disk.
- **A `codable-round-trip` refutation that is false for a NEW reason** would weaken the
  hypothesis more than another real one strengthens it.
- **An `idempotence` refutation that is real** would end the comparison outright. 18 for 18 is a
  strong prior and not a proof.

**Spent subjects, recorded so the *zero mentions across `docs/`* check disqualifies them:**
`jwt-kit` @ `8189d7c`, `swift-openapi-runtime` @ `643f3d6`. Neither is in the manifest, for the
same reason `swift-system` and `mcp-swift-sdk` are not — adding them would move every census's
universe.
