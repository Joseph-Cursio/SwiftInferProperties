import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// PROTOTYPE — slice 5b measured proof: verify value-semantics candidates that
/// are **`internal`** types inside a real SwiftPM package, reached via a
/// `.package(path:)` dependency + `@testable import` (the build passes
/// `-enable-testing`). This is the mode that makes `verify-value-semantics`
/// useful on real code, where types are seldom `public`.
///
///   - `PackageLeaky` (shared reference) → `.confirmedLeak`
///   - `PackageSafe` (correct copy-on-write) → `.verifiedSafe`
///
/// Spawns real `swift build`s resolving the path-dependency + kit; `.subprocess`.
@Suite("ValueSemantic package path-dependency verify — measured (slice 5b)", .tags(.subprocess))
struct ValueSemanticPackageVerifyMeasuredTests {

    @Test("verifies INTERNAL types in a real package via @testable path-dependency")
    func measuredPackagePathDependency() throws {
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent("vs-pkg-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: parent) }

        let results = try ValueSemanticVerifier.verifyInPackage(
            packagePath: Self.packageRoot,
            targetDirectory: Self.packageRoot.appendingPathComponent("Sources/PackageCorpus"),
            moduleName: "PackageCorpus",
            workParent: parent
        )

        func status(_ typeName: String) -> ValueSemanticVerifyResult.Status? {
            results.first { $0.typeName == typeName }?.status
        }

        if case .confirmedLeak = status("PackageLeaky") {
            // Reached the internal type via @testable; the shared-reference leak fired.
        } else {
            Issue.record("PackageLeaky expected confirmedLeak; got \(String(describing: status("PackageLeaky")))")
        }
        if case .verifiedSafe = status("PackageSafe") {
            // Internal correct-CoW type verified safe — no false positive.
        } else {
            Issue.record("PackageSafe expected verifiedSafe; got \(String(describing: status("PackageSafe")))")
        }
    }

    static let packageRoot: URL = {
        URL(fileURLWithPath: #filePath, isDirectory: false)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("valuesemantic-package-corpus")
    }()
}
