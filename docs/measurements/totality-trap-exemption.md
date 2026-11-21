# A trap is not an impurity to `input-totality`

> **Status:** `measured` · **As of:** 2026-11-21

**Verdict: shipped.** The impure-subject veto no longer withholds an `input-totality` row from a
subject whose **only** refuter is a trap. Every other template keeps the veto on a trap. Over 22
manifest corpora plus the 10-repo lexer corpus, the change **gains 14 `input-totality` rows, loses
none, and moves no other template's row**. 7 of the 14 are parsers whose trap plausibly sits on an
input path, which is the case the law exists for. Quote it as **14 rows moved, 7 worth reading**,
never as laws gained.

---

## 1. The defect

Found in passing by `lexer-corpus-census.md` §5.1. SwiftFormat's `tokenize(_ source: String) ->
[Token]` passes `input-totality`'s gate, yet drew no row. SEI's totality check counts `assert`,
`precondition`, `fatalError`, `!` and `try!` as partiality. A non-throwing function cannot be
`.pureButPartial`, so it is `.refuted` **with a witness**, and
`TemplateRegistry.applyImpureSubjectVeto` withdrew every law resting on it.

For most templates that is the intended veto: a trap is a precondition the generator does not know
about. **For `input-totality` it inverts the evidence.** The law claims *no input traps*, so a
visible trap is the strongest static sign that the law can fail. The veto withdrew it on exactly
those subjects. It did so silently, because a vetoed row is not printed. `purity-veto-precision.md`
priced `input-totality` removals together with every other template's, so the cost never showed.

## 2. The rule, and why it is sound

`SoundPurity.soleTrap(of:)` answers **the trap that is the only thing refuting this function**, or
`nil`. The scanner stores it as `FunctionSummary.soleTrap` for `.refuted` functions only. The veto
skips a summary when the template is `input-totality`, the summary has a sole trap, and it calls no
function `PackagePurityJoin` settled impure. The exempted row says why in `whySuggested`
(`` `tokenize` can trap (`assert`) — the case this law exists to catch ``), because a withheld veto
is a decision too.

A `.refuted` verdict carries **one** witness, SEI's first. The rule is sound only because of the
order SEI checks in, and each clause closes a way a trap could hide a real effect:

| hidden refuter | why the trap could mask it | what closes it | test |
|---|---|---|---|
| marker, file read, nondeterminism, construction | — SEI runs all of these **before** the trap scan | a `.partiality` witness means none fired | `trapBesideSideEffectStillVetoes` |
| refuting default argument | SEI checks defaults **after** the body | any parameter with a default answers `nil` | `trapHidingADefaultStillVetoes` |
| hidden static write | `ReducerPurityAnalyzer` is the other half of the meet and names no witness | it must say `.pure` on its own | `reducerRefuterWithholds` |
| callee settled impure elsewhere | a leaf witness cannot see past a call | `PackagePurityJoin.refutingNames` | `trapCallingImpureCalleeStillVetoes` |
| another template on the same subject | — | the exemption is keyed to `input-totality` | `otherTemplatesKeepTheVeto` |

Every clause errs toward `nil`, so the field **can only withhold a law, never admit one**. Losing
the field (a hand-built summary, a copy that drops it) keeps the veto.

**Scope: the discover path only.** Main's two other veto paths (#721) stay unchanged on purpose.
TestLifter's lifted rows never carry `input-totality`. The `--seeds` fallbacks synthesize
`determinism` and `mutator` laws, which a trap rightly withholds.

## 3. The A/B

`scripts/totality_trap_exemption_ab.py` ran a `swift-infer` built at `origin/main` `79908525` against
one built from this change. It used the same flags (`discover --sources <dir> --include-possible`),
the same day, and an empty working directory. It diffed printed suggestions by `(template,
Identity)`. **Every template other than `input-totality` is the control**: the change can only
un-veto `input-totality` rows.

### 3.1 The first run was void on three corpora, and why

Another session fast-forwarded swift-syntax, swiftlang-swift and swift-foundation about three
minutes into the run. That landed between their *before* and *after* scans, so swift-syntax showed
**606 `predicate` rows moved, with the control flagged**. Two scans of swift-syntax by the *before*
binary alone agreed row for row (977 = 977), which rules out nondeterminism. The three directories
were re-scanned on still trees (swift-syntax `60f0e15f9`, swift `9a9c2e9ae0d`, swift-foundation
`51139475`), and those are the figures below. **The script now records each checkout's HEAD and
uncommitted state before the first scan and after the second, and voids a directory whose tree
moved.** A control flag on a moving tree reads exactly like a broken change.

### 3.2 Result

| corpus | rows before → after | gained (`input-totality`) | lost | control moved |
|---|---|---|---|---|
| lexer corpus: Expression | 14 → 15 | 1 | 0 | no |
| lexer corpus: SwiftFormat `f09e539` | 201 → 202 | 1 | 0 | no |
| lexer corpus: SwiftSoup `e7f85f4` | 774 → 777 | 3 | 0 | no |
| swift-nio NIOCore | 69 → 70 | 1 | 0 | no |
| swift-syntax SwiftSyntax | 977 → 978 | 1 | 0 | no |
| swiftlang-swift stdlib core | 1,482 → 1,485 | 3 | 0 | no |
| swift-foundation FoundationEssentials | 883 → 887 | 4 | 0 | no |
| the other 30 directory scans | unchanged | 0 | 0 | no |
| **total** | | **14** | **0** | **no** |

### 3.3 The 14 rows, read

Each body was read for where its trap sits. None was run.

| class | rows | count |
|---|---|---|
| **a parser whose trap plausibly sits on an input path**: the law worth stating | SwiftFormat `tokenize(_:)` (six internal-invariant `assert`s) · Expression `parse(_:upTo:)` (`error as! Error`) · swift-syntax `parseTrivia(source:position:)` · stdlib `validateUTF8(_:)` · Foundation `compatibilityParse(buffer:)`, ISO 8601 `parse(_:fillMissingUnits:in:)`, HTTP-date `parse(_:in:)` | **7** |
| an index helper with a documented precondition on its arguments: the law is **false by contract**, and the subject is `internal` / `private` | stdlib `_nativeIndex(_:from:offsetBy:)`, `_findBoundary(_:before:)` | 2 |
| an `==` operator the template's gate admits: **a gate defect the veto was hiding**, not a parser | Foundation `Data.==`, NIO `ByteBufferView.==` (`getSlice(...)!` on an invariant) | 2 |
| a non-parser whose trap is guarded or on a constant: the law holds and says little | SwiftSoup `createShell(_:)` (`try!` on tag constants), `containsTrie(_:)` (`first!` under `count == 1`), `getActiveFormattingElement(_:)` (`next!` after a nil check) | 3 |

**7 of 14** is the yield. The 2 `==` rows are the template's gate admitting an operator; the veto
masked that until now. It is recorded here, not fixed: it is a separate change, with its own A/B.

## 4. What this does not claim

- **No law was run.** The rows reach `input-totality`'s output and its stub writer. Whether any
  refutes is the funnel's question, and per `template-refutation-rates.md` totality has refuted 0
  of 102.
- **No trap is shown reachable.** "Plausibly on an input path" is a reading of the body.
- **A function that throws was never affected.** Its trap made it `.pureButPartial`, which escaped
  the veto's `!isThrows` clause already.

## 5. Reproduce

```
python3 scripts/totality_trap_exemption_ab.py <before swift-infer> <after swift-infer> \
  ~/GitHub_projects/lexer-corpus/{Expression/Sources,Ink/Sources/Ink,Sourceful/Sources/Sourceful,Splash/Sources/Splash,Stencil/Sources/Stencil,SwiftFormat/Sources,SwiftSoup/Sources,SwiftyMarkdown/Sources/SwiftyMarkdown,leaf-kit/Sources/LeafKit,swift-mustache/Sources/Mustache}
```

Build both binaries with the same toolchain (`swift-6.4.1-RELEASE`). Do not run it while another
session is pulling corpus checkouts: the script now voids a moved directory instead of misreading
it, but a void directory is still a directory not measured.
