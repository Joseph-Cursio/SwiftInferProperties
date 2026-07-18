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

## Remaining candidates

`twoSum` argument ordering (numerics — commutativity), `gcd` on `Int.min`
(numerics — bounds), the other `PersistentSet` `union`/`intersection` fixes
(collections), BitSet/GRDB Codable round-trips. Plus a breadth **robustness sweep**
(run discover across the fetched libraries; success = no crashes / no default-tier
false-positive floods — extends the 11+ clean dogfoods).

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
