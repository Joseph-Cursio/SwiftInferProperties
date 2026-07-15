import Foundation

/// The package-based `--verify` path for `known-properties` laws that import an
/// external Apple package (swift-numerics / swift-collections / swift-algorithms).
/// The `swift` interpreter can't `import DequeModule`, so these laws are compiled
/// as a temp SwiftPM package's `main.swift`, built against the **real** package
/// releases, and run — every external law genuinely executed, not asserted.
///
/// The workdir is keyed by the imported-module set, so repeated runs reuse a warm
/// `.build/` (the first run resolves + builds the Apple deps; later runs are
/// incremental — the cycle-129 warm-workdir pattern).
enum KnownPropertiesPackageVerify {

    /// Build + run the package program for `laws` (all of which carry `imports`),
    /// returning the `PASS`/`FAIL` verdict map keyed by `displayName`.
    static func run(laws: [KnownProperty]) throws -> [String: Bool] {
        let modules = Set(laws.flatMap(\.imports))
        let resolved = try KnownPropertiesPackages.resolve(modules: modules)
        let root = try synthesizePackage(laws: laws, modules: modules, resolved: resolved)
        let output = try buildAndRun(packageRoot: root)
        return KnownPropertiesRenderer.parseVerifyOutput(output)
    }

    /// Write (idempotently) the temp package: `Package.swift` declaring the Apple
    /// dependencies + an executable target linking their products, and
    /// `main.swift` = the rendered verify program with the module imports.
    private static func synthesizePackage(
        laws: [KnownProperty],
        modules: Set<String>,
        resolved: (packages: [KnownPropertiesPackages.Dependency], products: [(String, String)])
    ) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("known-properties-verify")
            .appendingPathComponent(workdirKey(for: modules))
        let sources = root.appendingPathComponent("Sources/KnownPropertiesVerifier")
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)

        let manifest = renderManifest(resolved: resolved)
        let program = KnownPropertiesRenderer.renderVerifyProgram(laws, imports: Array(modules))
        try writeIfChanged(manifest, to: root.appendingPathComponent("Package.swift"))
        try writeIfChanged(program, to: sources.appendingPathComponent("main.swift"))
        return root
    }

    /// A stable, filesystem-safe key for the module set — same imports reuse the
    /// same warm workdir.
    private static func workdirKey(for modules: Set<String>) -> String {
        modules.sorted().joined(separator: "-")
    }

    private static func renderManifest(
        resolved: (packages: [KnownPropertiesPackages.Dependency], products: [(String, String)])
    ) -> String {
        let dependencyLines = resolved.packages
            .map { "        .package(url: \"\($0.url)\", \($0.requirement))" }
            .joined(separator: ",\n")
        let productLines = resolved.products
            .map { "                .product(name: \"\($0.0)\", package: \"\($0.1)\")" }
            .joined(separator: ",\n")
        return """
        // swift-tools-version:5.9
        import PackageDescription

        let package = Package(
            name: "KnownPropertiesVerifier",
            platforms: [.macOS(.v13)],
            dependencies: [
        \(dependencyLines)
            ],
            targets: [
                .executableTarget(
                    name: "KnownPropertiesVerifier",
                    dependencies: [
        \(productLines)
                    ]
                )
            ]
        )
        """
    }

    /// `swift run` the verifier, returning stdout. A non-zero exit with no
    /// `PASS`/`FAIL` output is a build failure (surfaced), not a silent empty map.
    private static func buildAndRun(packageRoot: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["swift", "run", "--package-path", packageRoot.path, "KnownPropertiesVerifier"]
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(data: data, encoding: .utf8) ?? ""
        if process.terminationStatus != 0, !output.contains("PASS"), !output.contains("FAIL") {
            let detail = String(data: errorData, encoding: .utf8)?.suffix(600) ?? ""
            throw KnownPropertiesVerifyError.buildFailed(String(detail))
        }
        return output
    }

    /// Skip an unchanged write so an existing warm `.build/` stays incremental.
    private static func writeIfChanged(_ contents: String, to url: URL) throws {
        if let existing = try? String(contentsOf: url, encoding: .utf8), existing == contents {
            return
        }
        try Data(contents.utf8).write(to: url)
    }
}
