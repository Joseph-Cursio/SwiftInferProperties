# TCA examples corpus — attribution

These `.swift` files are **unmodified reducer sources** vendored from
Point-Free's [The Composable Architecture](https://github.com/pointfreeco/swift-composable-architecture),
`Examples/` tree, at commit `2fc6ed2`.

- **License:** MIT — Copyright (c) 2020 Point-Free, Inc. See the upstream
  `LICENSE`.
- **Why vendored:** a real-world corpus for the reducer-interaction surface.
  This is a **discovery fixture** — the files are parsed by SwiftSyntax
  (`ReducerDiscoverer` / `InteractionTemplateEngine`), never compiled or run as
  part of this package. They are not a SwiftPM target and carry their original
  SwiftUI / navigation code untouched so discovery sees authentic reducers.
- **Not for measured-verify as-is:** most of these reference external models /
  child reducers and won't co-compile standalone. The measured-verify corpus is
  a separate, curated, compilable subset (see `docs/tca-determinism-verify-scope.md`).
