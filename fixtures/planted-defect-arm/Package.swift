// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "PlantedDefectArm",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "PlantedDefectArm", targets: ["PlantedDefectArm"])
    ],
    targets: [
        .target(name: "PlantedDefectArm")
    ]
)
