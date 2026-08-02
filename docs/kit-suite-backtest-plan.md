# Plan — backtest `scaffold-kit-suites` against real, already-fixed swift.org bugs

**Status: planned, not started. Written 2026-08-02 for execution in a fresh context.**

Read this file and `docs/backtest-apple-libraries.md` before touching anything. This plan is
a *different question* asked with the *same method* as that 2026-07-18 backtest.

---

## 1. The question, and why it is not the obvious one

The obvious road test — run `swift-infer scaffold-kit-suites` over the swift.org repos at
`HEAD` and report how many laws it generates — **must not be run as the headline.** These are
mature, heavily-tested libraries. Everything will pass. "N laws, all green" is strong evidence
of *reach* and almost no evidence of *value*, and it is the same discover-only-count mistake
this repo has now corrected four times.

Worse, at `HEAD` the two explanations are indistinguishable:

| observation at `HEAD` | reading A | reading B |
|---|---|---|
| generated suites all pass | the library is correct | **the tool is blind** |

**The backtest design separates them.** Check out the commit *before* a real fix (`<fix>^`),
generate the suites there, and run them. If they stay green on a commit that demonstrably had
the bug, that is blindness — not correctness. That is the only version of this road test that
can produce a falsifiable result.

The method is already established in `docs/backtest-apple-libraries.md` (§Method). Reuse it
verbatim; do not reinvent it.

## 2. What is different from the 2026-07-18 backtest

That backtest asked whether **`discover`'s catalog** would surface the violated law. It ran
7 cases and scored **1 hit, 6 misses**.

This one asks whether **PropertyLawKit's conformance suites, as emitted by
`scaffold-kit-suites`, would fail** at `<fix>^`. Nothing generated those suites in July — the
command shipped 2026-08-02 (PR #42, #43). So the cases may score differently, and a case that
missed for `discover` can still hit here (or vice versa).

Keep the two straight in any write-up. They are not comparable scores.

---

## 3. Do these three things first — all cheap, all affect the result

**3a. Bisect the zip-nesting cap.** `KitSuiteEmitter.maximumZipNesting = 4` is empirical, not
derived: 8 nested `zip`s failed to type-check, 4 compiled, and nothing in between was tried.
Third-party types nest more deeply than ours, so derivation rate would be measured against an
arbitrary constant. Bisect 4→8 on `SwiftInferCore` (and ideally on swift-collections) and set
the real boundary. Record the number that failed.

**3b. Measure `Sendable` / access-level compile failures.** `check<Protocol>PropertyLaws`
requires `Value: Sendable`, which a `TypeShape` cannot always establish, and a carrier may be
`private` or nested past `@testable`'s reach. On this repo it was 0 errors — **one data point,
on the codebase the emitter was written against.** Expect this to be the dominant failure mode
on third-party code. Measuring it is the point, not a prerequisite; just do not be surprised.

**3c. `--module` ergonomics.** `scaffold-kit-suites --sources` requires `--module`. A
multi-target package (swift-collections has several) needs one invocation per target. Confirm
the per-target loop works before running it 30 times.

---

## 4. The arms, in priority order

### Arm 1 — swift-collections `symmetricDifference` (`876177db`). **Predicted HIT.**

Case 2 of the July backtest, and its only hit. Pre-fix implementation was
`self.subtracting(self.intersection(other))` — i.e. `self \ other` — which is not commutative:
`{1,2,3} △ {3,4,5}` gave `{1,2}` one way and `{4,5}` the other; correct is `{1,2,4,5}` both.

`SetAlgebra` is in `ProtocolCoverageMap.protocolCoverage` (union-associative,
union-commutative, union-empty-identity, intersection-idempotent), so the emitted suite
should reach this. If it does not, that is the most interesting negative result in the whole
plan and worth stopping to diagnose.

### Arm 2 — the projection bugs. **Predicted MISS, and publish it.**

`fixtures/equatable-signal/README.md` measured that **3 of 3 real swift-collections projection
bugs pass 4 of 4 Equatable laws**: `OrderedSet` order, `BitArray` padding, `Deque` head
rotation. A projecting `==` is still a valid equivalence relation, so the conformance laws are
*structurally* blind to it.

`BitArray.toggleAll()` (`e01391e5`) is Case 6 of the July backtest — a miss there, which also
exposed a tool-side false positive.

**This arm is expected to go green on buggy code, and that is the finding.** It is the honest
counterweight to "877 laws generated": it states precisely what this codegen does not buy.
Do not soften it, and do not bury it under the Arm 1 hit.

Positive half: the model law (`left == right ⟺ model(left) == model(right)`) catches all three
at trial ≤3, and `ModelLawTemplate` / `SequenceViewModelLawTemplate` already ship. So the
finding converts into a recommendation — *generate model laws alongside conformance suites* —
rather than a shrug.

### Arm 3 — derivation and compile rate across the corpora. **Diagnostic only.**

For each package: carriers covered, laws covered, % derivable, % of emitted files that
compile, % of tests that pass. Report all five. This is the reach measurement; it is context,
never the headline, and it must not be reported without Arms 1 and 2.

`swift/stdlib/public/core` can only yield derivability — validating compilation there means
building the toolchain. Say so rather than quietly omitting it.

---

## 5. Scoring rules

- **Unscored. Do not freeze an answer key.** "Which laws does this library owe" is not
  freezable the way `fixtures/swiftorg-study/q2-answer-key.json` was, and forcing one is the
  premature ceremony already rejected on the leaderboard fixture.
- **Report in refutation units.** A suite that fails at `<fix>^` and passes at `<fix>` is the
  unit of value. Counts of generated laws are reach.
- **Every number carries its SHA** — the fix commit, the parent, and this repo's commit.
- **A tool may not grade its own homework.** Anything found that the July backtest's cases did
  not name is recorded separately and unscored.

## 6. Traps, all previously hit

- **Corpora live in `~/GitHub_projects/`**, not `~/xcode_projects/`: `swift`,
  `swift-collections`, `swift-foundation`, `swift-nio`, `swift-syntax`,
  `swift-package-manager`. `SwiftProjectLint` and the sibling kit are in `~/xcode_projects/`.
- **`swift package clean` before trusting a build.** Stale SwiftPM state produced
  `Internal Error: DecodingError.dataCorrupted … Corrupted JSON` repeatedly on 2026-08-02
  (root cause: the repo directory was moved mid-build). A from-scratch build cleared it.
- **`.swiftinfer/kit-evidence.json` now exists in this repo** and changes `discover`'s
  coverage headline from "no kit evidence" to the `contradicted` state. Never `git add` it.
- **zsh aborts a command line when a glob matches nothing** — `rm -rf foo-*` runs *nothing*,
  not "the rest". Use `find … -exec`.
- **Old commits may not build under the current toolchain.** The July backtest's workaround is
  to extract the pre-fix logic into a minimal verify-ready fixture with a generatable carrier
  (a `CaseIterable` enum is cleanest). Reuse it; do not fight the build.

## 7. State at handoff (2026-08-02, `main` @ `229c445`)

Seven PRs merged today: #38–#44.

| | |
|---|---:|
| `scaffold-kit-suites` live | 262 carriers / **877 laws** |
| blocked on a hand-written `gen()` | 91 carriers / 282 laws |
| generated `@Test` functions | **341** |
| generator derivation | **74%** of carriers |
| verified on `SwiftInferCore` | compiles 0 errors, **209/209 green** |
| suite | 4,747 tests green, `swiftlint --strict` clean |

Commands:

```sh
swift build -c release
.build/release/swift-infer scaffold-kit-suites --target <T> --output <path>
.build/release/swift-infer scaffold-kit-suites --sources <dir> --module <M> --output <path>
make test-fast          # ~26s, includes the lint gate
```

Two constants that encode judgement calls, both documented in `KitSuiteEmitter`:
`maximumZipNesting = 4` (see 3a) and the ±10_000 numeric bound (matches the verify path;
cannot find overflow bugs at the extremes, deliberately).

## 8. What would make this road test worthless

Writing it up as "we generated N laws across six swift.org repos." That is reach with a large
denominator, it will be all-green, and it answers nothing. If Arms 1 and 2 cannot be run, run
neither and say so — a diagnostic-only run should be labelled diagnostic, not published as a
road test.
