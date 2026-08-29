# `monotonicity` — what its 339 subjects actually are, at 20 corpora

> **Status:** `measured` · **As of:** 2026-08-29

**`open-threads.md` row 69 ends with *the next step is the full census, not a filter*. This is
that step, and it REOPENS the decline the sample produced.**

Two questions, deliberately kept apart, because the sample answered the second and was used to
settle the first.

---

## 1. The declined gate's premise is FALSE at full scope

Row 69 proposed gating the definitionally non-monotonic families — trigonometric functions, and
hashes, which cannot preserve order without being broken hashes — and **declined it because a
sample of 109 of the 339 rows across 10 of the 20 corpora contained ZERO of either.**

Over all 339 rows and all 20 corpora:

| family | rows | names |
|---|---:|---|
| trigonometric | **4** | `_cos(_:)` ×2, `_sin(_:)` ×2 |
| hash | **22** | `_rawHashValue(seed:)` 9 · `_rawHashValue(_seed:)` 5 · `_hashValue(for:)` 2 · `hashValue(at:)` 2 · `hashValue(for:)` 2 · `_hashValue(at:)` 1 · `Hashable_hashValue_indirect(_:)` 1 |
| **total** | **26 of 339 (7.7%)** | |

**Every one of the 26 is in `swiftlang-swift` or `swift-collections` — the two corpora the sample
did not scan, and the two row 69 named as the ones it was missing.** The warning was written and
the decline was taken anyway.

⚠ **This reopens the decline; it does not reverse it.** *No population* was the stated ground and
that ground is gone. Whether 26 rows earn a gate is a different question, and §3 is the evidence
for it.

## 2. The sample got the SHAPE right and the ZERO wrong

The head of the distribution reproduces almost exactly, which is why the sample's larger finding
survives:

| subject | sample (109) | full (339) |
|---|---:|---:|
| `decode(_:)` | 18 | **18** |
| `deleteAll(_:)` | 3 | **3** |
| `summary(of:)` | 3 | **3** |
| `columnCount(_:)` | 3 | 4 |
| `fetchCount(_:)` | 7 | 9 |
| `index(after:)` | 9 | **21** |
| `index(before:)` | 7 | **19** |

**The order-related family scales and the rest does not.** `index(after:)` and `index(before:)`
more than doubled; `decode`, `deleteAll` and `summary(of:)` did not move at all, meaning every
row of those already lay inside the sampled 10 corpora.

**And the ratio is stable to the decimal.** The `Collection` index family is **16 of 109 (14.7%)**
in the sample and **50 of 339 (14.7%)** here. A sample that reproduces a proportion that
precisely and still misses a whole family is the argument for censusing the population rather
than sampling it — the miss was not statistical, it was structural: the families live in corpora
the sample had no rows from at all.

**So row 69's thesis holds at 339 rows.** 194 distinct names; the genuinely order-related family
is **50 (15%)**; the definitionally false ones are **26 (8%)**; the remaining **263 (78%)** are
`decode(_:)`, `fetchCount(_:)`, `size(of:)`, `finalize(for:)`, `getLineNumber(for:)`,
`secondsFromGMT(for:)`, `byteOffset(at:)` — functions with no order semantics at all.

⚠ **Those two non-order buckets are NOT the same claim and must not be added together.** The 26
are laws that are **false**. The 263 are laws that are **unlicensed** — nothing says they hold and
nothing says they fail. Row 69's title is *nothing licenses an algebraic proposal*, and it is the
263 that carry it.

## 3. Is the reopened population worth a gate?

| reading | value |
|---|---|
| rows | 26 of 339 (7.7%) |
| corpora | **2** — `swiftlang-swift`, `swift-collections` |
| underscored names | **21 of 26** |
| visibility | 15 `internalOrSPI`, 11 unrestricted |

`internalOrSPI` does not block — `@testable import` reaches it — so all 26 are reachable in the
sense that matters. **But the concentration is the objection.** 26 rows in 2 corpora, 81% of them
`_`-prefixed standard-library internals, is the shape that killed the postcondition body-guard
route (*9 of 13 in one file*) and the `unchecked`-label gate (one corpus's local convention). It
is a larger population than the `involution` gate was built on (5 rows) and far larger than
`parameter-role` (2 of 118), so it is not decidable by size alone.

✅ **One reading argues FOR the gate's precision**: the same stdlib math shims contribute
`_exp(_:)`, `_exp2(_:)`, `_log(_:)`, `_log2(_:)`, `_log10(_:)` and `_nearbyint(_:)` — **8 rows
that are genuinely monotonic and correctly proposed.** A trigonometric gate removes the 4 false
ones and leaves those 8 untouched, so it is not a blunt *stop proposing this on math functions*.

**No gate is proposed here.** The row asked for the census; this is the census.

## 4. The instrument, and two ways it was wrong first

**In process, no teardown.** This is a second reading of the scan
`CatalogHealthCensusMeasuredTests` already performs over all 20 corpora — `FunctionScanner` plus
`TemplateRegistry.discover`, writing nothing. **The 109 came from an ad-hoc script that is not
committed**, so its classification was never reproducible; only its total was, because 339 comes
from this census's own catalog-health table and was never the sampled figure. That script also
ran `rm -rf .swiftinfer` per corpus and **deleted two tracked fixture files**, because four of the
twenty corpora are this repository.

⚠ **The name probe was wrong in BOTH directions before it was right, in one run:**

| probe | trigonometric | verdict |
|---|---:|---|
| exact whole-name | 0 | **too narrow** — misses `_cos`, `_rawHashValue`, `_hashValue` |
| substring | 17 | **coincidences** — `dis`**`tan`**`ce(to:)`, `editDistance(to:)`, `second`**`sIn`**`Day`, `numWeek`**`sIn`**`Year`, `clampedMinimumDay`**`sIn`**`FirstWeek` |
| **token** | **4** | splits on `_` and camelCase, then tests membership |

`distance` contains `tan` and `secondsInDay` contains `sin`. **All three counts are printed
beside each other** so the spread is visible rather than one being chosen and presented as the
number — and the gap between exact and token is precisely the 22 hash rows the decline turned on.

⚠ **My own first pin was wrong too**: I read `_cos(_:)` off a top-30 listing and pinned the
trigonometric population at 2. `_sin(_:)` sat below the cut. **Do not read a total off a truncated
distribution** — the assertion is on the computed set, and it is what caught it.

**The positive control** is asserted non-empty: if the `Collection` index family ever reads zero,
the subject join is broken and the two zeros above are the instrument rather than the population.

## 5. What would refute this

- **The trig or hash count changing without a catalogue change.** Both are pinned; a move is a
  result to re-take and write up, not a test to adjust. The assertion messages say so.
- **The 26 turning out to be unreachable in a way `internalOrSPI` does not capture** — that would
  make the reopening academic.
- **A reading that separates the 263 unlicensed rows into licensed and false.** This census does
  not attempt it, and until something does, *unlicensed* is the strongest word the evidence
  supports.
