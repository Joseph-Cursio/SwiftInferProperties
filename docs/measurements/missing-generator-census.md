# The missing generator — the funnel's largest blocker, measured (2026-09-16)

> **Status:** `measured` · **As of:** 2026-09-17
> **§3's causes were added the same day**, from the probe §4 asked for.
> ⚠ **Re-taken 2026-09-17 on SwiftPropertyLaws 4.7.0, as a same-commit A/B — §5.** That re-take **corrects §1**: the count is **1,326** blocked stubs, not 1,160, and **627** distinct types, not 548.
> **Instrument:** `swift-infer` at `56926b98`, the 19 repositories of [`corpus-funnel-census-2026-09-16.md`](corpus-funnel-census-2026-09-16.md)

The corpus funnel re-run moved the binding constraint from *no writer exists* to *does not
compile*. This asks what is behind that wall.

**It is the generator, and it is bigger than everything else measured this cycle put
together: 1,160 of 2,058 emitted stubs — 56% — carry at least one `.gen()` the tool could
not derive.** ⚠ **Corrected in §5: 1,326 (64%).** The marker regex matched a spelling only when
a word character preceded `.gen()`, so `[LintIssue].gen()`, `T?`, dictionaries and tuples were
invisible to it — 166 blocked stubs, and every figure in §1 and §2 is an undercount by the same
mechanism.

Against the other causes from the same corpus: 666 name a type not in scope, 288 could not
infer a closure parameter (since fixed, #499), 132 are access-restricted.

## Why this was not measurable until now

The `.todo` marker has always been in the emitted text. What hid its size was ordering:
**a stub blocked on a missing generator usually failed on something else first.** #499 measured
269 of 288 closure-inference failures as also carrying a `.todo`, and fixing the annotation
changed their error to `type 'DoctorCommand' has no member 'gen'` — the true one. *A refuter
that fires first hides every refuter behind it*, paid again.

This census reads the marker at **emission**, so it needs no compile step and is not subject
to that ordering at all.

## 1. The shape of it

| | |
|---|---:|
| stubs emitted | 2,058 |
| stubs with ≥1 underived generator | **1,160 (56%)** |
| distinct types with no generator | **548** |
| stub-type pairs | 1,653 |
| covered by the top 10 types | 428 (26%) |

⚠ **Undercounts, corrected in §5**: 1,326 stubs, 627 distinct types, 1,893 pairs, top 10
covering 428 (23%). The long-tail conclusion below survives and strengthens.

⚠️ **This is a long tail, and that makes it unlike every other defect measured this cycle.**
The import problem was 88% one repository; the identity collapse was 17 sites; the generic-parameter
gate was 50 rows. Here the ten most-wanted types cover a quarter of the population and 548 types
share the rest. There is no single fix with most of the value behind it.

**Most wanted:** `Syntax` 99 · `FunctionCallExprSyntax` 83 · `ExprSyntax` 56 ·
`FunctionDeclSyntax` 38 · `VariableDeclSyntax` 31 · `TypeSyntax` 30 · `ClosureExprSyntax` 27 ·
`AttributeListSyntax` 24 · `NonInjectedNondeterminismVisitor` 21 · `MemberBlockSyntax` 19.

**By repository:** SwiftProjectLint 595 · SwiftAssist 94 · SwiftPropertyLaws 87 ·
SwiftLintRuleStudio 83 · SwiftUMLStudio 83 · SwiftEffectInference 52 · the rest under 40.
SwiftProjectLint is 51% of the total, and it is a syntax-analysis tool, so its carriers are
SwiftSyntax nodes.

## 2. What kind of type has no generator

Classified against the corpus's own declarations, per stub-type pair:

| declaration | pairs |
|---|---:|
| class with a superclass or conformance | **482** |
| plain struct | **318** |
| plain class | 59 |
| enum | 27 |
| actor | 21 |
| `private` / `fileprivate` struct or enum | 14 |
| **declared nowhere the scan looked** (external) | **685** |
| stdlib / Foundation | 16 |

Two of those are not defects:

- **The 482 classes with a superclass** are genuinely underivable by a memberwise strategy —
  a `SyntaxVisitor` subclass has no memberwise init.
- **The 685 external types** are the dependency problem, and importing them is not enough:
  it needs a `.package` and product edge, which
  [`dependency-carrier-imports-scope.md`](../plans/dependency-carrier-imports-scope.md)
  scoped and declined. That decline rested on a population of 2 rows and is stale, but the
  concentration objection applies here too.

**The 318 plain structs are the interesting bucket**, because a memberwise struct is exactly
what `GeneratorResolver` exists to derive.

## 3. Why the resolver declined — measured, over all 19 repositories

The probe §4 asked for is built (`GeneratorBlockerCensusMeasuredTests`) and has been run over
every scan group. It asks `GeneratorResolver` through the same entry point the accept path uses,
and where that cannot answer it reads the **shape** — stored members, initializers, enum cases —
rather than source text.

**3,296 type shapes scanned; 2,016 (61%) have no generator.**

| why | types | share |
|---|---:|---:|
| struct, nothing to build from | 490 | 24.3% |
| blocked by a member | 348 | 17.3% |
| struct, has members — **reason not visible** | 348 | 17.3% |
| enum, nothing to build from | 270 | 13.4% |
| class, no memberwise init | 228 | 11.3% |
| class, nothing to build from | 174 | 8.6% |
| struct, initializers only | 101 | 5.0% |
| actor, no memberwise init | 31 | 1.5% |
| enum, has members — reason not visible | 22 | 1.1% |
| actor, nothing to build from | 4 | 0.2% |

⚠️ **Two denominators, and they are not the same question.** The 2,016 here is every type the
tool *cannot build*; the 548 in §1 is every type a stub actually *asked for*. Supply gap and
demand. Neither is wrong and they must not be compared.

### The families, ranked

**Nothing to build from — 938 types, 46.5%.** No stored members, no initializers, no enum cases.
Hand-checked: `struct ActorReentrancy: PatternRegistrarProtocol` carries only a computed
`var pattern`, so the shape is right rather than the scan wrong. **This is a defect this
repository already recorded and shelved** — `filter-subset-stub-writer.md`: *a stateless struct
gets NO generator; `struct Stateless {}` → `.todo` … isolated on a four-line probe, upstream,
affects every template.* It was left unfixed because its population was unknown. It is the
largest single family, and `Gen.always(T())` serves any of them with an accessible
no-argument init.

**Has members and still refused — 370 types, 18.4%.** The probe cannot see why. It is kept as
its own outcome rather than folded into a neighbour, because an unexplained residue that gets
quietly bucketed is how §3's earlier regex attempt produced a number that looked complete and
was not.

**Blocked by a member — 348 types, 17.3%**, and the blockers are app-shaped:
`DiagramViewModel` 17 · `KnowledgeGraph` 16 · `BeadStore` 14 · `ModelRouter` 11 ·
`MacCloudSyncManager` 9. Those are view models and stores — classes and actors — so this family
is largely **downstream of the no-memberwise-init one**, not independent of it.

**No memberwise init — 259 types, 12.8%.** Genuinely underivable by a memberwise strategy.

⚠️ **The first reading of this probe was one target and was NOT representative.** On
`SwiftProjectLintRules` alone, *nothing to build from* was **70%** of declines and *has members,
reason not visible* was 5.7%. Corpus-wide they are **46.5%** and **18.4%**. The single target
overstated the finding and understated the residue — a reminder that this census's own §1
warning about concentration applies to its follow-ups too.

## 4. What to do next, and what not to

**The stateless-type fix is the one with a population behind it** — 938 types, 46.5%, and a
defect already isolated on a four-line probe. It belongs in the kit's `DerivationStrategist`
rather than here, and unlike everything else measured this cycle it plausibly moves *laws*
rather than rows, because a stateless type is often a leaf blocking a whole tree. ⚠ **Built
(SwiftPropertyLaws #49, v4.7.0) and that prediction is REFUTED in §5**: it cleared all 490
stateless structs and 101 more, and *blocked by a member* moved **348 → 347**. The leaves were
not holding up trees.

⚠️ **The 370 unexplained deserve the next probe, not a guess.** `GeneratorResolver` still
reports no reason; the probe reconstructs two of its three `nil` paths from the same inputs and
infers the third. Teaching the resolver to say why would replace that inference with an answer.

⚠️ **Do not reach for the head of §1's type list.** Those ten are SwiftSyntax nodes serving one
repository that is 51% of that count. A hand-written `ExprSyntax` generator would move this
census and not the general case.

⚠️ **`Duration` is worth checking on its own terms** — a stdlib type absent from `RawType`,
which is the kit's call rather than this repository's. Its population here was read by hand,
not counted.

## 5. Re-taken on SwiftPropertyLaws 4.7.0 (2026-09-17)

4.7.0 carries the stateless-struct derivation §4 asked for (#49, `Gen.always(T())`) and a
resolver that reports why it declined (#50–#53). Taken as a **same-commit A/B**: `c438c3f1`
built twice, with the kit pinned `exact: "4.6.2"` in one arm and at 4.7.0 in the other. The only
resolved dependency that differs is `swiftpropertylaws`, and the only source difference is the
verifier's kit-pin string, which stub emission never reads. Same worktrees, seeds, scan groups
and scripts. Stub emission ran the arms **sequentially**, because both write `.swiftinfer/` into
the shared worktrees and a recorded decision suppresses a suggestion.

**The 4.6.2 arm reproduces every published figure to the digit** — 2,058 stubs, 1,160 by the old
regex, 3,296 shapes, 2,016 with no generator, every §3 bucket — so the published numbers belong
to the kit, not to the binary they were first taken on, and the A/B is clean.

### 5.1 The correction to §1

The census regex, `(\w[\w.]*)\.gen\(\)`, needs a word character before `.gen()`. **A blocked
collection, optional, dictionary or tuple is invisible to it** — `[LintIssue].gen()` ends in `]`.
Counted on the marker text itself, `no generator derived`:

| | old regex | marker text | missed |
|---|---:|---:|---:|
| blocked stubs, 4.6.2 | 1,160 | **1,326 (64%)** | 166 |
| blocked stubs, 4.7.0 | 1,092 | **1,265 (61%)** | 173 |

Re-counting distinct types with the spelling anchored to the marker: **627** distinct, **1,893**
stub-type pairs, the top ten still **428 (23%)**. Nine blocked stubs parse no spelling and one
captured spelling is a bare `?`; both are small and stated rather than cleaned. **The long tail is
longer than §1 said.** §2's declaration breakdown was not re-taken and is an undercount by the same
mechanism.

### 5.2 What 4.7.0 moved

| | 4.6.2 | 4.7.0 | moved |
|---|---:|---:|---:|
| **types with no generator** | 2,016 (61%) | **1,425 (43%)** | **−591** |
| struct, nothing to build from | 490 | **0** | −490 |
| struct, initializers only | 101 | **0** | −101 |
| enum, nothing to build from | 270 | 270 | 0 |
| class, nothing to build from | 174 | 174 | 0 |
| class, no memberwise init | 228 | 228 | 0 |
| blocked by a member | 348 | 347 | −1 |
| has members, reason not visible | 370 | 371 | +1 |
| **stubs blocked on a generator** | 1,326 (64%) | **1,265 (61%)** | **−61** |

**Every stateless struct is cleared** — all 490, plus the 101 *initializers only*, which were
empty structs whose declared `init()` is callable. The enums and classes stay by design: a
namespace enum is uninhabited, and a class's inherited designated initializers cannot be proven
to include `init()`.

⚠ **591 types, 61 stubs — about 10:1 against.** The repository's rule, *state gains as rows moved,
never laws gained*, arriving on the supply side: most of the stateless structs were never a
generator a stub needed.

⚠ **The whole-tree prediction of §4 is refuted.** *Blocked by a member* moved by one type. A
stateless struct was rarely the leaf holding up someone else's derivation.

### 5.3 The single-value risk, measured at zero

A stateless type has exactly one value. Where it is a law's only generated input, every trial
draws the same value and a pass says nothing. **Of the 61 freed stubs, all 61 draw a
`Gen.always` argument — so #49 is what freed them — and none draws only constants.** Every one
pairs the stateless type, as a receiver (`Swift6ConcurrencyAuditor`, `ThinkingRecipeExtractor`,
`CorrectOrder`), with an argument that varies. ⚠ `CSVFormatter.format` looked freed to the old
regex and is not: its second argument is still `[LintIssue].gen()` — §5.1's defect, caught in the
act.

⚠ **Two instruments disagreed before this was believed**: one counted generator slots and read
2, one matched sampled expressions line by line and read 13. Reading the flagged stubs refuted
both — a member chain like `Gen<Character>.letterOrNumber.string(of:)` escaped the first, and
multi-line `zip` expressions escaped the second. The zero is from the sampled-argument parse,
confirmed to have parsed arguments in all 61.

### 5.4 What still stands

- The **370 unexplained** (371 now) are still inferred: this re-take kept the probe unchanged so
  the bucket means the same thing in both arms. 4.7.0's `resolutionFailure(forTypeName:)` can now
  answer instead, and reading it is the next change to the probe.
- **Enums 270 and classes 174** are not a derivation gap. The enums are namespace enums; a law
  over one should not be proposed at all, which is a discovery question in this repository.

