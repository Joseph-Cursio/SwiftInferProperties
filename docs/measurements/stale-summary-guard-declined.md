# A guard for stale summaries — four designs, all refuted

> **Status:** `declined` · **As of:** 2026-08-07


**Question:** three times in one month, a doc's *detail* was maintained while its *summary* went
stale, and an index quoted the summary. Can that be caught mechanically?

**Answer: not by text.** Four designs were built and scored. The root cause is not tuning — it is
that this repo's correction convention *preserves the incorrect sentence verbatim and annotates it*,
so a stale claim and a corrected claim are lexically identical **by construction**. The remedy does
not remove the string a detector keys on.

---

## 1. The three instances

| doc | summary said | detail said |
|---|---|---|
| `docs/design/tca-determinism-followups.md` | "only slice 3c deferred" | per-slice row: `✅ BUILT` |
| `docs/design/Interaction Invariant Taxonomy.md` | "gated on a kit-side harness landing" | header note: the harness shipped in kit v2.2.0 |
| `docs/design/tca-identified-action-slice3-design.md` | "Keep **3c deferred**" | banner + sign-off: 3c shipped `23de8e4` |

In every case the contradicting fact was **already in the same file**, which is what made a text
detector look promising.

## 2. Scoring method

Recall was measured the way `docs/plans/kit-suite-backtest-plan.md` insists — **at `<fix>^`, never at
HEAD**, because every instance is corrected now and an all-quiet run at HEAD is indistinguishable
from a detector that sees nothing. Precision was measured at HEAD, where every remaining hit is by
definition a false positive.

## 3. The four arms

| arm | rule | recall (at `<fix>^`) | precision (at HEAD) |
|---|---|---|---|
| 1 | same token appears in a "done" line and an "open" line, anywhere in one doc | — | **48 hits**, ~0 |
| 2 | …restricted to *summary* (header block) says done, *body* says open | **2/2** real instances | **0/6** |
| 3 | …plus: a line carrying a date or SHA is a correction, not a drift | 2/2 | **0/11** |
| 4 | CLAUDE.md row uses open-work vocabulary about a doc whose status header is settled | **0** | 0 hits |

Arm 2 is the interesting failure: it *works*. It fires on `slice3-design §3c` at all three pre-fix
commits, and on `taxonomy §3.6` at exactly the commits before that fix — going quiet afterwards.
Recall is real. Precision is what kills it.

Arm 4 is the honest trap: **0 hits at HEAD and 0 at every pre-fix commit.** A guard that is green
because it can never fire would have shipped as "no stale summaries found."

## 4. Why precision cannot be recovered

Three independent causes, and the third is fatal:

1. **Token collisions.** `§13`, `M11`, `v1.1+ M11` and `§9.6 Still open after §9` all yield spurious
   subject tokens. Tightenable, but only at the cost of recall.
2. **Legitimate forward deferrals.** *"Persistent semantic indexing across runs (deferred to v1.1)"*
   is a plan, not a drift. A doc is *supposed* to say what it is not doing yet.
3. **The correction preserves the stale text.** `tca-identified-action-slice3-design.md:288` still
   reads *"Keep **3c deferred**"* — correctly, because the fix was a banner above it, not a rewrite.
   This repo's stated norm is to correct by **ordering and annotation, not hiding** (see
   `docs/design/predicate-display-order.md`), and every banner written this month quotes the wrong
   claim so a reader can see what changed. So the fixed doc keeps firing forever.

Cause 3 is not a tuning problem. **The fix is invisible to the detector because the fix is additive.**

## 5. What did work, and why it still is not a guard

The one clean separator found: **a correction carries a date or a SHA on the same line; a stale claim
does not.** Measured on the four candidate hits — every correction (`"this row said … until
2026-08-07"`) was stamped, and both genuine stale deferrals were bare.

It is a real practice and worth keeping by hand: *an undated deferral is unfalsifiable.* It did not
become a guard because it is already ~75% self-adopted — **CLAUDE.md carries 8 lifecycle claims, 6
already stamped**, and the 2 bare ones are legitimate (a directory pointer, and a scope doc that
genuinely has no date). Enforcing it would need two allowlist entries and would catch nothing that
is not already caught.

## 6. What would actually work, if someone wants to pay for it

A deferral claim that names its own falsifier — *"3c deferred (would be refuted by
`IdentifiedActionResolver.maxChildDepth`)"* — is checkable: the guard asks whether the named symbol
exists in `Sources/`, and all three instances would have failed loudly. That is a **convention
change across every doc**, not a test, and it was not attempted here. Recording it so the option is
not rediscovered from scratch.

## 7. The transferable rule

Score a candidate detector against **the corrected state as well as the broken one**. Recall at
`<fix>^` was 2/2 and looked like success; the same rule at HEAD fires on every doc it previously
caught, because the repository's remedy is additive. A guard that stays red after the fix is worse
than no guard — it trains its readers to ignore it, which is the failure mode a guard exists to
prevent.

This is the same shape as `fixtures/domain-transfer-signal/` (recall 4/5, precision 4/12, declined):
high recall on the target class says almost nothing.
