// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CollisionPairingDomain",
    platforms: [.macOS(.v14)],
    products: [.library(name: "CollisionPairingDomain", targets: ["CollisionPairingDomain"])],
    targets: [
        .target(name: "CollisionPairingDomain"),
        .testTarget(
            name: "CollisionPairingDomainTests",
            dependencies: ["CollisionPairingDomain"]
        )
    ]
)
