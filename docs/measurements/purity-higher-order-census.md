# Does purity propagate through a higher-order call?

> **Status:** `measured` · **As of:** 2026-08-17

Re-derivable at any time — `PurityHigherOrderCensusMeasuredTests` *is* the
harness, and `make batch2` runs it.

Answers open-threads item 33. **The premise is FALSE, the real gap runs the
opposite way, and the base rate could not be measured — because the instrument
shares the blindness being measured.** That last point turned up a separate,
larger defect, filed as item 42.

> **Re-taken at SEI `3ea25f2`. Item 42 is CLOSED; item 33's decline stands unchanged.**
> The bump refuted every witness item 42 was filed on — `unmaskedIO` is now 0 — and moved
> item 33's population 27 → 26. **Every number in §2 is unmoved**: 1,329 closure literals,
> 8 refuted, **0** reaching the population. The base rate is still unmeasurable, and §2
> now records *why the fix did not help* — the closure oracle never consulted the callee
> verdict that `3ea25f2` corrected, so fixing the leaf left the closure claim untouched.
> That is the sharpest statement of item 30's package-internal half this census has
> produced.

---

## The question, and the answer to it

Item 33 says purity *does not propagate* through a higher-order call — that `map`
is pure-if-its-argument-is, that nothing models the conditional form, and that
therefore *"every chain terminates at the first `map`/`reduce`/`filter`, which is
where the laws are."*

**Chains do not terminate. They sail straight through.**

| shape | verdict |
|---|---|
| `xs.map { $0 * 2 }` | `.pure` |
| `xs.reduce(0) { $0 + $1 }` | `.pure` |
| `xs.filter { $0 > 0 }` | `.pure` |
| `xs.map { … }.filter { … }.reduce(0, +)` | `.pure` |
| `func f(_ xs: [Int], _ t: (Int) -> Int) { xs.map(t) }` | **`.pure`** |
| `_ t: @escaping (Int) -> Int` | **`.pure`** |
| `func f(_ x: Int, _ t: (Int) -> Int) { t(x) }` | **`.pure`** |
| closure through a local `let` | `.pure` |
| nested named function | `.pure` |
| `xs.map { print($0); return $0 }` | `.refuted` |

Nine of ten reach `.pure`. `map`, `reduce` and `filter` are in neither marker
set, and `PurityInferrer` refutes only on markers, totality and — for a throwing
function — a propagated `try`. The single refutation is the one with `print`
written inside the literal, which is the refuter that was always there.

**So there is no under-claim to fix. There is an over-claim.**

```swift
func f(_ xs: [Int], _ t: (Int) -> Int) -> [Int] { xs.map(t) }   // judged .pure
```

`f` is pure if and only if `t` is. The analyzer claims it unconditionally, and a
caller passing `{ print($0); return $0 }` makes the claim false. That *is* the
`rethrows`-for-purity gap item 33 names — but knowing which way the error runs
changes what the fix has to be. A conditional verdict would stop the
over-claiming; it would not unblock any chain, because no chain is blocked.

**Third time in this line of work that the documented error direction was
backwards.** Item 30 was the first (*"any doubt refutes"* — true only of the
tokens it recognises), this is the second and third. The pattern is worth more
than either finding: **a posture stated in a doc comment is a claim about intent,
and intent is not measurable from the same doc.**

---

## Provenance

| | |
|---|---|
| corpus | this repo's `Sources/`, tree `8599bd51` |
| SEI pin | **`3ea25f2`** (`Package.swift:122`) — re-taken; the `c66fceb` column is kept beside each figure |
| harness | `Tests/SwiftInferCoreTests/PurityHigherOrderCensusMeasuredTests.swift` |
| closure oracle | SEI's **public** `PurityInferrer.isPure(_ closure:)` — used directly, not replicated |

The item 29 census replicates SEI's function-level refuters because they are
`private`. The closure oracle is published precisely so a caller can ask this
question, so replicating it would have invented a drift trap for nothing.

---

## 1 · The population is small

| | count (`c66fceb`) | count (`3ea25f2`, current) |
|---|---|---|
| non-refuted functions | 2,441 | 2,433 |
| …taking a function-typed parameter | **27** (1.1%) | **26** (1.1%) |
| of those, `.pure` | 26 | 25 |
| of those, `.pureButPartial` | 1 | 1 |
| with `@escaping` / `@autoclosure` | 2 | 2 |

Function types are unwrapped through `@escaping`, `?`, `!` and redundant
parentheses rather than matched by scanning for `->`, which would also hit a
*return* type. Missing a wrapper would under-count, which is the direction that
flatters the tool.

The population is mostly dependency-injection seams — `diagnostic`, `readFile`,
`write`, `matches`, `customGenerator`. That is the shape a conditional verdict
would exist to describe, and it is 26 rows (27 at `c66fceb`).

---

## 2 · The base rate could not be measured, and that is the finding

The item 40 question, asked of item 33: of these 26 over-claims, how many are
*wrong* — how many call sites actually hand one an impure argument?

| | count (`c66fceb`) | count (`3ea25f2`, current) |
|---|---|---|
| closure literals passed at any call site in `Sources/` | 1,329 | 1,329 |
| …that the oracle refutes | 8 | 8 |
| …refuted **and** passed to one of the population | **0** | **0** |

A zero, and it looks like item 40's result — an unchecked claim with no measured
victims. **It is not, and the reason matters more than the number.**

Here is a real call site, in `Discover+Pipeline.swift`:

```swift
diagnostic: { diagnostics.writeDiagnostic($0) }
```

and here is `writeDiagnostic`:

```swift
func writeDiagnostic(_ text: String) {
    FileHandle.standardError.write(Data("\(text)\n".utf8))
}
```

That closure writes to standard error, and `isPure(_ closure:)` calls it **pure**.

> **At SEI `3ea25f2` this example still holds, and the reason it holds has changed —
> which makes the finding sharper, not weaker.** `writeDiagnostic` itself is now
> **`.refuted`**: `FileHandle` joined `sideEffectMarkers`, so the oracle sees the write.
> Every count in the table above is nevertheless **unmoved** — 1,329 / 8 / **0**.
>
> The blindness simply moved down one level. Before, `writeDiagnostic` was pure and so
> the closure was pure. Now `writeDiagnostic` is refuted and **the closure is still
> pure**, because `isPure(_ closure:)` does not consult the verdict of a function the
> closure body names — it only scans that body for markers, and `writeDiagnostic` is not
> a marker. Fixing the leaf did not fix the closure oracle, because the two never
> consulted each other.
>
> **This is the most precise available statement of item 30's package-internal half.**
> The gap was never really "unrecognised stdlib names"; it is that **a verdict already
> computed for a callee is not read by the caller** — and a closure is just the caller
> shape where that omission is hardest to see. `3ea25f2` proves the leaf can be fixed
> without touching it.

**A zero measured with a blind instrument is not a zero.** The 8 refuted closures
are the ones with a literal `print` or `Date` inside them; every impurity routed
through a named helper is invisible. The honest statement is *the base rate is
unmeasured*, and it stays unmeasured until item 30's package-internal half is
built — **which `3ea25f2` did not do**, for all that it fixed the witness this
section happens to quote.

---

## 3 · The finding this census was not looking for — item 42

Chasing `writeDiagnostic` turned up something larger than item 33.

`throwsOnlyItsOwnErrors`' **own doc** lists the impurities the `throws` gate used
to mask: *"`Process`, `Pipe`, `FileHandle`, `String(contentsOf:)`,
`Data(contentsOf:)`, the SQLite surface."* **None of them is in either marker
set.** That gate re-closed the hole for *throwing* functions only:

> ## Item 42 is CLOSED — fixed upstream at SEI `3ea25f2`, and the falsifier caught it
>
> `50125f8` put `FileHandle`, `Process` and `Pipe` into `sideEffectMarkers`. Every shape
> and every function tabulated below now reads **`.refuted`**, and `unmaskedIO` — the
> count of non-refuted functions in `Sources/` naming any of the three — is **0**.
>
> **The notification came from the mechanism, not from anyone re-reading this file.**
> `maskedIOIsStillInvisible` was written to assert the hole *open*, with the instruction
> *"if the marker set grew, delete this test with the fix"*. It fired on the very run that
> bumped the pin. It has been **inverted rather than deleted** — now
> `maskedIOIsRefuted`, asserting `unmaskedIO.isEmpty` plus a per-marker probe — because
> the marker set lives in a pinned dependency and can therefore regress without a line of
> this repo changing. A falsifier's job ends when the gap closes; a regression guard's
> begins.
>
> **`String` and `Data` are still in neither mechanism's marker set, deliberately.** They
> are matched by bare identifier and are among the most common pure types in Swift, so
> admitting them would refute nearly everything; and `String(contentsOf:)` /
> `Data(contentsOf:)` throw, so `throwsOnlyItsOwnErrors` already reaches them. **The
> doc's list is fully covered between the two mechanisms** — worth stating because "add
> the rest of the list" is the obvious next thought and it is wrong.
>
> The tables below are the **pre-fix** measurement, kept as the record of what was found.

| shape | verdict (pre-fix, `c66fceb`) | verdict (`3ea25f2`) |
|---|---|---|
| `FileHandle.standardError.write(Data(…))` | **`.pure`** | `.refuted` |
| `h.write(d)` on a `FileHandle` | **`.pure`** | `.refuted` |
| `let p = Process(); p.arguments = []; return p` | **`.pure`** | `.refuted` |
| `Pipe()` | **`.pure`** | `.refuted` |
| `h.readDataToEndOfFile()` | **`.pure`** | `.refuted` |
| control: `print(t)` | `.refuted` | `.refuted` |
| control: `FileManager.default.fileExists(…)` | `.refuted` | `.refuted` |

`FileHandle.standardError.write(_:)` does not throw. It is the most common
non-throwing I/O call in a Swift CLI, and **7 non-refuted functions in this
package did it**, all judged `.pure`, all hand-checked as genuine writes — all
`.refuted` as of `3ea25f2`:

| function | verdict (pre-fix) |
|---|---|
| `ProveThenShowCommand.writeDiagnostic` | `.pure` |
| `SwiftInferCommand.writeDiagnostic` | `.pure` |
| `AcceptCheckCommand.runPipeline` | `.pure` |
| `KnownPropertiesCommand.usedTypes` | `.pure` |
| `ProveThenShowCommand.loadPreVerifyTiers` | `.pure` |
| `VerifyCommand+SeedHelpers.parseBudget` | `.pure` |
| `VerifyInteractionPipeline+Evidence.emit` | `.pure` |

**It was 8 by the time the fix landed**, not 7:
`VerifyCommand+CorpusDisclosure.discloseSupersededDependencies` had joined the corpus in
between. The eight were surfaced not by this table but by
`verdictAgreesWithSoundPurity` failing with eight `real=refuted replicated=pure`
mismatches when the pin moved — **the same population, found by a completely different
instrument**, which is about as good a corroboration as this apparatus can produce.

This was item 41's shape again — a small, unambiguous marker-set gap with real
instances — and unlike item 33 it needed no new verdict state, no dataflow
analysis, and no design decision. That is why it closed in a day and item 33 did not.

---

## The verdict

**Item 33 is DECLINED as filed, and re-filed.** Its premise is falsified: nothing
terminates at a higher-order call. What exists is the mirror-image defect — 26
functions whose purity is conditional on a caller-supplied argument and claimed
unconditionally.

**Building parameterised purity is not the next move, for three reasons.**

1. **The population is 26 rows**, 1.1% of the non-refuted corpus. Item 22 closed
   at *measured-not-buildable* against a larger population than this.
2. **The base rate is unmeasured and unmeasurable today.** Whether any of the 26
   is *wrongly* claimed cannot be established while the closure oracle waves
   through unrecognised callees. That is item 30's package-internal half, and it
   is a precondition here just as item 34 turned out to be for item 31.
3. **Item 42 is strictly cheaper and strictly more certain.** Seven functions
   that write to standard error are judged pure right now, with no analysis
   needed to see it.

**On item 22's reopen condition.** Item 33's row proposes that parameterised
purity might *be* the dataflow proposal item 22 asked for, scored against its 47
rows. That still holds as a route — but it should be scored against a population
that has been measured, and 26 rows of *over*-claim is not the 47 rows of
*under*-reach item 22 was about. The two are not the same scorer.

### What would reopen it

- **The population grows past a few percent** of the non-refuted corpus. On a
  corpus more functional than this one it plausibly does, and this census is
  re-runnable against any tree.
- **The base rate becomes measurable** — i.e. item 30's within-package join
  lands — and comes back non-zero.
- **A consumer appears that acts on the `.pure` claim for a closure-taking
  function.** Today the claim is visible in the advisory and nowhere else, and
  whether any *law* is emitted over these 26 is a question this census does not
  ask: the parameter needs a generatable carrier, and that is a separate gate.
