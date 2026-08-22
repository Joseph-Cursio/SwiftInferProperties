# A-quality, answered — and the trial budget is the answer

> **Status:** `measured` · **As of:** 2026-08-22

**A-quality: NO at the shipped budget. YES at N ≥ 500.**

Subject: **`swift-system` @ `6a63f08`**, reverted clean afterwards. The first time in three
subjects that the bar has been evaluable at all — A-reach cleared on 2026-08-22
(`toolchain-exit-criteria.md` §5).

---

## 1. The result

The bar: *≥1 emitted law kills a mutant the subject's existing tests miss.*

| mutant | violating input | swift-system's **78** tests | emitted law @ **N=100** | @ N=500 / 1k / 5k |
|---|---|---|---|---|
| **NUL guard** | rare — ~0.4% per draw | **MISS** (EXIT=0) | **MISS** (PASS) | **KILL** — `SystemChar(rawValue: 0)` |
| **lowercase guard** *(control)* | common — ~18% per draw | **CATCH** (EXIT=1) | **KILL** — trial 9, `rawValue: 97` | — |

**The only mutant their tests miss is the one the shipped budget also misses.** Raise `small`
(N=100) to 500 and the law kills it, naming the counterexample exactly.

---

## 2. The subject and the mutants

`isSeparator(_:)` is one of the two laws that cleared A-reach, holding at 5,000 trials. Its
law is **totality**: *the predicate returns for every input its type admits.*

```swift
internal func isSeparator(_ c: SystemChar) -> Bool { c == platformSeparator }
```

Trivially total, so a violating mutant must make it fail to return. Per
`toolchain-exit-criteria.md` §6, the defect is **chosen to violate the law**, not chosen for
realism — though this one is both:

```swift
precondition(c.rawValue != 0, "NUL is not a valid path character")
```

**Realistic**, because `SystemString` genuinely forbids an interior NUL
(`criterion-a-swift-system.md` §8.3), so a developer adding a defensive guard here is a
plausible mistake rather than a contrivance.

**Baseline verified before planting**: 78 tests (70 XCTest + 8 swift-testing), EXIT=0.
⚠ The first baseline reading said *8 tests* and was wrong — the command was piped through
`tail -6`, so the log never held the XCTest half. **Fourth occurrence this cycle** of the
capture truncating the measurement; see §5.

---

## 3. The control is what makes this readable

A single mutant would have shown *the law missed it at N=100* and left the cause ambiguous:
blind law, or unlucky draw?

The control answers it. A guard on lowercase letters — ~18% of draws instead of ~0.4% —
is killed **at trial 9**, at the shipped budget, counterexample `SystemChar(rawValue: 97)`.

**So the law is not blind. It is under-budgeted.**

The control also establishes the other half, and it is the half that matters for the bar:
**swift-system's own tests CATCH the common mutant** (EXIT=1, seven precondition failures).
Where the violating input is common, the emitted law and the subject's suite agree and the
law adds nothing. **The law's unique value is exactly on the rare input their tests cannot
reach — and the shipped budget throws that value away.**

---

## 4. This is the second independent measurement that N=100 is the binding constraint

The two failure modes a trial budget has are letting a false law pass and letting a real
defect through. **The shipped `small` budget exhibits both, on the same subject, within a
day:**

| | |
|---|---|
| `removingLastComponent()` idempotence | passes at **100**, **fails at 2,000** — a false law wearing a pass (`criterion-a-swift-system.md` §8.2) |
| `isSeparator(_:)` totality vs the NUL mutant | passes at **100**, **kills at 500** — a real defect wearing a pass |

Two arrivals from opposite directions at the same number. **Neither is an argument for a
particular new default**, and this document does not propose one: the right budget is a
cost/benefit question over wall-clock across a whole survey, and nothing here measures that
cost. What is measured is that **100 is too small to answer the ratified bar on the one
subject where the bar is answerable.**

---

## 5. What this does NOT establish

**Not a general refutation rate.** One law, one subject, two mutants. `planted-defect-arm`'s
standing rule applies: planted evidence falsifies, it cannot estimate precision.

**The law is a totality predicate — the weakest family in the catalogue.** `toolchain-exit-criteria.md`
§5.2 recorded this before the measurement rather than after: both laws that cleared A-reach
are totality predicates, so a pass here must not be read as *the catalogue works*. A totality
mutant is also the easiest kind to plant.

**Says nothing about whether the emitted laws are TRUE.** The standing count is **17 of 17**
hand-checked refutations being false laws, plus one of three swift-system passes false at a
higher budget. A law that kills a mutant can still be false; these are independent questions
and only one of them is now answered.

**The mutant sits at the generator's rarest value, and that was not chosen for difficulty.**
NUL is ~1/243 per draw under `asciiScalar()`'s band weights. The NUL guard was picked because
it is the realistic defect for this subject; that it lands on the rarest band is a fact about
the subject, and it is why the budget finding surfaced at all.

**⚠ Instrument note, and the fourth of its kind this cycle.** The baseline was first read as
8 tests because the run was piped through `tail -6`. The same shape — the cheap capture
answering a different question — has now cost a `--target System` misconfiguration, a
`.build`-contaminated availability count, a default-vs-`--include-possible` join, and this.
`open-threads.md` records it as a standing observation; four recurrences in one cycle say the
observation is not doing its job.

---

## 6. The default was raised — N=100 → N=1000, on 2026-08-22

§4 declined to propose a new default because *"the right budget is a cost/benefit question
over wall-clock across a whole survey, and nothing here measures that cost."* **The cost was
then measured, and the premise behind `small` turns out to be false.**

| | |
|---|---:|
| per-stub **build** (fixed cost) | **3.56 s** |
| run at N=100 | 0.022 s |
| run at N=1,000 | **0.027 s** |
| run at N=20,000 | 0.130 s |
| run at N=100,000 | 0.547 s |

**Raising the budget 10× costs ~5 ms against a 3,560 ms build — 0.14% of the per-row cost.**
Verify is compile-bound, not trial-bound, and has been the whole time. The `--budget` help
text advertised `small` as *"~5s on round-trip-on-Complex<Double>"*, which is very nearly all
compilation.

**N=1000 clears both measured failures**, which was checked rather than assumed:

| case | N=100 | N=250 | N=500 | N=1,000 |
|---|---|---|---|---|
| `removingLastComponent` idempotence (a **false law**) | PASS | **FAIL** | FAIL | FAIL |
| NUL-guard mutant vs `isSeparator` totality (a **real defect**) | miss | — | **KILL** | KILL |

**The default moves, `small` does not.** `small` still means N=100 and remains available for a
deliberately cheap sweep — the opt-in posture that justified it is still a real posture, it is
just no longer the right *default*.

**The unknown-value fallback moved with it**, and had to: a typo'd `--budget` silently landing
on the tier measured to miss a real defect is precisely the silent-downgrade shape this
project keeps paying for. Falling back to the safer tier costs 5 ms and cannot hide a defect.

⚠ **The cost measurement is on a cheap-per-trial law** — a totality predicate over
`SystemChar`. A law doing substantial work per trial costs proportionally more, and this does
not measure that. The structural claim survives regardless: **the build cost is fixed per
stub and dominates at any plausible per-trial cost**, and a law would have to be ~100× heavier
per trial before N=1000 reached even 15% of its own build time.

