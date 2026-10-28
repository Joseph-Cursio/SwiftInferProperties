# Does the uniquifier law have a population, and does it catch what a suite misses? (#669)

> **Status:** `proposed` · **As of:** 2026-10-28
>
> **Frozen** by the commit that adds this file: nothing below changes after the census reads a subject or the
> law runs, except by a dated amendment. §10 lists everything read, written and run before the freeze.

#669 asks for a law the catalogue does not have. For a **uniquifier**, a stateful function that hands out names
and remembers which names it has handed out, the law is:

> take a fresh receiver (or fresh `inout` state) and drawn inputs `x1 … xn`; the results `r.f(x1) … r.f(xn)` are
> pairwise distinct, apart from the guard's sentinel.

A **memoizing** uniquifier, one that returns early with the result it stored for a key, owes another form: *equal
keys give equal ids, and distinct keys give distinct ids*.

**What is already settled.** #669's witness was `DiagramContext.uniqName(item:relationship:)` in SwiftUMLStudio's
`SwiftUMLBridge`. At `e36da59` it suffixed a repeated name with one diagram-wide counter and never re-checked the
result, so `struct Foo0`, `struct Foo` and `extension Foo` were all declared as `Foo0`.

- That was filed as SwiftUMLStudio#54 and fixed by that repository's PR #65 (merged 2026-10-13 as `9465254`).
- The second allocator #669 describes, `LayoutGraphBuilder.uniqueId(for:existing:)` on the SVG path, was filed
  as SwiftUMLStudio#55 and fixed by PR #77 (`84af31b`).
- PR #65 created the suites `DiagramContextAliasTests`, `ClassDiagramAliasTests` and `ClassDiagramEdgeIdTests`.
  `ClassDiagramAliasTests` holds #669's `Vector` witness among its `collidingSources`, which fail before the fix
  and pass after it. So #669's request to push the `Vector` set through both emitters is met by SwiftUMLStudio's
  own suite and is not repeated here.

**What the fix changed about the law.** At `c6c82e3`, the revision this scope reads, `uniqName`'s contract asks
for a call first. `reserveIdentifiers(drawing:)` reserves every id the diagram will use, "before the first alias
is issued", and a first declaration keeps its own name without being checked against suffixes issued earlier.

- So #669's law exactly as written is predicted to **fail on the fixed code**: a fresh `DiagramContext()` with
  nothing called first. The order `struct a`, `extension a`, `struct a0` gives `a`, `a0` and `a0`.
- The kill arm measures this separately (§5.2, S0).
- A template reads a signature and cannot know about a setup call, so every judged uniquifier records SETUP
  (§4.4).

**What remains is #669's step 1:** write the law by hand and score it against the fixed code (§5), and take a
census of the population before building (§1–§4). #669 itself expects that this "may end in a recorded decline
rather than a template".

---

## 1. The census pass

`scripts/uniquifier_census.py`. Section numbers in its comments are this scope's.

### 1.1 The unit

The unit is each `func` with a body that `layering_census.declarations` finds. That is the same scanner,
masking, owner rule and copy key #667's census used. Computed properties, subscripts, initialisers and closures
are not units (§9).

The cues below are read off the function's own text through `regex_acceptor_census.mask_code`. It blanks comments
and literal text but **keeps each interpolation's code**, because a uniquifier's decoration lives inside a literal
(`"\(base)_\(n)"`).

### 1.2 Cues

Each cue is read off the body, except NAME, STATE and RETURNS.

**Shared terms.**

- **Stored.** A name is stored when it is not declared in the body by `var`, `let` or `for`, and is not a
  parameter, unless it is an `inout` collection.
- **Statement.** The statement at a position is its line, joined with any neighbouring line that continues the
  expression. A line continues when it ends in a binary operator, `(`, `,`, `=`, `[`, `?` or `:`, or when the next
  line starts with `.`, `+`, `)`, `]`, `?` or `:`. The statement is then narrowed to the part between `;`s or
  braces that holds the position.
- **Returned.** A decoration is returned when its statement is a `return`, or when it builds a variable that a
  `return` names.

**The cues.**

- **TEST.** The body tests something against a collection. Each test records three things: the tested
  collection's **chain** (`self.`, `?`, `!` and whitespace removed), its **base** (the chain's first component, so
  `existing.values.contains` tests `existing`), and its **argument**. One of:
  - a `.contains(` call;
  - a subscript compared with `nil`;
  - a subscript with `default:`;
  - a subscript followed by `??`;
  - an optional binding from a subscript, in any clause of an `if`, `guard` or `while`;
  - `.index(forKey:`;
  - `.insert(…).inserted`.

  A test's position is where its chain starts, so `if let x = t[k]` puts the test inside the `if`'s condition.
- **Counters.** A counter is any of:
  - a chain the body increments (`n += 1`, `n &+= 1`, `n = n + 1`, `self.index += 1`);
  - an identifier bound from a subscript with a numeric `default:` or `?? <digits>`, optionally in parentheses and
    followed by `± <digits>`, ending the statement (`let n = (counts[b] ?? 0) + 1`), together with the base it
    was read from;
  - a `for` loop's variable over a range (`...` or `..<`);
  - a local copied from an incremented chain (`let id = next`);
  - a local copied from a subscript (`let n = counts[b]!`, `if let n = used[b]`), together with its base. This
    applies when the base is a counter table, or when the body writes the entry back as `n ± <digits>`.

  A **counter table** is the base of a subscript incremented in place: `t[k, default: 0] += 1`, or
  `t[k] = (t[k] ?? 0) + 1`.
- **SUFFIX.** The body decorates with a counter. A decoration is any of:
  - an interpolation whose code is a counter, a counter `± <digits>`, `<chain>.count`, or a counter table's entry
    (`\(counts[b]!)`);
  - `String(<counter>)`;
  - `<counter>.description`.
- **TIED.** This is #669's criterion 2, "on a hit decorates the candidate". A decoration is tied to a test when
  any of these holds:
  - its counter was read from a tested base, or it reads a counter table whose base is tested. This is the
    per-key counter: `let i = names[n, default: 0]`;
  - it sits inside a test's argument, or inside what is written to a tested base: a write call's argument, or
    the right-hand side of an assignment to it;
  - the variable its statement assigns is a test's argument, or is written to a tested base;
  - it sits in a span a test decides, **and** it is returned. The spans are:
    - the body of an `if` or `while` whose condition holds the test, and the `else` block straight after such an
      `if`;
    - the `else` block of such a `guard`;
    - the body of a `repeat` (only a block that opens with `repeat`) whose trailing `while` holds it;
    - a ternary's branches after the test on the same line.

    `#if` is not an `if`. A decoration in a span that is not returned, such as a log line in the hit branch, is
    not tied.
- **RETEST.** A `while` (a `repeat`'s trailing one included, a multi-line condition included) whose condition
  tests an argument with an identifier the loop body reassigns (`=`, `+=`, `&+=` or `.append(`). It stands in for a
  decoration that is not a counter, such as `while used.contains(name) { name = name + "_" }`.
- **NAME.** A word of the base name (`budgeted_truncation_census.words`) starts with `uniq`, `fresh` or
  `disambig`. It is a recall cue only; #669 warns that a name alone mostly finds deduplication helpers.
- **FRESH.** A stored incremented counter, or a local copied from one, decorates, and the decoration is returned.
  This reaches the counter-only generator (`counter += 1; return "\(prefix)\(counter)"`), which has no TEST.
- **STATE**, #669's criterion 1. At least one of:
  - **class**: the owner is a `class` or `actor`, or an extension of a name that some `class` or `actor` in the
    same repository declares, and the function is neither `static` nor `class func`;
  - **mutating**: the function is `mutating`;
  - **inout**: a parameter is `inout` with a collection type (`[…]`, `Array`, `Set`, `Dictionary`, `OrderedSet`,
    `OrderedDictionary`, `ContiguousArray`).

  The repository is every subject that shares the git toplevel (§2).
- **RETURNS.** The result is not empty, `Void`, `()` or `Never`. This is #669's criterion 1 read loosely, because
  "returns `String`, or a type whose text is a `String`" cannot be read without types. The judges see the result
  type.
- **WRITE**, #669's criterion 3. At least one of:
  - a tested base that is stored and that the body writes. A write is any of:
    - an `append`, `insert`, `formUnion`, `updateValue`, `merge`, `add` or `unionInPlace` on the base or a chain
      below it;
    - a subscript assignment;
    - a whole assignment, `=` or `+=`;
  - an `.inserted` test on a stored base;
  - an incremented counter chain whose base is stored.

### 1.3 Candidates and copies

A function is a **candidate** when any of these holds:

- TEST ∧ (TIED ∨ RETEST);
- FRESH;
- NAME ∧ (TEST ∨ SUFFIX).

**Copies merge across the whole universe**, as #667's §1.3 merges them: same name, same argument labels, and the
same masked body with whitespace collapsed. A copy counts once, at the first in this order: group (decision,
unmet, layout, wide), then repository, subject, path and line. Every other copy is listed on it.

### 1.4 The gate a template could read

A candidate is **GATED** when STATE ∧ RETURNS ∧ TEST ∧ (TIED ∨ RETEST) ∧ WRITE hold. That is #669's three
criteria, applied mechanically:

1. "the subject keeps state across calls … and returns `String`";
2. "the body tests a candidate against a collection of names already issued … and on a hit decorates the
   candidate";
3. "the body writes back to that same state".

TIED and RETEST each imply TEST. The TEST conjunct is kept for #669's wording, and no control can catch its
removal (§3). NAME is not part of the gate: #669 allows it only as corroboration.

GATED is computed for every candidate and never shown to the judges. #669's own counterexample, `uniqueId`, is
not GATED, because it writes neither `existing` nor a stored counter (C3). So §8 measures the gate's precision,
not only its count.

## 2. The universe, frozen

The census reads four groups. Three are #667's universe, frozen in `layering-law-census-scope.md` §2 and asserted
by `layering_census.universe()`. The fourth is #667's graph-layout corpus.

- **Decision (36 subjects).** The manifest (22) and funnel (19) groups of `regex_acceptor_census.FROZEN_UNIVERSE`,
  with five subjects in both. That is the manifest #669 names ("take a shape census across
  `fixtures/corpora/manifest.json`"), plus the funnel repositories #666 and #667 also counted.
  - **One departure from #667: every decision subject is read from its root, not through its manifest source
    directories.** #667 read the manifest's corpora at their target directories only. That would read
    swift-syntax at `Sources/SwiftSyntax`, which has neither of #669's `makeUniqueName`s, and this repository at
    `Sources/SwiftInferCore`, which lacks `uniqueCaseName` (`Sources/SwiftInferCLI`).
  - #669's own grep read whole checkouts, and a uniquifier lives wherever code is generated, not in one target.
  - Both review agents found this before the freeze (§10).
- **Unmet (5).** Euclid, swift-docc, OpenAPIKit, jwt-kit and swift-system, read from their roots. Reported as
  **N_unmet**.
- **Layout (18).** The graph-layout corpus (`layering-law-graph-layout-corpus-scope.md` §2), asserted by
  `layering_census.corpus_universe()`: each clone at its frozen revision with a clean tree. Reported as
  **N_layout**. It is here because it is checked out and asserted, not because it was chosen for this law.
- **Wide (67 directories).** Every other directory with Swift sources under `~/xcode_projects` and
  `~/github_projects`, as #667 froze it (sha256 `c7ad7e6c…`). Read from their roots and reported as **N_wide**.

The asserts are #667's. The script exits non-zero with no population if any of these fails:

- the decision and unmet lists are `FROZEN_UNIVERSE`'s;
- SwiftUMLStudio is at `c6c82e3` with a clean tree;
- the wide list's hash matches, and each wide directory exists with its `origin`;
- each layout clone is at its revision with a clean tree.

**Skipped files.** These are #667's rules:

- hidden directories;
- `Tests`, `tests`, `test`, `validation-test`, `.build`, `build`, `DerivedData`, `checkouts`, `Pods` and
  `Carthage`;
- any directory component ending in `Tests` or `UITests`.

**Plus `fixtures`, ignoring case**, below a subject's root. This is test data: swift-package-manager's `Fixtures/`
holds 812 Swift files of sample packages, and this repository's `fixtures/` holds study code. A manifest corpus
that lives under this repository's `fixtures/` is its own subject, and its root is below that component, so it is
still read.

**Plus any file the masker cannot finish within 10 s.** `mutation_check.mask`, which every pass over a file runs,
loops forever on a comment or a multi-line literal whose closer it cannot find. Valid Swift can reach that: an
escaped `\"""` inside a multi-line literal ends it early for the masker. Such a file is dropped before any cue is
read, and its path is listed in its subject's record as `unparsable`, with the count reported beside N.

## 3. Controls for the census pass, asserted before any subject is read

`uniquifier_census.py --self-test` runs 85 checks, with no subject and no compiler, and joins
`make measurement-selftest`: 63 pass controls (C49 has three cases) and 20 decision controls. `run` refuses to
report when any control fails.

**The rule-break audit.** These were switched off in turn, 51 in all:

- each TEST form;
- each counter, table, alias and member pattern;
- each helper: the spans, the tie, the statement, the return check, the write spans, the stored rule, docs,
  member order, and the parse guard;
- each gate conjunct and candidate branch, and `join`'s SETUP agreement;
- each bar.

A control caught every one except the gate's TEST conjunct, which TIED and RETEST imply (§1.4). Sub-rules inside
one helper are each covered by a control of their own: C49's three spans, C51–C53's three ties, C54's write calls
and C55's inout types. The audit's script is in the scratchpad (§10), not the repository.

| # | snippet or rule | expected |
|---|---|---|
| C1 | `uniqName` at `e36da59` | GATED; STATE class; TIED `index`, decorated in the `contains` branch and returned; WRITE names and counter |
| C2 | `uniqName` at `c6c82e3` | GATED; RETEST on `takenIdentifiers` through `repeat … while`; TIED |
| C3 | `uniqueId(for:existing:)` at `e36da59` | candidate, **not** GATED: WRITE empty; STATE inout; RETEST |
| C4 | `DiagramIdentifiers.id(forKey:sanitizing:)` | GATED; mutating; binding and contains TESTs; WRITE `byKey` and `taken` |
| C5 | a `makeUniqueName` of swift-syntax's shape | GATED; its counter is read from the tested table, so TIED |
| C6 | `uniqueCaseName(for:taken:)`, `taken: inout Set<String>` | GATED; a `static` function admitted through inout |
| C7 | a `uniqued()` deduplication helper | candidate by NAME ∧ TEST, not GATED |
| C8 | a counting logger that returns nothing | no FRESH, no candidate |
| C9 | a counter-only `nextName()` | candidate by FRESH, not GATED, no NAME |
| C10 | a lone `contains` | no candidate |
| C11 | an interpolation inside a comment | no SUFFIX |
| C12 | `.contains(` inside literal text | no TEST |
| C13 | a batch renamer over a local `Set` | candidate, WRITE empty, not GATED |
| C14 | a `mutating` claim on a struct | GATED |
| C15 | a `static` function on a class with static state, no inout | STATE empty, not GATED (§9) |
| C16 | an extension of a class | STATE class, GATED |
| C17 | a raw string's interpolation `#"\#(base)_\#(n)"#` | SUFFIX |
| C18 | `base + String(n)` | SUFFIX |
| C19 | `return names.contains(base) ? "\(base)\(names.count)" : base` | TIED through the ternary alone |
| C20 | `let name = "\(base)\(i)"` then `if !used.contains(name)` | TIED, because the value is tested |
| C21 | an `inout Int` counter parameter | no STATE, no stored counter |
| C22 | a claim that returns nothing | RETURNS false, not GATED |
| C23–C24 | NAME words | `makeUniqueName` gives `unique`; `freshVariable` and `disambiguated` match; `nextName` gives none |
| C25 | `names[k] == nil`, `names.index(forKey: k)` | two TESTs |
| C26 | a `while i < 10` loop | no RETEST |
| C27 | `class func` | static, STATE empty |
| C28 | `if used.insert(name).inserted` with a local counter | TEST and WRITE on `used`, no counter write |
| C29 | a copy in the decision, layout and wide groups | one row, at the decision copy |
| C30 | a `func` in a doc comment above the signature | the body is the real one |
| C31 | `n = n + 1`, `n.description`, `used = used + [name]` | counted, SUFFIX, WRITE |
| C32 | `let k = seen[base] ?? 0` | TEST coalesce, TIED, GATED |
| C33 | NAME ∧ SUFFIX with no TEST | candidate |
| C34 | every gate conjunct but the decoration | candidate by NAME, not GATED |
| C35 | 301 non-wide candidates | the pass stops |
| C36 | 75 wide candidates and one unmet, in two orders | 60 wide sampled by the seed, the same set; unmet judged |
| C37 | `return "\(selected.count) selected"` after a toggle | no TIED, no candidate |
| C38 | `return "Added \(item), \(items.count) in cart"` on the miss path | no TIED, no candidate |
| C39 | `let n = (counts[b] ?? 0) + 1` | a per-key counter, TIED, GATED |
| C40 | `counts[b, default: 0] += 1` then `"\(b)_\(counts[b]!)"` | a counter table, TIED, GATED |
| C41 | `if flag, let e = byKey[k]`, and a `while` condition over two lines | a TEST, and a RETEST |
| C42 | `while queue.contains(x) { queue.removeFirst() }` | no RETEST |
| C43 | a local's member incremented (`stats.count += 1`) | no stored counter |
| C44 | an `actor`; `n &+= 1`; `used.formUnion([name])` | STATE class, counted, WRITE |
| C45 | owner members across two files | the row's file first; properties, signatures, `///` docs above an attribute line, `/** */` docs; bodies and the row left out; a plain `/* */` is no doc |
| C46 | `fixtures/` and `Fixtures/` below a root | skipped |
| C47 | `counts[b] = (counts[b] ?? 0) + 1` | a counter table, TIED, GATED |
| C48 | `while used.contains(name) { name = name + "_" }` | RETEST alone carries the gate |
| C49 | a returned decoration in a `guard`'s else, in the `else` after an `if`, and in an `if let` binding's span | TIED, GATED, each |
| C50 | `let label = "t\(n)"; return label` | FRESH through a returned variable |
| C51 | `let c = "\(base)\(n)"; names.append(c)` after an unrelated test branch | TIED by the write alone |
| C52 | `names.append("\(base)\(n)")` | TIED inside the write's argument |
| C53 | `while names.contains("\(base)\(n)")` | TIED inside the test's argument |
| C54 | each write call on a tested base | WRITE |
| C55 | `inout` `Array`, `[K: V]`, `OrderedSet`, `ContiguousArray`, `Dictionary`, `Set`; and `inout String` | STATE inout for each collection, none for `String` |
| C56 | a log line with a counter in the hit branch | no TIED, no FRESH, no candidate |
| C57 | a `while` straight after an `if`'s closing brace | a `while`, not a `repeat`'s: RETEST, GATED |
| C58 | a test inside `#if … #endif` before a loop | no span, no candidate |
| C59 | `return Label(\n id: "L\(counter)")` | one statement: FRESH |
| C60 | one-line bodies: a printed decoration, a returned one | no FRESH; FRESH |
| C61 | a subscript with a string `default:` | no counter |
| C62 | `let id = next`; `if let n = used[b]` written back as `n + 1`; `let n = counts[b]!` | FRESH; GATED; GATED |
| C63 | a comment that never closes | unparsable within the time limit; a normal file is parsable |
| D1–D20 | §8's outcomes, refusals, merges, sensitivity lines, R2, the counts without EXPRESSIBLE, calibration | see `decision_controls()` |

## 4. The hand-check

### 4.1 What is judged

Every decision, unmet and layout candidate is judged. If there are more than 300 of them, the script stops, and
this scope gets a dated amendment before any packet is written; that is a stop, not a sample.

Wide candidates are judged in full up to 60. Above that, a sample of 60 is drawn by `random.Random(20261028)` over
the rows sorted by id. N_wide is then estimated over the judged share and reported with its sample size.

### 4.2 Calibration, before any packet

Two judges first classify the nine rows of `fixtures/uniquifier-law/calibration.md`. The rows are in a packet's
own format, owner members included.

- Rows 1 and 3 are SwiftUMLStudio's, rendered by `uniquifier_census.py render` from `c6c82e3`. The judges may
  read that repository, as they may any row's.
- Rows 2 and 4 are its older revision, text only. Rows 5–9 are synthetic.

Row 1's *body disagrees* flag is left unscored. In Mermaid and Nomnoml, `uniqName` returns a macro's alias
without recording it, so a later suffix can repeat it. The brief exempts results the contract says are not
identifiers, and a macro's alias there is only a comment. That reading is fine-grained enough that a careful judge
could miss it, and the flag never enters N.

Only the script holds the expected answers (`uniquifier_census.CALIBRATION`). Each judge must match on every field
listed. A miss stops the arm until the brief is amended, by a dated amendment, and calibration runs again.

| row | expected |
|---|---|
| 1. `uniqName` at `c6c82e3` | UNIQUIFIER, not EXPRESSIBLE, SETUP (its *body disagrees* flag is not scored: see below) |
| 2. `uniqName` at `e36da59` | UNIQUIFIER, EXPRESSIBLE, body disagrees |
| 3. `DiagramIdentifiers.id(forKey:sanitizing:)` | MEMOIZING, EXPRESSIBLE, no SETUP, body agrees |
| 4. `uniqueId(for:existing:)` at `e36da59` | LOOKUP |
| 5. a `uniqued()` deduplication helper | NOT-UNIQUIFIER |
| 6. a one-call column disambiguator | BATCH |
| 7. a request logger that returns its numbered line | NOT-UNIQUIFIER |
| 8. a round-robin worker picker | NOT-UNIQUIFIER |
| 9. `freshName(_ prefix:)`, a counter appended to a prefix | UNIQUIFIER, EXPRESSIBLE, body disagrees: `a1` on call 1 and `a` on call 11 both give `a11` |

### 4.3 Packets and judges

**Packets.** `uniquifier_census.py packets` writes the judged rows in a seeded order (`random.Random(20261028)`
over the rows sorted by id), in packets of at most eight.

- They go into a directory that must be empty; the script refuses otherwise.
- The label index is written beside that directory, not in it.

**Judges.** Two judges, **A** and **B**, judge each packet independently. Each is a subagent given only the brief
(`fixtures/uniquifier-law/judge-brief.md`), its packet and an output path. **C**, a third judge, decides a row
when A and B disagree on the verdict, or, for UNIQUIFIER or MEMOIZING, on EXPRESSIBLE or SETUP. When A and B
agree, their record flags *body disagrees* if either does, and keeps both witnesses. A row where A's or B's record
is incomplete also goes to C, even when their verdicts agree: an owing verdict with a flag left unanswered.

**Refusals.** `join` refuses any of these:

- an unknown, repeated or missing label;
- a disagreement that C has not judged.

`decide` refuses unless every judged row has exactly one judgement, so a dropped packet can never read as rows
that are not uniquifiers. A record whose verdict is unknown is UNDETERMINED. So is one that gives UNIQUIFIER or
MEMOIZING without answering all three flags.

**What a judge sees:**

- the function's full text and doc comment;
- its owner's name, kind and doc;
- **the owner's other members in its repository**, as properties and signatures without bodies, from
  `owner_entries` and `member_lines`:
  - each with its doc comment: a `///` run or a `/** … */` block, found above any attribute lines;
  - the row's own file first;
  - the row itself left out;
  - at most 200 lines.

  These are the declarations where a setup requirement is written;
- the file path, and the repository's name and path;
- the same-file functions it calls, and those that call it;
- the brief.

**What a judge does not see:**

- the cues, GATED, the group;
- this scope's predictions, §8's bar and outcomes;
- any count;
- the other judge's verdict.

**What a judge may read.** The brief's rules say this in those words:

- **Allowed:** the packet, and, for context, source files under the row's own repository path.
- **Forbidden:** any `docs`, `scripts` or `fixtures` directory of this repository; any `.json` file; any other
  packet or judge output; and any search for a function's name outside the row's own repository.
- **Required:** reading the row's whole file before answering EXPRESSIBLE or SETUP.

### 4.4 Verdicts

The brief's text is the definition. In short:

- **UNIQUIFIER.** It issues a name and keeps state so no call repeats an earlier result. A counter that only
  grows counts.
- **MEMOIZING.** The same, except that a key seen before gets back its first result.
- **BATCH.** It makes a whole collection's names distinct in one call. Outside the population.
- **LOOKUP.** It computes a free name but does not record it, so the law is false. Outside.
- **NOT-UNIQUIFIER.** Anything else: deduplication, logging counters, round-robin or recycling, UUID or hash
  names, formatting.
- **UNDETERMINED.**

For UNIQUIFIER and MEMOIZING, the judge also records three flags:

- **EXPRESSIBLE.** The contract promises the law for a fresh receiver or `inout` value with nothing else called
  first, and a test can set that up from the module's API, internal API through `@testable import` included.
  This is #667's *expressible* clause restated for this law. It is false when:
  - a setup call is required;
  - the state is shared global or static state;
  - an input cannot be built.

  Whether the body keeps the promise is a separate flag.
- **SETUP.** The contract requires another call first. A documented requirement settles it, whatever a test or
  caller does.
- ***body disagrees*.** A witness sequence, allowed by the contract, on which the body breaks the law. Each such
  row is hand-checked and listed with its revision for upstream filing.

### 4.5 Counting

**N** counts the decision rows whose final verdict is UNIQUIFIER or MEMOIZING and that are EXPRESSIBLE, as
**merged groups**:

- copies merge as §1.3 says;
- an owing row also merges with an owing row in the same file that it calls or that calls it, transitively, by
  name.

A repository counts toward the bar only if it holds a merged group's first row. The **unmerged count**, reported
beside N, counts every owing EXPRESSIBLE decision row with its copies.

## 5. The kill arm (#669 step 1)

`scripts/uniquifier_kill_arm.py`. It imports #667's mutant generator, watchdog, patching and flake rule
(`layering_kill_arm.py`) unchanged, and binds them to this subject, law, suites and controls.

### 5.1 The subject

SwiftUMLStudio `c6c82e3`, package `SwiftUMLBridge`: the revision #667's kill arm used. It is exported with
`git archive` into this session's scratchpad and never built in the user's checkout.

It is built with Xcode 27's Swift 6.4, found by `xcrun --find swift`. The runner refuses to start unless
`swift --version` names `swiftlang-6.4.0.34.1`.

Unmutated, with both law suites skipped:

- the export built in 41 s;
- `SwiftUMLBridgeFrameworkTests` passed 1,823 tests in 31 s;
- the reduced suite (§5.4) passed 1,784 tests in 23 s.

### 5.2 The law, prototyped by hand

`fixtures/uniquifier-law/UniquifierLawTests.swift` is copied into the export's `SwiftUMLBridgeFrameworkTests`
target, never into SwiftUMLStudio itself. Its sha256 is recorded in the report. It holds three properties. Each
runs 1,000 trials from a SplitMix64 generator with a fixed seed, and prints one summary line,
`UNIQUIFIER-LAW <property> … failures=<k>`.

- **U1 (aliases, with the contract's setup).** Run once per `DiagramFormat`, so four times.
  1. Draw the items. Half the trials draw 1–16 items, with names `a` or `b`, bare half the time and otherwise
     followed by one of `0`, `1`, `2`, `10`, `11` or `_2`. The other half are a **dense stratum**: 11–24 items
     over `a`, `a1`, `b` and `b1` only. Kinds are drawn independently from `class`, `struct`, `enum`,
     `protocol`, `extension` and `macro`.
  2. Take a fresh `DiagramContext` for the format, and call `reserveIdentifiers(drawing: items)`.
  3. Call `uniqName` on each item in the drawn order, with the relationship its emitter uses
     (`ElementKind.classNode`, and `"macro"`).
  4. Among the items the format declares (a macro only in PlantUML), no alias may repeat.
- **M1 (memoizing).** A fresh `DiagramIdentifiers(sanitize: DepsScript.mermaidId)` per trial.
  - Draw a pool of 3–6 keys, each 1–3 characters from `a`, `_`, `.`, `-` and `2`. Then draw 1–16 lookups from
    the pool, so keys repeat.
  - `mermaidId` rewrites `.` and `-` to `_`, so distinct keys collide when sanitized, and a sanitized key can
    spell another's `_2`.
  - For every pair of lookups, the keys are equal exactly when the ids are equal.
- **U0 (#669's law as written).** U1's draw generator, on seeds of its own, with **no** `reserveIdentifiers`
  call. It is its own suite, `UniquifierLawSetupFreeTests`, run once on the unmutated export as **S0**: never in
  the law run, never in either suite. It is a measurement, not a runner control.

**Why the dense stratum.** The names let a drawn name equal another drawn name plus the subject's suffix. This
is the collision-dependent case CLAUDE.md names: a generator drawing realistic names never fails.

- The dense stratum exists for collisions such as `a1` + `0` against `a` + `10`.
- That family is how a reserved, re-checked `uniqName` fails once `takenIdentifiers.insert(newName)` is removed.
- **The power check, in a Python model of `c6c82e3`**, run over 200 seeds (§10):
  - Without the stratum, U1 found that mutant in about 0.12 trials per 1,000 per format, so it missed in all
    four formats on about 60% of seeds.
  - With the stratum, U1 found it on every seed, at about 568 failures per 4,000 trials.
  - The unmutated model failed on no seed.

The first failure names the colliding pair and the whole sequence. The generators are hand-written; a built
template would compose `DerivationStrategist`'s generators instead.

### 5.3 The mutants

These are #667's generator's operators (`layering-law-census-scope.md` §5.3): arithmetic, relational,
negate-conditional, logical, boolean-literal, swap-ternary and remove-side-effects. Code is masked first, so
comments and literals, interpolations included, are never mutated.

**One property of that generator matters here.** It finds a condition by the `{` that ends it, so a `repeat`'s
trailing `while` is never negated. The re-check PR #65 added is therefore not among the mutants; RC2 removes it
by hand instead.

**The mutated functions** are the bodies on the law's call tree in two files:

- `Model/DiagramContext.swift`: `uniqName`, `reserveIdentifiers`, `declaresIdentifier`, `linkTarget`,
  `addExtensionEdge`, `drawsExtensionEdge`, `nomnomlEdge` and `linkType`;
- `Emitters/DiagramIdentifiers.swift`: both `id` overloads.

That is **39 mutants**. The file's other 27 (in `addLinking`, `text`, `supertypeEnd` and
`collectNestedTypeConnections`) are counted by function and not run.

### 5.4 Each mutant

This is #667's §5.4, with these suites:

- **The law:** `swift test --skip-build --filter '\.UniquifierLawTests/'`, with a 120 s limit.
- **The full suite:** `--filter '^SwiftUMLBridgeFrameworkTests\.' --skip '\.UniquifierLaw(?:SetupFree)?Tests/'`,
  with a 300 s limit.
- **The reduced suite:** the full suite less **the four suites that this law family's own findings produced,
  whole**, as they stand at `c6c82e3`: 39 tests.
  - The four are `DiagramContextAliasTests`, `ClassDiagramAliasTests` and `ClassDiagramEdgeIdTests`, which PR #65
    created for #54, #669's witness, and `DiagramIdentifiersTests`, which PR #52 created for the sanitizer
    collision whose fix is `DiagramIdentifiers`.
  - This is #667's rule by provenance: #667 left out PR #64's law-derived tests. Here it is whole suites,
    because tests later added to them, renamed or rewritten, belong to the same fix.
  - Other suites stay, including ones that check ids are distinct for other reasons:
    `BoundGenericExtensionTests` (for #66), `LayoutGraphBuilderNodeIdTests` (the SVG path) and the Nomnoml
    identifier tests.
  - The runner reads the 39 display titles from the export's four files and refuses to start on any other
    count. A failed test is matched to a derived suite by its title, with or without its argument, because a
    run's `✘ Test "…"` line names the title.

  The reduced suite is read off the full run as #667's is.

- **The watchdog** is #667's, with one change made from this file and none in #667's. #667's process list skips
  its own runner by script name only, and this runner's command line names the export too. Left alone, it would
  SIGKILL itself and the shell that started it at the first sweep, which round two of the review reproduced. So
  `uniquifier_kill_arm.py` rebinds `layering_kill_arm._export_processes` to a copy that also skips any command
  line naming this runner, and this process and its ancestors. `_sweep`, `_kill` and `_resident_kb` look the name
  up when they run. Three self-test checks cover this, and each fails with its rule removed.

The outcome rules are #667's: ASSERTION, CRASH, TIMEOUT and MEMORY (6 GiB) are detections, and anything else is
SURVIVED. So are the flake rule, the watchdog, and the restore after every mutant.

### 5.5 Controls for the runner

| # | control | expected |
|---|---|---|
| RC1 | the unmutated export | builds; U1 (four lines) and M1 hold, `failures=0` on all five; the full suite passes at least 1,800 tests |
| RC2 | `uniqName`'s `repeat … while takenIdentifiers.contains(newName)` replaced by one suffix, as before PR #65 | the law detects it by ASSERTION, U1 failing and M1 not; the full suite detects it |
| RC3 | `if uniqElementNames.contains(name)` → `if uniqElementNames.firstIndex(of: name) != nil` | both SURVIVE |
| RC4 | a statement `let _: Int = "x"` in `uniqName` | UNVIABLE |
| RC5 | after the run | the export's `Sources/` and `Tests/` hash as before the run |
| RC6 | the law run twice on the unmutated export | the same five summary lines, compared as a set |
| RC7 | `suffix += 1` removed from `DiagramIdentifiers.id(forKey:sanitizing:)` | law and full suite both TIMEOUT, each within its limit plus 45 s, and nothing naming the export survives the 5 s grace |

RC7's hang needs a third claimant. Without the increment, the first collision still gets `_2`. The loop then
spins only when a name's `_2` is already taken, as in `collisionGetsSuffix`'s `Outer-Inner`, or in M1 within its
first hundred trials.

RC1 and RC6 run first, then S0 on the same unmutated build, before any patch, then RC2–RC4 and RC7. If any control fails, the runner writes no summary. RC5 is
checked after the last mutant, and a failure voids the summary. A run resumes from its report only when the law's
file and the source tree hash as the report recorded.

**If RC1 fails**, the first counterexample is hand-checked:

- **A law or generator error** is fixed by a dated amendment before any mutant runs.
- **A real defect in SwiftUMLStudio** is listed with its revision and offered to the user for filing upstream.
  The arm is then scored against a hand-fixed body, in a fresh report, and the doc says so.

UNMEASURED (kills) applies only when neither is done.

### 5.6 What is counted

These are #667's §5.6 counts. Over the viable mutants, the runner counts what the law detects, what the full
suite detects, and what the reduced suite detects. Each law-only row records its mechanism, the properties that
failed, and its class:

- **issuing**: the mutated function decides which id is issued (`uniqName`, `reserveIdentifiers`,
  `declaresIdentifier`, `linkTarget`, `id`);
- **edges**: it only writes edges and arrows (`addExtensionEdge`, `drawsExtensionEdge`, `nomnomlEdge`,
  `linkType`).

**The decisive count** is law-only detections **by ASSERTION** against the **reduced** suite, for #667's reasons:

- a crash or a timeout is something any test with random inputs would catch;
- the full suite holds the law's own examples, so scored against them the law gets no credit for its own finding.

The full-suite figure is reported beside it. So are:

- every mutant that survived both, read for equivalence;
- the suite-only count;
- each mechanism's count;
- for every suite kill by a single failing test, which test that was.

## 6. Recall probes

These are reported beside the census and never enter N:

- **R1.** The unmet, layout and wide groups (§2): does a uniquifier live outside the corpora the toolchain has
  read?
- **R2.** The owing decision groups with no GATED member (`ungated_owing`), EXPRESSIBLE or not, each with its
  EXPRESSIBLE and SETUP flags. These are what the gate misses that the cues reached. The expected shapes are the
  counter-only generator and `static` state (§9).
- **R3.** #669's grep sites, by name: `makeUniqueName` (twice in swift-syntax), `uniqueCaseName` (this
  repository), GRDB's `resolvedNames` and swift-foundation's `unique(_:)`. The census records every `func` with
  one of these names, candidate or not, with its cues. Each site is reported in one of three ways:
  - as a candidate;
  - as read but no candidate, naming the cue that missed;
  - as **not read**: not a `func` with a body, or outside the files §2 reads.

## 7. Predictions, frozen

Each says whether it is blind and, if not, what informed it.

1. **N = 4 over 3 repositories, so DECLINE (population).**
   - The four are `DiagramIdentifiers.id(forKey:sanitizing:)` (SwiftUMLStudio), `makeUniqueName` twice
     (swift-syntax) and `uniqueCaseName(for:taken:)` (this repository).
   - `uniqName` is judged UNIQUIFIER, not EXPRESSIBLE, with SETUP. **N + N_setup = 5** then clears the count half
     of the bar, and the doc's first paragraph says the decline rests on the setup call.
   - *Partly blind.* #669's grep named three of the four, and the fourth and `uniqName` were read for the kill
     arm. Whether SwiftUMLStudio's SVG path gained another id allocator with PR #77 was not checked.
2. **N_gated = N**: every owing decision group is GATED, and **the gate's precision is at least 70%**. *Partly
   blind:* the gate's controls were written from those shapes.
3. **No decision row is flagged *body disagrees*.** *Partly blind:* #669 read its four grep sites as correct.
4. **R3 finds both `makeUniqueName`s and `uniqueCaseName` as candidates.** It finds `resolvedNames` as not read,
   because it is not a `func`, and swift-foundation's `unique(_:)` as read, not a candidate. *Partly blind:* from
   #669's descriptions only.
5. **A dagre port's id counter is judged UNIQUIFIER**, in the layout group.
   - If the port keeps dagre's global or static counter, the row is not EXPRESSIBLE. N_layout is then 0, and the
     row shows in N_layout without EXPRESSIBLE (≥ 1).
   - N_layout ≥ 1 only if the port moved the counter onto an instance.
   - *Partly blind:* dagre's JavaScript `uniqueId` is a prefix plus a global counter, known before this scope.
     Whether a Swift port keeps that was not checked.
6. **RC1 holds, and S0 fails** in every format, on an order like `struct a`, `extension a`, `struct a0`. *Not
   blind:* reasoned from `c6c82e3`'s `uniqName`, and the review's model failed 160–210 trials per 1,000 per
   format without the dense stratum.
7. **The reduced suite does not detect RC2**, the pre-#65 body, as #667's did not detect its pre-fix body.
   *Partly blind:* which of the 1,784 remaining tests draw a colliding suffix was not checked.
8. **The decisive count is between 1 and 8, and every decisive kill is issuing.**
   - The candidates are:
     - `takenIdentifiers.insert(newName)` removed from `uniqName`, and its twin, the `declaresIdentifier(of:)`
       condition before it negated;
     - `takenIdentifiers.insert(fullName)` removed from `reserveIdentifiers`, or its condition negated;
     - the three `declaresIdentifier` mutants: two change what Mermaid declares, and one changes only PlantUML's
       macros;
     - `taken.insert(candidate)` removed from `DiagramIdentifiers`.
   - Against the full suite, law-only kills are 0.
   - The last of those rests on leaving `DiagramIdentifiersTests` out (§8's sensitivity line).
   - *Not blind:* the mutant list and the derived suites were read.
9. **The law detects at most 12 of the 39 mutants, and the full suite at least 25.** *Not blind:* the law sees
   only returned ids, and the U1 draws carry no supertypes, nesting or edges.

## 8. The decision, fixed now

The figures:

- **N**: §4.5's merged groups in the decision universe.
- **N_gated**: those groups with a GATED member.
- **Gate precision**: |GATED ∧ (UNIQUIFIER ∨ MEMOIZING)| / |GATED| over the judged decision candidates that are
  GATED, with every GATED row that does not owe the law listed.
- **The decisive count**: §5.6.

Reported beside them, none entering the decision:

- the unmerged count;
- N without EXPRESSIBLE;
- **N_setup**: owing groups that are not EXPRESSIBLE and have SETUP;
- N_unmet and N_layout, each also without EXPRESSIBLE;
- N_wide, with its judged and total counts and its estimate, and without EXPRESSIBLE;
- the unparsable files dropped (§2);
- N_undetermined;
- the full-suite law-only count;
- S0's summary lines.

The bar is **at least 5 across at least 2 repositories**, as #667 used it and `whole-to-parts-partition-declined.md`
§6 froze it. `uniquifier_census.py decide` computes all of this from the census, the judgements and the kill
arm's report, and prints each line below.

**The outcome is the first that applies:**

1. **DECLINE (population)**: N < 5, or N spans fewer than 2 repositories.
2. **DECLINE (signal)**: N_gated < 5, or it spans fewer than 2 repositories.
3. **DECLINE (gate precision)**: gate precision < 70%.
4. **UNMEASURED (kills)**: a runner control fails, RC5 fails, or the run did not finish every planned mutant.
   A run with no summary is never read as zero kills.
5. **DECLINE (kills)**: the decisive count is 0.
6. **BUILD**: otherwise. The gate passes, and the build is a separate issue.

**Every arm runs, and every arm is reported, under every outcome.** The decision line is `decide`'s first three
lines.

**Sensitivity.** `decide` prints a `SENSITIVITY` line for each sum below, with its count and repositories. A
repository counts when it holds a first row. The doc's first paragraph says so when one would clear, on both
halves, a population bar the decision failed:

- **N + N_setup**: the decline rests on setup calls a template cannot see;
- **N + N_unmet + N_layout + N_wide (its estimate)**: it rests on the universe's boundary;
- **N + N_undetermined**, each UNDETERMINED row counted as a group of its own: it rests on unsettled verdicts.

`decide` also prints **the decisive count with `DiagramIdentifiersTests` kept**: the decisive kills less those a
`DiagramIdentifiersTests` test detected in the full run. That suite unit-tests the type PR #52 created for the
sanitizer collision, which is #674's injectivity finding, not this law's. If the outcome is BUILD and this count
is 0, the doc's first paragraph says the BUILD rests on that exclusion.

**Disposition:**

- **Under every DECLINE**, #669 closes as not planned once the user approves, with a result comment. The universe
  holds every local repository, read whole, and the graph-layout corpus, so no reopen condition is frozen. None
  may be added after the run.
- **Under UNMEASURED or BUILD**, it stays open.

**Under every outcome:**

- the measurement doc, `uniquifier-law-census.md`, is written in `measurements/`;
- both indexes get a row;
- every row flagged *body disagrees* is hand-checked, then listed with its revision and offered for upstream
  filing;
- if S0 fails, its counterexample is recorded. It is the reason a template that states #669's law without setup
  would propose a false law on correct code.

## 9. What this does not answer

- **One subject for the kill arm.** The kill counts are SwiftUMLStudio's, against a suite that already holds the
  law's examples. They are not a rate.
- **The census finds only what its cues reach.** It misses:
  - a uniquifier written as a computed property, subscript, initialiser or closure;
  - one inside a larger function;
  - one whose counter is `static` or global state that it only reads through a helper;
  - one whose test is not one of §1.2's seven forms, such as `firstIndex(of:)`, `filter … isEmpty`, or a set
    passed to a helper;
  - one whose decoration is neither a counter nor re-tested in a `while`;
  - one whose decoration is tied to its test only through a helper, or across more than one statement.
- **`static` state.** A `static func` on a class or enum that writes `static var` state has no STATE (C15), so it
  is never GATED, though a judge may find it owing. Such a function is reported as an ungated owing group (R2).
- **The gate reads no types.** "Returns `String`, or a type whose text is a `String`" is reduced to "returns
  something" (RETURNS). Gate precision includes any row this admits that returns a non-name.
- **Hand-written generators.** The prototype is not a template. In particular, the U1 draws construct
  `SyntaxStructure` by hand, which a template would need a generator for.
- **A re-implemented tool.** The mutants are #667's operator set, comparable within this run only.

## 10. Disclosures before the freeze

**Read, beyond #669 itself:**

- SwiftUMLStudio#54 and #55's states, and the descriptions and file lists of PR #65 and PR #77. Also the titles
  of the other closed SwiftUMLStudio issues that a search for `uniqName` or `uniqueId` returned.
- The tests PR #52 and PR #65 added, from their merge commits' diffs (names and titles).
- At `c6c82e3`:
  - `DiagramContext.swift` lines 1–100 and 230–350, including `uniqName`, `reserveIdentifiers`,
    `declaresIdentifier` and `addExtensionEdge`, and its function list;
  - `DiagramIdentifiers.swift`, in full;
  - `SyntaxStructure`'s initialiser and `fullName`;
  - `Configuration`'s initialiser;
  - `ElementKind+ClassNode.swift`;
  - `DiagramContextAliasTests.swift` lines 1–60, `ClassDiagramAliasTests.swift` lines 1–40, and
    `DiagramIdentifiersTests.swift` in full;
  - every test line holding `Set(…).count ==`, and `BoundGenericExtensionTests.swift` lines 98–114.
- At `e36da59`: `uniqName` and `uniqueId`, now calibration rows 2 and 4, and the owner members of
  `DiagramContext` and `LayoutGraphBuilder`.
- #667's scopes, scripts and law file, whose parts this scope reuses.
- **Per manifest subject, a count of Swift files** under its target directories and under its root, with and
  without `fixtures`. These are file counts, not contents.

**Two review agents** read the first draft, the scripts, the law, the brief and the calibration file:

- **A conformance check.** Does the text say what the code does, rule by rule?
- **An adversarial read.** Could the design produce a wrong decision?

Both found the scan-root gap (§2) and the calibration-context gap (§4.2), and every finding was folded in:

- the universe change;
- TIED (a decoration must be tied to its test, which removes three look-alikes the reviewers probed: C37, C38 and
  the retry logger);
- the per-key counter shapes (C39, C40, C47);
- the owner members in packets, and calibration in packet format;
- the brief's rules on setup, `@testable` and *expressible*;
- the reduced suite by provenance;
- the dense stratum;
- `join`'s SETUP agreement and union of *body disagrees*;
- `decide`'s sensitivity lines, wide estimate and S0 lines;
- the R3 records;
- the RC7 wording;
- the missing controls.

**A second round, run as a workflow:** three lenses, each finding marked BLOCKING verified by a skeptic who tried
to refute it. The lenses were:

- conformance;
- the new cue parsers, attacked with hand-written Swift;
- judging and the kill arm.

It returned 23 findings. Of the 6 marked BLOCKING, 5 survived their skeptic:

- the watchdog killing its own runner (§5.4);
- `regions` reading any `while` after a `}` as a `repeat`'s (C57);
- counters copied into a local first (C62);
- calibration row 1's *body disagrees* flag, now unscored.

The masker's endless loop was graded not blocking by its skeptic. It is guarded anyway (§2, C63).

All the minor findings were folded in:

- a span-tied decoration must be returned (C56);
- a binding test opens its own span (C49);
- ties through a test's argument, or through what is written (C51–C53);
- statements over several lines (C59, C60);
- a numeric `default:` only (C61);
- RETEST on any identifier of the argument;
- `#if` (C58);
- owner members' docs above attributes, `/** */` docs, the row's file first and the row left out (C45);
- S0 before any patch;
- R2 over every owing group;
- counts without EXPRESSIBLE beside N_unmet, N_layout and N_wide;
- incomplete records go to C;
- the `DiagramIdentifiersTests` sensitivity line;
- predictions 5 and 8 restated;
- each sub-rule's own control (C49–C55).

No round-two agent opened a census subject other than SwiftUMLStudio.

The adversarial reviewer modelled `c6c82e3`'s `uniqName` and `DiagramIdentifiers` in Python:

- U1 and M1 held;
- S0 failed on 160–210 trials per 1,000 per format;
- the insert-removed mutant was nearly invisible without the dense stratum.

Neither reviewer opened a census subject other than SwiftUMLStudio. One listed this repository's files
(`git ls-files`), without opening any, to locate `uniqueCaseName`.

**Run before the freeze, on the export only:**

- the baseline build (41 s);
- the law's file, compiled twice by `swift build --build-tests`, **never run**;
- `swift test list`;
- the full suite with both law suites skipped (1,823 tests);
- the six-test reduced suite of the first draft (1,817 tests), and the four-suite one (1,784 tests);
- `uniquifier_kill_arm.py mutants`, a listing.

**Run without a subject:**

- both self-tests (85/85 and 17/17), and #667's (255/255 and 16/16), which this pass imports;
- the rule-break audit;
- the power model, `scratchpad/669/power_model.py`, built on the reviewer's model;
- `uniquifier_census.py render` on SwiftUMLStudio's two files, which made calibration rows 1 and 3.

**Not opened:** any census subject other than SwiftUMLStudio. That includes this repository's
`ViewModelActionEnumEmitter.swift`, swift-syntax's macro expansion contexts, GRDB and swift-foundation. Their
shapes come from #669's text. Prediction 5's dagre shape comes from prior knowledge of the JavaScript library.

## Amendments

None.
