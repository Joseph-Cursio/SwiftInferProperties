# Mutation / regression corpus (private)

A hand-authored mutant corpus for **sharpening the inference engine itself**
(Chapter 30 §30.4.4). Mutants live in the `IdempotenceWitnessDetector`'s pure
name-classifier — the logic that decides whether an action name (`reset`, `setColor`,
`increment`, …) is an idempotence witness — and each is killed by that detector's own
unit tests, which pin both what it *should* match and what it *should not*. Not a
scored benchmark — no frozen answer key.

Each mutant is a reversible patch (`patches/<id>.patch`). The runner applies one,
builds, runs its named killer test via `swift test --filter`, checks the outcome,
and reverts.

## Run

```sh
mutants/run-mutants.sh                    # all mutants
mutants/run-mutants.sh witness-drops-reset
```

Requires a clean working tree.

## The corpus (`manifest.json`)

| id | shape | expected | killer |
|---|---|---|---|
| `witness-drops-reset` | witness-recall | killed | `classifyExactNames` |
| `witness-admits-increment` | witness-precision | killed | `classifyNonMatching` |
| `witness-prefix-drops-set` | witness-recall | killed | `classifyPrefixes` |

Dropping `reset` makes the detector miss a real idempotence witness; adding
`increment` makes it claim a non-idempotent action as one (a false witness would
seed a property that can't hold); dropping the `set` prefix loses the `setX`
assignment family. Recall on two sides, precision on the third. All three verified
killed.

## Adding a mutant

1. Make the buggy edit; 2. `git diff -- <file> > mutants/patches/<id>.patch`;
3. `git checkout -- <file>`; 4. add an entry to `manifest.json`.
