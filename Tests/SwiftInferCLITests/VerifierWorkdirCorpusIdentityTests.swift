import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// #169 — a corpus that IS one of the verifier's own dependencies.
///
/// SwiftPM derives package identity from the last path component on both sides,
/// so a `.package(url: …/swift-collections.git)` and a
/// `.package(path: …/swift-collections)` are one identity from two sources and
/// the graph is rejected before any property is involved. Measured: 0 of 98
/// entries executed on swift-collections, 0 of 39 on SwiftPropertyLaws.
@Suite("Verifier workdir — a corpus that is one of our own dependencies")
struct VerifierWorkdirCorpusIdentityTests {

    private static func corpus(named directory: String) -> VerifierWorkdir.UserPackageReference {
        VerifierWorkdir.UserPackageReference(
            packagePath: URL(fileURLWithPath: "/tmp/\(directory)"),
            productNames: ["Collections"]
        )
    }

    private static func dependencyLines(
        corpus: VerifierWorkdir.UserPackageReference?,
        mode: WorkdirMode
    ) -> [String] {
        VerifierWorkdir.renderDependenciesBlock(userPackage: corpus, mode: mode)
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            // The last entry carries no trailing comma, so whether a line ends
            // in one depends on what follows it. Comparing raw lines would make
            // "a path dependency was appended" look like "a dependency changed".
            .map { $0.hasSuffix(",") ? String($0.dropLast()) : $0 }
            .filter { $0.hasPrefix(".package(") }
    }

    /// **The guard that makes the parse safe.** `urlDependencyIdentity` reads a
    /// string the renderer just produced; a shape it cannot read is silently
    /// *kept*, which re-opens the collision rather than dropping a needed
    /// dependency. That is the right failure direction only if something notices
    /// — this is that something. A new arm, or a `.package(url:)` spelled
    /// differently, fails here.
    @Test("every URL dependency in every mode yields an identity")
    func everyURLDependencyIsReadable() {
        for mode in WorkdirMode.allCases {
            let syntaxCorpus = Self.corpus(named: "SomeUnrelatedCorpus")
            for line in Self.dependencyLines(corpus: syntaxCorpus, mode: mode) {
                if line.contains("path:") { continue }
                #expect(
                    VerifierWorkdir.urlDependencyIdentity(in: line) != nil,
                    "unreadable URL dependency in \(mode): \(line) — the collapse silently skips it"
                )
            }
        }
    }

    @Test(
        "the colliding URL dependency is dropped",
        arguments: [
            ("swift-collections", "swift-collections"),
            ("swift-numerics", "swift-numerics"),
            ("swift-property-based", "swift-property-based"),
            ("SwiftPropertyLaws", "SwiftPropertyLaws")
        ]
    )
    func collidingDependencyIsDropped(directory: String, identity: String) {
        let lines = Self.dependencyLines(corpus: Self.corpus(named: directory), mode: .algebraic)
        let urlIdentities = lines.compactMap { VerifierWorkdir.urlDependencyIdentity(in: $0) }
        #expect(
            !urlIdentities.map { $0.lowercased() }.contains(identity.lowercased()),
            "\(identity) is still declared by URL beside the corpus path dependency"
        )
        #expect(lines.contains { $0.contains("path: \"/tmp/\(directory)\"") })
    }

    /// Identity comparison is case-insensitive, as SwiftPM's is. A checkout
    /// named `swiftpropertylaws` collides with `SwiftPropertyLaws.git` just as
    /// surely, and a case-sensitive filter would ship the graph SwiftPM rejects.
    @Test("collision detection ignores case")
    func collisionIsCaseInsensitive() {
        let lines = Self.dependencyLines(corpus: Self.corpus(named: "swiftpropertylaws"), mode: .algebraic)
        let identities = lines.compactMap { VerifierWorkdir.urlDependencyIdentity(in: $0) }
        #expect(!identities.map { $0.lowercased() }.contains("swiftpropertylaws"))
    }

    /// The normal case must not regress: an ordinary corpus keeps every
    /// dependency it had before, or the fix trades one broken population for a
    /// much larger one.
    @Test("an unrelated corpus keeps every dependency")
    func unrelatedCorpusIsUnchanged() {
        for mode in WorkdirMode.allCases {
            let withCorpus = Self.dependencyLines(corpus: Self.corpus(named: "MyApp"), mode: mode)
                .filter { !$0.contains("path:") }
            let without = Self.dependencyLines(corpus: nil, mode: mode)
            #expect(withCorpus == without, "\(mode): an unrelated corpus changed the dependency list")
            #expect(!without.isEmpty, "\(mode): no dependencies at all — the scan proves nothing")
        }
    }

    /// The `.product(name:package:)` edges deliberately do NOT change: the
    /// collision *is* the two identities being equal, so the surviving path
    /// dependency answers to the name the built-in edges already spell.
    @Test("product edges still name an identity that is declared")
    func productEdgesResolveAgainstSurvivingDependency() {
        let corpus = Self.corpus(named: "swift-collections")
        let declared = Set(
            Self.dependencyLines(corpus: corpus, mode: .algebraic).compactMap { line -> String? in
                if line.contains("path:") { return corpus.packageIdentity.lowercased() }
                return VerifierWorkdir.urlDependencyIdentity(in: line)?.lowercased()
            }
        )
        let products = VerifierWorkdir.renderTargetDependenciesBlock(
            userPackage: corpus, mode: .algebraic
        )
        for line in products.components(separatedBy: "\n") {
            guard let range = line.range(of: "package: \"") else { continue }
            let rest = line[range.upperBound...]
            guard let end = rest.firstIndex(of: "\"") else { continue }
            let named = String(rest[..<end]).lowercased()
            #expect(declared.contains(named), "product edge names undeclared package '\(named)'")
        }
    }

    /// Surveying swift-collections makes the built-in `OrderedCollections` edge
    /// and the corpus's own resolved product the same line.
    @Test("a product is not declared twice when the corpus vends a built-in one")
    func productEdgesAreDeduplicated() {
        let corpus = VerifierWorkdir.UserPackageReference(
            packagePath: URL(fileURLWithPath: "/tmp/swift-collections"),
            productNames: ["OrderedCollections", "DequeModule"]
        )
        let lines = VerifierWorkdir.renderTargetDependenciesBlock(userPackage: corpus, mode: .algebraic)
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        #expect(lines.count == Set(lines).count, "duplicate product edge: \(lines)")
    }

    @Test("the substitution is reportable, and empty when nothing collides")
    func supersededIdentitiesAreExposed() {
        #expect(
            VerifierWorkdir.supersededDependencyIdentities(
                userPackage: Self.corpus(named: "swift-numerics"), mode: .algebraic
            ) == ["swift-numerics"]
        )
        #expect(
            VerifierWorkdir.supersededDependencyIdentities(
                userPackage: Self.corpus(named: "MyApp"), mode: .algebraic
            ).isEmpty
        )
    }
}

/// The union half of #169 — and the reason the first fix measured as no fix.
///
/// The survey manifest is a `Set` union across members. Collapsing per member
/// removes the colliding URL line from the corpus member and leaves it in any
/// member with `userPackage == nil`, so the union puts it straight back. The
/// per-member fix alone left **54 of 98** entries still failing, unchanged.
@Suite("Shared survey package — the collapse must hold across the union")
struct SharedVerifierPackageCorpusIdentityTests {

    private static func corpus() -> VerifierWorkdir.UserPackageReference {
        VerifierWorkdir.UserPackageReference(
            packagePath: URL(fileURLWithPath: "/tmp/swift-collections"),
            productNames: ["Collections"]
        )
    }

    private static func member(
        hash: String,
        userPackage: VerifierWorkdir.UserPackageReference?
    ) -> SharedVerifierPackage.Member {
        SharedVerifierPackage.Member(
            entry: SemanticIndexEntry(
                identityHash: hash,
                templateName: "idempotence",
                typeName: "T",
                score: 50,
                tier: "Likely",
                primaryFunctionName: "f()",
                location: "Sources/T.swift:1",
                firstSeenAt: "2026-08-08T00:00:00Z",
                lastSeenAt: "2026-08-08T00:00:00Z"
            ),
            stubSource: "print(\"PASS\")\n",
            userPackage: userPackage,
            mode: .algebraic
        )
    }

    /// A corpus member beside a no-corpus member: exactly the shape that
    /// reintroduced the collision.
    @Test("a member with no corpus cannot reintroduce the colliding dependency")
    func unionDoesNotReintroduceCollision() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("shared-collapse-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        _ = try SharedVerifierPackage.synthesize(
            members: [
                Self.member(hash: "0xAAAA000000000001", userPackage: Self.corpus()),
                Self.member(hash: "0xBBBB000000000002", userPackage: nil)
            ],
            at: root
        )
        let manifest = try String(
            contentsOf: root.appendingPathComponent("Package.swift"), encoding: .utf8
        )
        #expect(
            !manifest.contains("apple/swift-collections.git"),
            "the no-corpus member put the colliding URL dependency back:\n\(manifest)"
        )
        #expect(manifest.contains("path: \"/tmp/swift-collections\""))
        // The denominator: an unrelated dependency must survive, or this passes
        // by having emitted nothing.
        #expect(manifest.contains("swift-property-based"))
    }
}

/// One member's unresolvable product edge must not fail the whole survey.
///
/// `--product`-per-member isolates *compilation*; an edge naming a product the
/// corpus does not vend fails **manifest loading**, before any target is built.
/// Measured on swift-collections: one `BigString` carrier resolved to product
/// `RopeModule` (the package vends `_RopeModule`, and has no `RopeModule` target),
/// and all **54** buildable entries recorded `build-failed`.
@Suite("Shared survey package — an unresolvable product edge is quarantined")
struct SharedPackageProductQuarantineTests {

    /// A real on-disk package, because the check reads the corpus manifest.
    private static func makeCorpus(products: [String]) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("quarantine-\(UUID().uuidString)")
            .appendingPathComponent("DemoCorpus")
        let sources = root.appendingPathComponent("Sources").appendingPathComponent("DemoCore")
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        try "public let placeholder = 0\n".write(
            to: sources.appendingPathComponent("Placeholder.swift"), atomically: true, encoding: .utf8
        )
        let productLines = products
            .map { ".library(name: \"\($0)\", targets: [\"DemoCore\"])" }
            .joined(separator: ", ")
        try """
        // swift-tools-version: 6.0
        import PackageDescription
        let package = Package(
            name: "DemoCorpus",
            products: [\(productLines)],
            targets: [.target(name: "DemoCore")]
        )
        """.write(to: root.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        return root
    }

    private static func member(
        hash: String,
        corpusRoot: URL,
        productNames: [String]
    ) -> SharedVerifierPackage.Member {
        SharedVerifierPackage.Member(
            entry: SemanticIndexEntry(
                identityHash: hash,
                templateName: "idempotence",
                typeName: "T",
                score: 50,
                tier: "Likely",
                primaryFunctionName: "f()",
                location: "Sources/T.swift:1",
                firstSeenAt: "2026-08-08T00:00:00Z",
                lastSeenAt: "2026-08-08T00:00:00Z"
            ),
            stubSource: "print(\"PASS\")\n",
            userPackage: VerifierWorkdir.UserPackageReference(
                packagePath: corpusRoot, productNames: productNames
            ),
            mode: .algebraic
        )
    }

    /// **The property that was broken.** One bad member is removed; the good one
    /// survives. Before the quarantine the bad member took the good one with it.
    @Test("a member naming a non-existent product is removed, and the others survive")
    func oneBadMemberDoesNotTakeTheOthers() throws {
        let root = try Self.makeCorpus(products: ["DemoLib"])
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }

        let (usable, quarantined) = SharedVerifierPackage.quarantiningUnresolvableProducts([
            Self.member(hash: "0xAAAA000000000001", corpusRoot: root, productNames: ["DemoLib"]),
            Self.member(hash: "0xBBBB000000000002", corpusRoot: root, productNames: ["RopeModule"])
        ])
        #expect(usable.count == 1)
        #expect(usable.first?.entry.identityHash == "0xAAAA000000000001")
        #expect(quarantined.count == 1)
        #expect(quarantined.first?.member.entry.identityHash == "0xBBBB000000000002")
        // The reason has to name the product AND what the corpus does vend, or a
        // reader cannot tell a typo from an unreachable target.
        #expect(quarantined.first?.reason.contains("RopeModule") == true)
        #expect(quarantined.first?.reason.contains("DemoLib") == true)
    }

    /// An unreadable manifest is not evidence that a product is missing.
    /// Quarantining on "I could not check" would turn a tooling failure into a
    /// claim about the user's carrier.
    @Test("a corpus whose manifest cannot be read passes through unvalidated")
    func unreadableManifestDoesNotQuarantine() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("no-such-package-\(UUID().uuidString)")
        let (usable, quarantined) = SharedVerifierPackage.quarantiningUnresolvableProducts([
            Self.member(hash: "0xCCCC000000000003", corpusRoot: missing, productNames: ["Whatever"])
        ])
        #expect(usable.count == 1)
        #expect(quarantined.isEmpty)
    }

    /// A member with no corpus has no corpus product edges to validate.
    @Test("a member with no corpus is never quarantined")
    func noCorpusMemberPassesThrough() {
        let (usable, quarantined) = SharedVerifierPackage.quarantiningUnresolvableProducts([
            SharedVerifierPackage.Member(
                entry: SemanticIndexEntry(
                    identityHash: "0xDDDD000000000004",
                    templateName: "idempotence",
                    typeName: "T",
                    score: 50,
                    tier: "Likely",
                    primaryFunctionName: "f()",
                    location: "Sources/T.swift:1",
                    firstSeenAt: "2026-08-08T00:00:00Z",
                    lastSeenAt: "2026-08-08T00:00:00Z"
                ),
                stubSource: "print(\"PASS\")\n",
                userPackage: nil,
                mode: .algebraic
            )
        ])
        #expect(usable.count == 1)
        #expect(quarantined.isEmpty)
    }
}
