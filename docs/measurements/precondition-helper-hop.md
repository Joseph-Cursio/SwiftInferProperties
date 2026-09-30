# Following a precondition one hop through a helper: built, and it moves only Harbeth

> **Status:** `measured` · **As of:** 2026-09-29

`subject-harbeth.md` traced 5 of Harbeth's 7 traps to a generator the kit should have declined. The
`init(values:)` initializers of `Matrix3x3` and its siblings check their count through
`HarbethError.failed(…)`, which is `fatalError` in DEBUG. `InitializerPreconditionDetector` reads one
initializer's body, so it never saw that check. `criterion-a-swift-system.md` §8.5 sized the same gap
through a same-type method (`SystemString._invariantCheck()`) at a ceiling of 61 candidate sites and left
it unbuilt. The plan and predictions are in `docs/plans/precondition-helper-hop-scope.md`, committed
before any code.

## 1. The change

`PreconditionHelperHop` makes the scan's single pass record two more things:

- every function whose body calls a kit precondition function, keyed `Owner.name`, or `name` for a free
  function;
- for each initializer, the keys of the functions it calls.

`TypeShapeBuilder` joins the two, so an initializer that calls a trapping helper reaches the kit with
`assertsPrecondition == true`. The kit's existing decline then applies unchanged, with no kit release.
The hop goes one level only, and matches by name. It was first wired where the accept path and `index` build
their shapes (`Discover+Pipeline`).

## 2. Result: the three funnel measurements

**Harbeth, same code (`6c01592`), funnel census before and after:**

| | before | after |
|---|---:|---:|
| stubs | 230 | 230 |
| compiled | 88 | **83** |
| passed | 66 (57 behaviour) | 66 (57 behaviour) |
| trapped | 7 | **2** |

The 5 stubs that stopped compiling are exactly `Matrix3x3`, `Matrix4x4`, `Matrix4x5`, `Vector3` and
`Vector4` `codable-round-trip`. They are now set aside with `.todo`, and nothing else moved. The two
remaining traps are `C7Rotate.resize` and `PipelineBinaryArchiveSnapshot.registeredPipelineCount`, as
before.

**The 19 funnel repositories, same code:** every per-repository line is identical to census 20, on every
bar (1,176 stubs, 940 compiled, 773 passed).

**A full `make test`** (unpiped, exit 0): fast **6,236**, which is the previous 6,233 plus this change's 3
tests, and batches **224**, every batch to the digit.

| # | prediction | result | |
|---|---|---|---|
| 1 | Harbeth traps 7 → 2, the stubs set aside with `.todo` | **7 → 2**, exactly the five | ✅ |
| 2 | Harbeth passes ≥ 66 | **66** | ✅ |
| 3 | the 19 funnel repositories: ≤ 10 stubs change, no pass becomes a failure | **0** change | ✅ |
| 4 | `make test` green, every batch unchanged | green, every batch unchanged | ✅ |

## 3. Population: what the hop marks across the 20 manifest corpora

The funnel moves only where a stub asks for the type, so a second reading counts initializers directly.
A throwaway probe (kept at `fixtures/precondition-helper-hop/population-probe.swift.txt`, output beside
it) scanned every manifest corpus and built each type's shapes with and without the hop:

| | |
|---|---:|
| initializers | 5,129 |
| marked by the hop | **300**, on 278 types |
| of which swift-syntax | 247, one per syntax node, all through `Syntax.forRoot` |
| types that **lost** initializer-based derivation | **5** |

**The 247 cost nothing.** `Syntax.forRoot` asserts on the arena, not on the caller's arguments, so for a
syntax node the mark is wrong. But no syntax node derived through an initializer before, so no generator
changes. ⚠ *Corrected in §4: `TokenSyntax` did, and loses it.* The other 53 marks are spread over GRDB (12, mostly `GRDBPrecondition`, a free wrapper around
`precondition`: Harbeth's own shape), swift-collections (29: `_checkInvariants`, and `append`/`insert`
on fixed-capacity `Rigid*` types), and single digits elsewhere.

**The 5 that lost derivation**, read against source:

| type | helper | verdict |
|---|---|---|
| `SuffixRowAdapter` (GRDB) | `GRDBPrecondition(index >= 0)` | correct: an argument precondition |
| `CircularBuffer.Index` (swift-nio) | `debugOnly { assert(…) }` | plausibly correct |
| `BigString.Index` (swift-collections) | `_bitsForUTF8Offset` | plausibly correct |
| `Heap` (swift-collections) | `_checkInvariants()` | **false**, checked |
| `BitSet.Counted` (swift-collections) | `_checkInvariants()` | **false**, checked |

⚠ **The two false declines are row 74's defect arriving through the hop.** Both `_checkInvariants()`
bodies that call `precondition` sit inside `#if COLLECTIONS_INTERNAL_CHECKS`, a condition the build
does not set. The live branch is `public func _checkInvariants() {}`. `FunctionScanner` walks inactive
`#if` branches as if they were live (`inactive-if-config-census.md`), so the trapping declaration marks
the key and the empty one cannot unmark it. `Heap`'s invariant would hold for any input in any case,
since `init(_:)` heapifies before checking. This is recorded, not fixed: the fix is row 74's, not the hop's.

**Against §8.5's ceiling of 61:** swift-collections' `_checkInvariants`, the shape §8.5 named, is marked
on 7 types, and every one of those marks is the inactive-branch case above. `SystemString` is not in the
manifest. The ceiling was a count of candidate sites. The measured figure that matters is **5 types
whose generator changes, 3 of them correctly**.

## 4. Wired everywhere, 2026-09-30 — and what `discover` changed

§1's join ran in one `TypeShapeBuilder` caller, so discover's own generator annotation, lifted
suggestions, the shape-driven templates and dependency shapes all built shapes without it. A `discover`
listing could therefore name an initializer-based generator that the accept path then declined. The join
now runs in `FunctionScanner.scanCorpus`, once per file and again at package scope, so every consumer
of `typeDecls` sees it, and the separate `trappingFunctions:` parameter path is gone.

**Row-level A/B over the 20 manifest corpora** (the row-dump probe, extended to print each suggestion's
generator; the hop was disabled in the before arm): **5,994 rows both sides, same row set, and 5
suggestions change generator** (`fixtures/precondition-helper-hop/discover-generator-changes-2026-09-30.tsv`):

| suggestion | carrier | before → after | |
|---|---|---|---|
| `_clearUTF16TrailingSurrogate` idempotence, `isAbove(_:)`, `isBelow(_:)` | `BigString.Index` | derived initializer → `.todo` | correct, a §3 decline |
| `isMarked(index:)` | `CircularBuffer.Index` | derived composite → not computed | correct, a §3 decline |
| `SyntaxRewriter.visit(_:)` idempotence | `TokenSyntax` | derived initializer → `.todo` | **false**: `init` goes through `Syntax.forRoot`, whose `precondition` checks the arena |

⚠ **This corrects §3.** It said no syntax node lost derivation, because the probe asked the strategist
about each shape in isolation, without the resolver context discover supplies. `TokenSyntax` derives
only with that context, so the probe missed it. **Read §3's 5 types as a lower bound.** At the level
that matters, suggestions whose generator changes, the count is 5 rows over 3 types: 2 correct and 1 false,
and the false one is the `Syntax.forRoot` family §3 already named.

The accept path is unchanged, because it already had the hop. Harbeth re-run: 83 compiled, 66 passed,
2 trapped, identical.

## 5. What this does not answer

- Declining trades a trap for a `.todo`. The five Harbeth types still have no generator, because a
  generator honouring a count precondition is the kit's job.
- The hop matches by name, one level deep. A helper that traps only on paths the arguments cannot reach
  counts the same as one that always does, and `Syntax.forRoot` is the measured example.
