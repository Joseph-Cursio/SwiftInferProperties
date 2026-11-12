// swift-tools-version: 6.2
// The uniquifier template's own run over the census universe (#692 step 5). Not part of the package
// build: run it from this directory with
//   swift run -c release UniquifierTemplateRun ../census-2026-10-28.json ../template-run-<date>.json
import PackageDescription

let package = Package(
    name: "UniquifierTemplateRun",
    platforms: [.macOS(.v26)],
    dependencies: [.package(path: "../../..")],
    targets: [
        .executableTarget(
            name: "UniquifierTemplateRun",
            dependencies: [
                .product(name: "SwiftInferCore", package: "SwiftInferProperties"),
                .product(name: "SwiftInferTemplates", package: "SwiftInferProperties"),
            ]
        ),
    ]
)
