# The census universe went 17 → 20, and every corpus figure moved

> **Status:** `measured` · **As of:** 2026-08-23

**The corpus-manifest fix of 2026-08-23 changed the population every corpus census measures.**
Three corpora had been resolving to zero `.swift` files
(`open-threads.md` → *Six wrong instruments in one cycle*), so the census universe was **17**
while the manifest declared 22 and 20 resolve. It is now **20**.

Every figure below is re-taken from **one genuine `make test` run** (`b4bf09b6`, 2026-08-23,
EXIT=0, 5,801 tests). `git diff b4bf09b6..HEAD -- Sources/ Tests/ Package.swift Makefile` is
**empty**, so these counts are current for `main` — the intervening commits are documentation.

---

## 1. What moved

| figure | at 17 corpora | at 20 | change |
|---|---:|---:|---|
| corpora scanned | 17 | **20** | +3 |
| **total discovery rows** | 5,544 | **5,892** | **+348 (+6%)** |
| functions scanned | 28,274 | **31,431** | +3,157 (+11%) |
| throwing functions | 2,830 | **3,802** | +972 |
| rows with a restricted subject | 2,407 | **2,515** (42% of rows) | +108 |
| **widenable by one modifier** | 883 | **918** (36% of restricted) | +35 |
| carrier `userDefined` | 87% | **88%** (5,213) | — |
| carrier `collection` | 2% (148) | **2%** (151) | +3 |

## 2. What did NOT move, and that is the more useful half

| figure | at 17 | at 20 |
|---|---:|---:|
| `internalOrSPI` restriction rows | 1,392 | **1,392** |
| collection rows in the two-operand templates | 6 | **6** |
| templates still unwitnessed | 4 | **4** |
| templates resolved by the wider list | 1 (`partition`) | **1** |

**Every conclusion drawn from those figures survives unchanged.** In particular:

- **`internalOrSPI` is still 1,392 and still blocks nothing** (`@testable import` reaches it),
  so `visibility-widenability.md`'s warning that counting it inflates the lever 2.7× stands at
  exactly the same magnitude.
- **The two-operand templates still hold six collection rows**, which is the finding
  `catalog-health-census.md` uses to close two build directions. Three more corpora and
  348 more rows did not add one.
- **The four unwitnessed templates are the same four.** 360 additional files witnessed none of
  them, which strengthens rather than weakens the case that they are unwitnessed rather than
  inert.

## 3. Three known-stale artifacts, not fixed here

**`catalog-health-census.md`'s filename encodes the old universe**, and the census itself
still prints `STILL UNWITNESSED at 17 corpora` and `re-checked at seventeen` while scanning
20. Those strings are hardcoded prose inside `*MeasuredTests`, two lines from a
`corpora: 20` the same census prints. **Renaming the doc and deriving the count are follow-up
work**, deliberately not bundled with a figures re-take.

**13 sites in `Sources/` and `Tests/` hardcode "17 corpora" in doc comments.** Four are in
shipped source (`TemplateName.swift`, `RolePostcondition.swift`). They are now false.

**`RolePostcondition`'s "401 rows across the 17 corpora" is not re-taken here** — that figure
needs its own census run, and this document does not guess at it.

---

## 4. Why nothing failed when the population grew 6%

The batch censuses passed unchanged through the fix. **That is them working as designed**: they
assert **floors and memberships**, not absolute totals, so 348 new rows moved their printed
figures and none of their assertions.

⚠ **It also means nothing would ever have flagged the stale prose.** A census that prints a
number it does not assert on will print a wrong one indefinitely. That is the same shape as
`open-threads.md`'s standing observation about rules stated in prose, arriving in the censuses'
own output — and the cheap fix is to derive "17" from `CorpusManifest` rather than write it.
