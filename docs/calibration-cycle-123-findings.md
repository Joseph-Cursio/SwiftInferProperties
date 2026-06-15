# Calibration cycle 123 — Phase B scoping (payload-bearing TCA Actions)

> **STATUS: SCOPING (no binary change — investigation + decision record).**
> Scopes Phase B of the `.tca` carrier epic: value generators for
> associated-value Action cases (the 60 of 69 `.tca` candidates Phase A
> rejects). **Finding: the strict raw-payload tier unlocks 2 Action enums
> in the entire corpus** — the all-or-nothing soundness gate is killed by
> 81 enums carrying ≥1 non-derivable composition case. The only Phase B
> framing with real reach (**relaxed/partial-exploration, ~73 enums**)
> trades the project's high-precision posture for recall and so is a
> **product decision, not just engineering**. Captured 2026-06-15.
> **No version bump** (documentation only — same posture as cycles 119 /
> 121).

## Why this was scoped

Phase A shipped (cycle 122) and its reachability was measured: ~4–5
non-degenerate `.tca` reducer types reachable, because the corpus is
dominated by payload-bearing Actions. Phase B is the named next phase — the
one the cycle-122 data said "carries the volume." This cycle measures
whether that volume is actually *reachable*, before committing to the
value-generator work (which converges with the shelved cycle-119 path).

## The measurement

Classified the payload of every case of all 99 `enum Action` declarations in
the real corpora (`tca-10` + `tca-25`), bucketing each case as **free**
(no payload), **raw** (all associated values in the 14 `DerivationStrategist`
raw types), or **other** (anything else).

| Action-enum bucket | count |
|---|---|
| all cases payload-free (Phase A already reaches) | 16 |
| every case free-or-raw, ≥1 raw — **strict raw tier newly unlocks** | **2** |
| ≥1 non-derivable ("other") case — **blocked** | **81** |
| total | 99 |

**The strict raw-payload tier unlocks 2 Action enums across both corpora.**
The all-or-nothing gate (don't verify over a partial action space) is the
killer: 81 of 99 enums carry at least one non-derivable case.

### What blocks the 81 (occurrence counts)

```
nested-X.Action=72   PresentationAction=25   Result/TaskResult=14   BindingAction=10
IndexSet=8   Tab=4   delegate(Delegate)=4   StackAction=1
long tail: CGPoint=2  Color=2  UUID?=2  Data?=2  String?=2  TimeInterval=2
           URLSessionWebSocketTask.CloseCode=2  *.State.ID×4  SpeechRecognitionResult=1  Alert=1 …
```

~108 of the blockers are **TCA composition cases** (nested-`X.Action` /
`PresentationAction` / `BindingAction` / `StackAction`). Generating those is
not "value generation for a payload type" — it is recursively synthesizing
the action algebra of an entire composed reducer tree (a child's action may
itself nest further). Massive, recursive, and precision-risky. The raw-type
long tail (IndexSet, CGPoint, Color, optionals, `*.State.ID`, …) is a
secondary, also-non-trivial blocker.

## The fork that changes the verdict

Idempotence verifies a **single witness** action over explored states — the
*exploration* action set need not be the complete action space. That yields
two very different Phase B framings:

- **Strict (complete-action-space, all-or-nothing).** Reach **+2**. Sound
  but worthless on this corpus.
- **Relaxed (partial-exploration).** Explore state using whatever cases are
  constructible (free + raw), verify any constructible witness, skip the
  non-derivable cases. **Reach: 73 of 99 enums** — 4× Phase A.

Relaxed is the only framing with real reach. **The tradeoff is real:**
`measured-bothPass` weakens from "held across sampled sequences over all
actions" to "…over the *constructible subset* of actions." A counterexample
that only manifests after a binding / nested / delegate action mutates state
would be **missed** (false `bothPass`). The existing verify is already
sampling (1024 random sequences, not proof), but relaxed Phase B
systematically excludes whole action *categories* — a stronger weakening
than random under-sampling, and in tension with PRD §3.5's
high-precision / low-recall mandate.

## Decision

**Do not build strict Phase B (+2).** The relaxed/partial-exploration
approach is the only one that moves the needle, and it is a **product /
precision decision, not a default**: it trades documented high precision for
~4× recall on TCA idempotence. If pursued, it requires:

1. **Richer discovery capture** — per-case payload *types*, replacing
   Phase A's payload-free-or-bail (`actionCaseNames`). Shares the capture
   work with the shelved cycle-119 value-gen path.
2. **A composed action generator** over the constructible subset —
   `Gen.one(of: [Gen.always(.free), rawGen.map(Action.rawCase), …])`,
   per-payload scalars delegated to `DerivationStrategist`.
3. **Explainability (load-bearing)** — every relaxed verdict must surface
   "verified over M of N action types (excluded: binding, child, …)" so a
   reviewer knows the guarantee is partial. Without this the weaker claim
   masquerades as the strong one — exactly the trust erosion §3.5 guards
   against.
4. **Owner sign-off** that a partial-action-space `bothPass` is acceptable
   evidence (and whether it may still drive `.likely → .verified`
   promotion, or only a weaker tier).

**Recommended posture:** the `.tca` epic's clean, high-precision ceiling is
Phase A. Phase B is **shelved pending a decision** on whether partial-
exploration's weaker guarantee is acceptable — that is the gating question,
not engineering effort. Phase C (corpus-scale survey) is moot until it is
settled, since it would survey the same constructible subset.

## Reproduction

Throwaway SwiftSyntax measurement (not committed): for each `.swift` in the
corpora importing `ComposableArchitecture`, parse every `enum Action`,
classify each case's parameter clause as free / all-raw / other; bucket the
enum by whether all cases are free, free-or-raw, or include an "other"; and
count enums with ≥1 constructible case (the relaxed ceiling). Raw set = the
14 `DerivationStrategy.RawType` names.

## What's next

The `.tca` epic stands at: **Phase A shipped**, **Phase B shelved pending a
precision decision** (this doc). Other untouched optionals: the shared
prebuilt user-package artifact (cycle 120 perf tail); the value-generator
path stays shelved (cycle 119, now subsumed by this Phase B analysis).
Default idempotence stays `.likely`; the other four interaction families
stay `.possible` behind `--include-possible`.
