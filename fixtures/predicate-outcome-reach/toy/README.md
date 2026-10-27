# The V1 toy of the predicate outcome-reach census (#665)

A package of predicates whose outcome reach is known by construction. It is the control that
`scripts/predicate_outcome_reach.py validate` runs before any census number is read: if the probe
misreads a subject here, where every answer is known, nothing it reads on the corpus counts.

```
python3 scripts/predicate_outcome_reach.py validate <scratch> <swift-infer binary> --rand-runs 8
```

## What `validate` does with it

1. Copies the package (without `Package.resolved`, `Oracles.swift` and this file's siblings
   `expected.json` and `.gitignore`) to `<scratch>/toy`.
2. Runs `discover --include-possible --interactive` with the given binary, accepting every
   suggestion, exactly as `corpus_funnel.walk_repo` drives it.
3. Rewrites the manifest with the funnel's own `rewrite_manifest` and `verify_manifest`, copies
   the committed `Package.resolved` in, and builds with `build_to_fixpoint`.
4. Asserts that the resolved SwiftPropertyLaws and swift-property-based versions equal
   `expected.json`'s `resolved`. If they do not, V1 fails; re-capturing them is a deliberate commit.
5. Writes a hand stub for any of `Faults.trapsLate`, `Faults.spinsLate`,
   `Sightings.isFirstSighting` and `HashOrder.firstOfTwoIsA` that `discover` did not offer: the
   emitted `Rules.isEven` stub with its subject replaced and its seed words kept. At `fef2971d`
   `discover` offers all four, so none is written; `expected.json` records `offered: true` for
   every subject, and a subject that stops being offered fails the gate.
6. Copies `Oracles.swift` into the census target and runs `run --package` on the toy with 8
   random-hashing runs and a 20 s timeout on every process.
7. Builds the oracles with the probe helper and runs them in one deterministic-hashing process.

## The gate

All of these must hold, and `validate` exits non-zero otherwise:

- **(a) Oracle agreement, bit for bit.** For every subject whose deterministic run gave a
  reading, the clone's answers in each of its three tests (`law` 100, `again` 100, `scale`
  1,000) equal the oracle's, and where the clone trapped or hung, the oracle stopped at the same
  call. Every test up to the clone's stop is compared: a test the oracle never logged is a
  disagreement, not a skip. The oracle process itself must exit 0 within its timeout, since it
  never hands a trapping or spinning draw to its subject.
- **(b) Every class and flag in `expected.json`**, and every subject offered by `discover`.
- **(c) No orphaned process** under the toy's `.build`, and no incomplete kill.

`expected.json`'s `readings` are the design-phase counts (`[true100, true1000]`). A count that
differs while (a) holds is printed as a provenance note, not a failure.

## The files

| File | What it is |
|---|---|
| `Package.swift` | A library target and a test target. The test target only gives `discover` somewhere to write; the funnel's rewrite drops it. |
| `Sources/PredicateReachToy/Subjects.swift` | The subjects, one per row of `expected.json`. |
| `Tests/PredicateReachToyTests/Placeholder.swift` | The test target's one test, and the `Registry()` construction the accept path harvests (see below). |
| `Oracles.swift` | Hand-written oracles: seed words and generator text copied verbatim from the stubs `swift-infer` emitted at `fef2971d`, a plain `Xoshiro(seed:)` loop, the subject called directly. It replays the clone's process (100, 100, then 1,000 draws), so a stateful subject sees the clone's history. It needs no wrap, no clone and no parse of a stub. |
| `Package.resolved` | The pinned graph, committed on purpose (the `.gitignore` here un-ignores it). |
| `expected.json` | Classes and flags per subject, the resolved versions, the tuned constants and M's counts. |

## Shapes changed to be offered at `fef2971d`

- **`Faults.trapsLate` traps by indexing**, `[value > 0][value == trapValue ? 1 : 0]`. With a
  `precondition` in its body `discover` did not offer it at all.
- **`Registry` is constructed once in `Placeholder.swift`.** Without a construction the actor
  has no derivable generator: its stub draws `Registry.gen()` with a `TODO` and is set aside.
  With it the accept path holds the receiver, and the stub calls `await Registry().holds(value)`.

## The tuned constants

`Rules.rareResidue`, `Faults.trapValue` and `Faults.spinValue` were chosen once, from 1,000 draws
of `Gen<Int>.int()` at each stub's own seed words, and frozen. A constant changes only a body,
not the suggestion identity the seed is derived from, so tuning it does not move the seed (the
stubs were re-emitted and compared after the change). `expected.json`'s `tuned` records how
each was chosen.

- `rareResidue = 566`: the residue of draw 500, the first draw from the 500th on whose residue no
  earlier draw has. So the first 100 draws never return `true`, draw 500 does, and so does draw 897.
- `trapValue = -8300438475956774088` and `spinValue = 4518500762316687390`: each stub's 150th
  draw, which occurs nowhere else among its 1,000. Only the 1,000-trial test reaches it.
