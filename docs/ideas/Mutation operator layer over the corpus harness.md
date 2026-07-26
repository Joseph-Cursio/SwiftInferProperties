# Idea: mutation-driven property quality — an operator layer over the corpus harness

## Status

**Idea only. Design-level.** A *producer* bolted in front of tooling that already
exists, not a new engine. Sibling to `docs/ideas/Refuted-high-confidence-guess as
candidate bug.md` (that note turns a *disproof* into a candidate bug; this one
turns a *surviving mutant* into a candidate gap in the property suite) and to the
self-dogfooding road test (`docs/roadtest-self-dogfood.md`). The concrete
integration target is **SwiftIdempotency's** `mutants/` harness, but every
corpus-carrying repo (MacCloud ×3 + the five tools) has the same shape.

**Home ≠ tool home.** This idea belongs here because mutation testing is the
*empirical dual* of swift-infer's refutability score — property quality is this
tool's mission. The *tool itself*, if it graduates, is cross-cutting: a shared
leaf serving every corpus, whose domain operators lean on **SwiftEffectInference**,
not swift-infer. The doc lives here; the package would not.

## The observation

The appendix already frames the refutability row of the road test as "mutation
testing (§30.4) asked at *proposal* time": a law is refutable if some plausible
implementation is rejected by it, and `f(x) == f(x)` is worthless because none is.
swift-infer computes that **statically, before execution**. Mutation testing is
the same question asked **at runtime, after the fact**: introduce a fault into
working code, re-run the tests, and a mutant that *survives* is a plausible
implementation the suite failed to reject — a tautology or an under-powered
generator, caught empirically. We have the static half. The empirical half is
missing, and it is the one that grades a property suite that is already green.

## What the corpus harness is today

SwiftIdempotency's `mutants/` is a **regression gate**, not a discovery tool:

- `patches/<id>.patch` — hand-authored reversible mutants (git-diff format).
- `manifest.json` — each entry carries a **named killer test** and `expected:
  killed`.
- `run-mutants.sh` — for each mutant: `git apply`, `swift build --build-tests`,
  run *only* its killer via `swift test --filter <test>`, classify
  killed/survives/error, `git checkout -- .`, revert. Exact and fast, because the
  kill is attributed by construction.

It re-confirms bug shapes *you already thought of*. It cannot find the survivor
nobody anticipated — that is the gap.

## The three deltas that make discovery a *sibling*, not a reuse

| | Curated corpus (today) | Mechanical discovery (proposed) |
|---|---|---|
| **Killer test** | known, run via `--filter` | *unknown* — must run the whole (scoped) suite |
| **Expectation** | `expected: killed` | none — the output *is* the survivor list |
| **Equivalent mutants** | none (hand-picked) | inevitable — needs triage + an ignore-list |

Rows 1–2 mean `run-mutants.sh` stays pristine as the CI gate; discovery is a
separate runner. Everything else — reversibility, patch format, manifest shape —
is reused verbatim.

## Design

### Directory layout (additive only)

```
mutants/
  manifest.json          # curated — the regression gate (unchanged)
  run-mutants.sh         # curated runner (unchanged)
  patches/*.patch        # curated, hand-authored (unchanged)
  generated/
    manifest.json        # emitted; expected: unknown, no killer
    patches/*.patch      # emitted, same git-diff format
    ignore.json          # adjudicated-equivalent fingerprints
    survivors.md         # the discovery report — the deliverable
  discover-mutants.sh    # sibling runner: whole-suite, report survivors
```

### The producer — a SwiftSyntax rewriter that emits patches

Its whole job is to *produce* the `(patches + manifest)` the runner already eats.
Emission mechanizes the exact steps the README documents for hand-authoring:

```
for each mutation site:
    apply one operator to the syntax tree     # SwiftSyntax rewriter
    write mutated source to the working file
    git diff -- <file> > generated/patches/<id>.patch
    git checkout -- <file>                     # revert; tree stays clean
    append entry to generated/manifest.json
```

**Operator set** — the generic four map directly onto the idempotency bug shapes;
the two domain-aware ones are the justification for owning the layer rather than
adopting muter, because a generic tool is structurally blind to them:

| Operator | Why it matters here |
|---|---|
| Relational (`<`↔`<=`, `==`↔`!=`) | boundary/off-by-one in `lub`, key comparisons |
| Logical connector / negate `if` | branch-sensitive effect inference |
| **Remove side-effect statement** | drops a `record(...)` or a retry pass — *this is* the `assert-property-runs-once` / `effects-property-skips-retry` mutants, generalized to every call site |
| Boolean / return-literal flip | detector-blindness shapes |
| **Effect-tier swap** (domain) | rewrite a `lub` result or `@Idempotent` annotation to an adjacent lattice tier — muter cannot synthesize this |
| **Key-derivation weakening** (domain) | derive `IdempotencyKey` from the entity, not `.id` — the `idempotencykey-derivation` mutant, mechanized |

### The sibling runner

`discover-mutants.sh` is the existing loop with rows 1–2 changed: no `--filter`,
run the whole scoped suite; `exit 0` means **survived** (report it), non-zero
means killed (discard). Output is `survivors.md`: `file:line`, operator, the diff,
and which suites stayed green.

### The payoff — discovery feeds the regression gate

```
discover → survivor → adjudicate ─┬─ real gap  → write a killer test, move the
                                  │              entry into the CURATED manifest
                                  │              as expected: killed
                                  ├─ equivalent → fingerprint into ignore.json
                                  └─ out-of-scope → drop
```

A mechanical survivor that is a real gap **graduates**: it gets a hand-written
killer and becomes a fast `--filter` guard forever after. Mechanical breadth
once; curated cheapness thereafter — the two halves in their lanes.

## Determinism and cost (the honest notes)

- **Determinism.** The scoped suite includes randomized property tests, so run the
  sweep under a **pinned seed** (`swift-property-based`'s `.fixedSeed`), or
  "survived" is indistinguishable from "flaked." But a frozen draw lets a mutant
  only a *different* draw would catch survive spuriously — so follow the seeded
  sweep with a **periodic unseeded, high-trial re-run over the survivor set only**
  (cheap, because survivors are few).
- **Cost.** Patch-per-mutant means one `swift build` per mutant — slower than
  muter's *schemata* trick (all mutants in one binary behind a runtime switch).
  That is the price of reusing `swift test` instead of owning an engine, and for
  a corpus of *dozens* of mutants it is fine. Scope tightly (a target dir, or
  diff-only on changed lines); parallelize with a `git worktree` per mutant if it
  ever gets slow. Reach for schemata only if the sweep ever grows into the
  thousands — a book corpus never will.

## Open design questions

1. **Generated-manifest schema** — the fields distinguishing a discovery entry
   from a curated one (`origin: generated`, `operator`, `site` fingerprint,
   `expected: unknown`). This is the producer/runner contract; freeze it first.
2. **Site fingerprinting** — key the ignore-list on `(file + enclosing function +
   operator + occurrence-index)`, not raw line, so reformatting and drift don't
   resurface adjudicated equivalents.
3. **Domain operators** — spec which tiers are "adjacent" for a meaningful swap,
   and what counts as a derivation site. This is where the design risk lives.
4. **Tool placement + dependency direction** — in-repo prototype vs. a shared leaf
   package; whether depending on SwiftEffectInference for the tier-swap operator
   is acceptable layering.
5. **Determinism knobs** — how the pinned-seed sweep and the unseeded survivor
   re-run thread through `.fixedSeed` in practice.

## Where to start

Smallest thing that proves the seam: the three generic operators (relational,
remove-side-effect, boolean-flip) plus the effect-tier swap, pointed at the `lub`
suite that the appendix already calls "exhaustively law-tested," in-repo under
`mutants/generated/`. One survivor on `lub` is a finding the word "exhaustive" was
hiding — the ideal first result, and self-consistent with the book's ethos.
