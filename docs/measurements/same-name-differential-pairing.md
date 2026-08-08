# Same-name differential pairing — can the miss class be templated?

> **Status:** `declined` · **As of:** 2026-08-08

**The question.** `DifferentialTemplate` exists to find *two implementations of one
specification*. Pointed at this repo it proposes rows only from lifted test bodies and
**zero from source**, while `Sources/` declares the same generic-parameter strip **nine
times** (`docs/measurements/roadtest-self-dogfood-2026-08-08.md` §3). `VariantMarkers` pairs
on a name *marker* — `parseIncrementally`, `appendUnchecked`, `fooSlow` — and real
duplication here is spelled with the **same name in a different type**, which carries no
marker.

The road test closed that instance by hand, with a property suite over six of the nine
copies. That is a guard for one instance, not a fix for the class, and
`NameStrippingDifferentialPropertyTests` says so in its own comments: *"A fifth copy added to
`Sources/` should be added here; that is the maintenance cost of the duplication."* This
document asks whether the class can be templated instead.

**The candidate rule.** Two functions pair when they share (a) a name, (b) a signature
(parameter types and return type), and (c) *differ* in enclosing type, within one package.

**The bar this has to clear is precision, not reach.** PRD §3.5 is conservative inference —
high precision, low recall — and corollary 3 says the remedy for too much output is to raise
thresholds, not to add filters. A pairing rule that fires on every `run()` and `==` in a
codebase is the Daikon flood, not a template.

---

## §1 The frozen prediction

> **Written and committed BEFORE the scorer existed**, so it cannot be tuned to the answer.
> This is the practice `fixtures/domain-transfer-signal/` established: it froze its
> prediction at `5a6cff0` before building its scorer, and was right on both halves —
> which is the only reason its 4/12 precision reads as a finding rather than as a
> disappointing tuning run. Git history is the evidence; check this file's first commit
> against the commit that adds `scripts/same_name_pairs.py`.

**P1 — the raw rule has low precision.** Under 40% of raw pairs are pairs a reader would
want to see. I expect the rule as stated to be dominated by noise.

**P2 — the dominant false-positive class is protocol conformance.** Two types implementing
`==`, `encode(to:)`, `hash(into:)`, `makeConstraint()`, `suggest(for:)` are *supposed* to
differ — that is what a protocol is. They share a name and a signature **because a protocol
made them**, which is the opposite of "someone wrote the same function twice".

**P3 — excluding protocol requirements lifts precision to 60–80% on this repo**, and that is
the version worth measuring further. It will not reach 100%: a codebase-local convention
(`makeFixture`, `entry(_:)` in test helpers) produces same-name same-signature functions that
are genuinely unrelated.

**P4 — the true positives concentrate in one shape**: small `String -> String` /
`[T] -> [T]` name-normalising or -stripping helpers, copied rather than shared because
extracting them would create a dependency edge nobody wanted. `strippingGenericParameters`
and `bareTypeName` are the witnesses that motivated this; I expect the census to find the
same shape and little else.

**P5 — reach.** More than 100 raw pairs in this repo, and fewer than 20 after the
protocol-conformance exclusion.

**What would make me decline this.** If P3 fails — that is, if excluding protocol
conformances still leaves precision under ~50% — the rule does not ship. A template that is
wrong half the time is the Daikon trap, and the honest outcome is a recorded decline plus the
hand-written suite that already exists. `fixtures/domain-transfer-signal/` is the precedent:
a candidate veto measured at 4/12 precision was **not built**, and the measurement is the
deliverable.

**How it will be scored.** Against the pairs the rule *fires on*, hand-labelled, not against
the nine copies it was designed to catch. Recall on the motivating instance is easy and says
almost nothing — that is the transferable lesson from the domain-transfer arm.

---

## §2 The census

`scripts/same_name_pairs.py`, six corpora, 2026-08-08. **10,947 functions scanned.**

| | count |
|---|---|
| raw same-name / same-signature / different-enclosing-type groups | **723** |
| after excluding protocol-requirement *names* (`==`, `encode`, `hash`, `run`, …) | **561** |

Per corpus, after the exclusion: swift-collections 257 · **this repo 119** · swift-syntax 96 ·
SwiftProjectLint 86 · SwiftPropertyLaws 3.

### §2.1 Precision, hand-scored on a seeded random sample

30 groups drawn from this repo's 119 (`random.seed(20260808)`), scored by the question
*would a reader want a differential law proposed here* — not by whether the rule found the
nine strippers, per the domain-transfer practice.

**12 of 30 useful — precision 40%.**

Two scoring calls were checked against the actual bodies rather than judged from names, and
**one of them flipped**: `identifiers(String) -> [String]` looked like a copied helper and is
not. `TypeShapeBuilder` keeps `.` and digits freely; `VerifyImportSet` excludes a leading
digit and `.`. Same name, same signature, deliberately different semantics. Scoring the
sample from names alone would have reported 43%.

### §2.2 The dominant false positive is not what was predicted

**P2 said protocol conformance. It is not.** The flood is *de facto role interfaces* —
families of types implementing a shared convention that was never declared as a protocol:

| name | types | why it must differ |
|---|---|---|
| `emit(Inputs) -> String` | 16 | each stub emitter emits a *different* stub |
| `makeCaveats() -> [String]` | 14 | each template's caveats are its own |
| `makeConstraint() -> Constraint` | 14 | the constraint *is* the template |
| `suggest(FunctionSummary) -> Suggestion?` | 13 | ditto |
| `signals(FunctionSummary) -> [Signal]` | 8 | ditto |

None of these is a protocol requirement, so the name-based exclusion could not reach them and
a conformance-based exclusion would not either. **They share a name because the name is the
ROLE, and differing bodies are the entire point.** That is indistinguishable, from name and
signature alone, from `strippingGenericParameters` copied four times.

A second artifact worth recording: `load(URL, URL?) -> Result` pairs five loaders whose
`Result` is a *different nested type* in each. The signature matches only because the
spelling does — real resolution would need types, not text.

### §2.3 The pairs it gets right are the pairs whose law cannot fail

Mechanically, across all 119 groups in this repo:

| bodies | groups | share |
|---|---|---|
| byte-identical | **33** | 27% |
| differ | 86 | 72% |

The true positives are overwhelmingly the byte-identical ones — small `String -> String`
helpers copied rather than shared. **A differential law over two byte-identical functions is
`f(x) == f(x)`: it cannot fail today**, which is exactly what PRD Appendix C's *score
refutability, not suggestion count* rules out. One group is worse still: `intEdgeSentinel()`
takes no arguments, so the law quantifies over nothing at all.

Their value is real but it is **drift protection over time**, not a conjecture about present
behaviour — the copies can diverge tomorrow. That is a regression guard, which is what the
hand-written `NameStrippingDifferentialPropertyTests` already provides, and what a
duplicate-implementation *lint* would provide generally.

---

## §3 Verdict — DECLINED

**Precision 40%, against the ≥50% bar frozen in §1 before the scorer existed. The rule does
not ship.** `fixtures/domain-transfer-signal/` is the precedent: a candidate measured at 4/12
was not built, and the measurement was the deliverable.

Scoring the frozen predictions — **2 of 5 right**, and the two failures are the informative ones:

| | prediction | outcome |
|---|---|---|
| P1 | raw precision under 40% | **right**, roughly — 40% even after exclusion |
| P2 | dominant FP is protocol conformance | **WRONG** — it is undeclared role interfaces (§2.2) |
| P3 | 60–80% after excluding protocol requirements | **WRONG** — measured 40%, and the exclusion is structurally unable to help |
| P4 | true positives concentrate in string-normalising helpers | **right** |
| P5 | >100 raw here, <20 after filtering | **half wrong** — 119 after filtering, not <20 |

P3 is the one that decided it, and it failed for the reason P2 got wrong: the exclusion was
designed against the wrong false-positive class.

### What to do instead

1. **Keep the hand-written suite.** `NameStrippingDifferentialPropertyTests` pins six of the
   nine copies and its maintenance note is honest about the cost. For a nine-instance problem
   that is the right size of tool.
2. **A duplicate-implementation check belongs in SwiftProjectLint, not here.** The signal that
   actually separates true from false is *byte-identical bodies*, which is a lint question
   ("you copied this") and not a property question ("these two must agree"). swift-infer
   infers laws; it should not grow a clone detector.
3. **Do not retry this with a smarter name list.** §2.2 is a structural result, not a tuning
   gap: `emit` / `suggest` / `makeConstraint` are role names, and no vocabulary distinguishes
   a role from a copy.

### What would reopen it

A pairing signal that is not name-based: two functions whose **bodies are near-identical but
not identical** are the population where a differential law is both true and refutable — the
copies that have already drifted. That is a clone-detection input, and if SwiftProjectLint
ever emits one, this template becomes worth revisiting with the pairs it hands over.
(falsifier: `SwiftProjectLint/DuplicateImplementationRule`)
