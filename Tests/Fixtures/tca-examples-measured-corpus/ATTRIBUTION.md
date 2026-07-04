# TCA examples measured corpus — attribution

These `.swift` files are **curated (modified) reducer sources** derived from
Point-Free's [The Composable Architecture](https://github.com/pointfreeco/swift-composable-architecture),
`Examples/` tree, at commit `2fc6ed2`.

- **License:** MIT — Copyright (c) 2020 Point-Free, Inc. See the upstream
  `LICENSE`.
- **How they differ from the originals:** the SwiftUI `View` / `#Preview`
  scaffolding and the `readMe` doc strings are stripped. Each `@Reducer` — its
  `State`, `Action`, and `body` — is kept **verbatim**, so the behavior under
  test is authentic Point-Free code.
- **Why a separate, curated set:** unlike the discovery-only
  `tca-examples-corpus`, this subset is **compiled and run** by measured-verify
  (`CorpusPackager` → verify-workdir → real `swift build` against
  ComposableArchitecture). Only reducers that co-compile standalone against CA
  alone are included — the maximal such subset of the 13-file discovery corpus:
  - `Counter` — pure.
  - `OptionalBasics` — pure; composes `Counter` via `.ifLet`.
  - `BindingBasics` — pure.
  - `AlertAndConfirmationDialog` — pure; CA `@Presents` / `AlertState` built-ins.
  - `Timers` — one CA built-in dependency (`\.continuousClock`), pinned by the
    verifier.
  - `Nested` — recursive (`.forEach` over `Self()`); one pinned built-in
    dependency (`\.uuid`).

  Excluded because they can't build flat: `Effects-Basics` / `NavigationStack`
  (`\.factClient`), `SearchView` (`\.weatherClient`), `Effects-LongLiving`
  (`\.screenshots`), `SharedState-InMemory` (`@Shared`), `Todos` (its `Todo`
  sub-reducer lives in another file), and `ReusableFavoriting` (generic
  `Favoriting<ID>` with a required stored closure — the verifier can't
  construct it).
- Requires **Swift 6.3.3+** (the 6.2.4 toolchain crashes compiling CA — see
  `docs/tca-determinism-verify-scope.md` and `docs/tca-determinism-followups.md`).
