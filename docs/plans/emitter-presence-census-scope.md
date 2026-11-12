# Emitter presence census (#673): scope, frozen before the run

> **Status:** `shipped` · **As of:** 2026-11-12

**Issue:** Joseph-Cursio/SwiftInferProperties#673. **Run 2026-11-12; result DECLINE (concentration: E = 14, 9 in this
repository; precision 75.6%)**, in `docs/measurements/emitter-presence-census.md`.

## 0. The question, and what this decides

#673 counts 39 `RemoveSideEffects` mutants in SwiftUMLBridge. Each one deletes the per-element `append` inside an
emitter's `for` loop (`docs/measurements/roadtest-swiftumlstudio-mutation.md`, F5 and F6).
- **Generated laws executed none of them.**
- **Two survive the hand-written suite as well:**
  - `ComponentScript.swift:82`, the Mermaid interface line;
  - `SyntaxStructure+PlantUML.swift:220`.

It proposes a **presence law read from the body**. Each element the loop visits owes its line in the output. The
law states that line as the element's interpolation **together with the literal text the body writes around it**,
not as bare `contains(name)`. Like `guard-domain` and `rewrite-postcondition`, it is a characterisation law: it
holds by construction, and what it catches is an edit.

**Its evidence is thin.**
- The kills are REASONED.
- The population is an uncommitted grep estimate:
  - 16 functions in SwiftUMLBridge;
  - 28 in this repository;
  - 19 in the other 17 roots.
- Reach is counted, not run.

**Its gate:**
- freeze a prediction and a precision bar;
- count with a real reader;
- put reach into the prediction.

**This scope runs a kill arm (§1) and the census (§2–§5), and decides under the rule in §7.** A build, if one is
decided, is filed separately. The dispatch-arm lift #673 describes is not part of this scope. Like the lift, the
build would get its own measurement.

Everything below is fixed before the harness reads any subject other than the named controls. Any later change is
an amendment, appended with its date and reason.

## 1. Step 1: the kill arm

### 1.1 The subject

The subject is copied verbatim from SwiftUMLStudio `e36da59`, the mutation run's revision, into
`fixtures/emitter-presence/kill-arm/`. It is `ComponentScript.swift`'s:
- `buildPlantUMLText(model:)`;
- `stereotypeText(for:)`;
- `buildMermaidText(model:)`;
- `safeAlias(_:)`.

The four model types it reads come from `ComponentModel.swift` and the shared `ComponentKind`: `ComponentModel`,
`Component`, `ComponentDependency` and `ComponentKind`.

Anchors mark the nine lines the run mutated:

| anchor | line | kind |
|---|---|---|
| L48 | `component "…" as … {` | element line |
| L50 | `  [interface]` | element line |
| L52 | `}` | frame line |
| L55 | `from ..> to` | element line |
| L57 | `@enduml` | frame line |
| L80 | `    subgraph alias["name"]` | element line |
| L82 | `        alias["interface"]` | element line; survives both suites |
| L84 | `    end` | frame line |
| L87 | `    from -.-> to` | element line |

### 1.2 The mutants

There are 9 `RemoveSideEffects` mutants, one per anchor. They are applied by anchored text edit, as recorded in
`fixtures/mutation-check/roadtest-swiftumlstudio-2026-10-10.jsonl`.

### 1.3 The laws

Every law runs over both builders, with 100 trials on one fixed seed, as the stub does.
- **Determinism:** `f(m) == f(m)`. This is the advisory the run gave these builders, and it is the control.
- **Bare presence:** every component name, interface name and dependency endpoint the loops visit occurs in the
  output.
- **Template presence, #673's law:** every obligation `R` (§2) reads from the original body holds. For each loop
  element, the output contains the element's interpolated text joined with the adjacent literal run, cut at any
  interpolation that is not element text (the stereotype).
  - Example: `"  [\(interfaceName)]"` for L50.
  - Example: `"component \"\(name)\" as \(safeAlias(name)) "` for L48.
  - The encoder `safeAlias` is called, as #673's sketch calls it.

### 1.4 The generators

Each law runs under two generators.
- **Naïve, the run's stub:**
  - names drawn from `letterOrNumber.string(of: 0...8)`;
  - `array(of: 0...8)` for every collection;
  - dependency endpoints drawn independently of the component names.
- **#673's stub requirements:**
  - **component names:** `C` plus 4–8 lowercase letters;
  - **interface names:** `I` plus 4–8 lowercase letters;
  - **no name is a substring of another;**
  - **collection sizes:** components 1–4, interfaces 0–3 (non-empty in most draws);
  - **dependency endpoints:** drawn from the drawn component names.

### 1.5 What is counted, and what is predicted

The result is a 10 variants × 3 laws × 2 generators matrix. **Control:** the original passes every law under both
generators, or the arm is void.

**Prediction (REASONED from the bodies):**
- **Template presence under #673's generator** kills all 6 element-line mutants and none of the 3 frame-line
  mutants.
- **Bare presence under #673's generator** misses L80, because the component name recurs in L82's alias and in the
  edge lines. It also misses L48, because the name recurs in the alias and edge lines and the PlantUML interface
  line does not name the component. It kills L50, L55, L82 and L87.
- **The naïve generator loses kills.**
  - Empty names are frequent.
  - One-character names occur in the boilerplate.
  - Edges reach a drawn component only by collision.

  Under it, template presence kills strictly fewer than under #673's generator, or the same.
- **Determinism** kills 0.

The arm decides nothing (§7).

## 2. The unit, and the reader

The unit is every `func` with a body in a universe file (§3), nested functions included.

### 2.1 Shape

- The function returns `String` or `[String]`.
- **W2:** a `String?` return is recorded as a widening. It is read by the same reader and reported separately.
- It is not `async` and not `mutating`.
- It may be free, static or an instance method, and may throw.

### 2.2 The accumulator

The returned value must be a local `var acc` declared at the top level of the body with one of these initialisers:
- a string literal, including `""`;
- `String()`;
- an array literal of string literals, including `[]` annotated `[String]`;
- `[String]()`.

**The return**, at every `return` and as the last statement, is one of these, optionally followed by `+ LIT`:
- `acc`;
- `acc.joined()`;
- `acc.joined(separator: LIT)`.

An early `return LIT` before the first loop (a `guard … else { return "" }`) is allowed.

### 2.3 Loops and their sources

A loop `for PATTERN in S` is **qualifying** when `S` is a **parameter path**. That means one of:
- an identifier that names a parameter, followed by zero or more member accesses and no calls;
- `self.a.b`;
- in an instance method, an identifier that is neither a parameter nor a local, read as an implicit `self` member.

`PATTERN` may be a name or a tuple of names. A `where` clause is a guard (§2.5).

**Refused as a source:**
- a String or its views: `S` ending in `.unicodeScalars`, `.utf8`, `.utf16` or `.characters`, or `S` the parameter
  itself when it is typed `String`;
- a loop variable named `c`, `ch`, `char`, `character` or `scalar`.

**W1, widening:** `S` is a local `let l = P.op` or an inline `P.op`, where `P` is a parameter path and `op` is
`.sorted(…)`, `.enumerated()` or `.filter { … }`. A filter is read as a guard. These rows are recorded and
reported, and are not admitted.

**Every other source** (a local, a call result, a `Set`) is refused as `source: other`.

A loop nested inside a qualifying loop qualifies when its source is a path from a name the outer loop tracks (§2.4),
for example `for i in component.providedInterfaces`. Its obligations carry both quantifiers.

### 2.4 Obligations

Inside a qualifying loop, the **tracked names** are:
- the loop's pattern names;
- every loop-local `let` whose initialiser reads a tracked name.

A tracked name is *element text* when its initialiser is one of:
- a tracked path;
- a one-argument call on one (an **encoder**, such as `safeAlias(component.name)`);
- a string literal built from them.

Any other tracked `let` is **opaque**. So is any `var` assigned inside the loop.

Every **accumulation** of the accumulator inside the loop is a candidate obligation if its argument reads a
tracked name. An accumulation is one of:
- `acc.append(X)`;
- `acc.append(contentsOf: X)`;
- `acc += X`.

`X` is read as a sequence of pieces. A string literal's segments are pieces; a `+` chain's operands are pieces; an
array literal's elements are read one by one. Each piece is one of:
- **literal text;**
- **element text:**
  - an interpolation of a tracked path;
  - an element-text name;
  - an encoder call on either;
- **a cut:** any other interpolation, such as an opaque name, a parameter or a helper's output.

The obligation is classified as one of:
- **primary:** the line has element text, and the run around it (extended through literal text and further element
  text, stopping at cuts) holds non-whitespace literal text. There are no cuts.
- **segment:** as primary, but the line has a cut. The kept run is the longest run that does not cross a cut. If
  the kept run holds no non-whitespace literal text, the obligation is **refused**.
- **bare:** the element text has no adjacent literal (`acc.append(e.name)`). Recorded, not statable.
- **helper:** `X`, or a piece of it, is a call that takes a tracked name or path as an argument and is not an
  encoder. It is resolved as §2.6 describes.
- **call-guarded:** the accumulation sits under a guard that is not restatable (§2.5). Refused.

An accumulation through any other verb on the accumulator (such as `appendAsNewLine`) is **W3**. It is recorded and
never statable.

### 2.5 Guards and skips

A guard is restatable when it uses only:
- tracked paths and literals;
- `==`, `!=`, `<`, `<=`, `>`, `>=`;
- `!`, `&&`, `||`, parentheses;
- `.isEmpty`.

The following count as guards on the accumulations they dominate. Each is read into the obligation verbatim, or,
when not restatable, makes those accumulations **call-guarded**:
- a `where` clause;
- an `if` condition, with its negation for the `else` arm;
- `guard COND else { continue }`.

`if let` and `guard let` bind through a call or an optional, so they are never restatable.

**Row-level refusals:**
- `break`, `return` or `throw` inside any qualifying loop, outside nested closures;
- after the last qualifying loop, any accumulator statement other than an append of a literal;
  - this refuses `removeLast`, `removeAll`, `dropLast`, reassignment, `replacingOccurrences` and a `prefix`;
- a return other than §2.2's.

### 2.6 Helper hops

A helper call is resolved by base name and argument labels against every function declared in the same repository.
- **Unique match required.** No match, or more than one, leaves it **unresolved**.
- The argument that carries the tracked value is mapped to its parameter `q`.

The helper **writes** `q` when its body holds a string-building site whose pieces include `q`, a path of `q`, or a
member-access transform of either (`q.xmlEscaped`), with non-whitespace literal text adjacent. A string-building
site is one of:
- a string literal;
- a `+` chain;
- a run of consecutive `v = …` / `v += …` statements on one local `v`.

A loop inside the helper over a path of `q` gives nested obligations by the same rules.

The helper may instead pass `q` (or a path of it) on to a further helper. That is a second hop, resolved the same
way. **Nothing is followed past 2 hops.**

- A **transform** (`q.xmlEscaped`) is recorded on the obligation.
- A resolved helper obligation is **statable**.
- An unresolved one is refused. Examples: `stereotypeLabel(for: component.kind)`, which returns a fixed word, or a
  helper the index cannot find.

### 2.7 Admission and tiers

A function is **admitted** when all of the following hold:
- it passes shape (§2.1, W2 excluded);
- it passes the accumulator rule (§2.2);
- it has no row-level refusal;
- it has at least one statable obligation (primary, segment or resolved helper) from a qualifying, non-widened loop.

There is **one row per function**, carrying all of its obligations. Refused obligations are listed and dropped
from the law.

Each admitted row has a tier:
- **as-written:** every statable obligation is primary or segment;
- **helper:** at least one statable obligation is a resolved helper.

### 2.8 Emittable

An admitted row is an **emittable candidate** when the syntax shows all of the following:
- neither it nor any enclosing declaration is `private` or `fileprivate`;
- it is not an actor member, and not nested in a function;
- it is free or static, or an instance method (the receiver's generator is hand-checked).

**The hand-check (§5) settles the rest:**
- every parameter's generator derives, and the receiver's does for an instance method;
- the file is not in an executable target.

Generator derivation is judged by the rule `docs/plans/count-threshold-boundary-census-scope.md` §2.6 uses:
- a memberwise or synthesised init over derivable leaves, as `DerivationStrategist`'s strategies derive them;
- or a type with a generator already known (`String`, `Int`, standard collections of derivable elements, a
  `CaseIterable` enum).

A row that is admitted but private is **surfaced with widening advice**, and is never counted as a law.

### 2.9 Recall pool

Every shape-passing function whose body holds both a `for` loop and an `append` or `+=` is recorded with `R`'s
verdict and first refusal reason. Refusals can then be read and recall judged.

## 3. The universe, frozen

The universe is #670's (`docs/plans/count-threshold-boundary-census-scope.md` §3), the one
`docs/plans/dedupe-count-law-census-scope.md` and `docs/plans/sanitizer-alphabet-census-scope.md` also used:
- the 20 manifest corpora, asserted against `count_threshold_census.FROZEN_MANIFEST`;
- the 19 funnel repositories (`budgeted_truncation_census.FUNNEL`), with files under a `Sources` path component;
- **plus this repository's whole `Sources/`**, read last.

SwiftUMLBridge is in it as part of the SwiftUMLStudio funnel repository, at that checkout's revision. That is HEAD
`9ad7631`, not `e36da59`, and the subjects' revisions are recorded.

**The decision is taken on the whole universe.** Counts without this repository's `Sources/` are reported beside
it.

Helper hops (§2.6) resolve within the repository whose function is being read.

## 4. Controls, asserted before the run

The controls are compiled into the harness, which asserts them before reading the universe. The verbatim ones come
from SwiftUMLStudio `e36da59`.

| control | source | expected |
|---|---|---|
| `buildMermaidText(model:)` | `ComponentScript.swift`, verbatim | admitted, as-written; 3 primary obligations (component, interface nested, edge) |
| `buildPlantUMLText(model:)` | `ComponentScript.swift`, verbatim | admitted, as-written; component line segment (cut at `stereotype`), interface and edge primary |
| `renderSVG(_:)` | `ComponentSVGRenderer+SVG.swift`, verbatim, with `componentSVGLines`, `textElement` and `edgeSVGLine` | admitted, helper tier: edge obligation call-guarded; component obligation resolved at 2 hops (`componentSVGLines`, then `textElement`), transform `xmlEscaped` |
| `componentSVGLines(for:)` | same file, verbatim | admitted, helper tier, 1 hop (`textElement`); the stereotype line unresolved |
| `if let` guard | `for n in model.nodes { if let line = nodeLine(n) { lines.append(line) } }` | not admitted (call-guarded) |
| `where` guard | `for s in model.states where s.isFinal { lines.append("[*] <- \(s.name)") }` | admitted; guard `s.isFinal` |
| dedupe via `Set` | `let names = Set(model.edges.map(\.from)); for n in names { lines.append("node \(n)") }` | not admitted (`source: other`) |
| trailing `removeLast` | a primary loop, then `lines.removeLast()` | refused, row-level |
| `break` | a primary loop with `if lines.count > 9 { break }` | refused, row-level |
| scalar loop | `for scalar in text.unicodeScalars { out += "\(scalar)" }` | not admitted (source) |
| `appendAsNewLine` | `for m in model.members { out.appendAsNewLine("+ \(m.name)") }` | W3, not admitted |
| `sorted()` source | `for n in model.nodes.sorted() { lines.append("n \(n)") }` | W1, not admitted |
| bare append | `for n in model.names { lines.append(n) }` | not admitted (bare) |
| private builder | `private extension K { static func b(model: M) -> String { …primary loop… } }` | admitted, not an emittable candidate |

`python3 scripts/emitter_presence_census.py controls` asserts the frozen universe: 20 manifest roots resolve, 19
funnel roots exist, and this repository's `Sources/` exists.

## 5. The hand-check

Every admitted row is read by hand. Each gets these verdicts:
- **law:** the presence law as `R` states it is true of the code. A dedupe, escaping, truncation, skip or overwrite
  the reader did not see makes it false.
- **read:** the obligations, guards and helper hops were read right.
- **emittable:** for a candidate, the generators derive (§2.8) and the file is not in an executable target.

**Precision** = admitted rows passing both **law** and **read**, divided by all admitted rows. A row that fails
either is a reader defect. It is named, and it does not count toward E.

After the first hand-check, an adversarial pass of read-only checker agents re-reads every row's verdicts against
the source and tries to refute them. A refuted verdict is re-checked by hand. Any change is recorded in the
write-up under its own heading, not folded in silently.

## 6. Predictions, frozen

- **Step 1:** as §1.5.
- **Admitted:** about 40–70 rows.
- **Emittable candidates:** about 25–40.
- **E:** about 6–12. The main cut is model types whose generators do not derive.
- **Concentration:** this repository holds more than half of E, through its own CLI renderers.
- **Precision:** at least 70%. The body reader states what the body writes.
- **The decision:** DECLINE on concentration.

## 7. The decision, fixed now

**E** is the admitted rows that pass the hand-check's **law**, **read** and **emittable** verdicts. Both tiers
count. W1, W2 and W3 rows do not count.

- **BUILD** when all three hold:
  - `|E| ≥ 5`;
  - no repository holds more than half of E;
  - precision ≥ 70%.

  A build issue is filed for the reader, a `TemplateMatch` payload, the writer, and the stub requirements of §1.4
  plus a reach check. #673 stays open.
- **DECLINE** otherwise. #673 is closed as not planned, with the counts.

**The 70% bar** is `docs/measurements/whole-to-parts-partition-prediction.md`'s. The worst case of a wrong read is a
false law about correct code.

**What does not enter the decision:**
- the kill arm;
- the widenings' counts;
- the private rows surfaced with advice.

## 8. What this does not answer

- **The dispatch-arm lift.** Stating the law on the init whose `switch` arm calls a private builder contests
  `docs/measurements/lift-caller-reach.md`'s decline, and needs its own measurement.
- **The count form** ("n elements give n `<rect` lines"), and the per-iteration multiplier it would need.
- **`map { … }.joined()` emitters.** They are outside the reader by design.
- **`+=` mutants.** swift-mutation-testing generates none, so the run measured nothing on the `+=` renderers.
- **Encoder collisions and escaping defects.** Those are #674's and `rewrite-postcondition`'s.

## 9. Disclosures before the freeze

- **Read before this freeze:**
  - the kill-arm subject and the control bodies, all from SwiftUMLStudio `e36da59`;
  - #673's own table of 39 mutants.

  No subject in the universe was read beyond #673's quoted examples.
- **The reader is a prototype in the harness.** If the decision is BUILD, the shipped reader is written from this
  scope, not copied from the harness.
- **A misread counts against precision.** It is not excused as a harness defect. The precision measured is the
  rule's as this scope writes it, implemented once.

## 10. Amendments

Both were made on 2026-11-12, when the controls first ran, before the harness read any universe subject.

- **A. §2.2, the accumulator.** An array literal whose elements are not all string literals is admitted when the
  declaration is annotated `[String]`.
  - **Why:** `componentSVGLines` seeds its accumulator with two `boxRect(…)` calls, and §2.2 refused it, which
    contradicted §4's expectation for that control. The initial lines are frame, and no obligation reads them.
- **B. §4, `buildPlantUMLText`'s expectation.** The component line is primary, not segment.
  - **Why:** §2.4 makes `stereotype` element text, because its initialiser (`stereotypeText(for: component.kind)`)
    is a one-argument call on an element path. So nothing in the line is a cut. The rule stands, and the control
    table had misapplied it.
  - **Consequence for the kill arm:** its law cut the run at `stereotype` (§1.3). That is the weaker reading, and it
    still killed L48.
