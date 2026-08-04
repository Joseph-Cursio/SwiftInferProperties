// swift-tools-version: 6.0
import PackageDescription

// A fixture, not a product. Deliberately dependency-free: every annotation here
// uses the `/// @lint.effect` doc-comment spelling, which needs no dependency on
// SwiftIdempotency at all. That is the point — the vocabulary is usable by a
// project that has not adopted the package.
let package = Package(
    name: "EffectDemo",
    targets: [.target(name: "EffectDemo")]
)
