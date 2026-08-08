# Idea: mutation-driven property quality — an operator layer over the corpus harness

> **Status:** `proposed` · **As of:** 2026-07-26


## Status

**Idea only. Design-level.** A *producer* bolted in front of tooling that already
exists, not a new engine. Sibling to
`docs/archive/Refuted-high-confidence-guess as candidate bug.md`
(that note turns a *disproof* into a candidate bug — **it shipped 2026-08-08 as the
EXPECTED TO HOLD verdict, so read it for reasoning, not as a plan**; this one
turns a *surviving mutant* into a candidate gap in the property suite) and to the
self-dogfooding road test (`docs/measurements/roadtest-self-dogfood.md`). The concrete
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

## Where the curated corpus's guarantees come from (and what discovery can't inherit)

It is tempting to say a mechanical layer that reuses the runner *inherits* the
curated corpus's two best properties — near-zero equivalent-mutant noise and
determinism control. It does not. **Both properties live in the hand-authoring,
not in the runner plumbing**, so tracing their source also draws the boundary of
what transfers.

**Near-zero equivalent-mutant noise** (an equivalent mutant changes source but not
behavior, so *nothing* can kill it — it survives forever as a false alarm) comes
from two structural facts about curation:

1. Each mutant is authored to break a *specific guarantee* — `second = first`
   defeats the run-it-twice invariant that is the whole detection mechanism — so
   it is behavior-changing by intent. Mechanical operators mutate wherever the
   grammar allows, and most such sites are semantically inert.
2. `expected: killed` + "verified killed" *is* an equivalence filter: an
   equivalent mutant is by definition one that cannot be killed, so confirming the
   named killer goes red before admission proves non-equivalence. The corpus
   cannot *contain* an un-killable entry, because passing that gate is the
   precondition for entry.

**Determinism control** — a "survived" verdict that is really a flaky miss —
is suppressed by the curation, not the mechanics:

1. `--filter` to one named killer, not a whole-suite needle-hunt; attribution is
   by construction.
2. The killers are **robust negative controls, not needles**: `Counter.next()` is
   non-idempotent on *every* input; `array(of: 1...8)` is deliberately non-empty
   so the retry *always* doubles effects. The discriminator fires across the whole
   input space, so a random generator has no rare input to miss.
3. `withKnownIssue` inverts polarity — a blinded detector's *silence* becomes a
   red test rather than a quiet pass (this is what kills the first two mutants).
4. One killer (`fromEntity`) is a fixed-input example with no randomness at all.

**What a mechanical sweep actually inherits** is the narrow, real part: the
reversible apply/build/run/revert mechanics — clean tree, `git apply`/`checkout`,
one mutant at a time, no schemata state to leak. It does **not** inherit the two
guarantees, and this is why the design re-earns them elsewhere: equivalents are
inevitable, so discovery adds triage + `ignore.json` (§ delta table, row 3); and
with no known killer it must run the whole suite, so determinism is re-established
with seed-pinning + the unseeded survivor re-run (§ *Determinism and cost*). The
guarantees are the payoff of curation — which is exactly why the curated corpus
stays the cheap regression gate and the sweep stays a noisier, discovery-only tool
that *feeds* it.

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
discover → survivor → adjudicate ─┬─ real gap    → write a killer test, move the
                                  │                entry into the CURATED manifest
                                  │                as expected: killed
                                  ├─ gen-unreachable → fix the generator, re-run
                                  ├─ equivalent   → fingerprint into ignore.json
                                  └─ out-of-scope → drop
```

A mechanical survivor that is a real gap **graduates**: it gets a hand-written
killer and becomes a fast `--filter` guard forever after. Mechanical breadth
once; curated cheapness thereafter — the two halves in their lanes.

**The `gen-unreachable` branch is not optional, and this repo already proves it.**
A survivor can be killable *in principle* — a killer may even already exist — yet
survive because the suite's **generator cannot reach the witness**. The
self-dogfood road test (`docs/measurements/roadtest-self-dogfood.md`) documents both halves of
this:

- §9.1, "a confident green on a law that is false": `Decisions.merge` commutativity
  verified `measured-bothPass` over 100 trials though it is false, because the
  derived generator drew `identityHash` from ~62⁸ and `timestamp` from ~2⁶⁴, so
  the tie branch carrying the failure was unreachable — "refutable in principle
  and unrefutable in practice." Any law whose failure needs two generated values
  to **collide** (tie-breaks, cache keys, dedup, injectivity) has this shape.
- §7, a mutation near-miss from *sampling*: `40..<75` → `41..<75` was caught by
  only one of three tests, because a uniform draw hit `40` ~22% of the time — it
  "would have reported that mutant as survived four runs in five" until the domain
  was walked exhaustively.

The hazard is **misrouting**. Filing a `gen-unreachable` survivor as *equivalent*
permanently ignores a real, reachable-in-principle bug the generator merely masks
— the worst outcome. Filing it as a *real gap* and writing another killer is
pointless: the killer is not the missing piece, the generator's **distribution**
is. The remedy is its own — collision-bias the generator, or walk a small domain
exhaustively (§7) — then re-run. This is the same domain-relativity the seeded
sweep warns about (§ *Determinism and cost*), surfaced at triage time.

## Corpus lifecycle — grows, governed, prunes

The corpus is **living tooling, not a benchmark** — and it sits opposite the road
test's frozen yardstick on the one axis that matters. That yardstick is **frozen**:
it must never be edited in response to tool output (the "grades its own homework"
trap). Its form varies — a pre-written *answer key* (MacCloud) or a *prediction
logged before the first run* (`docs/measurements/roadtest-self-dogfood.md` §1, hard-frozen at
"nothing above this line is edited in response to" the results below) — but the
invariant is the same: **the yardstick must predate and ignore the tool output.**
The corpus is the reverse: it is *meant*
to grow with new information, and that asymmetry is the whole point. Conflating the
two is the most likely misreading of this design.

**How it grows** (in order of designedness):

1. **Promotion** — the graduate path above is the primary engine: a confirmed
   mechanical survivor becomes a standing `--filter` guard.
2. **Field defects** — a real bug found in the wild becomes a mutant encoding its
   shape, so the shape can never silently return (this is how the three *surviving*
   mutants in the appendix arose — each closed by fixing the *test*).
3. **New API surface** — a new assertion or annotation brings mutants for the ways
   it can go wrong.
4. **Toolchain changes** drive *re-runs*, not growth directly — but a bump that
   exposes a new blind spot yields a new mutant.

**Governed by shape-diversity, not count.** The manifest's `shape` field
(`retry-value`, `retry-effect`, `key-derivation`) and the README's "diverse across
shapes" are the governor: a mutant earns its place by representing a *distinct*
failure mode, because every entry costs a per-mutant build on each run. Growth is
a ratchet of learned bug shapes, not accretion.

**It prunes, too.** "Living" cuts both ways: when the code moves and a mutant's
target site disappears, it goes stale — the runner surfaces that as an
`apply-failed` FAIL — and should be updated or removed, not left to rot.

The mental model: the corpus is **institutional memory of "defects we've seen and
the exact tests that catch them,"** so no suite can regress into blindness on a
shape it once caught. That is why it belongs *with* the code and grows with it,
while the answer key stays sealed in the past on purpose.

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
