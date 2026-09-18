# Does a `nonisolated` TYPE need its own isolation opt-out?

> **Status:** `measured` · **As of:** 2026-09-18

**DECLINED on population.** Closes
[#522](https://github.com/Joseph-Cursio/SwiftInferProperties/issues/522).
Instrument: `scripts/nonisolated_type_census.py`, built on `scripts/measurement.py`.

> **Answer: NO. 20 `nonisolated` type declarations across the four MainActor-default packages
> carry 5 suggestions between them, and ZERO of those 5 are refutable.** The issue's own
> pre-registered reversal condition — *the types carrying no refutable suggestions between them*
> — is met, on a population **three times wider** than the issue estimated.

## The gap

[#482](https://github.com/Joseph-Cursio/SwiftInferProperties/issues/482) fills in a target's
`.defaultIsolation(MainActor.self)` wherever a row carries no actor, and skips a declaration that
opts out:

```swift
guard row.globalActor == nil, row.declaresNonisolated == false else { return row }
```

`declaresNonisolated` is read off the **function's** modifier list. A type declared `nonisolated`
escapes default isolation for every member it owns, and `TypeDecl` records no isolation modifier
at all, so those members read `false` and are hopped onto an actor their own type opted out of.

## What was measured

Every package among the 20 resolved corpora that sets `.defaultIsolation` — three of them — plus
`LintStudioUI`, which sets it and is a dependency of two. For each: every `nonisolated` type
declaration, brace-matched to its line range, joined against `discover --include-possible`'s own
output by file and line.

| package | `nonisolated` types | suggestions inside | tautologies | **refutable** |
|---|---:|---:|---:|---:|
| swiftformat-rule-studio | 5 | 4 | 4 | **0** |
| swiftlint-rule-studio | 13 | 1 | 1 | **0** |
| lintstudio-ui | 1 | 0 | 0 | **0** |
| swift-project-lint (App target) | 1 | 0 | 0 | **0** |
| **total** | **20** | **5** | **5** | **0** |

The five:

| type | subject | class |
|---|---|---|
| `RuleHistory` | `anchorVersions()` | determinism tautology |
| `RuleHistory` | `compareVersions(_:_:)` | determinism tautology |
| `TuneScanScope` | `candidateRules(in:isEnabled:)` | determinism tautology |
| `ConfigIsolation` | `ensureFileExists(at:)` | determinism tautology |
| `TestTempDirectory` | `make(_:)` | determinism tautology |

## Why zero refutable is the right question, not zero suggestions

**A hop that was not needed still compiles.** `await MainActor.run { … }` around a nonisolated
call is legal, so an unnecessary hop costs nothing unless it sits under a law that could have
failed — and `f(x) == f(x)` cannot, by construction. That is the direction `TargetIsolation`
chose deliberately and it is why the over-approximation is affordable here: **the cost of the gap
is five stubs carrying a redundant hop under a law no wrong code fails.**

## ⚠ The issue's population was a floor, and it was 3× low

#522 recorded **6** type declarations across two packages, labelled a regex sizing pass and a
floor. Scanning the corpora that actually set the flag found **20** across four. The extra 13 are
`swiftlint-rule-studio`, which the issue did not scan.

**That matters because the wider population is the more interesting one and it still answers
zero.** `AnyCodable`, `RuleParameter`, `FileIO`, `SQLiteStatement` and `UserDefaultsBookmarkStore`
are exactly the shapes a refutable template looks for — `AnyCodable` is the `codable-round-trip`
shape almost by name — and **not one of them carries a suggestion at all**. The types that are
declared `nonisolated` are overwhelmingly namespace enums of static helpers and thin wrappers
around a subprocess or a file handle, which is what a codebase marks nonisolated *for*.

## What would reverse this

A MainActor-default package whose `nonisolated` types carry a refutable law — most plausibly a
value type with `Codable` + `Equatable` marked nonisolated so it can cross an actor boundary. The
shape is not exotic; it simply does not occur in the four packages measured.

Re-run: `python3 scripts/nonisolated_type_census.py <package> <discover-output>`.

## Still true, and still recorded

The deferral `IndexedTypeShape.isNonisolated` stands, and `DeferralFalsifierTests` will report it
the day that symbol resolves. **This declines building the join, not the observation** — the
scanner genuinely cannot see a type's isolation, and a future subject may make it worth reaching
for.
