# Seed-manifest parity fixture

`seeds.json` is **real producer output**, not a hand-written sample.

- Produced by: `swiftprojectlint <this repo>/Sources --format pbt-seeds`
- Subject: `SwiftProjectLint@08a4b09` (release build), 2026-08-06
- Reduced from 2,099 seeds to **one per distinct shape** — the nine combinations of
  `(kind, restriction, has-role, has-effect)` that run produced. Between them the nine
  cover all eight fields the producer emits.

## What it is for

`SeedFieldParityTests` asserts that **every key present here is one this build decodes**. It is a
guard against the one drift `Codable` cannot report: a producer *adding* a field. Unknown keys are
silently ignored, so an addition looks exactly like nothing happening. That is not hypothetical —
`restriction` shipped upstream on 2026-08-03 and was dropped on the floor here for three days,
during which this repo was independently getting the question it answers wrong.

## Its limit, stated so nobody over-trusts it

**A committed sample only catches fields that were present when it was regenerated.** A field the
producer adds tomorrow will not appear here and this fixture will not notice. That is why the suite
also cross-checks the producer's `PBTSeed` declaration directly when a sibling `../SwiftProjectLint`
checkout exists — that arm cannot go stale, and it is the one that would catch a new field. This
fixture is the arm that always runs, including in a checkout with no sibling.

Regenerate after a producer schema change, and update the subject SHA above with it.

## Why not just hand-write the JSON

The same reason `fixtures/swiftorg-study` pins a corpus SHA: a sample written by the consumer tests
what the consumer expects, which is the thing under test. This one can disagree with us.
