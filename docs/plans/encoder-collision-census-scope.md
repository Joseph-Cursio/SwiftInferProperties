# Encoder collision census (#674): scope, frozen before the run

> **Status:** `proposed` · **As of:** 2026-11-12

**Issue:** Joseph-Cursio/SwiftInferProperties#674.

## 0. The question, and what this decides

#674 records a defect in three SwiftUMLBridge emitters (SwiftUMLStudio `e36da59`). Each loops over a model's names
and declares each name `n` under `f(n)`, writing the raw name beside it as the label. `f` is `DepsScript.mermaidId`
or `ComponentScript.safeAlias`, both pure `replacingOccurrences` chains that pass `_` through. So `Outer.Inner` and
`Outer_Inner` were declared under one id, and Mermaid drew one node. SwiftUMLStudio#52 (`363168e`) fixed the call
sites with a per-diagram `DiagramIdentifiers` table. Both sanitizers are unchanged at HEAD.

**The proposal** is a Possible-tier advisory, with no stub. It fires only when both of these hold:

- **(a) `f` demonstrably merges.** `f` is a module-local unary `String -> String` whose body is a pure replacement
  chain. A search over `ReplacementChainClassifier`'s domain finds two strings it maps to one.
- **(b) The site declares names apart.** In one function, a loop appends to a buffer the function returns, and one
  literal in that loop interpolates both `f(n)` and `n`.

**Its gate**, which #674 states, is deliberately stricter than the pipeline walk's stop rule
(`docs/plans/corpus-pipeline-walk-scope.md`). BUILD only if the census finds **at least 3 sites in at least 2
subjects other than SwiftUMLStudio**. Otherwise DECLINE on population, and keep the collision search as the reusable
piece. The shape was read off SwiftUMLStudio, so its sites do not count, and they are fixed at HEAD anyway.

**Decided with the user on 2026-11-12:**

- **A site counts only if it is reachable**: two names the site could really be given collide. #674 calls
  reachability a hand-check, and an advisory is worth emitting only if real names merge.
- **The universe** is #668's frozen universe plus 12 new clones of diagram writers and code generators (§3).

There is no kill arm. #674 says the law kills no mutants and gets no stub: it is red on the unmutated sanitizers
and stays red after the correct fix. The controls (§4) take the kill arm's place as the check that the instrument
sees the witness.

## 1. Signal (a): the colliding chain

### 1.1 Candidates

A candidate is either of these:

- a function with exactly one parameter, of type `String`, returning `String`;
- a `var NAME: String` getter in an `extension String`, with root `self`.

Its body must be one expression, or a single `return` of one, that `ReplacementChainClassifier.steps(of:root:)`
accepts. That means a chain of `replacingOccurrences(of: LIT, with: LIT)` rooted at the parameter, or at `self` for
the getter, with a non-empty pattern in every step. A candidate is indexed under its name, its enclosing type, its
repository and its file.

The harness copies `steps`, `step`, `apply` and `replacingAll` verbatim from
`Sources/SwiftInferCore/ReplacementChainClassifier.swift`. They are `internal` and cannot be imported, and copying
them verbatim is what makes this the classifier's own reading.

### 1.2 The collision search

- **Domain:** the classifier's own. Strings up to length `searchLength` (3) over the chain's characters plus `x`,
  sorted and capped at `alphabetCap` (9).
- **Order:** breadth-first, from shortest to longest and in alphabet order. The first pair `s ≠ t` with
  `apply(s) == apply(t)` is the **witness**. Every string seen is recorded under its image, so the first repeated
  image gives a shortest pair.
- **Soundness:** a witness is a real merge. Finding none does not mean `f` is injective. #674's own example is
  `ActivityScript.mermaidEscape`, which maps both `"` and `&quot;` to `&quot;` beyond this domain's reach.

### 1.3 The identifier witness

For each step `(p, r)`, the harness tries `Ab` + `p` + `Cd` against `Ab` + `r` + `Cd`. For `mermaidId`, that pair
is `Ab.Cd` and `Ab_Cd`, the shape of `Outer.Inner` and `Outer_Inner`. It records the first pair that collides and
differs. This is a prompt for the hand-check (§5), not a reachability verdict.

## 2. Signal (b): the site

### 2.1 The loop, the name and the literal

The harness walks every function, initializer, accessor and closure body, and in each one every `for e in S` loop.
The pattern must be a plain identifier. The sequence can be anything.

- **A name `n`** is `e` itself or a member path of it (`e.a.b`) with no calls.
- **A local binding of `n`** is a `let` or `var`, declared in the loop body, where every assignment (initializer,
  `=` or `+=`) is `n` or a string literal interpolating `n`. That covers `label` assigned in two arms that both
  contain `node` (`DepsScript.swift:137–142`). A binding with any other assignment is not a binding of `n`.
- **An id expression** is a call `F(n)`, `Self.F(n)` or `T.F(n)` with one unlabelled or labelled argument that is
  exactly `n`, or a member access `n.F`. It may also be a `let` in the loop body whose initializer is one of those.
- **The literal** is a string literal in the loop body whose interpolations include an id expression (directly or
  as an identifier naming the binding) and `n`, or a binding of `n`, **for the same `n`**.

### 2.2 The buffer

The literal must reach a returned buffer:

- the literal is the argument of `buf.append(…)`, or the right side of `buf += …`, or of `buf += [ … ]`;
- or it initialises a loop-local `let` that is appended in that way;
- `buf` is a `var` declared in the function, outside the loop;
- the function returns `buf`, `buf.joined(…)` or `buf.joined()`, optionally `+ LIT`, or is a single-expression
  getter with that shape.

That excludes `print`, loggers, `fatalError`, `precondition` and error messages, a single entity's `description`,
and test messages.

### 2.3 Resolving `F`

`F` is resolved by name in the repository's candidate index (§1.1). The index holds every function or getter with
the candidate signature, whether a chain or not.

- **Preference:** a declaration in the same type (or its extensions in the repository) beats one elsewhere. A
  member access `n.F` resolves only to `extension String` getters.
- **Ambiguity:** two or more declarations at the preferred level are recorded as `ambiguous`, and the site is
  refused.
- **Unresolved:** a name with no declaration in the repository (Foundation, a dependency) is not a site.

### 2.4 Skips

In the same function, if the id expression, or a binding of it, appears as any of these, the site is
**skipped**, with the reason recorded:

- a subscript argument (`d[id]`);
- the argument of `insert`, `contains` or `remove` on anything, or an element of a `Set(…)` or `Set` literal;
- an operand of `==` or `!=`.

That is the caller handling collisions, as SwiftAssist's `AntiPatternStore.generateId(from:)` does with `merge`.

### 2.5 Where a site lands

A site that passes §2.1–§2.4 is filed by its resolved `F`:

- **admitted**: `F` is a chain (§1.1) and §1.2 finds a witness;
- **recall: chain, no witness**: `F` is a chain and the search finds none;
- **recall: not a chain**: `F` has the candidate signature but its body is not a pure chain (a character map, a
  `filter`, a regex).

The recall rows are never in the decision. They answer whether widening (a) would matter.

**One row per literal.** Rows are merged as copies when owner, function name and literal text match across
repositories (forks and vendored copies), and are kept under the first repository in universe order.

## 3. The universe, frozen

### 3.1 #668's universe

The four groups of `docs/plans/xml-emitter-census-scope.md` §2, asserted by `scripts/xml_emitter_census.py`'s
`groups()`, with that script's skipped-file rules:

| group | subjects |
|---|---|
| decision | 37, including SwiftLint at `ec4691d9e` and SwiftUMLStudio at `9ad7631` |
| unmet | 13 |
| layout | 18, #667's graph-layout corpus at its frozen revisions |
| wide | 67 (`WIDE668`, hash `5ce9dbf9…`) |

SwiftUMLStudio is read at `9ad7631`, where #52's fix has removed the sites. Its rows are reported and excluded from
the gate.

### 3.2 The new clones

**The rule** was written before any of these repositories was read. Six GitHub searches were taken on 2026-11-12,
each with `language:Swift`, sorted by stars, top 12: `plantuml`, `mermaid`, `graphviz`, `uml`, `code generator` and
`diagram generator`. The raw results are committed as `fixtures/encoder-collision/clone-search-2026-11-12.jsonl`.

**The screen** read descriptions only. A repository was kept if its description says it **writes diagram text**
(PlantUML, Mermaid, DOT) or **generates Swift source**. These were excluded:

- repositories already on disk (MarcoEidinger/SwiftPlantUML, apple/swift-openapi-generator,
  lukilabs/beautiful-mermaid-swift);
- editors, viewers, Quick Look plug-ins and Markdown apps;
- a wrapper of a listed repository (SwiftPlantUML-Xcode-Extension);
- runtimes (swift-openapi-runtime), example and design-pattern repositories;
- a QR code library, an ER canvas, a state-machine framework, and documentation generators (SourceDocs).

**What was kept:** the top 6 by stars of each kind. Each was cloned shallow at its default branch's head into
`~/github_projects/encoder-collision-corpus/<owner>__<repo>`, at these revisions:

| kind | repository | revision |
|---|---|---|
| diagram | SwiftDocOrg/GraphViz | `74b6cbd8c5ecea9f64d84c4e1c88d65604dd033f` |
| diagram | gabrielepalma/poddotify | `d3ead2f11df8b4ff04e95972b56746f5844566f2` |
| diagram | palaniraja/swiftuml | `07d96b6744e205216f46e7ffb54c5f81411732b8` |
| diagram | Ryu0118/swift-dependencies-graph | `e9c8abd4ff5d84e24421c50e66a6781213857365` |
| diagram | Christmas-Blues/tca-diagram | `e1bdc0d52d045868d48689be7736df6101e322a4` |
| diagram | pauljohanneskraft/Acai | `30f4223a55c11d8c8ffeadc0692a65fcf4930a17` |
| codegen | SwiftGen/SwiftGen | `ddb03a73cab2a9feaf870b00ecab0fdda3d451e1` |
| codegen | JiriTrecak/Laurine | `230fa63f3862bd88e487f1caf673a2acc4d8c4e3` |
| codegen | krzyzanowskim/Natalie | `0cab43da7e6d59c85ce379b186b04f0c6d51b4bd` |
| codegen | Bouke/SwiftInitializerGenerator | `8b0c4610d2d40e3a4ec5a6ad17656dd3798561e5` |
| codegen | yonaskolb/SwagGen | `61877cb860d59cdf4c2cc747354ec9d8b397d588` |
| codegen | CreateAPI/CreateAPI | `7d0a70a8e1e18387738d19d7167b15e996e1d33f` |

The script asserts each clone is at its revision with a clean tree.

**Disclosure.** These were chosen for the shape. Together with the layout corpus, this census can show that a
population exists; it cannot give a rate. #674 says the same.

## 4. Controls, asserted before the universe is read

The harness exits non-zero, having read no subject, if any control fails.

**Verbatim**, from `fixtures/encoder-collision/census-run/control-sources/`, each read as its own repository:

| control | expected |
|---|---|
| `e36da59` `DepsScript` + `ComponentScript` + `ActivityScript` | 3 admitted sites: `DepsScript.buildMermaidText` (the `safeId` / `label` line), `ComponentScript.buildPlantUMLText` (the component line) and `ComponentScript.buildMermaidText` (the `subgraph` line) |
| the same | `mermaidId` and `safeAlias` are colliding chains, each with an identifier witness; `mermaidEscape` is a chain with no witness |
| the same | the interface line (`safeAlias("\(component.name)_\(interfaceName)")`) is not a site: its argument is not a name |
| the same | the edge and `style` lines are not sites: neither interpolates the name beside its id |
| `9ad7631`, the same three files | no admitted site |

**Synthetic** (`Controls.swift`), with one colliding chain `sid` and one character-map sanitizer `cid` in scope:

| case | expected |
|---|---|
| `print("\(sid(n)) \(n)")` in the loop | not a site (no buffer) |
| `fatalError` / `precondition` message | not a site |
| `var description: String { "\(sid(name)) \(name)" }` (no loop) | not a site |
| the id also inserted into a `Set` | skipped |
| the id also used as a `Dictionary` key | skipped |
| the id also compared with `==` | skipped |
| `label` assigned in two arms, both containing `n` | admitted |
| `label` with an arm that does not contain `n` | not a site |
| `cid(n)` beside `n` | recall: not a chain |
| a sanitizer named like a Foundation method with no declaration in scope | not a site |
| a buffer returned as `lines.joined(separator: "\n") + "\n"` | admitted |
| two declarations of `sid` in two other types | refused, ambiguous |

**The Foundation check.** Every witness and identifier witness the run reports is evaluated again by real
`String.replacingOccurrences(of:with:)` in the harness, and the run fails if any disagrees with `apply`.

## 5. The hand-check

Every admitted row gets these verdicts. The checker reads the row's function, `F`'s declaration and the callers of
the row's function in the same repository.

- **`read`**: the site declares one entity per element under the id, in a document the function returns.
- **`merge`**: the witness collides. The harness's Foundation check decides this.
- **`reachable`**: two names from the element's real domain collide under `F`. The domain might be Swift type
  names (including generics and nesting), module names, file names, schema names or asset names. The pair is
  recorded, preferring identifier characters (`Outer.Inner` / `Outer_Inner`). If no in-domain pair exists, the
  verdict is false.
- **`handled`**: a caller in the repository dedupes by `F`, or keys by it, before the site runs.
- **`loud`**, a column only: whether the collision makes the output invalid (a redeclaration in generated Swift, a
  parse error) or merges silently.

Recall rows get `read` and `reachable` only, so the write-up can say what widening (a) would add.

**Adversarial pass.** One read-only refuter agent per counted row, up to 8, and in batches beyond that, each told
to refute `read`, `reachable` and `¬handled`. A refutation that holds up when re-read moves the row.

## 6. Predictions, frozen

1. **Colliding chains:** 7–12 over the universe. That is the grep's 7 (SwiftUMLBridge 3, SwiftAssist 3,
   SwiftLintRuleStudioTeam 1), plus 0–5 from the wide and layout groups and the clones.
2. **Admitted sites outside SwiftUMLStudio:** 0–2. DOT writers mostly quote ids rather than sanitize them, and code
   generators use character maps (SwiftGen's identifier escaping is one).
3. **Recall sites:** 3–10, mostly `not a chain`, in the code generators.
4. **SwiftUMLStudio at `9ad7631`:** 0 admitted sites.
5. **Decision: DECLINE (population).**

## 7. The decision, fixed now

A **counted site** is an admitted row with `read ∧ merge ∧ reachable ∧ ¬handled`, after the adversarial pass.
Subjects are git repositories (toplevels), and copies count once (§2.5).

1. **BUILD**: at least 3 counted sites outside SwiftUMLStudio, in at least 2 repositories.
   - File the build issue: (a)'s collision predicate beside `ReplacementChainClassifier`, (b)'s site visitor, and
     the advisory with #674 §5's caveats. Include precision (`read` over admitted, reported, not gating).
   - #674 stays open until that build lands.
2. **DECLINE (population)**: otherwise.
   - Close #674 as not planned, with the counts and the user's approval.
   - The collision search stays in `fixtures/encoder-collision/census-run/` as the reusable piece. The write-up
     says so.

The recall column does not enter the decision. If recall sites would clear the gate, the write-up says so, as the
case for a later census of a widened (a).

## 8. What this does not answer

- **The `_`-separator collision** at `ComponentScript.swift:82`, where an interface id meets a component named
  `A_B`. It is not caused by `f` and spans two sites.
- **The uniquifier breaks** of the same document-level law, which are #669's.
- **Widening (a) to character maps.** The recall column only sizes this.
- **A rate.** The clones were chosen for the shape.
- **Collisions behind a helper hop**, such as SwiftPropertyLaws' `QualifiedTypeName.identifier(for:)`: (b) follows
  no hops.

## 9. Disclosures before the freeze

- **Some of the universe was already read** in #668, and in this session for #673. SwiftUMLBridge's emitters are the
  witness. No new clone had been opened before this freeze: they were cloned and their revisions recorded, and that
  is all.
- **The grep estimate** in #674 (2026-10-10) read the manifest and funnel groups with `scripts/replacement_chain_census.py`'s
  extraction. The harness's candidate list is cross-checked against that script on the funnel group, and every
  difference is explained in the write-up.

## 10. Amendments

None yet. Any amendment is dated and appended here, and none is made after the universe is read without saying so.
