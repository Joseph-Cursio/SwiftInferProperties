// swift-tools-version: 6.1
import PackageDescription

/// Fixture package for the Seam-C generator question (2026-08-08): the curated
/// `OrderedSet` recipe in `StrategistDispatchEmitter+OCRecipes` draws from a
/// domain of **101 reachable values**, and the question is whether widening it
/// buys anything measurable.
///
/// See `README.md` for the domains, the mutant table, and — the part worth
/// reading — the two mutant classes this change deliberately does **not** reach.
///
/// **One dependency: swift-collections, for the real `OrderedSet`.** The claim
/// under test is about `OrderedSet`'s insertion-order and duplicate-collapse
/// semantics, so a hand-rolled stand-in would be testing the stand-in. The
/// sampling itself is a seeded LCG rather than `PropertyBased.Gen`, following
/// `fixtures/equatable-signal/Tests/EquatableSignalTests/ModelLaw.swift` — the
/// subject here is which VALUES a domain can reach, not the `Gen` plumbing, and
/// one driver with only the domain varying is the controlled A/B this repo asks
/// for. That is a modelling choice with a cost, and `README.md` §5 states it.
///
///     cd fixtures/ordered-set-generator && swift test
///
/// **Not** part of the main `Package.swift`'s targets and deliberately not wired
/// into a Makefile batch — same posture as `fixtures/integer-division-generator`
/// and `fixtures/equatable-signal`.
let package = Package(
    name: "OrderedSetGeneratorFixture",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-collections.git", from: "1.1.0")
    ],
    targets: [
        .target(
            name: "OrderedSetGeneratorDomain",
            dependencies: [
                .product(name: "OrderedCollections", package: "swift-collections")
            ]
        ),
        .testTarget(
            name: "OrderedSetGeneratorDomainTests",
            dependencies: ["OrderedSetGeneratorDomain"]
        )
    ]
)
