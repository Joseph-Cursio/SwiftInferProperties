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
  alone are included:
  - `Counter` — pure.
  - `OptionalBasics` — pure; composes `Counter` via `.ifLet`.
  - `Timers` — one CA built-in dependency (`\.continuousClock`), pinned by the
    verifier.
- Requires **Swift 6.3.3+** (the 6.2.4 toolchain crashes compiling CA — see
  `docs/tca-determinism-verify-scope.md` and `docs/tca-determinism-followups.md`).
