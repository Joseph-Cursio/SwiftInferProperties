# A `_modify` property was summarised as read-only

> **Status:** `measured` · **As of:** 2026-08-18

Re-derivable at any time — `ModifyAccessorCensusMeasuredTests` *is* the harness, and
`make batch2` runs it. The rule's own vocabulary is guarded by `ReadOnlyAccessorTests` in
the fast path.

Open item 50, found by `docs/measurements/purity-refactoring-reach.md` §3 while that
census was measuring something else — the fifth in a row.

**Both halves are now closed: the first by a fix, the second by having no population.**

---

## The defect

`makeSummary(fromComputedProperty:)` models a read-only computed property as a nullary
`self -> T` method, which is what lets `involution`, `round-trip` and friends fire on
`var conjugate: Self`. The modelling is sound only while the property really is read-only.

The gate was:

```swift
guard specifiers.contains("get"), !specifiers.contains("set") else { return false }
```

**Swift has more mutating accessors than `set`.** A `_modify` coroutine yields an inout
projection, and `set.unordered.insert(x)` writes through exactly that accessor:

```swift
public var unordered: UnorderedView {
  get { UnorderedView(_base: self) }
  _modify { … self = OrderedSet(); defer { self = view._base }; yield &view }
}
```

So the property was admitted, and laws were proposed that assume a value cannot change
under them.

---

## The fix is an allowlist, not another exclusion

```swift
private static let readOnlyAccessors: Set<String> = ["get", "_read", "unsafeAddress"]
```

Naming the **read-only** kinds means an accessor Swift adds later makes a property
writable by default. Naming the mutating ones would admit each new kind silently, which is
the wrong direction for a tool whose stated posture is *when in doubt, fewer suggestions*.

**The rule's reach stops where the parser's does**, and that is worth stating rather than
implying. An *invented* token — `_futureAccessor { }` — is not parsed as an accessor at
all; the block collapses to the implicit-getter form and the property is admitted. The
fail-closed property therefore holds for every accessor kind `SwiftSyntax` recognises,
which is every one Swift ships, and not for syntax it cannot parse. The unit suite's first
version asserted the stronger claim and failed; the premise was wrong, not the rule.

---

## The A/B

OrderedCollections, both arms taken with the **same** instrument:

| | before | after |
|---|---|---|
| summaries | 435 | **429** |
| computed properties | 103 | **97** |
| declaring `_modify` yet summarised | **6** | **0** |
| suggestions resting on one | **8** | **0** |
| …of those, vetoed | 8 | 0 |

The six are `unordered`, `elements`, `header`, `values` ×2 and `__unstable`.

**The 8 suggestions were all vetoed before this landed**, by open item 54's
impure-subject veto — because `verdict(forGetter:)` read the `_modify` body, saw
`self = OrderedSet()`, and answered `.refuted`. **Two defects were cancelling**, and that
is what made this urgent rather than merely open: narrowing the oracle first would have
made `unordered` read `.pure`, stopped the veto firing, and re-admitted eight laws over a
genuinely mutable property. The source of the rows had to close first.

### The census's first detector over-matched, and the before-number moved because of it

The first `declaresModify` was a 20-line text window over the source. It reported **8**
properties, two of them `keys` declarations that are genuinely read-only — a
*neighbouring* declaration's `_modify` fell inside the window. Re-parsing and reading the
accessor specifiers gives **6**, and both arms above were re-taken with the precise
instrument.

**This is the blind-detector failure inverted.** `docs/measurements/module-state-base-rate.md`
published a zero from an instrument that could not see; this would have published a
residue from one that saw too much. The same rule catches both: state what the detector
matched on, and prefer a parse to a window.

---

## The second half had no population

`SoundPurity.verdict(forGetter:)` is handed the whole `AccessorBlockSyntax`, so it reads
every accessor rather than the getter it was asked about. That was the other half of open
item 50, and item 40 left the same question open from the other side.

**Measured across all three corpora — self, OrderedCollections, SwiftPropertyLaws — over
325 admitted computed properties: ZERO declare more than one accessor.** With mutating
accessors rejected upstream, every block the oracle now sees holds exactly one, so there
is nothing else in it to misread.

**Closed as *measured-no-population*, not as fixed**, and the distinction matters: the
whole-block read is still there. `theOracleSeesOneAccessor` reopens it the day an admitted
property declares a second accessor — a `get` + `_read` pair is legal and would be
admitted.

---

## What this does NOT establish

**That the eight laws were wrong.** They were withheld by the veto and are now not
proposed at all. Whether `round-trip` over `unordered` would have held is unmeasured; the
objection is that the subject is mutable, not that the law failed.

**Anything about `_read` or `unsafeAddress` in practice.** Both are allowlisted on the
argument that they cannot write. Neither occurs in these corpora, so the allowlist's two
non-`get` entries are asserted rather than exercised.

**That six is the population anywhere else.** It is a fact about OrderedCollections, which
uses `_modify` heavily for CoW projections. A corpus with no coroutine accessors would
have measured zero and shown nothing.
