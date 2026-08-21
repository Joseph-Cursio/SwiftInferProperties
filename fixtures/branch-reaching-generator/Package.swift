// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BranchReachingDomain",
    platforms: [.macOS(.v14)],
    products: [.library(name: "BranchReachingDomain", targets: ["BranchReachingDomain"])],
    targets: [
        .target(name: "BranchReachingDomain"),
        .testTarget(name: "BranchReachingDomainTests", dependencies: ["BranchReachingDomain"])
    ]
)
