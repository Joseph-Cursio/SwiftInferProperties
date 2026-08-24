# Turning "1 real of 19" into a rate — NOT ACHIEVED, and the two subjects say why

> **Status:** `measured` · **As of:** 2026-08-24

**The question.** `criterion-a-quality-mcp.md` found the first refutation that was a **real
defect** (`ToolChoice`, `codable-round-trip`) against 18 hand-checked false ones (all
`idempotence`). One data point, and the first suggesting *which template refutes* carries
information. This is the attempt to make it a rate by running a second unmet subject.

**The answer: the rate was not obtained. Zero new refutations, on two subjects.** The tally
is unchanged at **1 real of 19**.

> ⚠ **SUPERSEDED IN PART, SAME DAY, by `module-qualified-leaf-spelling.md`.** §7 of this document
> named *recursive generator derivation* as the blocker. **That premise is false** — recursion
> already worked; the binding constraint was `RawType(typeName: "Swift.String")` returning nil.
> Fixing the spelling took `MacPaw/OpenAI` from **0 to 15 of 55** executing rows and produced
> **9 refutations**, so *zero refutations on two subjects* is no longer true of this subject.
> **The headline verdict survives**: all 9 are one mechanism and hand-check as FALSE laws, so the
> tally moves to **1 real of 28** and the rate question is still unanswered. Read §7 as the
> question that was asked, and the newer doc as the answer that corrected it. What the attempt produced instead is a shipped bug fix, a
correction to the subject-selection rule, and two decline causes named precisely.

**Nothing here weakens the MCP finding and nothing strengthens it.** No refutation fired
either way, so this is silence, not evidence.

---

## 1. What was measured

| | `swift-aws-lambda-events` | `MacPaw/OpenAI` |
|---|---|---|
| revision | `d18360e` | `a532be8` |
| in the manifest? | no | no |
| prior mentions across `docs/` + `fixtures/` | **0** | **0** |
| source files scanned | 26 | 147 |
| C / header files | **0** | **0** |
| target vs directory | `AWSLambdaEvents` / `Sources/AWSLambdaEvents` ✅ | `OpenAI` / `Sources/OpenAI` ✅ |
| their own suite, at that revision | **136 tests, 25 suites, green** | **187 XCTest + 25 swift-testing, green** |
| index rows | 15 | 55 |
| of which `codable-round-trip` | **5** | **28** |
| **rows executing, first run** | **1 of 15** | **0 of 55** |
| refutations | **0** | **0** |

Both were left clean; the only artifact is a gitignored `.swiftinfer/`.

**Both fail §6.1's short-chain pre-check**, and the pre-check cost one run each, exactly as
`toolchain-exit-criteria.md` §6.1 says it should. MCP read **10 of 67** on its first run. These
read 1 of 15 and 0 of 55. **The rule works; the subjects did not.**

---

## 2. The selection rule was wrong, and the correction is measurable

§6.1 selects for *unmet AND short-chain*: public value types, clear initializers, no C interop.
Both subjects satisfy every clause of that and still executed almost nothing. The missing
clause is about the **template**, not the subject:

> **`codable-round-trip` needs `Codable` ∩ `Equatable` on the SAME type.** The law is
> `decode(encode(x)) == x`; `Codable` supplies the round trip and `Equatable` supplies the
> `==`. A type with only one of them yields no statable law.

Measured, on the subject that made it obvious:

| `lottie-ios` @ `3a7fb59` | |
|---|---|
| types conforming to `Codable` | 32 |
| types conforming to `Equatable`/`Hashable` | 48 |
| **types conforming to both** | **5** |
| `codable-round-trip` rows emitted | **1** |

Counting the two conformances separately predicted a rich subject and the intersection
predicted a poor one. **The intersection was right.** Lottie's model layer is 23 Codable files
of JSON animation models, and they are classes without `Equatable` — so the law cannot even be
written, let alone refuted.

Screened across every unmet local subject on this machine, the intersection is thin: the
largest is 14 (`swift-aws-lambda-events`), and everything above it in the raw Codable count is
either in the manifest, previously disqualified, or behind C interop. **`MacPaw/OpenAI` was
cloned specifically because it scores 411** — and it is the only local subject that does.

### 2.1 A second precondition, learned from the first subject

Derivation needs a **non-failable, non-throwing initializer**. `AWSRegion` declares only
`init?(rawValue:)` — failable, though it can never actually return `nil` — and that alone
blocks the generator. Screening on conformances cannot see this; screening on
*conformances + a derivable init* can, and that is what selected OpenAI.

**It was not sufficient either.** See §4.

---

## 3. A real bug, found and fixed: one `private` type suppressed 26 laws

On the first OpenAI run, **26 of the 28 `codable-round-trip` rows** declined as:

> `not-a-candidate: no test can name the subject: its enclosing type is `private` or
> `fileprivate``

**That claim is false for all 26.** `Components.Schemas.Filters` is a `public struct` inside
`public enum Schemas` inside `public enum Components`, with a `public init` and the
`public func encode(to:)` at exactly the indexed line. Nothing in the chain is `private`.

**Mechanism, confirmed end to end.** `withAccessRestrictionCaveats` joined scanned restrictions
to suggestions on `SymbolJoinKey` — `(file basename, bare symbol)` — with *first wins*:

- `Components.swift` declares **72** `func encode(`.
- Exactly **one** is genuinely unreachable: line **563**, inside `private struct Storage`
  (lines 523–603).
- All 72 share the key `Components.swift::encode`. `Dictionary(_:uniquingKeysWith:)` bound it
  to the restricted one.
- `blocksEveryTest` then attached `subjectNotVisibleToTests`, and `verify` filed each row
  `not-a-candidate`.

**A law suppressed by a true statement about a different function.** The old code's own comment
justified first-wins with *"two remedies for one key differ only in wording — picking either
beats trapping on a duplicate"*. **That premise is what failed**: the colliding remedies did
not differ in wording, they differed in **truth**, and picking either was picking wrong for 71
of the 72.

`SymbolJoinKey`'s doc calls the collision *"a known, currently-empty hazard, not an
oversight"*. That emptiness was measured on **seeds, across FILES** (145 seeds, 134 keys, no
key spanning two files). This collision is **within one file**, which that measurement could
not have seen. The hazard was not empty; it was unmeasured in the direction that fired.

**Fixed** — the join is now per-declaration (`file#line`), with the lossy name key kept only
for rows carrying no resolvable coordinate (a lifted row locates at `<test-body>:0`).
`AccessCaveatJoinCollisionTests` pins all four arms, and **the two negative arms were watched
failing on the old code** before the fix went in. The negative arm is the load-bearing one: a
join that merely suppressed nothing would pass a positive-only test.

### 3.1 What the fix bought: 26 rows moved, 0 laws gained

Re-run after the fix, same binary otherwise: all 26 rows moved from `not-a-candidate` to
`unsupported-carrier`. **Executions went 0 → 0.**

This is the standing rule landing again — *state a gain as ROWS MOVED, never LAWS GAINED*,
with a measured ratio of ~5:1 against. Here it is ∞:1. **The fix is still right**: a false
suppression is a soundness defect regardless of whether removing it reveals a runnable law,
and it would have silently mis-explained every future run on any codebase with a large
generated file. But it bought no laws, and recording it as a win would be the mistake the rule
exists to prevent.

---

## 4. The blockers, named

Every decline was traced to a cause rather than left at its bucket label. **`unsupported-carrier`
was the label on rows with four different causes, none of them "the carrier is exotic"** —
the fourth instance of *a decline bucket's NAME is not its cause*.

`swift-aws-lambda-events`, all 5 `codable-round-trip` rows:

| carrier | real cause |
|---|---|
| `AWSRegion` | only a **failable** initializer — derivation requires non-failable, non-throwing |
| `CognitoEvent` | enum case `preSignUp` has an associated value (`Parameters`) resolving to no generator |
| `CognitoEventResponse` | **not `Equatable`** — the law cannot be stated |
| `HTTPRequest.Method` | type belongs to a **dependency**, extended here with `@retroactive Codable` |
| `HTTPResponse.Status` | same |

The last two are a shape worth naming: **retroactive conformance is discoverable but
ungeneratable.** The `encode(to:)` is in this package, so discovery sees it; the type is not,
so no indexed `TypeShape` exists to build a generator from. Population unmeasured.

`MacPaw/OpenAI`, after the fix: all 28 blocked at generator derivation. `Filters` holds
`value1: ComparisonFilter?` and `value2: CompoundFilter?` — **custom types whose own
generators are not derived recursively.**

⚠ **One hypothesis was checked and refuted rather than reported.** The obvious explanation was
that the index keys `TypeShape` on the **bare** name (`Filters`) while verify asks for the
qualified one (`Components.Schemas.Filters`) — the shape of a real bug elsewhere in this
project. It is wrong: the index holds **1,221** type shapes and `Components.Schemas.Filters` is
present under exactly the qualified key verify asks with. Recorded because a plausible
mechanism that survives to publication is how five instrument defects got into one subject.

---

## 5. One hand-check, and it came out negative

`HTTPResponse.Status` encodes **only** `self.code` and decodes via `init(code:)`, dropping
`reasonPhrase`. That is the `ToolChoice` shape — an encoder discarding a field the type
carries — and it was checked as a candidate defect.

**It is not one.** `swift-http-types` defines `==` as `lhs.code == rhs.code` and hashes only
`code`. The dropped field is outside the equivalence the law quantifies over, so
`decode(encode(x)) == x` holds. **A round trip that loses information is not a round-trip
violation unless `Equatable` can see the loss** — which is the precise inverse of the MCP
finding, where `Equatable` distinguished two values the encoder conflated.

The two cases together sharpen the mechanism: **`codable-round-trip` refutes exactly when
`Codable` and `Equatable` disagree about identity.** It says nothing about whether either is
independently right.

---

## 6. What this does NOT establish

**Not evidence about the catalogue.** Zero refutations fired, so nothing here bears on whether
`codable-round-trip` is more trustworthy than `idempotence`. The tally is **1 real of 19**,
exactly where it started.

**Not a verdict on either subject's quality.** Both suites are green and neither was shown to
contain a defect. That is not a finding about them — no law ran.

**Not a claim that the subjects were badly chosen.** They satisfy every published criterion.
§2's intersection rule is the correction, and it was derived *from* this run.

**Not a measurement of the retroactive-conformance population.** Two rows on one subject.

---

## 7. What would move this

1. **A subject whose Codable ∩ Equatable types have generator-derivable fields** — i.e.
   primitives and stdlib types, not nested custom types. Both subjects here failed on the
   second clause after passing the first, so the screen needs a third: *field types resolve*.
2. ~~**Recursive generator derivation for custom field types.** This is the single blocker
   behind all 28 OpenAI rows.~~ **WRONG, and corrected the same day** — see
   `module-qualified-leaf-spelling.md`. Recursion was already built and working. The blocker was
   **leaf recognition**: a member spelled `Swift.String` resolves to no generator, and generated
   code spells every type that way. A/B: **0 of 28 → 16 of 28** member trees resolve. The
   recursion story is true of the **12** rows that remain, whose leaves are genuinely
   unresolvable types in a dependency (`OpenAPIRuntime.OpenAPIObjectContainer`,
   `CopyOnWriteBox<…>`) — it was simply not true of the other 16. **Generalising from the first
   row inspected (`Filters`, whose members really are custom types) would have aimed a build at
   12 rows and missed the 16 that needed only a correct spelling.**
3. **Do not re-pick these three.** `lottie-ios`, `swift-aws-lambda-events` and `MacPaw/OpenAI`
   are recorded here precisely so the *zero mentions across `docs/`* check disqualifies them
   next time, the way `swift-system` and `mcp-swift-sdk` are — neither is in the manifest
   either.
