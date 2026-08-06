import Foundation
@testable import SwiftInferCLI
import Testing

/// swift-syntax is declared in a verifier workdir **only when the corpus
/// declares it**, and this is the regression guard for what happens otherwise.
///
/// The first draft declared it unconditionally, on the reasoning that the
/// dependency block is rendered from `(userPackage, mode)` and cannot see which
/// carrier recipe resolved — the same reasoning that justifies the
/// unconditional OrderedCollections and DequeModule entries. The measurement
/// disagreed: `swift test` on this package went from `peakDeltaMB=233.7` to
/// `8871.4` against a 800 MB §13 budget, because every verify integration test
/// in the suite began resolving and building a large module it had no use for.
/// The §13 memory ceiling caught it; nothing else would have.
///
/// The gate is an equivalence rather than a heuristic, which is why it can be
/// this cheap: a corpus function can only *take* a `FunctionCallExprSyntax` if
/// the corpus itself links swift-syntax. So "the syntax recipes are reachable"
/// and "the corpus declares swift-syntax" are the same condition.
@Suite("Verifier workdir — swift-syntax is declared only when the corpus declares it")
struct VerifierWorkdirSwiftSyntaxGateTests {

    // MARK: - Helpers

    private func makeCorpus(manifest: String) throws -> (URL, VerifierWorkdir.UserPackageReference) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("verifier-syntax-gate-tests")
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("Corpus")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try manifest.write(
            to: root.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8
        )
        return (root, VerifierWorkdir.UserPackageReference(packagePath: root, productNames: ["Corpus"]))
    }

    private func cleanUp(_ url: URL) {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    private static let syntaxManifest = """
        .package(url: "https://github.com/swiftlang/swift-syntax.git", exact: "602.0.0"),
        """

    private static let plainManifest = """
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
        """

    // MARK: - The predicate

    @Test("a corpus declaring swift-syntax reads as true")
    func syntaxCorpusReadsTrue() throws {
        let (root, _) = try makeCorpus(manifest: Self.syntaxManifest)
        defer { cleanUp(root) }
        #expect(VerifierWorkdir.packageDependsOnSwiftSyntax(at: root))
    }

    /// The older `apple/swift-syntax` path is still in the wild; matching the
    /// repository name rather than an org keeps both readable.
    @Test("the legacy apple/swift-syntax path reads as true")
    func legacyPathReadsTrue() throws {
        let (root, _) = try makeCorpus(
            manifest: #".package(url: "https://github.com/apple/swift-syntax.git", from: "509.0.0"),"#
        )
        defer { cleanUp(root) }
        #expect(VerifierWorkdir.packageDependsOnSwiftSyntax(at: root))
    }

    @Test("a corpus not declaring swift-syntax reads as false")
    func plainCorpusReadsFalse() throws {
        let (root, _) = try makeCorpus(manifest: Self.plainManifest)
        defer { cleanUp(root) }
        #expect(!VerifierWorkdir.packageDependsOnSwiftSyntax(at: root))
    }

    @Test("an unreadable manifest reads as false")
    func unreadableReadsFalse() {
        let missing = URL(fileURLWithPath: "/nonexistent-corpus-\(UUID().uuidString)")
        #expect(!VerifierWorkdir.packageDependsOnSwiftSyntax(at: missing))
    }

    // MARK: - What the gate controls

    @Test("a syntax corpus gets the package line and both products")
    func syntaxCorpusGetsDependency() throws {
        let (root, reference) = try makeCorpus(manifest: Self.syntaxManifest)
        defer { cleanUp(root) }
        let dependencies = VerifierWorkdir.renderDependenciesBlock(
            userPackage: reference, mode: .algebraic
        )
        let products = VerifierWorkdir.renderTargetDependenciesBlock(
            userPackage: reference, mode: .algebraic
        )
        #expect(dependencies.contains("swift-syntax.git"))
        #expect(products.contains("\"SwiftSyntax\""))
        #expect(products.contains("\"SwiftParser\""))
    }

    @Test("a non-syntax corpus gets neither")
    func plainCorpusGetsNothing() throws {
        let (root, reference) = try makeCorpus(manifest: Self.plainManifest)
        defer { cleanUp(root) }
        let dependencies = VerifierWorkdir.renderDependenciesBlock(
            userPackage: reference, mode: .algebraic
        )
        let products = VerifierWorkdir.renderTargetDependenciesBlock(
            userPackage: reference, mode: .algebraic
        )
        #expect(!dependencies.contains("swift-syntax"))
        #expect(!products.contains("SwiftSyntax"))
        #expect(!products.contains("SwiftParser"))
    }

    /// The stdlib-carrier path, which has no corpus at all. It predates the
    /// syntax recipes and must be untouched by them.
    @Test("no user package gets neither")
    func noUserPackageGetsNothing() {
        let dependencies = VerifierWorkdir.renderDependenciesBlock(
            userPackage: nil, mode: .algebraic
        )
        let products = VerifierWorkdir.renderTargetDependenciesBlock(
            userPackage: nil, mode: .algebraic
        )
        #expect(!dependencies.contains("swift-syntax"))
        #expect(!products.contains("SwiftSyntax"))
    }

    /// **The invariant that makes the gate safe to have at all.** A
    /// `.product(name: "SwiftSyntax", package: "swift-syntax")` entry without a
    /// matching `.package(…)` line is a manifest error, so the two lists cannot
    /// be allowed to drift apart. They are gated on one predicate; this asserts
    /// they agree for every corpus shape rather than trusting that they do.
    @Test("package and product declarations never disagree", arguments: [true, false])
    func packageAndProductAgree(corpusUsesSyntax: Bool) throws {
        let (root, reference) = try makeCorpus(
            manifest: corpusUsesSyntax ? Self.syntaxManifest : Self.plainManifest
        )
        defer { cleanUp(root) }
        let dependencies = VerifierWorkdir.renderDependenciesBlock(
            userPackage: reference, mode: .algebraic
        )
        let products = VerifierWorkdir.renderTargetDependenciesBlock(
            userPackage: reference, mode: .algebraic
        )
        #expect(dependencies.contains("swift-syntax.git") == products.contains("\"SwiftSyntax\""))
        #expect(dependencies.contains("swift-syntax.git") == products.contains("\"SwiftParser\""))
    }

    /// `from: "600.0.0"` means `600.0.0 ..< 601.0.0` under semver, because
    /// swift-syntax versions by Swift release. A corpus pinning 601 or 602
    /// `exact:` — which is what a syntax-visitor package does — would then fail
    /// to resolve. The open range lets SwiftPM take whatever the corpus already
    /// resolved.
    @Test("the requirement is an open range, not a major-pinning `from:`")
    func requirementIsOpenRange() throws {
        let (root, reference) = try makeCorpus(manifest: Self.syntaxManifest)
        defer { cleanUp(root) }
        let dependencies = VerifierWorkdir.renderDependenciesBlock(
            userPackage: reference, mode: .algebraic
        )
        #expect(dependencies.contains("\"600.0.0\" ..< \"700.0.0\""))
    }
}
