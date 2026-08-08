# Same-name differential pairing — can the miss class be templated?

> **Status:** `open` · **As of:** 2026-08-08

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

*(To be filled after `scripts/same_name_pairs.py` runs. Corpora: this repo,
SwiftPropertyLaws, SwiftProjectLint, SwiftEffectInference, swift-collections, swift-syntax.)*

## §3 Verdict

*(Ship or decline, with the number that decided it.)*
