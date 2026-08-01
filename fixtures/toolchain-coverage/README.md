# Does the toolchain work, end to end?

**2026-08-01.** Not a scorecard — the leaderboard fixture tried to score `discover` in
isolation and the numbers were noise, because a perfect PropertyLawKit with nothing left to
infer would have scored it 0% recall. This asks the functional question instead: **pointed
at real types, does the kit run, and does it catch a bug planted for it?**

```
cd fixtures/toolchain-coverage && swift test
```

Path dependencies on both siblings (`../leaderboard-sort`, `../../../SwiftPropertyLaws`), so
it runs against whatever is checked out. Unlike the other fixtures this one **does** resolve
an external package, so it is not in the sub-second class.

## Verdict: yes

| check | result |
|---|---|
| kit passes the correct type (`PlayerScore`, ordinary domain) | ✅ |
| kit **catches** the planted bug (`ProjectedPlayerScore`) | ✅ `Hashable.equalityConsistency`, **Strict**, 17 trials |
| Equatable laws still pass on the broken type | ✅ — and that is the point |

The bug is a hand-written `==` comparing only `score`, alongside a `hash(into:)` Swift
synthesizes from **all** stored properties. `a == b ⟹ a.hashValue == b.hashValue` is
violated the moment two players share a score.

**The kit's verdict on that type is split, and the split is the finding.** The Equatable
suite says fine; the Hashable suite says broken. A projection is a legitimate equivalence
relation — reflexive, symmetric, transitive — so the Equatable laws pass *because* it is one,
and only the hash law looks at the field the `==` forgot. That is
`fixtures/equatable-signal`'s conclusion (three real swift-collections bugs pass 4 of 4)
reproduced against the live kit rather than by hand.

## What the run taught that wasn't planned

**One generator cannot serve both laws in the same suite.** The first version used the narrow
generator everywhere and the **correct** type failed — `Hashable.distribution`, because 12
distinct values over 1000 trials is a degenerate distribution.

That is not a nuisance to tune away:

- the projection bug needs **collisions** to be visible at all
- the distribution law needs their **absence**
- `checkHashablePropertyLaws` runs both together

Tier is what makes it survivable. `EnforcementMode.default` throws only on `Strict`, so the
heuristic complaint is reported without failing the run. **A reader who narrows a generator
to hunt a collision bug should expect the distribution law to grumble, and must not widen the
generator to silence it** — that would hide the bug they narrowed it to find.

## How a fixture asserts "the kit rejected this"

Not with `do`/`catch`. The kit records a swift-testing `Issue` itself on a Strict violation,
so a caught error still fails the enclosing test. `LawSuppression.intentionalViolation` is
the kit's own way to say *this violation is the documented design*: the outcome becomes
`.expectedViolation`, carrying the counterexample, and asserting on **that** proves detection
without the detection failing the suite.

Worth knowing before writing any fixture that expects a law to fail.

## Scope

Deliberately narrow. It answers "do the pipes connect", not "how much does the toolchain
cover" — the coverage question needs laws-owed as a denominator and three buckets (kit /
`discover` / nothing), and `owed-laws.frozen.json` holds a first draft of that denominator.
That is a larger measurement and this is not it.
