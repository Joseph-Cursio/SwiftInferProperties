# The blocker was not recursion — it was `Swift.String`

> **Status:** `measured` · **As of:** 2026-08-24

**The premise this was built on is FALSE, and measuring it first is the only reason that was
found.** `refutation-rate-second-subject.md` §7 named *recursive generator derivation for custom
field types* as the single blocker behind all 28 of `MacPaw/OpenAI`'s `codable-round-trip` rows.
Recursion was already built and already working. The binding constraint was **leaf
recognition**: `RawType(typeName:)` matches exactly, nothing anywhere in the kit strips a module
qualifier, and generated code spells every type `Swift.String`.

**A/B on the subject: 0 → 15 of 55 rows execute.** The largest movement any fix in this line of
work has produced.

---

## 1. The mechanism

`RawType(typeName:)` compares against `allCases.rawValue` — `"String"`, `"Int"`, `"Bool"`. A grep
across `SwiftPropertyLaws` finds **no** module-prefix handling anywhere. So:

- `Swift.String` resolves to no generator.
- A member typed with it makes its enclosing type underivable.
- The row reports `unsupported-carrier` — a label claiming *the carrier is exotic*, about a
  `String`.

`Components.Schemas.Metadata` is the clean exhibit: one struct, one non-failable initializer,
one parameter of type `[String: Swift.String]`. No custom types anywhere in its tree. It
declined.

---

## 2. Why the wrong premise was believable

The first row inspected was `Components.Schemas.Filters`, whose members *are* custom types
(`ComparisonFilter?`, `CompoundFilter?`), one of which bottoms out in
`OpenAPIRuntime.CopyOnWriteBox<…>` — a generic from a dependency. That is a real unresolvable
leaf, and it is genuinely a recursion story. **It was also the atypical row.**

Generalising from it would have produced a build aimed at 12 rows while ignoring the 16 that
needed nothing but a correct spelling. The A/B is what separated them:

| arm | rows whose member tree fully resolves |
|---|---|
| `Swift.X` unrecognised (today) | **0 of 28** |
| `Swift.X` recognised | **16 of 28** |

---

## 3. What it is worth, in both directions

**On the subject — measured, not projected:**

| | before | after |
|---|---|---|
| rows executing (all templates) | **0 of 55** | **15 of 55** |
| `codable-round-trip` reaching a verdict | 0 | **15 of 28** |
| refutations | 0 | **9** |
| `bothPass` | 0 | **5** |
| traps | 0 | 1 |

**Across the 20 resolving manifest corpora, the population is ONE occurrence.**
`scripts/measurement.py` supplied corpus resolution and the denominator; the single hit is in
`swift-foundation`. **Quote the 1 beside the 16, always.** A reader given only the 16 is being
handed a number about generated code as though it were a number about Swift.

**The manifest cannot answer how common this is**, because it contains no generated-code
subject. Twenty hand-written libraries measure ~0 by construction, and `swift-openapi-generator`
output is a large class of real Swift the toolchain will keep meeting. This is the fifth payment
of *a census is only as wide as its corpus list* — recorded, not resolved.

**Why it is a correctness fix rather than a threshold.** The standing rule is *raise thresholds,
don't pile on filters*, and the Daikon trap is about buying recall with precision. This buys
neither. `Swift.String` **is** `String`; treating it as unknown is wrong. No suggestion gets
weaker and nothing is admitted that was not already admissible under its own spelling.

---

## 4. The fix

`StdlibTypeSpelling.canonical`, applied at `IndexedTypeShape.toKitShape()` — the one seam every
scanned type spelling crosses on its way into the kit. It strips a **named** module prefix
(`Swift.`, `Foundation.`) and only when the remainder is a leaf the kit actually generates for.

**Not a last-component rule, and that is the whole of the safety argument.** Taking the last
dotted component would map `Components.Schemas.Response` → `Response` and `MyModule.String` →
`String`, inventing generators for types that have none. `StdlibTypeSpellingTests` asserts both
negatives, plus that a strippable module before an *unknown* leaf (`Swift.Duration`) is left
alone and that a three-component path is never collapsed.

All three positions are covered — stored members, initializer parameters and enum payloads.
Fixing only the arm that motivated the change is the mistake `EqualityBodyClassifier` already
made once.

### 4.1 MOVED UPSTREAM, same day — and the local copy is DELETED, not kept

The first version of this fix lived here, as `StdlibTypeSpelling` applied at `toKitShape()`, and
this section recorded the consequence as an open gap: *the kit is still blind, so
`PropertyLawDiscoveryTool` pointed at generated code has the same hole.* **The maintainer chose
upstream.**

**SwiftPropertyLaws [#15](https://github.com/Joseph-Cursio/SwiftPropertyLaws/pull/15), released
as `v4.2.0`.** Two seams there, because one does not cover the other:

- **`RawType(typeName:)`** accepts the `Swift.`-qualified spelling — what memberwise derivation
  and `RawRepresentable` enum derivation read.
- **`CompositeMemberParser`** covers the Foundation half by recursing on the unqualified name,
  the same idiom `knownTypeAlias` already used for `TimeInterval`.

The kit's version is **stricter than the local one was**, in the direction that matters: the
remainder resolves only against the known-leaf tables and **never against `resolve`**. Stripping
first and asking the whole-module resolver second would let a source saying `Swift.Foo` bind to a
user type called `Foo` — silently wrong rather than declined, the worst available outcome. A test
there pins that the resolver is never offered a stripped name.

**The local copy is deleted rather than kept as belt-and-braces.** Two implementations of one
rule drift, and PRD §11 says generator inference delegates to the kit. What remains here is
`QualifiedSpellingDerivationTests` — an assertion about the *behaviour* this package depends on,
including that a qualified **custom** type is still declined, which is the arm that would catch a
kit fix that made everything derive.

⚠ **The deletion was A/B'd, not assumed.** Same subject, same binary otherwise, local fix versus
kit fix: **0 of 55 rows differ at row level** — 40 pending / 9 `defaultFails` / 5 `bothPass` /
1 trap, both ways. The kit reproduces the local result exactly, which is the evidence that
removing the local copy costs nothing.

**Pins:** `Package.swift` and `VerifierWorkdir.swiftPropertyLawsRequirement` both move to
`4.2.0`, kept equal by `VerifierWorkdirKitPinTests`. The floor is a claim about what the
generated code needs, and what derivation needs changed.

---

## 5. The 9 refutations are one mechanism, and it is a FALSE-LAW mechanism

**Tally: 1 real of 28** (was 1 of 19). Every one of the 9 is the same shape.

All nine counterexamples have **both `value1` and `value2` set**. These are
`swift-openapi-generator` `anyOf` / `allOf` wrappers:

```swift
public init(value1: String? = nil, value2: Value2Payload? = nil)      // admits any combination
public func encode(to:) throws {
    try encoder.encodeFirstNonNilValueToSingleValueContainer([value1, value2])   // writes ONE
}
public init(from:) throws {
    // tries to decode BOTH from that one value; requires at least one to succeed
}
```

Verified in full on `ModelIdsShared`: encode writes `"L0eZAui"` (first non-nil); decode sets
`value1 = "L0eZAui"` and fails `value2`, yielding `value2 = nil`. The round trip drops a field,
and `Hashable` sees it.

**The `valueN` fields are alternative views of ONE JSON value and must be mutually consistent.
The memberwise initializer does not enforce that**, so the generator draws states the type's real
domain excludes — one counterexample even nests `ModelIdsShared(value1: nil, value2: nil)`, which
`verifyAtLeastOneSchemaIsNotNil` rejects on decode by design.

**New nameable false-law mechanism**, alongside *idempotence over a derivation rather than a
projection* and *takes-operand idempotence on accumulating operations*:

> **Round-trip over a type whose optional fields carry an undeclared mutual-consistency
> invariant.**

### 5.1 Why this is NOT the `ToolChoice` shape, though it looks like it

Both are "the encoder loses something `Equatable` can see". The difference decides the verdict:

- **`ToolChoice` is a contradiction inside the type's own stated semantics.** Its doc comment
  says an omitted `mode` *means* `.auto`; the encoder agrees and `Equatable` does not. Nothing
  outside the type is needed to see the inconsistency.
- **These over-quantify.** The type never claims `value1` and `value2` are independent. The law
  reaches outside the real domain because the invariant is undeclared, which is exactly the
  failure `refutation-hand-check.md` names for `idempotence`.

**Hand-check honesty:** the mechanism was traced in full on one of the nine and pattern-matched
on the other eight by their shared both-set counterexample signature and identical generated
shape. That is weaker than nine independent hand-checks and is stated as such.

**No filter proposed.** The standing rule is raise thresholds rather than pile on filters, and
this is generated code — the same pattern will appear in *every* `swift-openapi-generator`
client, which makes it a high-volume false-law source and therefore a **presentation** question
(attach the mechanism to the refutation) long before a suppression one.

---

## 6. The 5 passes, and what they are worth

`EnvPayload`, `ResponsePromptVariables`, `HeadersPayload`, `Metadata`,
`VectorStoreFileAttributes` all held at 1,000 default + 1,000 edge trials. Every one is a
**dictionary-wrapper** type — a single `[String: String]`-shaped member — so they are the
simplest possible round trip and their passing is unsurprising.

**They are not evidence the catalogue is sound.** They are evidence the pipeline now reaches
this subject at all, which it did not four hours ago.

---

## 7. What this does NOT establish

**Not a rate.** `template-refutation-rates.md`'s question is untouched: 9 more `codable-round-trip`
refutations, all false, all one mechanism, all from one generated codebase. Nine instances of one
pattern is not nine data points.

**Not a claim about `MacPaw/OpenAI`'s quality.** The refuting types are generator output; nothing
here is a defect in code anyone on that project wrote.

**Not a measurement of generated-code prevalence.** One subject.

**Not a resolution of the recursion question.** 12 of 28 rows are still blocked, and
`OpenAPIRuntime.OpenAPIObjectContainer` / `CopyOnWriteBox<…>` are genuine unresolvable leaves in
a dependency. §2's original story is true of those 12 — it was simply not true of the other 16.
