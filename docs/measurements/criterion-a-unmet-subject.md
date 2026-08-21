# Criterion A: does an emitted law kill a mutant the subject's own tests miss?

> **Status:** `measured` · **As of:** 2026-08-21

Subject: **`swift-http-types` @ `5b99e00`** — genuinely unmet. Not in
`fixtures/corpora/manifest.json`, not among the seventeen scanned this cycle, and no
template was developed against it. Re-derivable: `swift-infer index --target HTTPTypes`
then `verify --all-from-index`, from that revision.

**Measured NO, and not for the predicted reason. Of 163 emitted laws, 6 ran. The one
whose property directly describes a planted defect did not catch it — while the
package's own test suite did.**

---

## 1. Why this measurement and not another reach number

`docs/design-internal/toolchain-exit-criteria.md` §5 proposes criterion **A**: *on a
subject the toolchain has never met, ≥1 emitted law kills a mutant the subject's own
tests miss.* It is the only proposed bar that is an **outcome** rather than a
capability, and §3 records why that matters: five consecutive well-made measurements
said *no movement*, and nothing distinguished *the tool correctly declines* from *we are
measuring the wrong things*.

**Ratification was not required to measure it.** Ratification decides whether A is *the*
bar; measuring it answers A either way.

### The subject had to be chosen carefully, and the obvious pick was disqualified

`swift-algorithms` was proposed and rejected: its own manifest entry records it as
*"a member of the v1 algebraic corpus behind `fixtures/cycle27-surface`"*, so templates
were developed partly against it. GRDB is likewise spent — it already served as the
never-met subject in `exploratory-swiftformat-grdb.md`. **The manifest recorded both
facts; the check cost one grep and saved a contaminated result.**

`swift-http-types` was picked from packages on disk and absent from the manifest, over
four alternatives, because it is small (14 files, 227 functions), dependency-free, has a
real test suite, and carries `codable-round-trip` — the only template ever measured at
100% yield.

---

## 2. What the tool emitted, and what happened to it

163 laws indexed: `idempotence` 149, `codable-round-trip` 7, `predicate` 6,
`round-trip` 1. Tiers: **7 `Likely`, 153 `Possible`, 3 `Advisory`**.

| verify outcome | rows | share |
|---|---:|---:|
| **`build-failed`** | **145** | **89%** |
| `unsupported-carrier` | 5 | 3% |
| `internal-api-not-accessible` | 4 | 2% |
| `not-a-candidate` | 3 | 2% |
| **ran (`measured-bothPass`)** | **6** | **3.7%** |

**Zero of the 7 `Likely` ran.** Three were `unsupported-carrier` — `HTTPRequest`,
`HTTPFields`, `HTTPResponse`, ordinary `Codable` structs. The entire credible surface
failed to execute.

### 89% of the output does not compile, and it is three bugs

The shared-survey workdir raises an obvious artifact risk: one bad target failing the
build and being reported 145 times. **Checked and ruled out — 145 of 145 errors are
located in the failing entry's own target directory.** These are independent failures.

| emitted-stub defect | failures |
|---|---:|
| optional not unwrapped — `HTTPField.Name?`, `HTTPRequest.Method?` (failable inits) | **95** |
| `cannot convert value of type 'Status' to '(Status) -> …'` — function where a value belongs | **49** |
| compiler unable to type-check the expression in reasonable time | 1 |

**Three defects cost 89% of the tool's output on an unmet subject.** None is a stated
limitation, a conservative decline or a carrier gap: **the tool generated Swift that does
not build.**

The timeout is not new. CLAUDE.md records commit `bbd634c` (2026-05-02), where a 12-arm
`+` chain compiled locally and tripped the CI runner's type-check limit, silently failing
every push for eight commits. **The same class is back, in emitted code, on a real
subject.**

**Why no measurement this cycle saw this**: every one ran `discover`, not `verify`, or
ran `verify` on the home corpus, whose carriers do not have failable initialisers of this
shape. Reach was measured nine ways; **whether the emitted code compiles was measured
zero ways.**

---

## 3. The six that ran, and the mutant

All six are real, meaningful subjects — this is not a degenerate survivor set:

| template | subject |
|---|---|
| idempotence | `HTTPField.legalizeValue(_:)` |
| idempotence | `HTTPField.lenientLegalizeValue(_:)` |
| idempotence | `HTTPResponse.Status.legalizingReasonPhrase(_:)` |
| predicate | `HTTPField.isValidValue(_:)` |
| predicate | `HTTPResponse.Status.isValidStatus(_:)` |
| predicate | `HTTPResponse.Status.isValidReasonPhrase(_:)` |

`legalizeValue` being idempotent is a genuine law worth checking: legalising an
already-legal value must be a no-op.

**The planted defect.** `legalizeValue` maps illegal bytes to `0x20`, then trims
whitespace from **both** ends. The mutant drops the leading trim — one plausible
forgotten half of a two-sided operation. `_isValidValue` rejects a leading space, so
`legalizeValue(" x") == " x"` is *itself invalid* and a second pass returns `"x"`.
**Idempotence is plainly broken.**

### The two arms disagree, and the tool is on the wrong side

| arm | result |
|---|---|
| `swift-http-types`' own test suite | **CAUGHT** — 2 of 20 tests fail |
| the emitted `idempotence` law on `legalizeValue` | **MISSED** — `measured-bothPass`, 100 default + 100 edge trials |

A second mutant, in `lenientLegalizeValue` (`\n` → `\r`, itself illegal, so a second pass
changes it again), was also **caught by the package's tests**.

**So the law is not redundant. It is inert on a defect its own property describes.**

The predicted outcome was *"laws true but redundant, already covered."* Redundant would
have been a better result than this.

### The mechanism is the one this repo already names

`legalizeValue` returns early when the value is already valid; the mutation lives in the
`else` branch. A generator drawing realistic `ISOLatin1String`s produces valid values, so
the branch containing the defect **never executes**. That is the standing rule verbatim:
***`measured-bothPass` means "no counterexample in the generated domain," not "the
property holds."***

It is also `fixtures/collision-pairing/`'s finding in another guise: the regime where the
law can fail is a narrow subset of the domain, and a realistic generator never enters it.
The tests catch it because a human wrote `" "` down on purpose.

---

## 4. The verdict

**Criterion A fails on this subject, at three independent stages:**

1. **89% of laws never compiled** — three emitter defects.
2. **The entire `Likely` tier declined or failed** — 0 of 7 ran.
3. **The one law positioned to catch the planted defect passed on it**, while the
   package's existing tests caught the same defect.

On a subject the toolchain has never met, its emitted laws are **strictly weaker than the
tests already present**. Not one killed anything.

**This is the most useful result of the cycle**, and the capability bars could not have
produced it. Reach was measured nine ways this week and every answer was interpretable
only against a bar nobody had set. One outcome measurement answered it.

---

## 5. What this does NOT establish

- **One subject, one revision, two mutants.** `planted-defect-arm` already ruled on the
  epistemics: *planted evidence has no base rate — it falsifies, it cannot estimate
  precision.* A is an existence claim, so falsification is the right instrument; but
  **failing A here does not measure how often A fails.**
- **The three build defects are not proven general.** They are proven present, on the
  first unmet subject tried, at 89%. Their rate elsewhere is unmeasured.
- **Nothing here says the templates are wrong.** `legalizeValue` idempotence is a true
  and worthwhile law. The generator could not reach the branch that breaks it.

## 6. The three defects, fixed 2026-08-21

| defect | failures | fix |
|---|---:|---|
| inaccessible initializer selected | 95 | `MemberBlockInspector.initializers` no longer captures `private` / `fileprivate` inits |
| `static` member matched the *instance* self-form | 49 | `IdempotenceTemplate+TypeSymmetry` gains `!summary.isStatic` |
| compiler type-check timeout | 1 | a symptom of the first, not a separate defect |

Re-measured on the same subject and revision:

| | before | after |
|---|---:|---:|
| suggestions emitted | 163 | **18** |
| **build-failed** | **145** | **0** |
| unsupported-carrier | 5 | 8 |
| **laws that ran** | **6** | **6** |

**Read the last row before the second.** Build failures went to zero and **reach did not
move**. The first fix converted 96 broken builds into honest `unsupported-carrier`
declines — strictly better, because a decline is information and a build failure is
noise — but not one additional law runs.

**The second fix removed 145 suggestions that should never have existed.**
`HTTPResponse.Status` declares roughly sixty static constants (`badGateway`, `notFound`,
…), and the tool was emitting **one idempotence law per HTTP status code**. The gate's
own comment said *Instance … `self` is the operand*, and nothing checked `isStatic`,
while the sibling `IdempotenceTemplate+ErasedSelfForm.swift` carries exactly that guard.
**A doc asserting a guard is not a guard** — the finding `SpeculativeWidening`'s
enclosing-type trap already recorded, in a different file.

Both fixes were verified by removal: the guard taken out, the regression test watched
failing, the guard restored. The static fix ships with a companion test that the
*instance* self-form still fires, so it cannot pass by being a blanket suppression.

**Criterion A is unchanged: still 0 laws killed.** The six that run are the same six, and
the `legalizeValue` idempotence law still passes on the planted defect its own property
describes. **The emitter defects were real and are fixed; they were not what stood
between this tool and criterion A.**

## 7. What follows

- ~~Fix the three emitter defects first.~~ **DONE — see §6. Build failures 145 → 0, and
  reach did not move.**
- **The generator finding is what remains, and it is the deeper one.** A branch-blind
  generator makes a true law inert, and no emitter fix touches it: `legalizeValue`
  returns early on valid input, the mutation lives in the `else` branch, and a realistic
  generator never enters it. `fixtures/integer-division-generator/` (2/8 → 8/8) remains
  the only measured intervention that moved refutation power.
- **The 145 spurious laws are a warning about the home corpus.** They were emitted for
  two years' worth of runs and no measurement caught them, because this repo declares few
  `static var X: Self` constants. **Every count taken before 2026-08-21 includes them
  wherever a corpus does** — the 6,508-row censuses of 2026-08-20 among them. Those
  figures are upper bounds now, not measurements.
