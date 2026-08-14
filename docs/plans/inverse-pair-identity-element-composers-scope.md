# Scope: composers for `inverse-pair` and `identity-element`

> **Status:** `declined` · **As of:** 2026-08-14

**Scoped, and the recommendation is DON'T** — including via the projection route, which was the
half of this worth investigating rather than dismissing.

The motivating count is in `docs/measurements/exploratory-swiftformat-grdb.md` §7.2: 41 GRDB
rows decline `unsupported-template`, of which **`inverse-pair` 17 and `identity-element` 14**
are the two largest. They were described there as "laws discovery proposes and verify cannot
attempt", which is true, and as the largest block of unrealised tests, **which is not**.

---

## §1 The composer is the blocker that reports, not the one that binds

Three independent blockers sit behind it, and the first is measured *in the same run*.

**The same carriers already decline `unsupported-carrier` on templates whose composers exist
today.**

| carrier | blocked here | already `unsupported-carrier` elsewhere in the same run |
|---|---|---|
| `SQLExpression` | 9 | **11** |
| `AssociationAggregate` | 15 | **6** |
| `SQLCollection` | 5 | **1** |

That is not a prediction about what would happen after building a composer. It is what already
happens, on the same corpus, on the same carriers, for templates that are fully composed.

**`inverse-pair` fires only when the carrier is NOT Equatable.** This is the template's stated
reason for existing: `RoundTripTemplate` vetoes when `T` is not Equatable because its emitted
property uses `==`, and `InversePairTemplate` surfaces the structural claim as an
informational Possible-tier row instead. So `g(f(x)) == x` is unwritable across its **entire**
population by construction, not by accident. Its own header names the remedy — "a custom
equality witness" — which is hand curation, not a composer.

**`identity-element`'s population is one generic, non-Equatable type.** All 14 rows carry
`AssociationAggregate`, declared `public struct AssociationAggregate<RowDecoder>` and
conforming to `Refinable` and nothing else. Generic parameters are already an
`unsupported-carrier` case, and `f(x, identity) == x` needs an `==` the type does not have.

---

## §2 The projection route — reachable, and still declined

The idea is sound and has shipped twice in this repo: when a type has no usable `==`, verify a
**projection** instead (`fixtures/equatable-signal`, `ModelLawTemplate`,
`SequenceViewModelLawTemplate`). For a SQL AST the obvious projection is the rendered SQL.

GRDB does render. `SQLExpression.sql(_ context: SQLGenerationContext)` and
`quotedSQL(_ db: Database)` both exist, and both are `internal` — **which is not the
obstacle**: the survey already emits `@testable import GRDB` into 42 stubs, so `internal` is
reachable.

**The obstacle is what the projection needs.** `quotedSQL` takes a `Database` — a live
connection — and `sql` takes a `SQLGenerationContext` built from one. `Database` is this
corpus's **single largest ungeneratable carrier at 17 rows**, and correctly so: a live
connection is not a value and no derived generator can produce one. So the projection route
reaches the law only by first solving the carrier the tool has already, rightly, declined.

An in-memory `DatabaseQueue` would satisfy it — and that is a **GRDB-specific fixture**, which
is the whole objection.

### §2.1 The line this draws, and it generalises past GRDB

Both shipped model laws work because **the projection comes from a conformance the tool can
see**: membership via `contains`, sequence view via `elementsEqual`. The tool derives them from
the type's protocols without knowing anything about the library.

Here the projection is a **library-specific method requiring library-specific setup**. Nothing
in `SQLExpression`'s conformances says "render me"; the knowledge that `sql(_:)` is the model,
and that it needs a `Database`, is domain knowledge a template cannot infer.

**So: a model law is derivable when the projection is a conformance, and hand curation when it
is an API.** That is the same statability gap `TriviaInsensitivityExperimentTests` reached for
the metamorphic family — the law is true and the tool cannot state it — arrived at
independently, on a different family, for a different reason.

The type is also documented as **"an opaque representation of an SQL expression"**. Proposing a
law about the internal structure of a type whose author calls it opaque is a fight with the
design, not a gap in it.

---

## §3 Population: one corpus

| corpus | `inverse-pair` | `identity-element` |
|---|---|---|
| GRDB | 17 | 14 |
| `SwiftInferCore` | **0** | **0** |
| swift-format | **0** | **0** |

Every row is GRDB, and within GRDB every row is one of three carriers. This is the shape
`whole-to-parts-partition-declined.md` abandoned on — "emittable population is 1 declaration in
1 corpus" — and the same clause applies before precision is even reached.

---

## §4 What would reopen it

**A witness, not a symbol**, for the reason `falsifier-naming-failure-modes.md` gives: no name
settles whether a population exists, and two attempts to name one for the layout gap in this
same session were both wrong.

Reopen on **≥5 `inverse-pair` or `identity-element` rows whose carrier is `Equatable`, across
≥2 corpora**. That is the condition under which a composer emits a law that can actually run,
and it is checkable from any banked run with a one-line query over
`fixtures/verify-runs/`.

Not a reopen condition: a bigger `unsupported-template` count. §1 is the reason — that count
measures which blocker reports first, not how many laws are recoverable.

---

## §5 What this does not claim

- **The templates are not wrong.** Both correctly identify real structure; `inverse-pair` is
  explicitly an informational tier and is behaving as designed.
- **The rows are not noise.** A reader learns something true from "these two functions look
  like inverses"; they simply cannot get an executed law out of it here.
- **Building the composers would not be harmful**, only unproductive: 31 rows would
  re-attribute from `unsupported-template` to `unsupported-carrier`, which is *truer* labelling
  — the same argument the WS-3a fallback deletion made. If that relabelling is judged worth
  having on its own, it is a small change; it is just not tests.
- **This is one corpus.** A persistence or query-builder library with `Equatable` AST nodes
  would change the answer, and §4 is how to notice.
