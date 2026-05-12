// swift-tools-version: 6.1
import PackageDescription

/// V1.50.A — fixture package for full 109-surface verify measurement.
///
/// Depends on the four cycle-27 corpus packages (swift-algorithms,
/// swift-collections, swift-numerics, SwiftPropertyLaws) so SwiftPM
/// resolves them into `.build/checkouts/`. Running
/// `swift-infer index` against each checkout's source target produces
/// per-package SemanticIndex files; merged, they reconstruct the
/// 109-surface from the v1.29 discover state.
///
/// **Not** part of the main `Package.swift`'s targets — this is a
/// developer-only fixture. The main test suite does not depend on it.
let package = Package(
    name: "Cycle27SurfaceFixture",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-algorithms.git", from: "1.2.0"),
        .package(url: "https://github.com/apple/swift-collections.git", from: "1.1.0"),
        .package(url: "https://github.com/apple/swift-numerics.git", from: "1.0.0"),
        .package(url: "https://github.com/Joseph-Cursio/SwiftPropertyLaws.git", from: "2.1.0")
    ],
    targets: [
        .target(
            name: "Cycle27SurfaceFixture",
            dependencies: [
                .product(name: "Algorithms", package: "swift-algorithms"),
                .product(name: "OrderedCollections", package: "swift-collections"),
                .product(name: "ComplexModule", package: "swift-numerics"),
                .product(name: "PropertyLawKit", package: "SwiftPropertyLaws")
            ]
        )
    ]
)
