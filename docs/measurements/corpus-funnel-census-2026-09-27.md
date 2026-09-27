# The funnel, re-run on kit 4.9.2 — and what scoped aliases and operator stubs bought it

> **Status:** `measured` · **As of:** 2026-09-27

PR #598 pinned SwiftPropertyLaws 4.9.2, handed the scan's type aliases to the accept path's generator
resolver (resolving a nested alias in the scope of the type declaring it), and wrote operator subjects
as valid Swift. All three came out of BigInt, where they took compiles **10 → 31** and passes
**6 → 21**. This is the whole funnel corpus, run to see what the same work does where it was not built.

## Method

`scripts/corpus_funnel.py` over census 14's 19 repositories, at their current checkouts, twice on the
same code: **arm A** with the binary from before the PR (`b790afcd`), **arm B** with the merged one
(`6bbfebd5`). Both resolve kit 4.9.2, both for the binary and for the stubs (the harness takes the newest
kit ≥ 4.7.0), so the A/B isolates the alias and operator changes and nothing else.

## Result

| | census 14 | arm A (before) | arm B (after) |
|---|---:|---:|---:|
| stubs | 1,141 | 1,176 | 1,176 |
| compiled | 840 | 938 | **940** |
| passed | 681 | 771 | **773** |
| — behaviour | 224 | 264 | **266** |
| — does not crash | 457 | 507 | 507 |
| failed | 116 | 123 | 123 |
| crashed | 42 | 43 | 43 |
| unaccounted | 1 | 1 | 1 |

**The A/B moves ONE repository by two stubs.** SwiftUMLStudio's `ComponentSVGRenderer.renderSVG` and
`DepsScript.nodeStereotypes` guard-domain laws were set aside on *`ComponentLayout` / `DependencyGraphModel`
has no member `gen`*; both now compile and pass. SwiftUMLStudio deliberately made `Component.Kind` and
`SPMTargetDescription.Kind` nested aliases of one `ComponentKind` enum, and `DependencyGraphModel` stores
`[String: SPMTargetDescription.Kind]`, so no generator derived until the resolver was told the alias.
The other 18 repositories are identical on every bar, and the three upstream stages do not move
(named 2,752, any law 1,933, refutable 956 in both arms). No failure changed.

**The operator fix has no population here: zero operator-subject stubs in 19 repositories.** App and
tooling code declares almost no operators. BigInt is its only exhibit, where it freed all eight `+`/`*`
commutativity and associativity laws (all pass) and two `~` idempotence laws (false: NOT is an
involution). Read the fix as a correctness repair whose value lies in arithmetic libraries, not as a
funnel lever — the same shape as the module-qualified leaf fix, whose population was 1 across 20 corpora.

## Census 14 → arm A is not this PR

Compiles rose **840 → 938** and passes **681 → 771** between census 14 and arm A, but that gap mixes
subject drift (SwiftProjectLint alone +54 compiles, after its widening PRs) with every tool change since
census 14 — ternary guard-domain, `rewrite-postcondition`, the `[String]` element draw, the underscore
fix, kits 4.8.0 → 4.9.2. It is recorded as the corpus's current standing, never attributed.
`refutable` rising 939 → 956 is the two body-derived templates adding laws.

⚠ **Yield rose and bug-finding did not**: failures 116 → 123 across the gap and unchanged by the A/B.
The two new passes are characterisation laws, which pin today's guarded answer.
