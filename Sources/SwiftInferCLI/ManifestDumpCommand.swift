import Foundation

/// The argv for reading a package's manifest, in one place — because the interesting part is
/// not the subcommand, it is where SwiftPM is allowed to put its scratch directory.
///
/// ## The defect this closes
///
/// `swift package dump-package` creates `.build/` in the package it is pointed at —
/// `CACHEDIR.TAG`, `.lock`, `.buildSystem_debug` on the toolchain measured here. That is a
/// side effect nobody asked for: `discover` reads code and writes inside a documented
/// allowlist (PRD §16 #1), and three files appearing in the user's package because the tool
/// wanted to *read a manifest* is outside it.
///
/// It surfaced when #414's destination resolution made the accept path consult the manifest
/// on packages it previously never dumped, and `HardGuaranteeAllowlistTests` — whose whole
/// job is to catch a writeout escaping the allowlist — caught it immediately, in three
/// separate arms. It was already happening before that change on at least one path:
/// `LiftedDecisionsHardGuaranteeTests` had been failing on `.build/CACHEDIR.TAG` and
/// `.build/.buildSystem_debug`, and the guard was read as flaky rather than as right.
///
/// `--scratch-path` sends all of it somewhere else, verified: the fixture package keeps
/// exactly `Package.swift` and `Sources/`, and the scaffolding lands in the scratch directory
/// instead. The manifest JSON is unaffected — scratch is where build products go, and a dump
/// builds none.
enum ManifestDumpCommand {

    /// One directory per process, reused: the contents are a few bytes of SwiftPM
    /// bookkeeping, so a fresh directory per call would leak one per manifest read. Swept by
    /// `make clean-temp` along with the rest of `$TMPDIR`.
    static let scratchDirectory: URL = FileManager.default.temporaryDirectory
        .appendingPathComponent("swift-infer-manifest-scratch")

    /// `swift package dump-package`, pointed at `packageRoot`, scratching elsewhere.
    static func argv(packageRoot: URL) -> [String] {
        [
            "swift", "package", "dump-package",
            "--package-path", packageRoot.path,
            "--scratch-path", scratchDirectory.path
        ]
    }
}
