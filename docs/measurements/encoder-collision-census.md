# Does #674's encoder-collision advisory have a population? No site in 147 subjects: DECLINE (#674)

> **Status:** `measured` · **As of:** 2026-11-12
>
> **Decision: DECLINE (population)** under `docs/plans/encoder-collision-census-scope.md` §7. The census admitted
> **0 sites**, so 0 count toward #674's bar of 3 sites in 2 repositories other than SwiftUMLStudio.
> - **(a) works.** Over 30,734 files, 18 functions are colliding replacement chains. That is #674's grep's 7, all
>   found again, plus 11 more.
> - **(b) never fires through one of them.** Not one of the 18 is used as the id an emitter declares an entity
>   under. A widened recall probe finds no such literal anywhere, inside a loop or not, and neither did a hand read
>   of all 30 uses.
>
> The defect class itself is not rare. Four adversarial readers, each refuted, found **28 sites in 16
> repositories** where an emitter declares names under an id function that merges them. 21 of the 28 fail loudly,
> with a redeclaration in generated code. But **not one of them goes through a replacement chain**: they go through
> character maps, camel-casers and split/join. That is the case the scope's §7 names for a later census with a
> widened (a), and these reader counts cannot decide it. Two of the 28 are in this toolchain.
>
> The collision search is the reusable piece. It lives in `fixtures/encoder-collision/census-run/`.

**Issue:** Joseph-Cursio/SwiftInferProperties#674.

#674 found three SwiftUMLBridge emitters that declared each name `n` under `mermaidId(n)` or `safeAlias(n)`. Both
are pure `replacingOccurrences` chains that pass `_` through, so `Outer.Inner` and `Outer_Inner` were drawn as one
node. SwiftUMLStudio#52 fixed the call sites with a per-diagram `DiagramIdentifiers` table.

#674 proposed a Possible-tier advisory, with no stub, that fires on two signals together:
- **(a)** `f` is a module-local pure chain, and a search finds two strings it merges;
- **(b)** a loop appends a literal to a returned buffer, and that literal interpolates both `f(n)` and `n`.

#674 set its own gate: **at least 3 sites in at least 2 subjects other than SwiftUMLStudio.** The user added that
a site counts only if it is **reachable**, meaning two names the site could really be given collide. The universe
was #668's, plus 12 diagram writers and code generators cloned for this shape.

## Instrument

The scope was frozen and committed (`ece6bf9a`) before any source was read. The harness was committed
(`2dd7fc89`) before the run.

- **(a)** runs `ReplacementChainClassifier`'s own `steps` and `apply`. They are copied, because they are internal;
  the bodies are verbatim. A breadth-first search over the classifier's domain gives a shortest colliding pair.
  Every witness is checked again against Foundation's `replacingOccurrences`, and all 82 agree.
- **(b)** reads each `for e in S` loop's literals for an id expression and the name beside it, for the same name.
  - It chases bindings: `label` assigned in two arms that both contain `node` counts.
  - It requires a returned buffer.
  - It resolves the callee by name in the repository, preferring the enclosing type.
- **Controls**, asserted before the universe was read:
  - At `e36da59` the harness finds **exactly** #674's three sites: `DepsScript.swift:143`, `ComponentScript.swift:48`
    and `ComponentScript.swift:80`.
  - It finds #674's own witnesses: `" "` ~ `"-"` for `mermaidId`, and `" "` ~ `"+"` for `safeAlias`.
  - It does not take the interface line, `:82`.
  - At `9ad7631` it finds nothing.
  - All 12 synthetic cases land as frozen.

## The census

| group | subjects | files | loops |
|---|---|---|---|
| decision | 37 | 8,110 | 10,149 |
| unmet | 13 | 6,231 | 1,345 |
| wide | 67 | 13,450 | 4,912 |
| layout (#667's graph-layout corpus) | 18 | 1,270 | 4,074 |
| new clones: diagram writers | 6 | 906 | 662 |
| new clones: code generators | 6 | 767 | 243 |
| **total** | **147** | **30,734** | **21,385** |

**(a):** 1,167 functions have the candidate signature (157 of them `String` getters). 50 of them are pure chains,
and 18 of those collide.

| repository | chain | witness | what it does |
|---|---|---|---|
| SwiftUMLStudio | `DepsScript.mermaidId` | `" "` ~ `"-"` | the #674 id, now behind `DiagramIdentifiers` |
| SwiftUMLStudio | `ComponentScript.safeAlias` | `" "` ~ `"+"` | the #674 id, now behind `DiagramIdentifiers` |
| SwiftUMLStudio | `String.nomnomlEscaped` | `","` ~ `";"` | nomnoml label text |
| SwiftAssist | `BookTitle.restoreColons` | `": "` ~ `"_ "` | title text |
| SwiftAssist | `SwiftSourceScanner.normalizeLineEndings` | `"\n"` ~ `"\r"` | line endings |
| SwiftLintRuleStudioTeam | `markdownCell` | `"\n"` ~ `" "` | Markdown table cell text |
| swift-package-manager | `String.withSwiftLineEnding` | `"\n"` ~ `"\r\n"` | test support, unused in read files |
| SwiftLint | `String.removingDollarsAndBackticks` | `""` ~ `"$"` | a `Set` key for identifier matching |
| SwiftMutator | `LocalPackageDependencies.unescaped` | `"\""` ~ `"\\\""` | parsing |
| IceCubesApp | `AddAccountView.cleanServerStr` | `""` ~ `" "` | user input |
| postgres-nio | `String.encodedAsSaslName` | `","` ~ `"=2C"` | wire encoding |
| swift-markdown | `String.newlineEscaped` | `"\n"` ~ `"\\n"` | debug dump text |
| swift-protobuf | `NamingUtils.periodsToUnderscores` | `"."` ~ `"_"` | a generated field name (below) |
| MermaidKit | `DOTParserImpl.mapLabel` | `"\n"` ~ `"\\l"` | label text |
| SwiftDependencyGraphExplorer | `MermaidGraphBuilder.escapeMermaidLabel` | `"\n"` ~ `"\\n"` | label text |
| Acai | `String.mermaidGenerics` | `"<"` ~ `">"` | a type's display string |
| Acai | `String.mermaidTextEscaped` | `"\n"` ~ `" "` | label text |
| SwiftGen | `String.newlineEscaped` | `"\n"` ~ `"\\n"` | template context text |

**(b):** 1 site row, refused because it has no returned buffer: SwiftAssist's `AppleDocsIngester.ingest` log line.
- Admitted: **0**.
- In the recall column: **0**. No (b) site goes through any repository-local `String -> String`, chain or not.

## Predictions, scored

| # | prediction | outcome |
|---|---|---|
| 1 | 7–12 colliding chains | **missed high: 18.** All 7 of #674's grep are among them, but the wide group and the clones added 11. Every one of the 11 is a text escaper or normaliser, not an id |
| 2 | 0–2 admitted sites outside SwiftUMLStudio | **held: 0** |
| 3 | 3–10 recall sites, mostly not a chain, in the code generators | **missed: 0.** The code generators do not write `cid(n)` beside `n` in a loop literal (below) |
| 4 | 0 admitted sites in SwiftUMLStudio at `9ad7631` | **held** |
| 5 | DECLINE (population) | **held** |

**Cross-check with #674's grep** (`scripts/replacement_chain_census.py`, manifest and funnel groups). The grep finds
25 chains in the funnel, 13 after removing the copies under `.claude/worktrees` (hidden directories, which the
census skips). The harness finds the same 13 except `plainTitle`. That one is a getter on a struct, rooted at a
stored property, so it is not a unary `String -> String`, and `f(n)` cannot name it. This is why #674 counted 3
colliding chains in SwiftAssist and the harness counts 2.

## Recorded after the first report

A zero from a reader that admits only `for e in S` with an identifier pattern could be blindness, not absence. Three
checks were added after the first report. None of them enters the decision.

1. **A recall probe** (`Probe.swift`) looks at every string literal anywhere, in any loop form or none. It takes each
   one that interpolates `G(A)`, or a local `let` bound to it, beside `A`, where `G` resolves to a repository
   candidate. It finds **13 literals, and none of them goes through a colliding chain.** Only one goes through a
   chain at all: indexstore-db's `escapePath`, which has no witness and is a Ninja file's path text. The other 12 call
   non-chain helpers in log messages, doc text, or generated stub bodies in this repository and SwiftPropertyLaws.
2. **Every use of each of the 18 colliding chains**, read by hand. There are 30. In each one the chain makes label or
   display text, normalises line endings, escapes wire or parse text, or (SwiftLint) builds a `Set` key. Of the
   rest:
   - `mermaidId` and `safeAlias` are passed as function values into `DiagramIdentifiers` (the fix);
   - `markdownCell` is mapped over a table row;
   - two are unused in the files read.

   **The one id-like use is swift-protobuf's** `periodsToUnderscores(extensionScopeSwiftFullName + "_" +
   fieldBaseName)`. It names a generated Swift field, so a collision would be loud. But it has the `_`-separator
   shape the scope sets aside (§8), it is not in a loop beside the name, and the generator's namer guards field-name
   clashes elsewhere. That last point was not checked here.
3. **An adversarial search** by four independent readers, one per slice of the universe, looking by hand and without
   the harness for any emitter that declares entities under a lossy `f(name)`, in any loop form, with `f` a chain or
   not. Each report was then given to a refuter.

**Results** (`fixtures/encoder-collision/adversarial-2026-11-12.json`):

| slice | subjects | sites reported | survived the refuter |
|---|---|---|---|
| layout | 18 | 12 | 6 |
| clones | 12 | 17 | 11 |
| decision + unmet | 50 | 14 | 4 |
| wide | 67 | 23 | 7 |
| **total** | **147** | **66** | **28, over 16 repositories** |

- **No surviving site goes through a replacement chain.** Four reports named a chain, and every one was refuted
  or falls outside (a)+(b):
  - this repository's `InteractionTraceEmitter.suiteIdentifier` concatenates its chain with a suffix, so it is not
    a pure chain, and it writes one suite per run, not one id per element. A collision is a later run overwriting
    an earlier trace file;
  - swift-argument-parser's zsh `variableName` uses `replacing(_:with:)`, not `replacingOccurrences`, over CLI option
    spellings;
  - swift-protobuf's output file names and XcodeGen's bundle ids are inline expressions, not candidate functions,
    and declare no entities inside a returned document.

  So the harness missed nothing inside the shape it was frozen to read.
- **The 28 survivors:**
  - **18 character maps:** simonbs/dependency-graph's `safeName` (×3: Mermaid, DOT and D2; `Core_UI` and `CoreUI`
    both become `target_CoreUI`), Graffle's `Ident.name`, Natalie (×4), Laurine, SwagGen (×3), Acai's state ids, swift-package-manager's
    C99-mangled resource names, and swift-openapi-generator's `SafeNameGenerator` (×4).
  - **10 others**, camel-casers and split/join: Graffle (×2), swiftuml's `uniqName`, SwiftGen's
    `swiftIdentifier`, swift-argument-parser's completion function names, swift-protobuf's
    `toLowerCamelCase`, fluent-kit's joined SQL aliases, sourcekit-lsp's JSON-to-`Codable` refactoring, and the two
    below.
  - **21 of the 28 are loud.** Generated Swift with two identical declarations does not compile.
- **How far to trust these counts.** Each verdict comes from one reader and one refuter. They are unscored and were
  not hand-checked here, so they show that a population exists outside chains. They do not measure it. 16
  reports were refuted because a table, a uniquifier, a counter or a `Set` already handles the collision. Among
  them are CreateAPI ×4, Graffle's `Ident.unique` ×2, Acai's `mermaidSafeID`, SwiftDependencyGraphExplorer's
  `identifiers` table and swift-openapi-generator's schema names. That is the kind of fix SwiftUMLStudio#52 made.

**Found in passing, in this toolchain** (not filed):
- `KitSuiteEmitter.functionName` (`Sources/SwiftInferCLI/KitSuiteEmitter.swift:382`) splits a type name on `.` and
  camel-joins the parts. An `extension Diagram.Node: Equatable {}` beside a type `DiagramNode` therefore gives two
  `func diagramNode…` in one scaffolded suite, and the suite does not compile.
- SwiftPropertyLaws' `RecursiveGeneratorEmitter.helperName(for:)` is `"__gen" + typeName.split(separator: ".").joined()`.
  A nested recursive `Tree.Node` and a top-level recursive `TreeNode` therefore emit `__genTreeNode` twice into one
  stub. The helper's doc comment says it cannot collide.
- `InteractionTraceEmitter`'s trace path uses `workdirSegment`, which maps only `.` to `_`. A run on `Outer_Inner`
  therefore overwrites the trace of an earlier run on `Outer.Inner`.

**Disclosure.** The adversarial workflow ran 70 agents: 4 readers and one refuter per reported site. That is above
the session's medium size guideline of under 10, because verification fanned out per site.

## What this does not answer

- **Character-map and other non-chain id functions** (SwiftGen-style identifier escaping, `filter { $0.isLetter }`).
  (a) is chains only, as #674 specified. The recall column is empty because (b) never fires, not because those
  functions are injective. The adversarial readers looked at them.
- **The `_`-separator collision** (`ComponentScript.swift:82`, and swift-protobuf above).
- **Collisions behind a helper hop**, such as SwiftPropertyLaws' `QualifiedTypeName.identifier(for:)`.
- **A rate.** The clones were chosen for the shape.

## Reproduce

Run the first two from the repository root, and the third from `fixtures/encoder-collision/census-run`:

```bash
python3 scripts/encoder_collision_census.py controls fixtures/encoder-collision/subjects-2026-11-12.json
```

```bash
python3 scripts/encoder_collision_census.py report fixtures/encoder-collision/census-2026-11-12.json fixtures/encoder-collision/handcheck-2026-11-12.json
```

```bash
swift run -c release CollisionCensus run ../subjects-2026-11-12.json ../census-2026-11-12.json
```

The clones are at the revisions in the scope, §3.2.
