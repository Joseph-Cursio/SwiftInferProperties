// swift-tools-version: 6.1
import PackageDescription

/// Fixture package for the **sort walkthrough** (2026-08-01) — a legible, end-to-end
/// example chosen to answer "what is actually happening" rather than to close a gap.
///
/// The subject is a bowling leaderboard: `PlayerScore` values sorted high-to-low, in a
/// member form (`Leaderboard.sorted`) with a free function as the control. See
/// `README.md` for the two comparator arms, the mutant table, and what `discover`
/// proposed.
///
/// **No external dependencies and no `swift-infer verify`.** Discovery only — the laws
/// here are run by this package's own tests against deliberate mutants, which keeps it
/// in the sub-second class rather than the real-builds class:
///
///     cd fixtures/leaderboard-sort && swift test
///
/// **Not** part of the main `Package.swift`'s targets and deliberately not wired into a
/// Makefile batch — same posture as `fixtures/integer-division-generator`,
/// `fixtures/cycle27-surface` and `fixtures/equatable-signal`.
let package = Package(
    name: "LeaderboardSortFixture",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        // Exposed so `fixtures/toolchain-coverage` can run PropertyLawKit's suites against
        // these types without duplicating them.
        .library(name: "LeaderboardSort", targets: ["LeaderboardSort"])
    ],
    targets: [
        .target(name: "LeaderboardSort"),
        .testTarget(
            name: "LeaderboardSortTests",
            dependencies: ["LeaderboardSort"]
        )
    ]
)
