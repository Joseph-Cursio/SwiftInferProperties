# Upstream reproductions for #691

#669's census (`docs/measurements/uniquifier-law-census.md`) flagged functions whose bodies break the uniquifier
law: one receiver, n calls, n distinct results. Issue #691 tracks the reachable ones. This directory holds each
reproduced at upstream HEAD as a test, with a minimal patch and a draft issue. **None is filed upstream.** Filing
needs the user's approval.

| repository @ revision (upstream `main` on 2026-10-28) | defect | test file → destination in the package | patch |
|---|---|---|---|
| MarcoEidinger/SwiftPlantUML @ `0f5875e` | `PlantUMLContext.uniqName` gives two elements one PlantUML alias when a type name ends in a digit | `PlantUMLContextUniqNameTests.swift` → `Tests/SwiftPlantUMLFrameworkTests/` | `uniqName-distinct-aliases.patch` |
| jpsim/Yams @ `df801bc` | under either redundancy aliasing strategy, a dictated anchor and a counter anchor collide, and an alias decodes to the wrong value | `AnchorCollisionTests.swift` → `Tests/YamsTests/` | `anchor-collision-fix.patch` |
| groue/GRDB.swift @ `0d8cf95` | a generated table alias takes a user alias's name when a table name ends in a digit: the statement fails to prepare, or the row's scopes hold another table's columns | `AssociationTableAliasDigitSuffixTests.swift` → `Tests/GRDBTests/QueryInterface/Association/`; `DigitSuffixedTableAliasTests.swift` (the draft's self-contained repro) → `Tests/GRDBTests/` | `alias-collision-fix.patch` |

Each directory's `issue-draft.md` is the text proposed for the upstream issue, as of 2026-10-28.

## Run one

```bash
mkdir repro && git -C <clone> archive <revision> | tar -x -C repro
cp <test file> repro/<destination>
cd repro && rm -f .swift-version   # SwiftPlantUML pins Swift 5.3
swift test --filter <test class>   # fails
patch -p1 < <patch>
swift test --filter <test class>   # passes
```

## Measured, Xcode 27.1's Swift 6.4, macOS 27.2

**The filtered tests, run again from fresh exports in this session:**

| package | without the patch | with the patch |
|---|---|---|
| SwiftPlantUML | 5 of 5 fail | 5 pass |
| Yams | 13 of 17 fail. The 4 that pass guard behaviour the patch must keep | 17 pass |
| GRDB | 6 of 7 fail. The one that passes is a control, a self-join with no user alias | 7 pass |

**The full suites with the patch,** run by the reproducing and checking agents:

- SwiftPlantUML: 131 tests, 13 failures (`FileCollectorTests`, `GlobsTests`), the same 13 that fail without the patch.
- Yams: 211 tests, 0 failures.
- GRDB: 2,884 tests, 31 skipped, 1 failure (`Issue1838Tests.test_interrupted_commit`), which fails the same way without the patch.

**Every patch leaves output without a collision unchanged.** That was checked as byte-identical output over each
package's own inputs and over seeded generated inputs; each draft gives the figures. One exception: GRDB's patch
also renames a non-ASCII alias pair that Swift's `lowercased()` treats as equal, harmlessly.

## Known limits, also stated in the drafts

- **Yams.** The patch does not cover a non-`Hashable` `YamlAnchorCoding` value under `HashableAliasingStrategy`,
  whose dictated anchor the keyed container writes directly. The draft shows that path and says it is fixable
  without a protocol change.
- **SwiftPlantUML.** Relationship lines still name a type by its Swift name, not its alias. CONTRIBUTING asks for
  PRs against `dev`, where one context line of the patch differs.
- **GRDB.** #691 listed this one as reasoned but never run. It reproduces, but it needs more than #669 described:
  the user alias must be spelled like the table name of an unnamed alias in the same request, and that table name
  must end in a positive integer. The checking agent also found a separate subquery case that needs no digit: a
  correlated subquery's generated names can shadow an outer alias. The draft records it under its limits, and it
  has no test here.
