# `ProtocolCoverageMap` — the coverage claims are false at law level, and the guard watches the wrong join

> **Status:** `measured` · **As of:** 2026-08-02


**Measured 2026-08-02.** SwiftInferProperties `main` @ `3056657`; SwiftPropertyLaws @ `4a2dada`
(44 `check…PropertyLaws` suites). Every number below is reproducible from those two SHAs with
the commands inline.

Found while pre-flighting `docs/kit-suite-backtest-plan.md` Arm 1 — the plan described the
kit's `SetAlgebra` coverage as four laws, which is `ProtocolCoverageMap`'s list, not the kit's
fifteen. Checking why the two disagreed turned up the drift below.

---

## 1. What the map claims, and on whose authority

`ProtocolCoverageMap.protocolCoverage` maps a textual conformance name to a
`Set<KnownProperty>` — the laws PropertyLawKit is asserted to already run for that
conformance. `assumedKitCoverage` uses it to **fully suppress** a template's suggestion, and
renders the reason:

> `Property already covered by conformance to 'X' — checked by PropertyLawKit's checkXPropertyLaws`

**The mechanism is deference, not rejection, and the original naming obscured that.** Until
2026-08-02 this was `protocolCoverageVeto` / `coverageVetoSignal`. But the six other `*Veto`
helpers in the templates all mean *this law is FALSE or unsafe here*, while this one means
*this law is TRUE and someone authoritative already runs it* — opposite claims under one word.
While that held, a suppressed-because-redundant row and a deleted-law-nobody-checks row were
indistinguishable in the vocabulary, which is a fair part of how §3 survived as long as it did:
`ProtocolCoverageAudit` had already written *"a veto that prevents double-reporting looks
exactly like nothing to report"* without anyone reading it as a naming problem. Renamed to
`assumedKitCoverage` — `assumed` being the status `ProtocolCoverageAudit` itself assigns, in
its `verified` / `assumed` / `contradicted` split.

The principle is sound: **known information removes the need to infer.** A conformance is a
fact about the code, and where the kit genuinely runs the law there is nothing left to infer.

**The problem is that the known information was not known.** Each entry is a claim about
*another repository's source*, restated by hand, in a package this one pins by version and
whose source nothing in the veto path reads. At law level it is false for **13 of 56
`(key, law)` pairs** — and the guard built for exactly this passes green through every one
(§5).

## 2. The sweep

**17 keys, not 13.** The type doc says "**13 keys**" and enumerates them; `Strideable`,
`IteratorProtocol`, `Sequence` and `LosslessStringConvertible` were added later (2026-07-30 /
2026-08-01) without updating the count. Minor, but it is the same class of drift as everything
below: a hand-maintained assertion about a set that moved.

Kit law counts are `grep -oE '"<Suite>\.[A-Za-z]+'` per `Sources/PropertyLawKit/Public/<Suite>Laws.swift`,
plus laws reached by delegation (`await check<Parent>PropertyLaws` inside the entrypoint).

| map key | kit laws (own + delegated) | map claims | **false** |
|---|---:|---:|---:|
| `Equatable` | 4 | 3 | 0 |
| `Comparable` | 8 (4 + `Equatable` 4) | 4 | 0 |
| `Hashable` | 7 (3 + `Equatable` 4) | 4 | 0 |
| `Strideable` | 12 (4 + `Comparable` 8) | 1 | 0 |
| `IteratorProtocol` | 2 | 1 | 0 |
| `Sequence` | 5 (3 + `IteratorProtocol` 2) | 1 | 0 |
| `LosslessStringConvertible` | 1 | 1 | 0 |
| `Codable` | 1 | 1 | 0 |
| `Semigroup` | 1 | 0 | 0 |
| `Monoid` | 3 (2 + `Semigroup` 1) | 1 | 0 |
| `CommutativeMonoid` | 4 (1 + `Monoid` 3) | 1 | 0 |
| `Group` | 5 (2 + `Monoid` 3) | 2 | 0 |
| `Semilattice` | 5 (1 + `CommutativeMonoid` 4) | 2 | 0 |
| **`AdditiveArithmetic`** | 5 | 6 | **3** |
| **`Numeric`** | 11 (6 + `AdditiveArithmetic` 5) | 10 | **3** |
| **`SignedNumeric`** | 15 (4 + `Numeric` 11) | 11 | **3** |
| **`SetAlgebra`** | 15 | 7 | **4** |
| | | **56** | **13** |

## 3. Defect A — `setUnionAssociative`: the kit has no such law, and a test pins the veto

```sh
cd ~/xcode_projects/SwiftPropertyLaws && grep -rn "unionAssociat" Sources/   # zero hits
```

`checkSetAlgebraPropertyLaws` runs fifteen laws — idempotence ×2, commutativity ×2, empty
identity, `symmetricDifference` ×4, distributivity ×2, absorption ×2, De Morgan ×2. **Union
associativity is not among them.** Yet:

- `ProtocolCoverageMap.swift:83` lists `.setUnionAssociative` under `SetAlgebra`
- `AssociativityTemplate.swift:317` emits it for `union` on a `SetAlgebra` carrier
- `AssociativityTemplate.swift:56` justifies the veto with the words *"kit `checkSetAlgebraPropertyLaws`"*
- `AssumedKitCoverageTests.swift:224` **asserts the suppression is correct behaviour**

So a true, refutable law is suppressed from `discover` on the grounds that another tool runs
it, that tool does not run it, and a green test ratifies the arrangement. This is
`ProtocolCoverageAudit`'s failure mode with the premise now measured rather than suspected —
*"a veto that prevents double-reporting looks exactly like nothing to report."*

**The generated suites inherit it.** `KitSuiteEmitter` emits a call to
`checkSetAlgebraPropertyLaws`, so union associativity is unchecked in `scaffold-kit-suites`
output too. Neither surface covers the law and both report as though something does.

**FIXED 2026-08-02 — the map entry was dropped, not the kit extended.** The fork was real
(add `unionAssociativity` to the kit, making the veto true; or drop the entry, letting
`discover` propose the law) and the A/B in §9 settled it: dropping costs **+3 rows on
swift-collections and 0 everywhere else**, so the Daikon concern does not arise. The
identifier is gone from `KnownProperty` entirely rather than merely unmapped — its only
meaning was the false claim — and `AssociativityTemplate` now returns no candidate for the
set verbs, with the reason inline.

## 4. Defect B — `equatableBase` on four keys: 12 false claims (FIXED)

The map hand-bakes transitive coverage: *"Each entry's `Set<KnownProperty>` already includes
its parents'."* The premise is that a conformance's kit entrypoint runs its parent protocol's
laws. **The kit is inconsistent about this, and exactly two files delegate:**

```sh
grep -rln "await checkEquatablePropertyLaws" Sources/
  ComparableLaws.swift
  HashableLaws.swift
```

| key | claims `equatableBase` | entrypoint delegates? |
|---|---|---|
| `Comparable` | yes | ✅ |
| `Hashable` | yes | ✅ |
| `AdditiveArithmetic` | yes | ❌ |
| `Numeric` | yes (via `additiveArithmeticBase`) | ❌ inherited |
| `SignedNumeric` | yes (via `numericBase`) | ❌ inherited |
| `SetAlgebra` | yes | ❌ |

4 keys × 3 laws (reflexive / symmetric / transitive) = **12 false claims**.

**Currently latent, and that is the dangerous part.** No template proposes
`.equatableReflexive` / `.equatableSymmetric` / `.equatableTransitive` — the only references
outside the map are a doc comment in `ProtocolCoverageAudit` and one in
`CuratedStdlibCatalog`. So nothing is suppressed today and no output is wrong.

**FIXED 2026-08-02.** `equatableBase` removed from `additiveArithmeticBase` (which
`Numeric` and `SignedNumeric` inherit) and from `SetAlgebra`. `Comparable` and `Hashable`
keep it — they genuinely delegate. **A/B: zero delta on all six corpora**, which is the
expected shape for a latent claim and is the confirmation, not a disappointment. Four
assertions in `ProtocolCoverageMapTests` pinned the wrong behaviour and were inverted; the
`Comparable transitively covers Equatable` test still passes and is now the control.

It was a loaded trap for the next equivalence-relation-on-`==` arm. That author would add the
emission, watch it veto correctly on `Comparable` / `Hashable` carriers, conclude the
mechanism works, and ship silent false suppression on every `Numeric` and `SetAlgebra` one.
Same latency the `losslessStringRoundTrip` and `iteratorTerminationStability` entries were
added to prevent, pointing the other way: those made a **decline** explicit before someone
recreated a double-report; this one makes a **veto** wrong before anyone can see it fire.

## 5. Root cause — `KitCoverageDriftTests` guards the key, never the value

There *is* a guard, added 2026-07-30, and its header states the problem exactly:
*"`ProtocolCoverageMap` is a hand-kept subset of PropertyLawKit, and nothing kept the two in
sync."* It reads the kit's suite names out of the resolved checkout by regex, so it cannot
drift on names.

**All four of its assertions work at suite granularity:**

| test | asserts |
|---|---|
| `everyKitSuiteIsClassified` | every kit suite has a recorded `Disposition` |
| `coveredClaimsAreTrue` | every `.covered` disposition has a map **entry** |
| `coverageEntriesAreNotStale` | every map **key** names a suite the kit ships |
| `noLiveDoubleReports` | no suite sits in `.uncoveredDoubleReports` |

Nothing ever opens the `Set<KnownProperty>` on the value side. `SetAlgebra` is a real kit
suite and it is in the map, so all four pass green while three of its seven claimed laws are
not run and a fourth does not exist.

`coverageEntriesAreNotStale`'s own comment names the failure it is guarding against —
*"the veto may suppress on a law nobody runs"* — one level above where it happens. **The
test's stated purpose is the bug it cannot see.** Same shape as `CuratedEntryRole`, which
says role cannot drift from `template`, which is true, and which guards the wrong join.

## 6. The third direction — under-claiming, and the double-report class

The map also under-claims, systematically and by a lot: `SetAlgebra` names 4 of 15,
`Strideable` 1 of 12, `Semigroup` 0 of 1, `CommutativeMonoid` 1 of 4.

Under-claiming is the **safe** direction for the veto and the **unsafe** direction for
double-reporting — and that is not hypothetical, it is the `Strideable` defect the
`KnownProperty` doc records as having shipped. Every unclaimed kit law is a place `discover`
could propose something the kit already runs. `noLiveDoubleReports` does not measure this; it
checks a `Disposition` a human recorded by hand.

**Not swept.** Whether any template currently proposes an unclaimed law is open, and it is the
obvious follow-up.

## 7. The guard — BUILT 2026-08-02

Extend `KitCoverageDriftTests` to law level: parse each suite's law-identifier string literals
the same way it already parses entrypoint names, and assert every claimed `KnownProperty`
resolves to one the kit runs.

**The work was the mapping, and it is not 1:1.** `.distributivity` corresponds to two kit laws
(`leftDistributivity` + `rightDistributivity`); `.comparableTotalOrder` covers four; several
`KnownProperty` cases (`multiplicativeInverse`) exist in the enum and appear in no map value
at all. So the guard needed an explicit `KnownProperty → [kit law identifier]` table — 27 rows,
hand-written once, and *itself* checked by the regex sweep (`mappedLawsExist`) so it cannot go
stale. `.multiplicativeInverse` maps to `[]` deliberately: the enum carries it "for symmetry
with `additiveInverse`" and no kit law implements it, so no map value may claim it and the
empty list is the assertion that says so.

One parsing trap worth keeping: the identifier regex must **not** require a closing quote.
`Codable`'s is `"Codable.roundTripFidelity[\(codec)]"` — interpolated — and a stricter
pattern silently dropped it, which would have read as *"the kit ships no Codable law"*.

**Delegation is modelled, not assumed** — `kitDelegations()` reads
`await check<Parent>PropertyLaws` out of each entrypoint and `effectiveLaws(of:)` follows it
transitively. §4 is the whole argument: the map assumed protocol inheritance implies law
inheritance, and the kit honours that in 2 files of 17. Deriving the edges from Swift's
conformance graph would have reproduced the bug inside its own guard.

## 8. A fifth defect, found by probe rather than by reading

Two carriers, semantically identical, differing only in how the parameter is spelled:

```swift
public struct SelfSet: SetAlgebra, Equatable, Hashable {      // the stdlib idiom
    public func union(_ other: Self) -> Self { self }
}
public struct ConcreteSet: SetAlgebra, Equatable, Hashable {  // the same thing, spelled out
    public func union(_ other: ConcreteSet) -> ConcreteSet { self }
}
```

| template | `union` | `intersection` | `symmetricDifference` |
|---|---|---|---|
| commutativity | **`SelfSet` only** | both | both |
| associativity | **`SelfSet` only** | both | both |
| binary-idempotence | both | both | — |

**The coverage deferral is spelling-dependent.** `assumedCoverageSignal` keys on
`summary.parameters.first?.typeText`; for the `Self` idiom that text is the literal string
`"Self"`, `inheritedTypesByName["Self"]` is nil, and the veto returns early.
`FunctionScannerVisitor+Summary.swift:165` says so outright — *"Plain `Self` already works via
textual `Self == Self`, so this stripping — **not `Self`-resolution** — is the actual fix."*
There is no `Self`-resolution anywhere in the path.

This is **not fixed**, deliberately, and the ordering is the point. Resolving `Self` makes the
whole map live *including its remaining false claims* — it would convert §4's 12 latent false
vetoes into live ones across every corpus. **Correct the map first, then make the veto
reachable.** §4 is the blocker for that work, not a parallel task.

It also supplies a mechanism for CLAUDE.md's measured *"the veto is close to a no-op — 1
suggestion out of ~300"*, which was attributed to there being nothing to suppress. Offered as
a hypothesis about that number, not a replacement for it: the measurement stands, and
swift-collections shows the veto is emphatically **not** dead where carriers spell the
concrete type (`public func intersection(_ other: BitSet) -> BitSet`), which is how all nine
§9 rows were reachable in the first place.

## 9. The A/B — 12 rows removed, 3 added, net −9

Method per CLAUDE.md §10.3: two release binaries, before (`3056657`) and after, run the same
afternoon over the same nine corpora with `--include-possible`.

| corpus | before | after | Δ |
|---|---:|---:|---:|
| `SwiftInferCore` · `SwiftInferTemplates` · `SwiftInferCLI` | 94 · 79 · 74 | 94 · 79 · 74 | **0** |
| `SwiftEffectInference` · `SwiftPropertyLaws` | 11 · 19 | 11 · 19 | **0** |
| swift-collections `OrderedCollections` | 106 | 106 | **0** |
| swift-collections `BitCollections` | 104 | 98 | **−6** |
| swift-collections `HashTreeCollections` | 46 | 43 | **−3** |
| swift-collections, all targets | 640 | 631 | **−9** |

Row-level diff on the full swift-collections tree — **not a net count, the actual rows**:

| direction | rows | what |
|---|---:|---|
| removed | 3 | `binary-idempotence` on `intersection` — kit runs `intersectionIdempotence` |
| removed | 3 | `binary-idempotence` on `union` — kit runs `unionIdempotence` |
| removed | 3 | `commutativity` on `intersection` — kit runs `intersectionCommutativity` |
| removed | 3 | `commutativity` on `symmetricDifference` — kit runs `symmetricDifferenceCommutativity` |
| **added** | **3** | `associativity` on `union` — **the kit runs nothing** |

Carriers: `BitSet`, `BitSet.Counted`, `TreeSet` in every case.

**Every removed row is a law PropertyLawKit already executes**, so this is 12 fewer
double-reports, not 12 fewer findings. **Every added row is a law nothing was checking.**
`OrderedCollections` is flat at 106 because the B29 order-sensitive-carrier veto already
suppressed set commutativity there — two vetoes, and the stricter one was already winning.

Zero delta on all five non-swift-collections corpora, which is the expected shape: these are
`SetAlgebra`-specific claims and only one corpus has `SetAlgebra` carriers. It also means the
repo's own frozen baselines are untouched.

## 10. Status

**Defects A (§3) and the four double-reports (§6, §8) are FIXED**, with the A/B above,
4,750 tests green and `swiftlint --strict` clean. Enum count 25 → 27 — one removed, three
added — and `ProtocolCoverageMapTests` records which way each moved, because a bare +2 would
have read as two additions.

**§4 (the 12 `equatableBase` claims) and §7 (the law-level guard) are now also FIXED.**
All 17 keys are verified law-by-law, and the map's contents can no longer drift from the kit
without a named failure. The §4 fix measured zero corpus delta on six corpora, which is the
expected shape for a latent claim.

**Open, in dependency order:**

1. **§8 — `Self` resolution.** Was blocked on §4; that dependency is now discharged, so this
   is next. It makes the map reachable on the idiom `SetAlgebra` is actually written in, and
   the map is now correct enough for that to be safe.
2. **A behavioural companion to §7.** The law-level guard checks the map's *contents*; §8 is
   a *reachability* defect and a contents-only guard passes straight through it. The
   `SelfSet`/`ConcreteSet` probe should be checked in as a fixture asserting the two
   spellings produce identical output — it is the only thing that would have caught §8.
3. **§6 — the under-claim direction.** Now measurable rather than hand-recorded: the guard
   knows every law each suite runs, so "claimed ⊂ run" can be reported. `SetAlgebra` claims
   6 of 15, `Strideable` 1 of 12. Each unclaimed law is a possible double-report.
4. **The third catalog.** `known-properties` ships 71 executable stdlib laws and overlaps the
   kit's 182 by roughly 40% — `Double` fully, `Set` 7 of 9 — with no guard between them. It
   independently asserts `a.union(b).union(c) == a.union(b.union(c))` as known-true, which is
   the exact law §3's false claim said the kit ran. The two catalogs together would have
   caught that defect on the day it was written. `known-properties` is a third input to this
   same join.

Referenced from `docs/kit-suite-backtest-plan.md` §4 Arm 1, whose blocking decision this
resolves — the arm's generated suite is unaffected either way, since `KitSuiteEmitter` emits
whole-suite calls and none of this changes which suites are emitted.
