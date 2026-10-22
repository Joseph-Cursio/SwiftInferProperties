# Input-order independence — a dictionary's hash order reaching a sorted result

> **Status:** `measured` · **As of:** 2026-10-22

Builds the second law of [#647](https://github.com/Joseph-Cursio/SwiftInferProperties/issues/647):
*the result is unchanged by permuting the input*. The first law, `sorted-output`, shipped in #650,
whose PR deferred this one as *a conjecture below the cut*. The scan could establish neither of
the two conditions it named, a unique last key and order-ignoring upstream steps.

**Verdict: built, gated on one syntactic fact the scan CAN establish.** The sorted array was
mapped from a `Dictionary`, and one element member holds the dictionary's key. **4 rows over
the corpus. Two of them fail today on real defects**, in SwiftLintRuleStudioTeam and SwiftAssist,
and the compiled stub found both. The other two hold, and on them the law adds no kill that
`sorted-output` does not already make.

---

## 1. The gate, and why it is not "a unique last key"

A dictionary iterates in hash order, and Swift seeds that order per table
(`_HashTable.hashSeed(for:scale:)` takes the storage object's address). `sorted(by:)` is stable,
so anything the comparator calls tied comes out in the order the dictionary yielded it, which no
input decides:

```swift
// SwiftLintRuleStudioTeam — Derivations.swift:274
return totals
    .map { RuleHotspot(rule: $0.key, violations: $0.value.violations, repoCount: $0.value.repos) }
    .sorted { $0.violations > $1.violations }
```

The issue framed entailment as *the chain ends on a unique key*, which the scan cannot read in
general. Reading **where the elements come from** gets something better than that condition. If
the elements are a dictionary's entries and one member holds its key (`rule: $0.key`), then:

- **the keys are distinct**, so the sequence of `rule` values is the whole order, ties
  included, and comparing it needs only the key's `==`. A key is `Hashable`, so the stub needs
  no `Equatable` on the element. The best defect found here has an element (`RuleHotspot`) that
  is not `Equatable`, so the issue's own `f(xs) == f(xs.reversed())` would not compile on it;
- **if the comparator reaches the key** (`ImpactReport.from`'s `ruleID`), the order is total and
  the law holds today. It catches the edit that drops the key;
- **if it does not**, every tie leaks hash order, and the law fails as soon as the trials draw
  one. That is the defect the issue said *the tie-break exists to prevent*.

`DictionaryKeyReader` (`Sources/SwiftInferCore/SortedOutput+DictionaryKey.swift`) reads it.
`.sorted`'s receiver is `.map`/`.compactMap` over an inline `Dictionary(…)` or over a body-level
local typed `[K: V]` / `Dictionary<K, V>`, or initialised `[:]`, `[K: V]()` or `Dictionary(…)`.
The closure names the key (`{ k, v in }`, `{ (k, v) in }`, `{ e in … e.key }`, `$0.key`), and
it reaches exactly one labelled argument of what the closure returns, either a call or a
labelled tuple. Anything else is declined. The template also needs an array parameter to
reverse.

## 2. Does a permuted call actually see a hash-order leak? Measured first

Before building, on a standalone copy of the leaking shape (`leaky` sorts on a count; `fixed`
adds `rule` as the last key), 100 random inputs per row, two runs, Xcode 27 toolchain, `-O`:

| input (keys drawn from / at most) | `f(xs) != f(xs)` | `f(xs) != f(xs.reversed())` | `f(xs) != f(xs.shuffled())` | `fixed`, reversed |
|---|---:|---:|---:|---:|
| 3 keys / 10 findings | 1, 1 | 0, 1 | 0, 0 | 0, 0 |
| 5 keys / 20 | 0, 1 | **41, 29** | 35, 25 | 0, 0 |
| 100 keys / 20 | 1, 1 | **69, 76** | 58, 61 | 0, 0 |
| 1000 keys / 20 | 0, 0 | **67, 76** | 60, 67 | 0, 0 |

- **Calling twice is nearly blind (≈1%).** The first call's table is freed and its address
  reused, so the second table gets the same seed. A determinism law (`f(x) == f(x)`) would miss
  this defect.
- **Reversing the input sees it on 29–76% of trials** once five or more keys are drawn, which is
  certain over a 100-trial run. Inserting in another order is what moves the ties. Reversal
  beat a shuffle, and it is deterministic, so the stub reverses.
- **The fixed comparator never disagreed** in 800 trials.

## 3. Population

`discover --sources … --include-possible --no-docstring-advice` over the 35 resolvable subjects
of `scripts/budgeted_truncation_census.py`'s universe: the 16 manifest corpora that resolve, plus
the 19 funnel repositories. `sorted-output` fires **24 times in 10 subjects**, two more than
#650's 22, since the repositories have moved. **`input-order-independence` fires 4 times in 3:**

| subject @ SHA | function | comparator | reaches the key? | today |
|---|---|---|---|---|
| SwiftLintRuleStudioTeam @ `7789bde` | `ruleHotspots(_:)` | `(violations ↓)` | no — `rule` | **fails: real defect** |
| SwiftAssist @ `6974842` | `GitHistoryAnalyser.buildChurnScores(from:)` (`private`) | `(score ↓)` | no — `file` | **fails: real defect** |
| SwiftFormatRuleStudio @ `149526d` | `ImpactReport.from(findings:filesChecked:)` | `(fileCount ↓, findingCount ↓, ruleID ↑)` | yes | holds |
| SwiftFormatRuleStudio @ `149526d` | `TuneModel.aggregate(ruleID:findings:)` (`private`) | `(findingCount ↓, filePath ↑)` | yes | holds |

Not reached: **swift-syntax** (`discover` fails on it, as in #650) and **swiftlang-swift**
(300s timeout). SwiftProjectLint (`eec21fb`) timed out at 300s and was re-run alone at 600s. It
has one `sorted-output` row and none here.

**Every row was hand-checked against its source, and every reading is exact.** Of the other 20
`sorted-output` rows, most are array-fed, where a stable sort keeping input order is a choice,
not a leak (`perUserStats`, `fleetImpact`). Three are dictionary-fed through `.values`, sorted on
the member that holds the key (SwiftLintRuleStudio's `ruleRows` and `resolved`, SwiftUMLStudio's
`buildCandidates`). Those are total orders that leak nothing, but the law cannot reach them,
because `.values` says no member is the key.

### What the gate misses, found by reading every `.sorted` fed by a hash-ordered source

A text scan over the same universe found **29** `.sorted { … }` sites whose statement draws
from `.keys`, `.values`, `Set(…)`, `Dictionary(…)` or a two-parameter `map`. Read by hand,
**four more real leaks sit outside this law's reach**:

| site | why the law cannot reach it |
|---|---|
| SwiftAssist `GitHistoryAnalyser.buildCoChangeMatrix` | the key is split into two members (`file1`, `file2`) through `components(separatedBy:)`, so no ONE member holds it. Declined, correctly by the reader's rule, and a false negative |
| SwiftAssist `SkillGapDetector.detect(limit:)` | `async`, and `seen.values` names no key. It sorts on `priority`, then `prefix(limit)`, so **which gaps survive the cap** is hash-dependent |
| SwiftAssist `AntiPatternStore.mostFrequent(topK:)` | no input array, since it reads stored state. Same `prefix` consequence |
| SwiftLintRuleStudio `RuleAuditEntry.violationsByFile` | a computed property, which neither law reads |

All four are syntactically the same mistake. **That is a linter's question, not a property
test's** (`docs/ideas/error-law-instrument-split.md`: one declaration's syntax → linter), and
a SwiftProjectLint rule would reach all six leaks found here, where this law reaches two.

### A row the purity veto removes: `fleetBurndown`

SwiftLintRuleStudioTeam's `fleetBurndown(_:)` maps a `[Date: Int]` and sorts on `date`, the key
itself, so it should be a holding row. **Neither template proposes it.** Bisected on a copy:
renaming `Date` brings both rows back, and so does keeping `Date` but writing the local as
`[Day: Int]()` with `typealias Day = Date`. **The type annotation `var byDate: [Date: Int] =
[:]` alone withdraws the function.** That annotation constructs no `Date`, but the purity path
reads it as one and `applyImpureSubjectVeto` vetoes the row. This is the same veto that silently
withdraws `input-totality` from a trapping body (`lexer-corpus-census.md`), and it is not fixed
here.

## 4. End to end: accepted, compiled, run

A scratch SwiftPM package (not committed) holds three subjects copied from the SHAs above.
`ImpactReport.swift` is verbatim, in a `.defaultIsolation(MainActor.self)` target as in its
package, plus the `nonisolated` on `LintFinding` that #650's measurement also needed.
`ruleHotspots`, `RuleHotspot` and `RuleViolationCount` are verbatim, with `FleetRepo` reduced to
the one member the function reads. `GitCommit`, `ChurnScore` and `buildChurnScores` are verbatim,
on an actor as in SwiftAssist, with the method widened from `private`. The stubs were written by
`discover --interactive` accept, on the Xcode 27 toolchain.

| stub | as accepted | result |
|---|---|---|
| `ImpactReport.from` | compiles, whole check inside `MainActor.run` | **passes** |
| `buildChurnScores` | the actor receiver gets a TODO generator, which is the existing rule for a drawn actor. **One line hand-substituted**: `Gen.always(GitHistoryAnalyser())` | **fails at the default generator**: three commits whose files each appear once, so every score is `1.0` and the order is the dictionary's |
| `ruleHotspots` | compiles | **traps** at the default generator: `Gen<Int>.int()` draws full-range counts and `entry.violations += violation.count` overflows. Narrowed to `0...1_000` (copy only): **fails, the real defect** |

The overflow is the generator reaching an input the app never sees, not a finding. The
template's third caveat already says to narrow what the sort keys are summed from.

### What the law adds over `sorted-output`, on the subject that holds

Mutants of `ImpactReport.from`, each run against both accepted stubs at the default generator:

| edit | `sorted-output` | `input-order-independence` |
|---|---|---|
| none | passes | passes |
| final `ruleID` tie-break replaced by `return false` | **killed** | **killed** |
| chain ends on `findingCount` (`ruleID` step removed) | **killed** | **killed** |
| first key `fileCount` dropped | survives | survives |

**On a subject whose comparator is total, this law catches nothing `sorted-output` misses.** The
last edit leaves the order total, so it is out of this law's reach by design. Its value is the
other two rows, where `sorted-output` passes **by construction**: those comparators are valid
orders, and the defect is in what they do not order.

## 5. What it is, and is not

- **A CONJECTURE, not role-entailed.** A correct function can fail it: a sort key computed from
  the input's order (the first occurrence in a group) changes when the input is reversed, as
  intended. The second caveat says so. It is refutable today, unlike `sorted-output`, so it is
  not a characterisation either.
- **It compares keys, not elements.** A member that keeps a group in arrival order is not
  checked. The first caveat says so.
- **Not a `verify` composer**, like `sorted-output`: accept writes it and `verify` does not run
  it.
- **Not reported upstream.** The two defects are in this toolchain's sibling repositories, and
  filing them is the owner's call.

Reproduce: `scripts/input_order_census.py` (the census, §3). The hash probe (§2) is the
appendix below.

## Appendix: the hash-order probe

```swift
struct Finding { let rule: String; let file: String }
struct Impact: Equatable { let rule: String; let count: Int }

func leaky(_ xs: [Finding]) -> [Impact] {
    Dictionary(grouping: xs, by: \.rule).map { Impact(rule: $0.key, count: $0.value.count) }
        .sorted { $0.count > $1.count }
}
func fixed(_ xs: [Finding]) -> [Impact] {
    Dictionary(grouping: xs, by: \.rule).map { Impact(rule: $0.key, count: $0.value.count) }
        .sorted { lhs, rhs in
            if lhs.count != rhs.count { return lhs.count > rhs.count }
            return lhs.rule < rhs.rule
        }
}
// For (alphabet, size) in [(3, 10), (5, 20), (100, 20), (1000, 20)], 100 inputs of up to `size`
// findings with rules drawn from `alphabet`: count leaky(xs) != leaky(xs), != leaky(xs.reversed()),
// != leaky(xs.shuffled()), and fixed(xs) != fixed(xs.reversed()).
```
