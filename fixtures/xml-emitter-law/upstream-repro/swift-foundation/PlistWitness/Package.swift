// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "sf-witness",
    platforms: [.macOS("26")],
    dependencies: [.package(path: "../swift-foundation")],
    targets: [
        .executableTarget(
            name: "PlistWitness",
            dependencies: [.product(name: "FoundationEssentials", package: "swift-foundation")]
        )
    ]
)
