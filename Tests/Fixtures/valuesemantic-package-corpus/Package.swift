// swift-tools-version: 6.1
// 5b fixture — a REAL SwiftPM package whose value-semantics-shaped types are
// `internal`. The verifier path-depends on this package and reaches the types
// via `@testable import`, proving slice-5b works on non-public real code.
import PackageDescription
let package = Package(
    name: "valuesemantic-package-corpus",
    platforms: [.macOS(.v14)],
    products: [.library(name: "PackageCorpus", targets: ["PackageCorpus"])],
    targets: [.target(name: "PackageCorpus")]
)
