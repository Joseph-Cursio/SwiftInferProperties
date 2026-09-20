# Following a test-local to its binding — what it freed, and what it exposed

> **Status:** `measured` · **As of:** 2026-09-20

`ReceiverConstructionHarvester` copies the way a package's own tests construct a class the tool
cannot derive, and refuses any expression naming a lowercase identifier — a test-local the
generated file has no binding for. `corpus-funnel-census-2026-09-20.md` prices that refusal at
**37 stubs** corpus-wide and calls it deliberate:

> ⚠ **The refusal is deliberate and it costs 37 stubs.** `Visitor(pattern: pattern)` is the common
> shape in these tests, and copying it emits `cannot find 'pattern' in scope` — a compile error
> traded for a compile error.

It is only a trade if the binding is unreachable, and usually it is not. SwiftProjectLint's tests
call `makeVisitor()` **442** times, and at least **68** of its helper declarations are exactly the
bind-then-construct shape:

```swift
private func makeVisitor() -> TooManyEnvironmentObjectsVisitor {
    let pattern = TooManyEnvironmentObjects().pattern
    return TooManyEnvironmentObjectsVisitor(pattern: pattern)
}
```

The local is replaced by the expression it stands for, and the result re-checked.

## The A/B

Same subject tree, same seed binary, same kit pin; one `swift-infer` built from `main` and one
from the branch. Subject **SwiftProjectLint `f93d9edf`** — the SHA the 20 September census pinned.

| stage | before | after |
|---|---:|---:|
| seeds | 1,029 | 1,029 |
| named | 746 | 746 |
| any law | 659 | 659 |
| refutable law | 409 | 409 |
| stub file written | 434 | 434 |
| **stub compiles** | **251** | **253** |
| **law passes** | **248** | **250** |

✅ **The before arm reproduces the published census row to the digit** — 434 / 251 / 248 — which is
what licenses reading the after arm as the change rather than as a different harness. Every stage
above the compile line is identical, so nothing here moved a discovery row.

## The direct gain is +2, and it is not the finding

Two stubs freed, **zero lost**: `MainActorMissingVisitor_isCandidate_predicate` and
`ObservableMainActorMissingVisitor_isCandidate_predicate`. That is the ~5:1 decline-to-rows rule
landing where it usually does.

**The finding is the 54 stubs that changed their blocking reason.** `type '<Visitor>' has no member
'gen'` — the receiver, in **56 of 56** moved stubs, checked against each stub's own name — stops
being what kills them:

| set-aside cause | before | after |
|---|---:|---:|
| no generator for the receiver | 117 | **61** |
| a type is not in scope | 48 | 58 |
| the subject is `private` | 5 | **47** |
| a syntax error in the emitted text | 10 | 10 |
| everything else | 3 | 5 |

| was → now | stubs |
|---|---:|
| no generator for the receiver → **the subject is `private`** | **42** |
| no generator for the receiver → a type is not in scope | 10 |
| no generator for the receiver → other | 2 |

This is `#499`'s mechanism again: *a stub blocked on one thing usually fails on something else
first*, so fixing the first error does not free the stub, it reveals the true one. It was worth
recording there and it is worth recording here, because **what the revealed cause is decides who
can act on it**.

### The 42 are the population the census could not identify

The census's rule for widening a `private` subject is an ordering constraint:

> ⚠ **Access and derivation must fall in that ORDER.** Widening a subject whose arguments still
> have no generator frees nothing: measured directly, 137 widenings in SwiftProjectLint bought
> **1** compile until the receiver generator landed, and then the same widenings were worth
> **+121**.

Before this change those 42 stubs were indistinguishable from the rest of the 190-stub `private`
bucket, whose members the census describes as *mostly still have no generator, so widening them
would change a subject's code and free nothing*. They now say, in their own compiler error, that
derivation is no longer what stops them. **On this subject the widenable set is 47, not 5** — and
it is named, stub by stub, rather than estimated.

⚠ **That is a claim about what the compiler now reports, not a promise of 47 compiles.** A widened
subject can fail on the next thing behind it, exactly as these did.

### The 10 are a different owner

Five read `cannot find 'SyntaxPattern' in scope` and five `cannot find 'Parser' in scope`. The
harvested construction is correct Swift that names a type from a package *dependency*, and the
emitted stub does not import it — `#492`'s bucket, reached from a new direction. Supplying a
construction is not the same as supplying its imports.

## Two defects the measurement found in the change itself

✅ **A verbatim construction must outrank a recovered one.** Following a local makes *earlier*
construction sites eligible, and `harvest` kept the first in file order — so a type could be handed
a recovered expression in place of the verbatim one it already had.
`NamingConventionVisitor_isSwiftUIComponent_predicate` compiled before the inlining and failed
after it with `cannot find 'SyntaxPattern' in scope`: **one stub lost against two gained**, in the
first arm. Ranking verbatim above recovered removes it; the second arm loses none.

✅ **A name an enclosing parameter binds is dropped, not resolved.** Refusing every local made
shadowing harmless; following one does not. `categories.map { pattern in ShadowVisitor(pattern:
pattern) }` means the closure's own `pattern`, and with an outer `let pattern` a few lines up the
harvester answered it with the outer expression — confirmed by removing the filter, which emits
`ShadowVisitor(pattern: Shadow().pattern)`, a construction the test never wrote. The guard was
checked red against the unguarded code rather than assumed.

⚠ **A third, found on the way and fixed first:** `FreeNameChecker` skipped any name whose parent is
a `MemberAccessExprSyntax`, to let `Rule().pattern` through. Both halves of a member access hang off
that one node, so the **base** was skipped too, and `ChainedVisitor(pattern: pattern.category)` read
as self-contained. Also confirmed red against the unfixed checker.

## What it deliberately does not do

- A name with **no visible `let`** is refused, as before.
- A local whose **own binding does not resolve** is refused — `let pattern = makePattern()`
  substitutes to a call no generated file can make. Substitution moves the question rather than
  answering it.
- Only the **base** of a member chain is rewritten, so a local called `pattern` cannot rewrite the
  `.pattern` in someone else's chain.
- A substituted result that **no longer parses** is dropped rather than emitted — the 20 September
  census's own `expected ',' separator` finding is what that guard is for.
- Bindings are read from enclosing **code blocks** only, so a stored property is never substituted.

## Scope of the reading

⚠ **One subject.** SwiftProjectLint holds 45% of the corpus's stubs and both of this cycle's
generators were built for its shape, so `+2 compiles` is what this fix reaches *here* and says
nothing about a rate. The census's 37-stub figure is corpus-wide; the receiver bucket on this
subject alone fell by 56, which are different measurements of different things and must not be
subtracted from one another.

⚠ **Ten stubs still fail with a syntax error in text the reader did not write**, unchanged by this
work and unexplained — the same count on both arms. The 20 September census fixed one cause of
that message and this is evidence there is another.

## Reproducing

```
python3 scripts/corpus_funnel.py <out-dir> <swift-infer> <SwiftProjectLint CLI> SwiftProjectLint
```

Run once per binary into separate out-dirs; the per-stub causes are `packages[].set_aside` in
`result-SwiftProjectLint.json`.
