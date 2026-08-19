# Is cross-type round-trip pairing worth acting on?

> **Status:** `measured` · **As of:** 2026-08-19

Re-derivable at any time — `CrossTypePairCensusMeasuredTests` *is* the harness, and
`make batch2` runs it.

**Measured: no action — and RE-TAKEN across 17 corpora the same day, which turned an
uninformative control into a decisive one.**

> **The first version of this document said the control *"cannot discriminate"*** because
> OrderedCollections yielded **1** round-trip suggestion. That was true of the three corpora
> it looked at, and those three were the wrong universe — the same trio whose narrowness
> refuted both reasons of `docs/measurements/parameter-role-declined.md` an hour earlier.
>
> **Re-taken over `CorpusManifest.available`: 529 round-trip suggestions across 16 other
> corpora, 6 cross-type — 1.1%.** Against **220 of 230, 96%**, on this repository's
> `Sources/`. The control now discriminates, and it says the shape is **specific to this
> codebase**.
>
> | corpus | round-trip | cross-type |
> |---|---|---|
> | swiftlang-swift | 206 | **0** |
> | swift-collections | 107 | **0** |
> | swift-foundation | 82 | 4 |
> | swift-package-manager | 73 | **0** |
> | swift-syntax | 47 | **0** |
> | **this repo, all `Sources/`** | 230 | **220** |
>
> **The obvious explanation is wrong, and checking it is what makes this a control.** A
> multi-module scan might pair a forward in one module with a reverse in another — but
> `swift-collections` is scanned at `Sources/` and spans `Collections`, `OrderedCollections`,
> `DequeModule` and more, with **0** cross-type of 107. Same breadth, opposite result. So it
> is not scanning breadth; it is this repository's density of `emit` / `render` / `compose` /
> `parse` names across many types, which is what the template's forward/reverse pairing keys
> on.
>
> **The verdict is unchanged and now rests on evidence rather than on an empty control.**

---

## Why it was chased

The 2026-08-19 survey's largest single-cause population: `round-trip` proposes **72** index
entries and **0** run, **62** declining *"Cross-type round-trip pair: forward in X, reverse
in Y — property cannot type-check across distinct containing types."*

---

## What the numbers actually are

| level | round-trip | cross-type |
|---|---|---|
| `TemplateRegistry.discover` over all `Sources/` | **230** | **220** (96%) |
| the 2026-08-19 survey (index entries) | 72 | 62 |
| **`discover --target SwiftInferCLI`, default output** | **7** of 86 rows | — |

**220 of 230 is an API-level count over the whole package. It is not what a user sees.** A
single target's default output carries **7** round-trip rows out of 86, because the target
scope and the tier cut both narrow it. An earlier framing of this as a user-facing flood
was wrong, and the correction is the first useful thing the census produced.

Among the 220: **127 distinct type pairs**, every suggestion carrying exactly 2 evidence
rows. The top pairs are plainly unrelated — `AssociativityStubEmitter → KitEvidenceRecorder`
(9×), `StrategistDispatchEmitter → LiftedTestEmitter` (9×) — so the pairing is spurious
rather than a genuine round trip that happens to span types.

---

## The control is uninformative, and saying so is the point

Two declines this week were closed by the same control: point the census at a corpus this
repo does not own, and see whether the shape survives. It worked for the parameter-role
class — OrderedCollections had **9** binary-operator suggestions and **zero** role-distinct,
which is a real discriminating measurement.

**It does not work here:**

| corpus | round-trip suggestions | cross-type |
|---|---|---|
| self | 230 | 220 |
| OrderedCollections | **1** | 0 |
| SwiftPropertyLaws | **0** | 0 |

**Zero of one tells you nothing.** The other corpora do not produce round-trip suggestions
to classify, so this census cannot say whether cross-type pairing is a property of code
generators or of this template. **A control with no population is not a control**, and
reporting "0 cross-type on OrderedCollections" beside "220 on self" would imply a
discrimination that was never made.

That the other corpora produce ~0 round-trip suggestions is itself worth noticing: the
template needs a forward/reverse *name* pair, and library code apparently does not spell
one.

---

## The verdict

**No action.** The rows are `Advisory`, so `StructuralBlocker` already knows they cannot
run; they are 7 of 86 in a target's default output; and nothing here establishes that the
pairing rule is wrong rather than merely unproductive on one corpus.

**What would make this actionable** is a corpus that produces round-trip suggestions in
quantity *and* pairs them across types. The harness prints both numbers per corpus, so a
new subject answers it in one run — the same reopen shape as
`docs/measurements/parameter-role-declined.md`.

## What this does NOT establish

**That the pairing rule is sound.** 127 distinct pairs with obviously unrelated top entries
suggests it is not, on this corpus. What is missing is a corpus where the answer would
matter.

**That `Advisory` rows are harmless in the default output.** 38 of 86 rows in one target's
default output are `Advisory` — 44%. Most are the visibility class, which now carries the
lift caveat and is therefore explained rather than merely declined. Whether 44% is the right
share is a separate question this census did not ask.
