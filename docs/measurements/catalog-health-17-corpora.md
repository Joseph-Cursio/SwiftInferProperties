# Catalog health, re-taken at seventeen corpora

> **Status:** `measured` · **As of:** 2026-08-20

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
corpora: 17 · emitted 36 · catalogue 40 (derived) · total rows 6,508

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

The head is still heavy, and unchanged in character: `idempotence` (2,255) + `predicate`
(1,839) + `round-trip` (529) = **4,623 of 6,508 rows, 71%** — the quantitative form of
*the tool says the generic thing when it has nothing specific to say.*

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
