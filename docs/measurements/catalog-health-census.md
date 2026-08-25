# Catalog health — which templates fire on nothing

> **Status:** `measured` · **As of:** 2026-08-23

> **Renamed 2026-08-25, from `catalog-health-17-corpora.md`.** The filename and the title both
> encoded the corpus universe, and the universe moved to twenty while the figures inside were
> re-taken — so the name asserted something the contents contradicted. **A count belongs in the
> body, where it can be dated and re-taken; a filename cannot be.** The universe each figure was
> measured against is stated beside it below.

*Figures below were re-taken at twenty corpora (2026-08-23); the original seventeen-corpus run is
recorded inline where the two differ.*

Harness `CatalogHealthCensusMeasuredTests`, `make batch8`, ~7.5 minutes.

**`partition` is witnessed. The other three are not, and that is now a much stronger
claim than it was.** The larger finding is about the instrument: this project still has
no trustworthy runtime catalogue of templates, and the first version of this census
proved it by getting the denominator wrong.

---

## 1. Why re-take it

§10 of `swiftorg-property-test-study-findings.md` measured 6 of 39 templates at zero over
**eight** corpora. §10.5 then removed `involution` — its witness sat on a ninth corpus the
repo already held, registered and pinned — and drew the finding:

> *a census is only as wide as its corpus list, and its zero row is the one cell that
> cannot be trusted without knowing that list.*

`CorpusManifest` resolves **seventeen**. `docs/design-internal/toolchain-exit-criteria.md`
named this as the one action following from row 8 that needs no decision, because
*unwitnessed on eight corpora* and *unwitnessed anywhere* are different claims and only
the second is a defect.

---

## 2. The result

```
corpora: 17 · emitted 36 · catalogue 40 (derived) · total rows 5,514 (re-taken at 20 corpora 2026-08-23: **5,892**)

RESOLVED by the wider corpus list: 1
  partition                        2 rows

STILL UNWITNESSED at 17 corpora: 4
  diff-disjointness
  multiplicative-homomorphism
  selection-subset
  invariant-preservation           (deferred, not broken — see §4)
```

**`partition` fires.** It was on §10's zero row; two rows exist across the seventeen.
That is the fourth time this repo has paid for the corpus-list lesson — §10.5,
the three-corpus censuses re-taken 2026-08-19, row 46's module-state zero, and now this.

**The other three did not move**, and their zero is now measured against 17 corpora and
28,274 functions rather than 8 and ~55,000. Fewer functions, more corpora: a zero that
survives a wider *variety* is the stronger claim, and variety is what the §10.5 failure
was about.

---

## 3. The instrument finding: there is still no catalogue

The first version of this census computed the zero row as
`TemplatePack.allTemplateNames − emitted`. That is **10 declared against 36 emitted**, and
it produced a one-name zero row that was entirely a denominator artifact.

`CensusCommand`'s own header had already said so, one file away:

> *naming [a zero] needs a catalog of every template that could have fired, and this
> project has no trustworthy runtime source for that: `TemplateName` is 18 cases against
> ~92 template files and `TemplatePack.allTemplateNames` is 10, and both reject tags that
> are correct. **Printing a zero list against either would manufacture exactly the
> over-confident claim this command exists to prevent.***

The shipped `census` command therefore **refuses** to print a zero list and makes
`CensusRun.zeroRowTemplates(against:)` take the catalog as an argument. This census now
does the same thing: **the catalogue is supplied, not discovered.**

**What that costs, stated rather than implied: this census can confirm or resolve a
known zero. It cannot discover a new one.** A template firing nowhere and recorded
nowhere is invisible to it. That limit is inherited from the missing catalogue, not
chosen here.

**What caught it was a control, not a review.** `vocabularyAgrees` asserted every emitted
name was declared, failed with 26 undeclared names, and that failure is the only reason
the published number is not the artifact.

---

## 4. `invariant-preservation` is deferred, not dead

It fires zero times and belongs in the pinned zero row with its reason: `TemplateName`
records `differential-equivalence` as **FIXED 2026-08-08** and this one as **deferred**.
Its zero is expected.

This is worth separating because the first run's `zeroRowDoesNotGrow` control fired on
it as a regression. The control was right to fire — the expectation was wrong. **A
deferred template's zero and a broken template's zero are indistinguishable in the
counts**, which is §10's original point arriving from the other direction.

---

## 5. Scope

**Not the same instrument as §10.** That ran `discover --include-possible` over eight
named corpora, ~55,000 functions. This runs `TemplateRegistry.discover` directly over the
manifest's seventeen, one root each, taking every tier discovery produces rather than a
CLI tier filter. **Do not diff counts across the two.** What carries is the *membership*
of the zero row, which is what §10.5's finding concerned.

The head is still heavy, and unchanged in character: `idempotence` (1,263) + `predicate`
(1,840) + `round-trip` (527) = **3,630 of 5,514 rows, 66%** — the quantitative form of
*the tool says the generic thing when it has nothing specific to say.*

> **These figures were re-taken 2026-08-21 and the first ones were 15% too high.** The
> original run predates the two emitter fixes in
> `docs/measurements/criterion-a-unmet-subject.md` §6, and **992 of the 994 rows removed
> were `idempotence`** — one spurious law per `static var X: Self` constant, which took
> that template from **2,255 to 1,263, a 44% overcount**. Every other template moved by
> at most two rows. **The distribution's shape survives and one of its numbers did not.**

---

## 6. What this does to row 8

Criterion C of `toolchain-exit-criteria.md` — *zero templates unwitnessed across all 17
corpora* — is **not met: 4 remain**, one of them deliberately.

It is also now **the wrong bar as written**, for the reason §3 gives: a criterion over
"all templates" cannot be evaluated without a catalogue, and there is none. The
answerable form is **no template in the recorded zero row is still unwitnessed**, which
is 4 away and shrinks by one today.

## 7. What would reopen it

- **A trustworthy runtime catalogue.** It would make §3's limit disappear and could
  expose zeros nobody recorded. `TemplateName` at 18 against ~92 template files is the
  gap; closing it is unscoped.
- **A witness for any of the remaining three** on a corpus outside the manifest. Each has
  now survived 8 corpora and then 17, so the next witness is evidence about the
  *template*, not the list.
- **A new template shipping without a row here**, which would sit at zero unrecorded and
  invisible — the exact shape §10 was written to catch.

---

# Carrier shape — sizing the carrier build, and closing two directions

> Same census, same scan. A second reading of the rows §2 already produced, kept here
> rather than in its own suite because re-scanning seventeen corpora to re-derive
> identical data would double a seven-minute cost against a ~65-minute gate.

## The numbers

**All 6,508 discovery rows across the 17 corpora:**

| carrier shape | rows | share |
|---|---:|---:|
| **userDefined** | **4,851** | **87%** |
| absent | 369 | 6% |
| scalar | 146 | 2% |
| **collection** | **148** | **2%** |

*(Re-taken 2026-08-21 after the emitter fixes; previously 5,792 / 369 / 199 / 148 of
6,508. **The collection count is identical and the two-operand slice below is unchanged**
— the removed rows were `idempotence` on user-defined carriers, so the conclusion this
section draws is untouched.)*

**Two-operand templates only** (`commutativity` + `associativity`), whose emitters share
`supportedCarriers = ["Complex<Double>", "Double", "Int"]`:

| carrier shape | rows |
|---|---:|
| userDefined | 102 |
| **collection** | **6** |
| scalar | 6 |
| absent | 4 |

**And 146 of the 148 collection rows are three types**: `BitSet` (60),
`BitSet.Counted` (57), `BitArray` (29) — all swift-collections' bit types, none of them
the `[K: V]` / `Set<T>` shape a merge tie-break lives in. The remaining two are
one-offs (`Slice<AttributedString._InternalRuns>`, `BitArray._UnsafeHandle`).

## What this closes

**The collision-pairing pass is dead.** `fixtures/collision-pairing/` measured the lever
at +2 of 3 mutants on a wide domain, and the pass needs a collection carrier to have
anything to overlap. **That carrier is worth 6 rows.** The measurement was sound and the
lever is real; the population is not there.

**The collection carrier is dead as a general build too** — 2% of all rows, and 99% of
those are one package's bit types, which are fixed-width bit vectors rather than the
keyed containers the pairing argument was about.

## What it opens, and it is much larger

**88% of every discovery row has a user-defined carrier.** That is the
`DerivationStrategist` / memberwise-`Arbitrary` problem, and it dwarfs both the
collection gap and the scalar one by more than an order of magnitude. Any question of
the form *"why can so little run?"* points here and not at the carrier table.

This also reconciles the home-corpus survey, whose 47 `unsupported-carrier` declines
were **all** user-defined types and **0 of 47** collection-shaped. That zero was flagged
as not-to-be-carried — this repo analyses syntax and its types are structs, so it is a
poor witness for collections. **Taking the caution was still right, and the answer came
back the same**: collections are 2% rather than 0%, and the shape of the gap is
unchanged.

## What would reopen it

- **A corpus of keyed-container code.** Every collection row here is a bit vector. A
  package built on `[K: V]` merges could change the two-operand slice, and none of the
  seventeen is one.
- **Two-operand templates reaching user-defined carriers.** 102 of the 118 two-operand
  rows are user-defined. If those become runnable, the pairing question returns — but on
  derived generators, where "overlapping" needs a definition this fixture does not give.
