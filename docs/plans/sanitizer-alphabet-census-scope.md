# Per-character sanitizer census (#672): scope, frozen before the run

> **Status:** `shipped` · **As of:** 2026-11-11

**Issue:** Joseph-Cursio/SwiftInferProperties#672. **Run 2026-11-11; result DECLINE law 2 (count: E2 = 4), law 1
held**, in `docs/measurements/sanitizer-alphabet-census.md`.

## 0. The question, and what this decides

#672 shows that SwiftUMLBridge's `ERScript.sanitizeType`, a per-character keep-or-replace sanitizer, gets only
`idempotence`, and that F3's recorded `SwapTernary` survivor at L178 passes it
(`docs/measurements/roadtest-swiftumlstudio-mutation.md`). It proposes two laws, read by one shared reader:

- **Law 2, output alphabet:** every character of `f(x)` satisfies the keep predicate `P`, or is a character of a
  literal the body emits (the replacement, the fallback, an in-alphabet prefix). This would be a new
  `rewrite-postcondition` arm (`docs/measurements/rewrite-postcondition.md`).
- **Law 1, fixed point:** `x ∈ Safe ⟹ f(x) == x`. `docs/measurements/replacement-chain-idempotence-census.md`
  holds this law "until it has more than ten subjects". #672 respects that hold.

#672's kill evidence is a Python replica, not a run. Its population is a grep estimate with every hit hand-read:
6 law-2 subjects (5 callable, 3 of those in SwiftProjectLint) and 3 law-1 subjects. Its gate:
- measure the reader over the universe `rewrite-postcondition.md` used;
- hand-check every row;
- build law 2 if the count is of the order of 6.

**This scope runs the kill arm and the census, and decides law 2 under the rule in §7.** It reports law 1
against its standing hold. A build, if one is decided, is filed separately.

Everything below is fixed before the harness reads any subject other than the named controls. Any later change is
an amendment, appended with its date and reason.

## 1. Step 1: the kill arm

### 1.1 The subject

`ERScript.sanitizeType(_:)` (SwiftUMLStudio,
`SwiftUMLBridge/Sources/SwiftUMLBridgeFramework/Emitters/ERScript.swift`) is copied verbatim into
`fixtures/sanitizer-alphabet/kill-arm/`. The function body is identical at `e36da59` (the mutation run's, lines
169–179) and `9ad7631` (HEAD on 2026-11-11, lines 158–168), though the file around it has changed. Anchors mark
the keep test (L172), the verbatim append (L173) and the fallback (L178).

### 1.2 The laws

Every law runs 100 trials on one fixed seed, as the stub does.

- **Idempotence:** `f(f(x)) == f(x)`. It draws from the edge-biased `String` expression with the subject's
  literals `["_", "Unknown"]`, the generator `RawType.edgeBiasedGeneratorExpression(subjectTokens:)` spells.
  This is the control row.
- **Law 1:** `x ∈ Safe ⟹ f(x) == x`. `Safe` is drawn directly: non-empty strings of ASCII letters, digits and
  `_`, length 1–8. `Safe` excludes `""` because of the `isEmpty ? "Unknown" : …` fallback.
- **Law 2:** every scalar of `f(x)` is in `CharacterSet.alphanumerics` or is `_`. The `"Unknown"` fallback is
  inside that alphabet. It draws from the same edge-biased expression as idempotence, which supplies the
  forbidden characters (`" "`, `"-"`, `":"`, `"#"`, `"/"`, `"\n"`, `"\t"`).

### 1.3 The mutants

These are the five mutants #672 confirmed swift-mutation-testing `3be0c11` generates in this function, applied by
text edit:

1. **`NegateConditional` (L172):** `if !(CharacterSet.alphanumerics.contains(scalar) || scalar == "_")`;
2. **`||` → `&&` (L172);**
3. **`==` → `!=` (L172):** `scalar != "_"`;
4. **`RemoveSideEffects` (L173):** the append deleted;
5. **`SwapTernary` (L178):** `return sanitized.isEmpty ? sanitized : "Unknown"`.

### 1.4 What is counted, and what is predicted

The result is a 6 variants × 3 laws matrix. **Control:** the original passes every law, or the arm is void.

**Prediction (#672's replica, REASONED):**
- **Idempotence** kills `RemoveSideEffects`. It kills `NegateConditional` and `||` → `&&` only if the seed draws
  `""` (the replica puts the chance of that at about 0.997 per run). It never kills `==` → `!=` or `SwapTernary`.
- **Law 1** kills `NegateConditional`, `||` → `&&`, `RemoveSideEffects` and `SwapTernary`.
- **Law 2** kills `NegateConditional` and `==` → `!=`.
- **Laws 1 and 2 together** kill all five.

The arm decides nothing.

## 2. The unit, and the reader

The unit is every `func` with a body in a universe file (§3), nested ones included.

### 2.1 Shape

The function has exactly one parameter, of type `String` (any label, not `inout`), returns `String`, and is not
`async`, `throws`, `rethrows` or `mutating`. Static and free functions can be candidates. Instance methods are read
and recorded, but are never candidates.

### 2.2 The reader `R`

`R` reads the body as `pre* core post? return`.

**Pre-steps**, zero or more `let` statements of two kinds:
- **pre-transforms:** `let y = X`, where `X` is the parameter or an earlier pre-transform binding, followed by a
  chain of calls from the allowlist `lowercased()`, `uppercased()`, `trimmingCharacters(in: …)`;
- **local sets:** `let s: Set<Character> = …` or `let s = …`, initialised by a `Set` array or string literal
  (`Set("…")`, `["a", "b"]`), `CharacterSet(charactersIn: LIT)`, a `CharacterSet` static, or a `.union(…)` of
  those. These are copied into the stub.

**The input `X`** of the core is the parameter or a pre-transform binding, optionally followed inline by
allowlisted pre-transform calls (`text.lowercased().filter { … }`). It is optionally viewed as `.unicodeScalars`.

**Core**, one of:
- **F1, loop:**
  - `var acc = ""` (or `String()`), then exactly one `for c in X` loop with no `where`;
  - the loop body is exactly one `if P(c) { A } else { B }`, where the `else` is optional;
  - `A` is a verbatim append of `c`: `acc.append(c)`, `acc.unicodeScalars.append(c)`, `acc += String(c)` or
    `acc.append(Character(c))`;
  - `B` appends a string or character literal (`acc += LIT`, `acc.append(LIT)`).
- **F2, map:** `String(X.map { P($0) ? $0 : LIT })`. The closure may name its parameter, carry a signature
  (`c -> Character in`) and have one expression statement.
- **F3, filter:** `X.filter { P($0) }`, or `String(X.unicodeScalars.filter { P($0) })` and its
  `String(String.UnicodeScalarView(…))` spelling. Key-path predicates (`.filter(\.isLetter)`) are admitted.

F2 and F3 may be returned directly, or bound to `var acc =` / `let acc =`.

**Post-step**, at most one, a prefix rule: `if <condition reading only acc> { acc = LIT + acc }`. An `if let` on
`acc.first` is allowed.

**Return:** `acc`, the F2/F3 expression itself, or `acc.isEmpty ? LIT : acc`.

**`P`** is a boolean combination (`||`, `&&`, `!`, parentheses) of these atoms over the element:
- `CharacterSet.s.contains(c)` or `.s.contains(c)`, with an optional `.inverted`;
- `s.contains(c)` for a local set `s`;
- `c.isLetter`, `c.isNumber`, `c.isASCII`;
- `c == LIT`, `c != LIT`.

Each row records whether `P` uses only #672's spelling (`||` and `!`). A `P` that names anything else (instance
state, a helper call, another property) is refused as `predicate: other`.

**Refusals:** anything outside this grammar is refused with the first reason found:
- `shape`;
- `pre: other`;
- `core: none`;
- `core: other statement in loop`;
- `predicate: other`;
- `post: other`;
- `return: other`.

**Recall pool.** Every shape-passing function whose body text mentions `CharacterSet`, `isLetter`, `isNumber`,
`isASCII` or `alphanumerics` is recorded with `R`'s verdict, so refusals can be read and recall judged.

### 2.3 The two laws, per admitted row

- **Law 2 reads** every row `R` admits. It states `P ∪ characters(literals)`, where the literals are the else
  literal, the F2 replacement, the prefix literal and the fallback.
- **Law 1 reads** an admitted row only when it has no pre-transform and no prefix rule. `Safe` is
  `{ x : every element satisfies P }`, minus `""` when there is a fallback.

### 2.4 Emittable

A row is emittable when all of these hold:
- it is static or free;
- neither it nor any enclosing declaration is `private` or `fileprivate`;
- it is not an actor member, and not nested in a function;
- it is not in an executable target (hand-checked, §5).

## 3. The universe, frozen

The universe is #670's (`docs/plans/count-threshold-boundary-census-scope.md` §3), the same one
`docs/plans/dedupe-count-law-census-scope.md` used:
- the 20 manifest corpora, asserted against `count_threshold_census.FROZEN_MANIFEST`;
- the 19 funnel repositories, with files under a `Sources` path component;
- **plus this repository's whole `Sources/`**, read last, so `swift-infer-core`'s files stay attributed to it.

#672's two in-repo subjects are in `Sources/SwiftInferCLI`. The decision is taken on the whole universe. Counts
without this repository's `Sources/` (the universe `rewrite-postcondition.md` used) are reported beside it.

## 4. Controls, asserted before the run

| control | source | expected |
|---|---|---|
| `sanitizeType` | SwiftUMLStudio `ERScript.swift`, verbatim | F1, fallback, law 1 + law 2, candidate |
| `moduleIdentifier(from:)` | `Sources/SwiftInferCLI/InteractiveTriage+StubFile.swift`, verbatim | F2, local `Set("…")`, law 1 + law 2, candidate |
| `sanitizeForFileName(_:)` | `Sources/SwiftInferCLI/InteractiveTriage+StubName.swift`, verbatim | F2, law 1 + law 2, not a candidate (private) |
| `alphanumericsOnly(_:)` | SwiftProjectLint `SecurityVisitor.swift`, verbatim | F3, inline `lowercased()`, law 2 only, candidate |
| `c99Identifier(_:)` | SwiftProjectLint `PackageManifest.swift`, verbatim | F2 bound to `var`, prefix rule, law 2 only, candidate |
| key-path filter | `func lettersOnly(_ s: String) -> String { s.filter(\.isLetter) }` | F3, law 1 + law 2 |
| helper predicate | `func clean(_ s: String) -> String { s.filter { isAllowed($0) } }` | refused, `predicate: other` |
| instance state | `struct S { let allowed: Set<Character>; func clean(_ s: String) -> String { s.filter { allowed.contains($0) } } }` | refused, `predicate: other` |
| decoration | `func suite(_ s: String) -> String { s.filter(\.isLetter) + "Tests" }` | refused |
| split/join | `func slug(_ s: String) -> String { s.components(separatedBy: CharacterSet.alphanumerics.inverted).joined(separator: "-") }` | refused, `core: none` |
| token wrapping | a loop whose else branch appends `"\"" + String(c) + "\""` | refused |
| prefix cap | `func short(_ s: String) -> String { String(s.filter(\.isLetter).prefix(8)) }` | refused |
| instance method | `struct T { func clean(_ s: String) -> String { s.filter(\.isLetter) } }` | admitted, not a candidate |

`python3 scripts/sanitizer_alphabet_census.py controls` asserts the frozen universe: 20 manifest roots resolve, 19
funnel roots exist, and this repository's `Sources/` exists.

## 5. The hand-check

Every admitted row is read by hand. Each gets these verdicts:
- **law2:** law 2 is true as read;
- **law1:** law 1 is true as read, where it reads;
- **predicate:** `P` and the literals were read right;
- **emittable:** for a candidate, including the executable-target check.

A row that fails **law2** or **predicate** is a reader defect. It is named, and it does not count.

## 6. Predictions, frozen

- **Step 1:** as §1.4.
- **E2:** about 5: `sanitizeType`, `moduleIdentifier`, `alphanumericsOnly`, `NameListReader.normalize`,
  `c99Identifier`. SwiftProjectLint holds 3 of the 5.
- **E1:** 3 or fewer (`sanitizeType`, `moduleIdentifier`, plus the private `sanitizeForFileName` admitted but not
  emittable).
- **The decision:** DECLINE law 2 on concentration. Law 1 stays held.

## 7. The decision, fixed now

Let **E2** be the law-2 rows that are emittable and pass the hand-check. Let **E1** be the law-1 rows that are
emittable and pass the hand-check.

- **BUILD law 2** when `|E2| ≥ 5` and no repository holds more than half of E2. A build issue is filed for a new
  `RewritePostcondition.Guarantee` arm, and #672 stays open.
- **DECLINE law 2** otherwise. #672 is closed as not planned, with the counts.
- **Law 1** stays HELD unless `|E1| > 10`, the census's own line. It is reported here, not decided. If it
  clears, that is recorded as a reopening candidate for the maintainer.

The kill arm does not enter the decision.

## 8. What this does not answer

- **Split-then-join sanitizers** (SwiftAssist's five, by #672's count) are outside the reader by design.
- **Injectivity of a sanitizer** is collision-dependent; that is #674.
- **Whether one recorded kill earns law 1 below ten rows.** #672 leaves this to the maintainer, and so does this
  scope.
- **Unicode reach.** The kill arm draws ASCII. An edit narrowing `.alphanumerics` to ASCII would pass under those
  draws.

## 9. Disclosures before the freeze

- **The five named controls were read before this freeze.** They are #672's own subjects, read to state their
  expectations. No other subject was read.
- **The reader is broader than #672's in one way:** `P` may use `&&`. Each row records whether it does, and a row
  that needs `&&` is reported separately in the write-up.
- **The reader is a prototype in the harness.** If the decision is BUILD, the shipped reader is written from this
  scope.
