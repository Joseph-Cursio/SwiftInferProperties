# Looking for a fifth subject — eight screened, none viable

> **Status:** `measured` · **As of:** 2026-09-21

`candidate-screening-pass.md` §8.1 measured the local pool exhausted and replaced two refuted
selection theories with one that worked: **query the population** — rank repositories by how many
files hand-write `encode(to encoder:` — which surfaced `Euclid`, the best subject any method has
found. This applies that method to find a fifth subject, with `toolchain-exit-criteria.md` §6.1's
clauses and its pre-check discipline.

## The method reproduces itself

Two independent slices of GitHub code search — `encode(to encoder` and `init(from decoder` —
**both rank `nicklockwood/Euclid` first**. That is the subject this method found before, recovered
without being sought, which is as close to an instrument check as a search ranking gets.

Everything else in both slices is an application, a vendor SDK, or a wrapper around a C library.

## Eight candidates screened

`scripts/screen_candidates.py`, the committed instrument.

| candidate | src files | `Codable` | `Equatable` | **∩** | hand-written | verdict |
|---|---:|---:|---:|---:|---:|---|
| **mapbox/turf-swift** | 24 | 17 | 18 | **14** | **14** | richest — and stopped, §3 |
| AttilaTheFun/SwaggerParser | 44 | **46** | 1 | **1** | 1 | the conformance-count trap |
| postmates/PMJSON | 15 | 2 | 5 | 2 | 2 | too thin |
| tattn/MoreCodable | 18 | 5 | 1 | 1 | 1 | too thin |
| khanlou/Meridian | 0 | 5 | 3 | 1 | 1 | too thin |
| iwill/generic-json-swift | 0 | 2 | 1 | 1 | 1 | too thin |
| culturedcode/ThingsJSONCoder | 0 | 7 | 0 | 0 | 0 | no intersection |
| magicien/GLTFSceneKit | 48 | 25 | 0 | 0 | 0 | no intersection |

✅ **`SwaggerParser` is §6.1's trap, exactly as written.** It declares **46** `Codable` types — the
richest of any candidate — and **one** `Equatable`. *Counting the conformances separately predicts
a rich subject; the intersection predicted a poor one and was right.* A schema parser looked like
the ideal archetype and yields **one** row.

## 3. turf-swift: the richest intersection found, and it still stops

**14 hand-written `Codable ∩ Equatable` types in 24 source files** is denser than Euclid's 15 in 47.
It took two manifest adjustments before the pre-check could speak at all, and then the pre-check
spoke clearly.

| | |
|---|---:|
| named seeds | 59 |
| stub files written | **9** |
| **stubs compiling** | **0** |

**All 9 fail on a missing generator**, and the cause is concentrated:

- **5** need `LocationCoordinate2D` — `typealias` for **`CLLocationCoordinate2D`**, a CoreLocation
  struct. A framework type, which `corpus-domain-declined.md` already records as the shape no
  generator derives and no corpus mines.
- **3** need the package's own recursive GeoJSON types (`Geometry`, `GeoJSONObject`, `Polygon`).
- **1** is an ambiguous type lookup for `Ring`.

✅ **This is §6.1's third clause biting, and it is the clause the intersection cannot see**: *the
fields must be generator-derivable, and conformance does not imply it.* turf-swift is the textbook
case — 14 types in the intersection, and the coordinate every one of them is built from belongs to
Apple.

⚠ **This page first wrote that as *0 of 9 reaching the build stage*, which is wrong, and wrong in
exactly the way §6.1's last warning names.** All 9 stubs **reached** the build stage — they were
compiled and failed. **Zero compiled.** swift-system's `0 of 41` was zero *reaching* it, so the two
are not the same reading and turf-swift is the better of them on that axis.

**Under the reading this decision rests on — rows reaching a VERDICT — turf-swift is 0 of 59.**
Under *rows reaching the build stage* it is 9 of 59. §6.1 records that these differ by 3× on
OpenAPIKit and that **which one the threshold means is unresolved**; this page names its reading
rather than inheriting the ambiguity. Stopped on the verdict reading.

✅ **And there is an argument for resolving it that way, not merely a preference.** *Reaching the
build stage* means only that a stub was emitted and handed to the compiler — it says nothing about
whether it compiled. **All 9 of turf-swift's stubs reached it and all 9 failed**, so on that metric
a subject scores for producing code that does not build. **That is also exactly why the two
readings diverge 3× on OpenAPIKit**: the gap between them IS the rows that reached the compiler and
were rejected by it. A threshold that counts those as progress is measuring the emitter's
willingness, not the subject's reach. Proposed for §6.1, which currently leaves the choice open.

## ⚠ Two readings that were NOT the subject, and the distinction matters

The pre-check returned **0 twice before it returned a number that meant anything**, and neither
zero was about turf-swift's code:

1. **`scanned_targets: []` in 2 seconds.** On Darwin the manifest ships a **`binaryTarget`** — a
   prebuilt `.xcframework` from a release — and the source target exists only under `#else`, for
   Linux. There is no scannable source target on this host.
2. **`manifest: targets: is not an array`.** The manifest assigns `targets:` a *variable*, and the
   harness's rewriter needs an array literal to inject a census test target.

⚠ **§6.1's recorded discipline failure is *continuing past a pre-check that said stop*, and this is
not that.** The distinction is whether the pre-check read the subject and found it poor
(swift-aws-lambda-events at 1 of 15) or could not read it at all. **A zero from an unread subject
is not evidence about the subject** — and treating it as one would have discarded the richest
intersection found, for a reason that is about a manifest.

Both adjustments are stated and were made in a throwaway clone; nothing was proposed upstream.

⚠ **But the chain length is itself a reading.** Two manifest adjustments before a first honest
number is what §6.1 means by *A-reach's length is a property of the subject*.

## What this does not claim

- **Not that no fifth subject exists.** Eight candidates from two search slices is a sample, and
  the search returns at most ~80 results per query, so this ranks a window rather than the
  population of 136,192 files.
- **Not that turf-swift is a bad subject.** It is a good subject the toolchain cannot currently
  reach: a `CLLocationCoordinate2D` generator would unblock 5 of its 9 stubs at a stroke, and it
  is two stored `Double`s.

## What would change the answer

- **A generator for a small set of framework value types** — `CLLocationCoordinate2D` is two
  `Double`s and would turn turf-swift from 0 verdicts into a real reading. That is a kit question, and
  it is the first time a *named* subject has been blocked on a *nameable* framework type rather
  than on a long tail.
- **A wider slice of the ranking**, which needs paging the search rather than sampling it.

## Reproducing

```
gh search code --language=swift --limit 80 --json repository 'encode(to encoder'
python3 scripts/screen_candidates.py <clone>...
```
