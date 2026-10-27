// swift-tools-version:6.0
// The V1 toy of `scripts/predicate_outcome_reach.py validate`: one library of predicates whose
// outcome reach is known by construction. `validate` copies this package to scratch, lets the
// arm-A `swift-infer` write its predicate stubs, rewrites this manifest the way the corpus funnel
// does, and pins resolution to the committed `Package.resolved`.
import PackageDescription

let package = Package(
    name: "PredicateReachToy",
    platforms: [.macOS(.v14)],
    products: [.library(name: "PredicateReachToy", targets: ["PredicateReachToy"])],
    targets: [
        .target(name: "PredicateReachToy"),
        .testTarget(name: "PredicateReachToyTests", dependencies: ["PredicateReachToy"])
    ]
)
