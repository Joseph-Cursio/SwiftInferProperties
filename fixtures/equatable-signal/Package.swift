// swift-tools-version: 6.1
import PackageDescription

/// Fixture package for the "does `Equatable` alone justify a property test?"
/// measurement (2026-07-29). See `README.md` for the question, the arms, and
/// the measured result.
///
/// Both dependencies are URL-pinned rather than path-pinned so the fixture
/// resolves identically on either machine. The kit pin matches the main
/// `Package.swift`'s own `from: "3.21.0"` — the same discipline
/// `VerifierWorkdir+KitPin.swift` is guarded for. v3.21.0 is the tag the
/// measurement was taken against.
///
/// **Not** part of the main `Package.swift`'s targets, and deliberately not
/// wired into any Makefile batch — same posture as `fixtures/cycle27-surface`.
/// It resolves two external packages over the network and is run by hand:
///
///     cd fixtures/equatable-signal && swift test --no-parallel
let package = Package(
    name: "EquatableSignalFixture",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-numerics.git", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-collections.git", from: "1.1.0"),
        .package(url: "https://github.com/Joseph-Cursio/SwiftPropertyLaws.git", from: "3.21.0")
    ],
    targets: [
        .testTarget(
            name: "EquatableSignalTests",
            dependencies: [
                .product(name: "PropertyLawKit", package: "SwiftPropertyLaws"),
                .product(name: "PropertyLawComplex", package: "SwiftPropertyLaws"),
                // Supplies `smallIntOrderedSet` / `smallBitSet` / `smallIntDeque`
                // / `smallIntTreeSet` etc., so the real-type arms need no
                // generator work of their own.
                .product(name: "PropertyLawCollections", package: "SwiftPropertyLaws"),
                .product(name: "ComplexModule", package: "swift-numerics"),
                .product(name: "OrderedCollections", package: "swift-collections"),
                .product(name: "BitCollections", package: "swift-collections"),
                .product(name: "DequeModule", package: "swift-collections"),
                .product(name: "HashTreeCollections", package: "swift-collections")
            ]
        )
    ]
)
