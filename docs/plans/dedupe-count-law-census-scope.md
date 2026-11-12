# Dedupe count-law census (#671): scope, frozen before the run

> **Status:** `proposed` · **As of:** 2026-11-11

**Issue:** Joseph-Cursio/SwiftInferProperties#671.

## 0. The question, and what this decides

#671 shows that `discover` recognises a dedupe by name and can run only idempotence on one. Idempotence holds of
the identity and of every constant function, and those are what the two simplest dedupe bugs produce. Three
SwiftUMLBridge mutants of `CoreDataModelExtractor.dedupe(relationships:)` pass the generated law, while the
hand-written suite kills all three (`docs/measurements/roadtest-swiftumlstudio-mutation.md`, F3).

It proposes two count laws for a dedupe-role `f: [T] -> [T]`, gated on **name and body, never the name alone**:

- **C1** `xs.allSatisfy { f([$0]).count == 1 }`: a singleton survives;
- **C2** `f(xs + xs).count == f(xs).count`: a duplicate of everything adds nothing.

Its *Measure before building* fixes the order:
1. a hand-written kill arm (§1);
2. a name-and-body census (§2–§5);
3. an explicit tier decision (§7).

**This scope covers all three and the decision.** A build, if one is decided, is filed separately, as #692 was
for #669.

Everything below is fixed before the harness reads any subject. Any later change is an amendment, appended with
its date and reason.

## 1. Step 1: the kill arm

### 1.1 The subject

`CoreDataModelExtractor.dedupe(relationships:)` (SwiftUMLStudio,
`SwiftUMLBridge/Sources/SwiftUMLBridgeFramework/Parsing/CoreDataModelExtractor.swift:154`) is copied verbatim
into `fixtures/dedupe-count-law/kill-arm/`. `ERRelationship` and `ERCardinality` come from `Model/ERModel.swift`.
The function is identical at `e36da59` (the mutation run's) and `9ad7631` (HEAD on 2026-11-11), so there is one
revision.

### 1.2 The generator

The generator is what the stub would draw, written out by hand:
- `ERRelationship` memberwise;
- each `String` field is `Gen<Character>.letterOrNumber.string(of: 0...8)`;
- `inverseLabel` is that generator `.optional`;
- each cardinality is one of its four cases, uniformly. This is the kit's `.enumCases` strategy;
  `DerivationStrategy` prefers it to the raw-value filter, which never terminates for this enum (raw values of
  9–10 characters, drawn from 0–8).
- the array is `.array(of: 0...8)`, the kit's `GeneratorPlan` rendering of `[T]`.

The seed is fixed, with 100 trials per law.

### 1.3 The laws

- **C1** and **C2**, as in §0.
- **Idempotence**, `f(f(xs)) == f(xs)`, the law the run scored. This is the control row.
- **A sanity case**, not a law: the Bookstore shape, Author→Book `books`/`author` plus its inverse Book→Author.
  The correct code must return one relationship, and must pass C1 and C2 on it.

### 1.4 The mutants

The mutants are applied by text edit to anchored lines:

1. **L162** `seen.insert(key)` deleted: the function becomes the identity;
2. **L161** `!seen.contains(key)` negated to `seen.contains(key)`: the function returns `[]`;
3. **L163** `result.append(relationship)` deleted: the function returns `[]`.

### 1.5 What is counted, and what is predicted

The result is a 4 variants × 3 laws matrix, each cell PASS or FAIL. **Control:** the original passes every law
and the sanity case, or the arm is void.

**Prediction (#671's, REASONED):**
- C1 kills L161 and L163.
- C2 kills L162. On duplicate-free draws the identity mutant agrees with the correct code, so only C2's
  self-made duplicate exposes it.
- Idempotence kills none.

The arm cannot fail by construction, so it decides nothing. It turns the REASONED rows into MEASURED ones.

## 2. The unit, and the gates

The unit is every `func` declaration with a body in a universe file (§3), including methods, nested functions
and extension members. The harness reads each one with SwiftSyntax. `FunctionScanner.scanCorpus` is joined by
file and line, for whether the function is in the shipped scan.

### 2.1 Name family (stage 0, for the funnel only)

A function is in the **name family** when its name, lowercased, starts with `dedup`, `uniqu`, `distinct`,
`removingduplicate` or `removeduplicate`. This is #671's grep, done on syntax. Only its count is reported.

### 2.2 The name gate

Split the name into camel-case words. The name passes when it starts with one of these stems, as whole words:

| stem | words |
|---|---|
| `dedupe` | `dedupe` |
| `deduplicate` | `deduplicate` |
| `deduplicated` | `deduplicated` |
| `deduped` | `deduped` |
| `uniqued` | `uniqued` |
| `uniquing` | `uniquing` |
| `removingDuplicates` | `removing`, `Duplicates` |

What follows the stem must be either nothing or a tail starting with `By` (`By<Key>`, as in
`dedupedByStateAndAction`). A tail containing `Adjacent` or `Consecutive` revokes the role. Any other tail
(`dedupeRelationships`) is refused as `name: other tail` and counted. This is conservative: it under-counts
rather than guessing what a tail means.

`FilterSubsetTemplate.nameAnnouncesASecondOperation` is **not** used, as #671 says: it would reject
`dedupedByStateAndAction`.

Each row also records **recognised today**:
- exactly `dedupe` (`FixedPointNames.curated`);
- or exactly `deduplicate` / `deduplicated` (`IdempotenceTemplate.curatedVerbs`).

### 2.3 The shape gate

A function passes the shape gate in one of two forms:
- **parameter form:** exactly one parameter, of type `[T]` (or `Array<T>`), and a return of `[T]` with the same
  `T` by text;
- **receiver form:** no parameters, declared in an `extension Array`, `extension Sequence` or
  `extension Collection`, returning `[Element]`.

In both forms the function is not `mutating`, `throws`, `rethrows` or `async`, and has no `inout` parameter.
The parameter's label must not be a key-closure label (`on`, `by`, `using`, `keyPath`). Any other label, or
`_`, names the input and keeps the role.

A second parameter of any kind fails the shape gate. That excludes key closures (`dedupe(_:by:)`) and two-array
forms.

### 2.4 The body gate

Let `in` be the parameter (parameter form) or `self` (receiver form). The body passes by one of two routes, and
fails with a named reason otherwise.

**Set route (keep-first).**
- A local `var s` is initialised as a `Set` (`Set<…>()`, `: Set<…> = []`, or `= Set<…>()`).
- The result is built in one of two ways:
  - **loop:** a local `var r` initialised to an empty array, and exactly one `for x in in` loop. The final
    statement returns `r`.
  - **filter:** the body returns `in.filter { s.insert(k).inserted }`, the closure's sole expression being
    the insert. The closure's parameter may be named or `$0`.
- In the loop, every `r.append(x)` appends the loop variable, and is reached only through a successful insert,
  in one of three forms:
  - `if s.insert(k).inserted { … }`;
  - `if !s.contains(k) { s.insert(k); … }`, where the insert is in the same branch;
  - `guard s.insert(k).inserted else { continue }` before it.
- The loop may also contain `let` bindings (the key's computation) and nothing else that skips. Every
  `continue` must be that guard's.

**Dictionary route (canonical representative, not keep-first).**
- A local `var d` is initialised as a dictionary (`[K: V] = [:]`, or `[K: V]()`).
- There is exactly one `for x in in` loop, and the final statement returns `Array(d.values)`.
- In the loop:
  - the only writes are `d[k] = x`, with `x` the loop variable;
  - every `continue` sits under an `if` whose condition reads `d[k]` (key presence, possibly conjoined, as in
    `if let kept = d[k], kept.p < x.p { continue }`);
  - the loop may contain `let` bindings and nothing else.

⚠ **This refines #671's "a dictionary written once per key".** #671's own canonical-representative example,
`ConstructionUniverse.deduplicated`, overwrites a key when a later member has a smaller path. What the count
laws need is that every element's key ends with an entry and the result is one value per key. A skip guarded by
key presence keeps that property; a write per element is allowed.

**Both routes:**
- No `return` other than the final statement. An early `guard … else { return … }` refuses.
- No `throw`.
- No other `append` to `r`.
- No other statement that mutates `r` or `s`/`d`.

A body that matches neither route is refused, with the first reason found:
- `body: no set or dictionary local`;
- `body: append not behind an insert`;
- `body: early return`;
- `body: other skip`;
- `body: unread form`.

### 2.5 Admitted, and emittable

A function is **admitted** when it passes the name, shape and body gates.

An admitted function is an **emittable candidate** when the syntax shows all of the following:
- it is not `private` or `fileprivate`, and neither is any enclosing type;
- it is not an `actor` member;
- its element type is concrete: not a generic parameter of the function or of any enclosing declaration, and,
  in receiver form, not an unconstrained `Element`. Receiver-form rows are therefore never candidates. Generic
  receivers need a concrete element type (#493).

The **hand-check** (§5) settles the rest: the element generator derives, and the file is not in an executable
target.

## 3. The universe, frozen

- **#670's universe, unchanged** (`docs/plans/count-threshold-boundary-census-scope.md` §3):
  - the 20 manifest corpora `measurement.corpus_roots()` resolves, asserted against
    `count_threshold_census.FROZEN_MANIFEST`;
  - plus the 19 funnel repositories in `budgeted_truncation_census.FUNNEL`, with `.swift` files under a
    `Sources` path component.

  It uses the same skip rules: hidden directories, `.build`, `checkouts`, test directories, `fixtures`
  (except where a manifest corpus is a fixture), and `.swiftinfer`. The funnel includes SwiftUMLStudio.
- **Plus this repository's whole `Sources/`**, as #671 asks ("this repo's other library targets"). The
  `swift-infer-core` corpus already covers `Sources/SwiftInferCore`. A file is read once, keyed by its resolved
  path.
- **Revisions:** each root's `git rev-parse HEAD` and dirty state are recorded in the subject list.

## 4. Controls, asserted before the run

The harness's control mode runs these on in-memory sources. The run refuses to start if any fails.

| control | source | expected |
|---|---|---|
| `dedupe(relationships:)` | §1.1, verbatim | admitted, Set route, keep-first, recognised today, candidate |
| `deduplicated(_:)` | `ConstructionUniverse.swift:256`, verbatim | admitted, dictionary route, not keep-first, recognised today, candidate |
| `dedupedByStateAndAction(_:)` | `SwiftInferCommand.DiscoverInteraction+MultiModule.swift:129`, verbatim | admitted, Set route (`insert(_:).inserted`), not recognised today, candidate |
| `dedupedByIdentity(_:)` | `SwiftInferCommand.Discover+IdentityDedup.swift:65`, verbatim | refused, `body: early return` |
| filter form | `func uniqued(_ xs: [Int]) -> [Int] { var seen = Set<Int>(); return xs.filter { seen.insert($0).inserted } }` | admitted, Set route, keep-first |
| `uniquingAdjacentElements()` | a receiver-form method of that name | refused at name (revoking tail) |
| key closure | `func dedupe(_ xs: [Int], by key: (Int) -> Int) -> [Int]` | refused at shape (second parameter) |
| two arrays | `func deduplicated(_ a: [Int], _ b: [Int]) -> [Int]` | refused at shape |
| filters too | the Set loop with `guard x > 0 else { continue }` first | refused, `body: other skip` |
| pass-through | `guard let id = x.id else { result.append(x); continue }` in a Set loop | refused, `body: append not behind an insert` |
| extra append | a Set loop that also appends after the loop | refused, `body: append not behind an insert` |
| other tail | `func dedupeRelationships(_ xs: [Int]) -> [Int]`, with a correct Set body | refused, `name: other tail` |
| private | `private static func deduped(_ xs: [Int]) -> [Int]`, with a correct Set body | admitted, not a candidate |
| generic | `func deduped<T: Hashable>(_ xs: [T]) -> [T]`, with a correct Set body | admitted, not a candidate |

`python3 scripts/dedupe_count_law_census.py controls` asserts the frozen universe: 20 manifest roots resolve, 19
funnel roots exist, and this repository's `Sources/` exists.

## 5. The hand-check

Every admitted row is read by hand against its source. Each gets these verdicts:

- **c1** and **c2**: whether the law is true of today's code, read from the body. A dedupe that merges or picks
  a canonical representative still has to satisfy the count laws.
- **equatable**: whether `T: Equatable` is established. That makes C2's equality form,
  `f(xs + xs) == f(xs)`, available.
- **keepFirst**: whether the result is in input order. This licenses the subsequence law.
- **emittable**, for a candidate:
  - not in an executable target;
  - the element type's generator derives, judged against `DerivationStrategy`'s order (memberwise, init,
    case enumeration);
  - a stub can call it, under the visibility the funnel runs use.

A row that fails **c1** or **c2** is a gate defect. It is named, and it does not count.

## 6. Predictions, frozen

- **Step 1:** as §1.5.
- **Name family:** under 40 functions across the universe.
- **Admitted:** under 10.
- **E (§7):** 2 or 3:
  - SwiftUMLBridge's `dedupe`;
  - `ConstructionUniverse.deduplicated`, if `Member`'s generator derives (it holds a `URL`, which is doubtful);
  - `dedupedByStateAndAction`, if `ReducerCandidate`'s does.
- **The decision:** ATTACH, with A = {`dedupe`} or {`dedupe`, `deduplicated`}.

## 7. The decision, fixed now

Let **E** be the admitted rows that are emittable candidates and pass the hand-check (§5) in full.

- **BUILD** when `|E| ≥ 5` and no repository holds more than half of E.
  - A dedupe-role template is filed, with C1 and C2, the equality form of C2 where `Equatable` is established,
    and subsequence only on keep-first bodies.
  - It is placed in `Refutability.roleEntailedTemplates`. That is filter-subset's bar: a correct dedupe cannot
    fail C1 or C2, and §1 measures whether they catch the no-op and drop-all bugs.
  - #671 stays open until the build lands.
- **ATTACH** otherwise, when **A**, the rows of E that are recognised today (§2.2), is not empty.
  - A small build is filed: emit C1 and C2 beside the idempotence law on exactly the rows that a recognised
    name proposes and that pass the body gate.
  - #671 stays open until it lands.
- **DECLINE** otherwise, when A is empty. #671 is closed as not planned, with the counts.

The kill arm does not enter the decision.

## 8. What this does not answer

- **A wrong key.** `xs + xs` collides under any key, so neither law sees it (#671).
- **Whether the idempotence law on `ConstructionUniverse.deduplicated` is false of correct code**, because two
  `Array(byKey.values)` calls may order differently. #671 calls this REASONED, and it stays REASONED here.
- **Precision of a built template over a wider population.** This census bounds population; it does not test a
  shipped template.
- **swift-algorithms' `uniqued()`.** It returns `UniquedSequence`, which is out of shape, and is not checked out.

## 9. Disclosures before the freeze

- **Three of the controls are this repository's own code**, and so are in the universe. They are expected to
  appear among the rows. They are controls of the gate, not evidence for the decision; they count toward E only
  if they pass the hand-check like any other row.
- **The census universe is #670's plus one repository.** Its function count is reported, not reconciled with
  #670's 31,016 (or the 31,022 of `docs/measurements/guard-domain-syntax-gate.md`).
- **The gates are a prototype in the harness.** If the decision is BUILD or ATTACH, the shipped gate is written
  from this scope, not copied from the harness.
