// swift-tools-version: 6.1
import PackageDescription

/// Fixture package for Q4's stated deliverable — a before/after on generator
/// coverage for the swift.org **weak-generator** population (2026-07-31).
/// See `README.md` for the subject, the measurement, and its limitations.
///
/// The subject is `validation-test/stdlib/IntegerDivision.swift`'s
/// "Int64 division inbounds" arm, at corpus pin
/// `swift` @ `408632e59834c1a5ee4166ff61dd2c8b0585a1c5`.
///
/// **No external dependencies.** Unlike `fixtures/equatable-signal`, this one
/// resolves nothing over the network — it needs only the standard library,
/// because the standard library *is* the subject. So it is cheap to run:
///
///     cd fixtures/integer-division-generator && swift test
///
/// **Not** part of the main `Package.swift`'s targets and deliberately not
/// wired into a Makefile batch — same posture as `fixtures/cycle27-surface`
/// and `fixtures/equatable-signal`. The §13 perf suites assert wall-clock
/// budgets against a shared box; a fixture that runs 65,536 trials four times
/// over does not belong in that contention.
let package = Package(
    name: "IntegerDivisionGeneratorFixture",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .target(name: "IntegerDivisionGenerator"),
        .testTarget(
            name: "IntegerDivisionGeneratorTests",
            dependencies: ["IntegerDivisionGenerator"]
        )
    ]
)
