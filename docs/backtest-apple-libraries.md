# Historical backtest — Apple/Swift libraries (2026-07-18)

A validation method distinct from the planted-bug road-tests: point the toolchain
at **real, already-fixed bugs** in mature Swift libraries and ask whether it would
have caught each one *before* the fix. Real bugs beat planted ones — nobody can
argue the benchmark was tuned to the tool. This records the method, the honest
yield (mostly boundary-mapping misses + occasional clean hits), and the first
non-synthetic hit.

## Method

For a property-shaped fixed bug:
1. **Mine** git history for fix commits whose subject/diff is property-shaped —
   keyword-filter `fix|incorrect|wrong` × `round-trip|encode|decode|codable|
   comparator|sort|equatable|hashable|commutative|associative|idempotent|union|
   intersect|symmetric|subtract`. A strong signal: the fix touched a
   `PropertyTests`/added a general (not example) regression test.
2. **Check out the pre-fix parent** (`<fix>^`, detached).
3. **Discover** (AST-only, always works on old code): does the tool *surface* the
   property whose violation is the bug?
4. **Verify** (the strong claim): does measured execution *disprove* it
   (`measured-defaultFails` = a real counterexample)?

**Old-build friction + workaround.** Discover works on any old commit; verify needs
the pre-fix code to compile under the current toolchain, which old commits/deps may
not, and heavy types (a HAMT set) are impractical to build. Workaround (same
technique as the road-test corpora): **extract the pre-fix buggy logic into a
minimal, verify-ready fixture** with a generatable carrier (a `CaseIterable` enum
is the clean one), then discover + verify that.

**Scope is narrow — and that is the point.** Most library fixes (concurrency,
memory, API, index arithmetic) are outside the value-semantic / interaction scope.
The backtest's value is **mapping where the tool would have helped**; the *misses*
bound the claim as honestly as the hits (the Appendix C posture).

## Case 1 — swift-numerics `canonicalizedTransform` (`06341f3`): MISS

`canonicalizedTransform` on a negative-real quaternion flipped only the real sign
`(-r, x, y, z)` instead of negating the whole quaternion `-(r,x,y,z)`. Since `q` and
`-q` are the same R³ rotation, the correct canonical form is `-q`.

The tool does not catch it, for two independent reasons — both informative:
- **Recall:** `canonicalizedTransform`'s return type is written `Self`, and the
  idempotence shape-gate compares `containingType ("Quaternion") == returnType
  ("Self")` textually → no match (the documented `Self`-return recall gap).
- **Property mismatch (deeper):** the only law the tool would attach is
  **idempotence**, which the *buggy* code still satisfies (`f(f(x)) == f(x)` — once
  the real part is positive it is returned unchanged). The bug lives in a
  **rotation-equivalence domain invariant** the tool doesn't model.

The tool *did* correctly surface `conjugate()` as an **involution** — a real law,
just unrelated to this bug. Lesson: "the fix touched a property test" ≠ "the bug is
a generic-algebraic-law violation."

## Case 2 — swift-collections `symmetricDifference` (`876177db`): HIT

The pre-fix implementation was `self.subtracting(self.intersection(other))` —
i.e. `self \ other`, which is **not commutative** (`{1,2,3} △ {3,4,5}` gave `{1,2}`
one way and `{4,5}` the other; correct is `{1,2,4,5}` both ways). That *is* a law
the tool surfaces and verifies — but it was missed only because
`symmetricDifference` and `intersection` weren't curated commutativity verbs
(`curatedVerbs` carried the stale stem `intersect`, which never matched the real
method `intersection`, plus `union`). `symmetricDifference` also got a
`dual-style-consistency` pick, but `formSymmetricDifference` delegates to the buggy
non-mutating one, so both were wrong-in-agreement — no catch there either.

**Fix shipped** (`2463ee2`): `curatedVerbs` gained `intersection` +
`symmetricDifference` (both genuinely commutative; the B29 order-sensitive-carrier
veto still guards `OrderedSet`/`Array`).

**Loop closed on the pre-fix code:**
- **discover** on the pre-fix `PersistentSet` now surfaces **commutativity at Likely
  70** on `symmetricDifference` (and `intersection`, `union`).
- **verify** on a faithful `TinySet` reproduction (subsets of `{a,b}` with the exact
  `self \ other` formula) reports **`measured-defaultFails`, counterexample
  `(justA, justB)`**.

So the tool now catches the real 2020 swift-collections bug before its fix — the
first non-synthetic "caught a real library bug" demonstration.

## Case 3 — swift-numerics `Augmented.sum` / twoSum (`f6e5563`): MISS (shape boundary)

`Fix argument ordering in twoSum` — the pre-fix error term in the 2Sum
error-free-transformation was computed against the wrong operand (`x = head - a`
instead of `ɑ = head - b`). The bug is commutativity-flavored, but the tool
surfaces **nothing** on it: `Augmented.sum(_ a: T, _ b: T) -> (head: T, tail: T)`
returns a **tuple** (the exact-sum pair), and the algebraic templates require a
single-value `(T,T)->T`. **New boundary:** augmented / error-free-transformation
functions (`twoSum`/`twoProd` returning `(value, error)`) aren't reachable —
extending to them needs tuple-return recognition + a tuple-equality property, a
niche numerical-computing pattern, low priority.

**Bonus — precision holds at scale:** RealModule surfaces **2244** picks with
`--include-possible` and **every one is Possible-tier** (0 Strong, 0 Likely) — no
default-tier flood on a 2000+-pick module.

## Case 4 — swift-numerics `gcd` base case (`7f2d022`): MISS on the bug, but exposed + closed a recall gap

The specific `gcd` fix was a missing `if x == 0 { return y }` base case. An
exhaustive scan of the pre-fix `gcd` over `0...60 × 0...60` found **0 commutativity
violations and 0 wrong-value results** — the buggy `gcd` is still commutative and
still returns the correct value on that range (the base case only affected an
edge/termination path, not the algebraic law), so both discover and verify are a
clean **MISS**. The bug is a termination/edge invariant, not a law violation — the
same shape-of-boundary lesson as Case 1's rotation-equivalence.

**But the backtest paid off indirectly.** Setting up the `gcd`/`lcm`/`min`/`max`
recall fixture exposed a real asymmetry: those verbs — plus `join`/`meet` — are
commutative AND associative by definition, and surfaced **associativity at Likely
70** but **commutativity only at Possible 30** (shape +30, name +0).
`CommutativityTemplate.nameSignal` read `curatedVerbs` and the project vocabulary
but not `AssociativityTemplate.commutativeAssociativeVerbs`, the exact set already
gating the associativity name signal. **Fix shipped** (`b940bec`): nameSignal now
emits +40 for those verbs, so commutativity reaches Likely 70 to match — the same
safe recall pattern as Case 2's `symmetricDifference`. Not set-combination verbs, so
the B29 order-sensitive-carrier veto is untouched; the deliberate non-commutative
`leftBiased` FP (not a semilattice verb) stays Likely 45 for verify to disprove.
Measured-safe: the survey corpus's `join`/`meet` commutativity picks bump 45→85
(still surfaced), pick count unchanged, so the measured record count holds at 19.

Lesson: a backtest's value is not only the hit/miss on its named bug — reproducing
the fixture is itself a fuzz of the tool's recall surface.

## Case 5 — swift-algorithms `stablePartition(subrange:by:)` (`0dba0e5`): MISS (word-sense mismatch)

`stablePartition(subrange:by:)` used the whole-collection `count` instead of
`self[subrange].count`, so it partitioned the wrong range. The bug is squarely
**partition-property-shaped** — the fixing test asserts exactly the two-sided law
(`b[range.lowerBound..<p]` are the elements failing the predicate, `b[p..<upper]`
the ones satisfying it). And the tool *has* a `partition` template. Yet it surfaces
**0 suggestions** on either `stablePartition(by:)` or `stablePartition(subrange:by:)`.

The reason is a **word-sense mismatch**, not a recall or shape gap: the tool's
`partition` template models a **set-tiling** — a `(Int) -> Range<Int>` range tiler or
a `(C, Int) -> C` slice tiler whose *parts reassemble a whole* (paging / chunking).
swift-algorithms' `stablePartition` is the other sense of the word — an **in-place
reorder-by-predicate** (`mutating (by: (Element) -> Bool) -> Index`) that returns the
pivot separating the two groups. Same English word, disjoint law:

- *tiling* partition owes **"the parts tile the whole exactly"** (the template's law);
- *reorder* partition owes **"everything before the pivot fails the predicate,
  everything at/after it satisfies it, and the result is a permutation of the input"**
  (stable adds: relative order preserved within each group).

The `0dba0e5` bug violates the *reorder* law (on the subrange), which the tool does
not model — so it is neither surfaced nor verified.

**This was a concrete candidate template, not just a boundary — and it is now BUILT**
(`2196a3c`). `ReorderPartitionTemplate` recognizes the mutating-predicate-returns-index
shape (name-gated on "partition" plus mutating + one `-> Bool` predicate + a non-Bool
pivot return) and states the law directly: the two-sided predicate split around the
pivot, the **permutation** invariant (the load-bearing one), stability *only* when the
name says `stable`, and — for a subrange variant — a fence caveat that names the exact
`0dba0e5` failure mode ("splitting over the whole collection's count instead of the
subrange's"). It fires at **Likely 70** on the real swift-algorithms `Partition.swift`
(both `partition` and `stablePartition`, whole and subrange) **including the pre-fix
`0dba0e5^` source** — so discover now surfaces the property whose violation *is* the
bug. **The measured-verify stub is now built too** (`ae52b22`):
`ReorderPartitionStubEmitter` drives a mutating `partition(by:)` /
`stablePartition(subrange:by:)` over deterministically generated `[Int]` arrays and
asserts the split + permutation (+ the subrange fence), emitting the standard `VERIFY_*`
contract; the `reorder-partition-corpus` proves the split end-to-end — a correct stable /
non-stable / subrange partition → **bothPass**; an element-dropping partition and a
whole-array-reordering subrange partition (the `0dba0e5` shape) → **defaultFails** — so the
template is no longer discover-only. Unlike Case 3
(tuple-return), the missing piece here was a *law the tool could state*, not a signature
the templates couldn't parse — which is why this one was worth building rather than
recording as a boundary.

## Case 6 — swift-collections `BitArray.toggleAll()` (`e01391e5`): MISS on the bug, but exposed a tool-side FALSE POSITIVE

`e01391e5` fixed a logic error in `BitArray.toggleAll(in range:)` — an empty
range still ran the word-update and corrupted a bit (`guard !range.isEmpty else
{ return }`). Like the gcd base case (Case 4), the bug is an **empty-input edge
invariant** in the *ranged* overload, not a violation of any law on the whole
collection, so it is a MISS — the whole `toggleAll()` is correct in both
versions.

**But discover on the pre-fix file exposed a tool-side default-tier FALSE
POSITIVE.** The whole `toggleAll()` surfaces at **lifted-idempotence Likely 45**
— wrong: toggling all bits twice returns the original (`f(f(x)) == x`, an
**involution**), not `f(f(x)) == f(x)`. The bare `toggle` was already curated in
`MutatorBlockedFromIdempotence`, but `isBlocked` matches curated names *exactly*,
so the `toggleAll` compound slipped through — the identical exact-vs-compound gap
the swift-nio `pop` → swift-argument-parser `popNext*` prefix fix closed.

**Fix shipped** (`582b6fc`): a new `involutionPrefixes = {toggle, negate, invert,
complement}` matched by prefix. "Toggle / negate / invert / complement X" is a
self-inverse for every X, so `toggleAll` / `invertColors` / `negatePolarity` /
`complementAll` are all blocked from lifted-idempotence; additive, so the bare
verbs stay curated and the over-block guard (`convert` ≠ `invert`, `negotiate` ≠
`negate`) holds. This is the **fifth** backtest to pay off through the
*reproduction* rather than the named bug (cf. Case 2 symmetricDifference recall,
Case 4 gcd/semilattice recall, Case 5 reorder-partition template) — the honest
pattern here is that mining fixtures from real fixed bugs is as much a fuzz of
the tool's own precision surface as a test of its bug-catching.

## Case 7 — swift-foundation `Data` Base64 (`2d2e249`): MISS, and it exposed a round-trip recall gap

`2d2e249` fixed a capacity over-allocation in `encodeComputeCapacity` — with a
line-break option (`.lineLength64Characters`), a last row that exactly filled the
line still reserved a separator, so `base64EncodedString` and `base64EncodedData`
disagreed at lengths 46–48. The bug is a MISS on two grounds: it is **gated by a
non-default option** (the tool tests the default-argument round-trip), and it is a
**cross-method consistency** bug (string-form vs data-form agree) that no template
states.

**But probing the Base64 round-trip exposed a recall gap in the round-trip
pairing.** The canonical property here is `Data(base64Encoded:
data.base64EncodedString()) == data` — a textbook codec round-trip on named
methods. The tool surfaces **nothing** on it, and isolation shows why it is
neither the `init?` nor the `Optional`:

| Encode | Decode | Surfaced? |
|---|---|---|
| `func base64EncodedString() -> String` (instance) | `init?(base64Encoded: String)` | ✗ |
| `func encodeA() -> String` (instance) | `static func decodeA(String) -> Blob` | ✗ |
| `func encodeB() -> String` (instance) | `static func decodeB(String) -> Blob?` | ✗ |
| `func toHexString() -> String` (instance) | `static func fromHexString(String) -> Blob` | ✗ |
| `static func encode(Blob) -> String` | `static func decode(String) -> Blob` | ✓ **Strong 75** |

The discriminator is the **instance-method encode**: `FunctionPairing` pairs on
`parameters.first` (an *explicit* parameter), so a free/static `encode(Blob) ->
String` pairs fine, but an instance `func base64EncodedString() -> String` — whose
domain is the implicit `self` (`containingTypeName`), not a parameter — is
invisible to the pairing. This is the *most common* codec shape in real Swift
(`base64EncodedString` / `init?(base64Encoded:)`, `toHexString` / `init(hex:)`,
`description` / `init?(_:)`, `rawValue` / `init?(rawValue:)`), and it is entirely
unsurfaced.

**Fix shipped** (`eb18730`): a shared `FunctionPairing.transformationDomain(_:)`
canonicalizes a 0-param non-static instance method `func f() -> B` on `A` as the
transformation `A -> B` (domain = the receiver), so it pairs with a free/static
`decode(B) -> A`; `RoundTripTemplate`'s explainability uses the same helper so the
domain renders as the receiver (`Blob -> String`, not `? -> String`). Now
`func encode() -> String` (instance) + `static func decode(String) -> Blob` earns
**Strong 75**. Precision held: a 0-param *static*/free function has no receiver, so
it stays unpairable (a `make() -> Blob` factory is not an encode); the default tier
is still name-gated (curated `encode`/`decode` vocabulary), so non-codec
instance-method pairs stay at hidden Possible; and the frozen cycle27-surface index
gains **zero** new pairs (53/53 stays valid).

**Part 2 shipped** (`4cdd91e`): the failable-`init?` decode now surfaces too.
`InitializerDecodeSynthesizer` turns each single-parameter struct initializer
(already captured on `TypeDecl.initializers`) into a synthetic `paramType -> Self`
decode summary — named after the init's argument label, marked
`FunctionSummary.isInitializer`, and merged **only** into the round-trip pairing
input, so no other template sees it. `RoundTripTemplate` gains a label-stem name
signal gated to `isInitializer` (the init label being a case-insensitive substring
of the encode's name — `base64EncodedString` ⊃ `base64Encoded`, `toHexString` ⊃
`hex` — is +40), so a genuine codec reaches **Strong 75** while an unrelated label
stays hidden Possible; a caveat discloses the directional / failable law
(`Type(label: x.encode()) == x`; for `init?`, `decode(encode(x)) == .some(x)`).
So `func base64EncodedString()` / `init?(base64Encoded:)` — the literal Base64
shape — now surfaces at Strong. Contained + safe (the flag defaults false, set only
on synthetics; zero drift on the frozen cycle27-surface corpus). **The
measured-verify half is also built** (`7098ee9`): `InitDecodeStubEmitter` drives
the directional law over candidate values — for a failable `init?`,
`Type(label: x.encode())` must succeed and equal `x`; a nil for a freshly-encoded
value or a mismatch is a failure — proven by the `init-decode-corpus` (a correct
hex codec → bothPass; a lossy encode and an over-strict failable init →
defaultFails, one per failure mode). So the codec-init round-trip is now
discovered, scored, AND measured end-to-end.

## Review round 2 — boundary confirmations (all principled MISSes)

A further sweep (swift-syntax, swift-foundation, SwiftyJSON, swift-nio, swift-async)
turned up no new actionable fix — every property-adjacent bug fell outside the
value-semantic / named-default-law scope, which is itself the honest finding:

- **swift-syntax `JSONMapValue.equals(to:)` (`869b4e41`)** — a `memcmp`
  nil-`baseAddress` crash on empty buffers on some platforms. A *platform/edge*
  fix, not a symmetry/reflexivity violation, so no equivalence law is broken. (It
  reinforced a candidate template — an **equivalence-relation** template for named
  `equals(to:)` / `isEqual(to:)` owing reflexivity + symmetry + transitivity, the
  `==` analog of the comparator's SWO — now **built** (`dd3d632`): it fires at
  Likely on a same-type equality method and correctly leaves the cross-type
  `isEqualSet(to: Range<Int>)` overload alone, since operands that cannot swap
  have no symmetry — the exact boundary this MISS drew.)
- **swift-foundation path canonicalisation (`654fa54` / `50d7537` / `08d50c1`)** —
  `canonicalize` *looks* idempotent-shaped, but the fixes are in **internal,
  Windows-specific** filesystem-representation helpers (`/`→`\`), not a public
  value-semantic method with a stateable idempotence law.
- **SwiftyJSON round-trips (`e79ac38` and kin)** — `JSON.rawString()` (instance
  encode, pairable after Case 7 Part 1) with `JSON(parseJSON:)` / `init(data:)`
  decode. The decode is an **`init?`** — the exact shape that motivated **Part 2**,
  now shipped (`4cdd91e`), so this instance-encode / init-decode round-trip is
  reachable.

Net: every actionable item the review surfaced is now shipped — Case 7 Part 2
(init-decode round-trips, discover + measured) and the **equivalence-relation
template** (`dd3d632`). The mature-library HIT vein (isolated formula bug on a
named default-law method, buildable) is largely mined; Case 2
(`symmetricDifference`) remains the one clean library-bug catch, while the
*reproduction* pathway kept paying off: **6 recall gaps + 1 precision gap fixed,
3 templates shipped** (reorder-partition, codec-init pairing, equivalence-relation),
each with a measured-verify path where one applies.

## Remaining candidates

Data-structure-internal bugs are out of reach by construction: the `PersistentSet`
`union`/`intersection`/`subtracting` fixes (`4a4c4a75` / `a887a77e`) are deep HAMT
node-builder / collision-recursion bugs (the fix adds `_fullInvariantCheck`), not
formula-level, so no faithful tiny fixture reproduces them; `OrderedSet.reverse()`
(`86ddbd97`) turned out to be a *performance* fix (the pre-fix path already called
the correct `_regenerateHashTable()`), i.e. no bug to catch. Still open:
BitSet/GRDB Codable round-trips. The breadth **robustness sweep** ran clean on 7
more libraries (Alamofire/RxSwift/GRDB/Kingfisher/SwiftyJSON/Moya/CombineExt — no
crashes, no default-tier FP floods; ~18 libraries validated total).

## Measured-safety

The `curatedVerbs` change is **corpus-orthogonal** — the measured corpora contain no
`intersection`/`symmetricDifference`, so it adds no picks there. Proven directly:
survey-corpus discovery is byte-identical with the change and with its parent
(19 picks / 3 commutativity both ways), and the B29 veto still suppresses
commutativity on the order-sensitive `OrderedSet` the corpus contains.

One incidental finding: the `AlgebraicSurveyCorpusMeasuredTests` baseline was **stale
before this work** — a later catalogue-template widening moved the survey from 17 to
19 measured records (13 bothPass + 6 defaultFails) without refreshing this slow,
fast-suite-skipped assertion, so it was already red. Refreshed to 19 as part of this
change (the established `1967d04` maintenance pattern), and re-confirmed green.
