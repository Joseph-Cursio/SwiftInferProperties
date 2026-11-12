# Count-threshold boundary census (#670): scope, frozen before the run

> **Status:** `proposed` · **As of:** 2026-11-11 · **Issue:** Joseph-Cursio/SwiftInferProperties#670

## 0. The question, and what this decides

#670 shows that `ActivityGraphBuilder.compactText`'s `count > 80` → `>= 80` slip survives both the generated
`idempotence` law and SwiftUMLStudio's hand-written suite (`docs/measurements/roadtest-swiftumlstudio-mutation.md`,
F4). Its argument is that only a law on the side the boundary sits on, drawn at length 80, sees the slip. It
proposes three changes to guard-domain:

- **(a)** a boundary walk at `N − 1`, `N`, `N + 1`;
- **(b)** the complementary branch for cut-first bodies;
- **(c)** reading past the first statement, with a label-aware free-identifier gate.

Its Direction fixes the order: step 0 runs the kill (a measurement, not a gate), step 1 counts with the reader's
rules (not a grep) under a stop condition fixed before counting, and step 2 builds only if the count passes.

**This scope covers steps 0 and 1 and the decision.** The build, if it is decided, is filed separately, as
#692 was for #669.

Everything below is fixed before the harness reads any subject. Any later change is an amendment, appended with
its date and reason.

## 1. Step 0: the kill arm

### 1.1 The subject

`ActivityGraphBuilder.compactText(_:)` (SwiftUMLStudio, `SwiftUMLBridge/Sources/SwiftUMLBridgeFramework/Parsing/ActivityGraphBuilder.swift`)
at two revisions, each copied verbatim into `fixtures/count-threshold/kill-arm/`:

| revision | body |
|---|---|
| `e36da59` (the mutation run's) | a trim, a `\n` replacement, a split on `.whitespaces` + filter + join, then `if collapsed.count > 80 { return String(collapsed.prefix(77)) + "…" }; return collapsed` |
| `9ad7631` (HEAD on 2026-11-11) | one `let`: split on `.whitespacesAndNewlines` + filter + join, then the same threshold |

⚠ **#670 says the function is unchanged at HEAD; it no longer is.** The threshold, the cut and the marker are
unchanged, and the normalisation still has no effect on letters-and-digits input, so both revisions owe the
same two laws.

### 1.2 The laws, written by hand

Here `e(x)` is the whitespace collapse.

- **Law 1**, on the side the boundary sits on: `e(x).count <= 80 ⟹ f(x) == e(x)`. It is walked at lengths 79,
  80 and 81, with 20 draws each from `Gen<Character>.letterOrNumber.string(of: n...n)`, in a test function of its
  own.
- **Law 2**, the cap: `f(x).count <= 80`, over the walk plus 100 sampled draws from the edge-biased `String`
  expression.
- **Idempotence**, as the tool emits it: `f(f(x)) == f(x)`, with 100 trials of the edge-biased expression built
  from the subject's literals (`RawType.edgeBiasedGeneratorExpression(subjectTokens:)`). This is the control row.

### 1.3 The mutants

These are the three mutants swift-mutation-testing made at `:200`, applied by text edit to the threshold line:

1. negate-conditional: `!(collapsed.count > 80)`;
2. `>` → `<`;
3. `>` → `>=`.

### 1.4 What is counted, and what is predicted

The result is a 2 revisions × 4 variants (original + 3 mutants) × 3 laws matrix, each cell PASS or FAIL. A
mutant is **killed by a law** when that law fails on it.

**Control:** every original passes all three laws. If one fails, the arm is void.

**Prediction (#670's, REASONED):**
- Law 1 kills all three mutants.
- Law 2 kills the negation and `<`, but not `>=`.
- Idempotence kills the negation and `<`, but not `>=`.

As #670 says, the arm cannot fail by construction, so it decides nothing. It turns the REASONED rows into
MEASURED ones.

## 2. Step 1: the census pass

### 2.1 The unit

The unit is every `func` declaration with a body in a universe file (§3), including methods, nested functions
and extension members. Today's rows come from the shipped scan: `FunctionScanner.scanCorpus(file:)` →
`summary.bodySignals.guardDomain`, which is `GuardDomainReader.read`. The extended reader (§2.4) runs on the same
`FunctionDeclSyntax`. The two are joined by file and line.

### 2.2 A count comparison

A condition is a **count comparison** when it is exactly one comparison `E.V op K` or `K op E.V`, where:
- `V` is `count`, `utf8.count`, `utf16.count` or `unicodeScalars.count`;
- `op` is `>`, `>=`, `<` or `<=`;
- `K` is an integer literal (underscores allowed), or a static constant. A static constant is spelled `Self.k`,
  `T.k` for the enclosing type `T`, or a bare `k`, and resolves to a `static let k = <integer literal>` declared
  in the same file and the same type (including its extensions in that file).

Conjunctions, `==`, `!=` and computed constants are **not** count comparisons, and are recorded as such.

The **boundary** is the pair `(lo, hi)` of the last length on one side and the first on the other: `> N` gives
`(N, N + 1)`, `>= N` gives `(N − 1, N)`, `< N` gives `(N − 1, N)`, and `<= N` gives `(N, N + 1)`.

### 2.3 Today's rows, part (a)'s population

A **today's count row** is a function that today's reader admits and whose condition is a count comparison.
For each one, record:

- `N`, the boundary, and the **law side**: the range of counted lengths over which today's stated law fires.
  This follows from `firesWhenConditionHolds` and `op`.
- **Reach.** The longest `String` the stub's generator can draw. That is
  `max(10, L + 8)`, where `L` is the longest literal `SubjectLiterals.harvest(declarationAt:in:)` keeps for the
  function, or 10 when there is none. This is read from `RawType.edgeBiasedGeneratorExpression`: the baseline
  draws 8, a doubled curated token 10, a token plus filler 9, and filler + literal + filler `L + 8`.
- **`drawsN`**: whether `reach >= hi`, so the generator reaches the first length past the boundary.
- **One side only**: `reach < hi`, so every draw lands at or below `lo`.
- **`NOT APPLIED`**: the law side lies wholly above reach, so no draw enters it. A cut-first body read today
  (`if count > N { return cut }`) with `N + 1 > reach` gets this.
- **Beyond reach**: `hi > reach`.

Rows whose counted value is not a `String` or `Substring` parameter, or an allowlisted chain over one (§2.5),
are recorded but are not walk-eligible.

### 2.4 The extended reader, parts (b) and (c)

The extended reader is a prototype in the harness. It is not in `Sources/`. It admits a unary function, with a
named parameter, async, throws and `Void` results excluded as today (`GuardDomainTemplate`), whose body is:

```
L*  T  R
```

- **`L*`**: zero or more `let x = init` statements, single binding, no type-pattern tricks. Each initialiser
  mentions only the parameter, earlier admitted bindings, type names, and static members of the enclosing type,
  under the gate in §2.4.1.
- **`T`**: the threshold statement, one of:
  - **identity-first**: `if C { return e }` (no else) or `guard C else { return e }`, where the branch that
    returns is the one on the side where `e` comes back. Any `R` may follow; that is the cut side, and `let`s
    are allowed there.
  - **cut-first**: `if C { return cut }` (no else), followed by `R` = exactly `return e` and nothing else.
  - **ternary**: `return C ? a : b`, or a single expression statement that is that ternary as the body's last
    statement, where exactly one of `a` and `b` is `e`. `R` is empty.
- **`C`**: a count comparison (§2.2) on `e.V`.
- **`e`**: the counted expression, which must be **exactly the returned identity branch, by text** (before
  inlining). So `if s.count > N { … }; return s.uppercased()` is refused, as #670 requires.

**Law 1** is stated over `e` with the `let`s inlined. The row is recorded with the rule that admitted it:
- **(b)** cut-first or ternary-cut;
- **(c)** needs `let`s, the label-aware gate, a bare static, or a ternary after `let`s.

A row can need both. It is also recorded with its **cut form**: the other branch read as `prefix`, `suffix`,
`dropLast`, a `[..<i]` slice, or other, each with or without a literal marker appended.

A row is **new** when today's reader refuses the function, or admits it but states the other branch (a
cut-first first statement, such as `truncateURL`, which today states the cut).

#### 2.4.1 The label-aware gate

This is the free-identifier check, at syntax level:
- a `DeclReferenceExprSyntax` is **free** unless it is the member of a `MemberAccessExprSyntax`, or is a closure
  shorthand parameter (`$0`, `$1`) or an explicit closure parameter of an enclosing closure in the expression;
- argument labels are `LabeledExpr.label` tokens, not `DeclReferenceExpr`s, so they are never free;
- free names allowed are the parameter, admitted bindings, `true`/`false`/`nil`/`self`/`Self`, capitalised type
  names, and bare names that resolve to a static member of the enclosing type.

A bare static is rebound as `Type.name`. If it does not resolve, the site is refused.

This matches what `GuardDomainRebinding.unboundNames` already does with labels (`argumentLabelsPassThrough`).

#### 2.4.2 The A/B on guard-domain's existing rows

The harness reimplements today's `read` twice:
- with today's text gate (`mentionsOnly`);
- with the label-aware gate in its place, and nothing else changed.

The first must agree with the shipped reader on **every** function in the universe. That agreement is the
replica guard: a disagreement voids the A/B, as `verdictAgreesWithSoundPurity` voids a purity census. The second
is compared with the first, and the report gives rows gained and rows lost, over all guard-domain rows, not only
count rows.

### 2.5 Walk eligibility, part (a)

A row is **walk-eligible** when the parameter's type is `String` or `Substring` and the counted expression,
with `let`s inlined, is the parameter itself or a chain over it whose every step is on this allowlist:

- `trimmingCharacters(in: .whitespaces)` or `trimmingCharacters(in: .whitespacesAndNewlines)`;
- `replacingOccurrences(of: w1, with: w2)` where both are literals made only of whitespace;
- `components(separatedBy: .whitespaces)` or `components(separatedBy: .whitespacesAndNewlines)`, followed by
  `filter { !$0.isEmpty }` and then `joined(separator: " ")`.

`String(...)` wrapping a step is transparent.

Each step is the identity on letters-and-digits input, so the drawn length is the counted length. The allowlist
is #670's, plus `.whitespacesAndNewlines` for the split. That is the form `compactText` takes at HEAD, and it is
the identity on that input for the same reason.

### 2.6 Emittable

A row is **emittable** when all of the following hold:

1. **The proposal changes what is emitted.** Either it is a today's count row that is beyond reach (§2.3), so
   the walk is new, or it is a new extended row (§2.4).
2. **It is walk-eligible** (§2.5).
3. **A stub compiles today.** That means:
   - the function is not `private` or `fileprivate`;
   - it is not in an executable target (read from the package manifest at hand-check);
   - it is not an actor method;
   - it is a static or free function, **or** an instance method whose receiver type has a derived generator.
     guard-domain's writer **draws** the receiver (`InteractiveTriage+AcceptGuardDomain.swift`); it does not
     construct one. Derivation is hand-checked per row.

Copies count once. A function is keyed by its repository, its path within the repository, and its name, and the
roots are deduplicated by resolved path, so a sibling repo in both the manifest and the funnel list is read once.

## 3. The universe, frozen

- **The manifest corpora.** The 20 corpora `measurement.corpus_roots()` resolves from
  `fixtures/corpora/manifest.json`, read through `measurement.source_dirs`. `swift-numerics` and
  `swift-algorithms` do not resolve at their `localPath` and are out, as they were in the 20-corpus readings.
- **The funnel repositories.** The 19 in `budgeted_truncation_census.FUNNEL`, at `~/xcode_projects/<name>`.
  Every `.swift` file under a path component named `Sources` counts.
- **Skipped everywhere:** hidden directories (⚠ several funnel repos hold `.claude/worktrees/` copies of
  themselves, which would count every site again), `.build`, `checkouts`, `Tests`, any directory ending in
  `Tests`, `fixtures` (except where a manifest corpus *is* a fixture), and `.swiftinfer`.
- **Revisions.** Each root's `git rev-parse HEAD` and dirty state are recorded in the subject list.
- **The 33,150.** `docs/measurements/rewrite-postcondition.md` names this universe with 33,150 functions, but no
  harness for that count is committed. This census reports its own function count beside that figure and
  attributes any difference to the revisions that have moved since. It does not reconcile the two.

## 4. Controls, asserted before the run

The harness's control mode runs these on in-memory sources, and the run refuses to start if any fails.

| control | source | expected |
|---|---|---|
| `compactText` at `e36da59` | §1.1 | extended: admitted, cut-first, (b)+(c), walk-eligible, `N = 80`, cut `prefix` + marker |
| `compactText` at `9ad7631` | §1.1 | the same |
| `truncateURL` | SwiftProjectLint, `if urlString.count > 60 { return String(urlString.prefix(57)) + "..." }; return urlString` | extended: admitted, (b) only, walk-eligible. Today: admitted, stating the cut, `NOT APPLIED` (61 > reach 11) |
| `preview` | SwiftAssist, `let oneLine = text.replacingOccurrences(of: "\n", with: " ")` then a ternary | extended: admitted, (b)+(c), walk-eligible |
| `truncateOutput` | SwiftAssist, `if output.count <= Self.maxErrorOutputLength { return output }`, `static let maxErrorOutputLength = 10_000` | today: admitted, identity-first, `N = 10000`, beyond reach. Extended: admitted, not new |
| `trimStep` | SwiftAssist, a `let` trim, then `guard trimmed.count > maximumStepLength else { return trimmed }`, bare static `= 240` | extended: admitted, (c) only (a `let` and a bare static), walk-eligible, `N = 240` |
| `deriveName` | SwiftAssist, `[String]` input, opens with `guard let` | refused |
| uppercased return | `if s.count > 8 { return String(s.prefix(8)) }; return s.uppercased()` | refused (the identity branch is not `e`) |
| derived count | `let parts = s.split(separator: ","); if parts.count > 4 { … }; return …` | not walk-eligible |
| `GuardDomainReaderTests` fixtures | `Tests/SwiftInferCoreTests/GuardDomainReaderTests.swift` | the replica with today's gate agrees with the shipped reader on every one |

`python3 scripts/count_threshold_census.py controls` asserts the frozen universe: 20 manifest roots resolve, 19
funnel roots exist, and no root is dirty without being recorded as dirty.

## 5. The hand-check

Every row the extended reader admits, and every row counted emittable, is read by hand against its source. Each
row gets three verdicts:

- **law-right**: Law 1 as stated is what today's code does on the identity side, with the `let`s inlined
  correctly and the boundary on the right side;
- **counted-right**: the comparison and `N` were read correctly, including a resolved static;
- **compiles**: for an emittable candidate, access, target kind, and (for an instance method) whether the
  receiver's generator derives.

A row that fails **law-right** or **counted-right** is a reader defect. It is reported by name and does not
count as emittable. Verdicts are stored in the census JSON beside each row.

## 6. Predictions, frozen

- **Step 0:** as §1.4.
- **(a):** fewer than 20 today's count rows are beyond reach, and of those, fewer than 5 are walk-eligible and
  emittable.
- **(b) + (c):** fewer than 15 new extended rows, at most 3 emittable. SwiftAssist holds the most.
- **The A/B:** the label-aware gate gains rows (labelled calls such as `hasPrefix`, `range(of:)`,
  `trimmingCharacters(in:)` in conditions) and loses none, because a syntax-level gate only removes false free
  names.
- **The decision:** DECLINE on population. The issue estimates about one emittable row today.

## 7. The decision, fixed now

Let **E** be the set of distinct emittable rows (§2.6) that pass the hand-check (§5), over (a), (b) and (c)
together.

- **DECLINE** when `|E| < 5`, or when more than half of `E` sits in one repository. #670 is then closed as not
  planned, with the counts, as `docs/measurements/budgeted-truncation-census.md` did. The A/B is reported either
  way. A gate that gains rows and loses none is recorded as a separate, smaller candidate, and is not decided
  here.
- **BUILD** otherwise. #670 stays open, and the build is filed as its own issue, smallest part first, as #670 §2
  orders.

The kill arm does not enter the decision.

## 8. What this does not answer

- **Whether the cap (Law 2) should be emitted.** It is counted only through the kill arm. Its SwiftAssist
  failures belong to the author or to a linter, as #670 argues, not to this census.
- **Multibyte cuts.** The walk draws ASCII only, so every count view agrees on it.
- **Counts on a stored field of a composite input** (`edge.points.count`). That is a generator problem, F4's
  other half.
- **Precision of a built template over a wider population.** This census bounds population; it does not test a
  shipped template.

## 9. Disclosures before the freeze

- The revisions have moved since #670 was written. `compactText` changed (§1.1), and the funnel repos stand on
  their current `main`. Each is recorded.
- Static constants resolve within one file only. A constant declared in another file leaves the site refused,
  under-counting rather than over-counting.
- Reach is computed from the function's own literals (`SubjectLiterals.harvest`). A round-trip suggestion would
  pool both halves' literals, but guard-domain is unary, so this is exact for it.
- The extended reader is a prototype written for this census. If the decision is BUILD, the shipped reader is
  written from this scope, not copied from the harness.
