# Findings — the swift.org property-style-test study

Companion to `swiftorg-property-test-study-scope.md`, which is the plan. This is the
record. **Every number here carries the corpus SHA it was measured at**; a count without
one is not a measurement (scope §3).

**Status: setup complete, Pass 1 not started.**

---

## 0. Setup (2026-07-30)

Three items, and all three produced findings before any question was asked — which is the
argument for doing setup as measurement rather than as plumbing.

### 0.1 The corpus was re-pinned, and the old pin was contaminated by us

`~/GitHub_projects/swift` was on the local branch `fix-vacuous-sortedness-check` — two
commits ahead of upstream, **one of which edits a file inside the corpus**
(`test/stdlib/sort_integers.swift`, the `swiftlang/swift#91083` fix). Any count taken
against it would have been a count against a tree we had modified.

Re-pinned by fast-forwarding to upstream `main`, which moved **1,894 commits**. The PR
branch is preserved locally and on the fork; the PR is unaffected.

| repo | pinned SHA | date |
|---|---|---|
| `swift` | `408632e59834c1a5ee4166ff61dd2c8b0585a1c5` | 2026-07-30 |
| `swift-foundation` | `96d4094` | 2026-07-16 |
| `swift-syntax` | `1b5cd99f` | 2026-07-17 |

### 0.2 Population sizes at the pin

Produced by `scripts/swiftorg_sample.py`, over `test/`, `validation-test/`, `stdlib/`:

| population | sites | `.swift` | `.gyb` |
|---|---:|---:|---:|
| `check-battery` | **246** | 134 | 112 |
| `loops` | **698** | 694 | 4 |
| `roundtrip` | **833** | 809 | 24 |
| `lit-checknot` | **3,386** | 3,385 | 1 |

### 0.3 Three findings that change Q1 before Q1 starts

**(a) 46% of `check-battery` sites are `.gyb` templates, not Swift.** 112 of 246. A
`checkEquatable` inside a gyb template expands to N instantiations at build time, so
"how many property-style tests exist" is genuinely ambiguous: counting the template
undercounts what executes, counting expansions requires running gyb. **Q1 must decide this
explicitly**, and the sampler records `ext` per site so the adjudication can split it.

**(b) The battery's own implementation is not a test site.** `StdlibUnittest` defines
`checkEquatable` and calls it internally from `checkHashable`; 25 such matches on `swift`
inflated the population ~9% before `IMPLEMENTATION_PATHS` excluded them. A definition is
not a test.

**(c) `lit-checknot` is 3,386 and mostly not property verification.** The scope doc listed
"9 files", which was `test/stdlib/*.swift` only. Across the whole compiler test suite,
`CHECK-NOT` is overwhelmingly *diagnostic* assertion — "this error should not appear" —
not the print-on-failure property idiom `sort_integers.swift` uses. **This population needs
a much tighter definition or it should be dropped**; as measured it would dominate every
total while contributing almost nothing.

### 0.4 The classifier hazard fired three times during setup

Q1's guardrail is *"a structural classifier proved unreliable — it read `result ==
Decimal(12340)` as a round-trip; automate second."* That hazard recurred three times while
merely **preparing** to study it:

| attempted signal | what it actually was |
|---|---|
| swift-collections "associativity ×92" | 54 `associated`, 25 `associatedtype` — zero the law |
| swift-protobuf "idempotence ×315" | 214 `idempotencyLevel` — protobuf's `.proto` method option |
| `lit-checknot` ×3,386 | compiler diagnostics, not property verification |

Three witnesses in one sitting, none of them subtle in hindsight, all of them confident at
the time. This is why `scripts/swiftorg_sample.py` **locates and stops** — it does not
classify. Adjudication is by hand, into §1 below.

---

## 1. Pass 1 — adjudication

**Not started.** Schema below; one row per sampled site. Sample manifests are regenerated
with the seed and SHA recorded in each table header, so any row can be traced back.

### Adjudication schema

| column | values | notes |
|---|---|---|
| `site` | `file:line` | from the sample manifest |
| `ext` | `swift` / `gyb` | see §0.3(a) — gyb rows are templates, not instances |
| `property-style?` | yes / no / borderline | **the Q1 judgement** |
| `law` | free text | the property in one sentence, or `—` |
| `template` | template name / `none` | **Q2 recall** — which of ours would state it |
| `verdict` | `ours-covers` / `gap-with-witness` / `their-bug` / `declined` | see below |
| `generator` | idiom name | **Q5** — `.random(in:)`, LCG, instance-list, exhaustive, none |
| `notes` | free text | why, especially for borderline and `their-bug` |

`verdict` values, with `declined` being the one that is not a miss (scope §Q3d):

- **`ours-covers`** — a template states this law; counts toward recall.
- **`gap-with-witness`** — no template states it, and here is a real function that wants it.
- **`their-bug`** — the test does not check what it claims (the `sort_integers` class).
  Record separately; an upstream defect is a finding about the corpus, not the catalog.
- **`declined`** — we understand it and stand aside because PropertyLawKit runs it
  (operator conformances). Counts toward *toolchain coverage*, not *discover recall*.

### 1.1 `check-battery` — not started

### 1.2 `loops` — not started

### 1.3 `roundtrip` — not started

### 1.4 `lit-checknot` — deferred pending §0.3(c)

---

## 2. Pass 2 — census

**Not started.** Gated on Pass 1 producing a definition and a classifier error rate
(scope §6).

---

## 3. Upstream defects found

| defect | corpus | status |
|---|---|---|
| `test/stdlib/sort_integers.swift` — sortedness check could not fail (`CHECK-NOT: Error!` vs printed `Error: `) | `swift` | **`swiftlang/swift#91083`**, approved by `tbkka`, unmerged |

Found opportunistically before this study began. Q2 predicts more; each gets a row.
