import Foundation
import SwiftInferCore
import Testing

@testable import SwiftInferCLI

/// The one package a survey builds in, and the four properties that make it a
/// *replacement* for one package per suggestion rather than a cheaper approximation.
///
/// The cost case is measured elsewhere (`SharedVerifierPackage`'s own doc, and #130).
/// What is pinned here is that nothing was traded for it: each stub still reaches its
/// own target byte-for-byte, each target still declares only what its mode needs, and
/// a shrinking survey does not leave the previous one's targets behind.
@Suite("SharedVerifierPackage — one package, N targets")
struct SharedVerifierPackageTests {

    private func member(
        hash: String,
        stub: String = "print(\"PASS\")\n",
        mode: WorkdirMode = .algebraic
    ) -> SharedVerifierPackage.Member {
        SharedVerifierPackage.Member(
            entry: SemanticIndexEntry(
                identityHash: hash,
                templateName: "idempotence",
                typeName: "Widget",
                score: 60,
                tier: "Likely",
                primaryFunctionName: "normalize",
                location: "Sources/Widget.swift:1",
                firstSeenAt: "2026-08-05T00:00:00Z",
                lastSeenAt: "2026-08-05T00:00:00Z"
            ),
            stubSource: stub,
            userPackage: nil,
            mode: mode
        )
    }

    private func makeRoot() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("shared-verifier-\(UUID().uuidString)")
    }

    /// The stub is the only thing that differs between two entries, so it must arrive
    /// unaltered. A synthesizer that reformatted or re-emitted it would make a verdict
    /// difference unattributable — the failure mode the byte-for-byte harvest in the
    /// original prototype was built to rule out.
    @Test("each member's stub lands verbatim in its own target")
    func stubsAreVerbatimAndSeparate() throws {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = member(hash: "aaa111", stub: "// first\nprint(\"PASS\")\n")
        let second = member(hash: "bbb222", stub: "// second\nprint(\"FAIL\")\n")
        _ = try SharedVerifierPackage.synthesize(members: [first, second], at: root)

        for candidate in [first, second] {
            let path = root.appendingPathComponent("Sources")
                .appendingPathComponent(candidate.targetName)
                .appendingPathComponent("main.swift")
            #expect(try String(contentsOf: path, encoding: .utf8) == candidate.stubSource)
        }
    }

    /// A SwiftPM target name must be an identifier and an identity hash can start with
    /// a digit. The hash is kept so a binary under `.build/debug/` traces back to its
    /// entry without a side table — which is what makes per-product attribution work.
    @Test("target names are identifiers that still carry the hash")
    func targetNamesAreTraceableIdentifiers() {
        let name = member(hash: "0f3c9d").targetName
        #expect(name == "V0f3c9d")
        #expect(name.first?.isLetter == true)
    }

    /// Every member declares a target; the package declares each dependency once.
    /// Collapsing the package-level list is the entire saving — 53 targets sharing
    /// four dependency builds instead of 53 copies of them.
    @Test("dependencies collapse while targets do not")
    func dependenciesAreUnionedAndTargetsAreNot() throws {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let members = (0..<3).map { member(hash: "hash\($0)") }
        _ = try SharedVerifierPackage.synthesize(members: members, at: root)
        let manifest = try String(
            contentsOf: root.appendingPathComponent("Package.swift"), encoding: .utf8
        )
        #expect(manifest.components(separatedBy: ".executableTarget(").count - 1 == 3)
        // Counted over `.package(` lines, not over the whole manifest: swift-numerics
        // is also named by each target's `.product(package:)` entries — twice per
        // target, since ComplexModule and RealModule both come from it. A naive
        // whole-file count reads 7 and says nothing about whether the package-level
        // list collapsed, which is the only thing being claimed here.
        let declarations = manifest
            .components(separatedBy: "\n")
            .filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix(".package(") }
        #expect(declarations.filter { $0.contains("swift-numerics") }.count == 1)
        #expect(declarations.count == Set(declarations).count, "no dependency declared twice")
    }

    /// The per-suggestion path narrowed products by mode. Sharing a package must not
    /// flatten that into a union — an `.interaction` stub imports two products and
    /// declaring the algebraic set on its target would compile things it never uses.
    @Test("per-target product lists stay narrowed by mode")
    func targetProductsAreNotFlattened() throws {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try SharedVerifierPackage.synthesize(
            members: [
                member(hash: "alg001", mode: .algebraic),
                member(hash: "int002", mode: .interaction)
            ],
            at: root
        )
        let manifest = try String(
            contentsOf: root.appendingPathComponent("Package.swift"), encoding: .utf8
        )
        // Split at the interaction target so each block is read on its own.
        let blocks = manifest.components(separatedBy: ".executableTarget(")
        let interaction = try #require(blocks.first { $0.contains("Vint002") })
        let algebraic = try #require(blocks.first { $0.contains("Valg001") })
        #expect(algebraic.contains("ComplexModule"))
        #expect(!interaction.contains("ComplexModule"))
        #expect(interaction.contains("PropertyLawKit"))
    }

    /// A second survey over fewer entries must not inherit the first one's targets.
    /// They would not be declared in the new manifest, so they would never build — but
    /// they would sit on disk claiming space the change exists to reclaim.
    @Test("a re-synthesis clears the previous survey's targets")
    func staleTargetsAreRemoved() throws {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try SharedVerifierPackage.synthesize(
            members: [member(hash: "keep01"), member(hash: "drop02")], at: root
        )
        _ = try SharedVerifierPackage.synthesize(members: [member(hash: "keep01")], at: root)
        let sources = root.appendingPathComponent("Sources")
        let remaining = try FileManager.default.contentsOfDirectory(atPath: sources.path).sorted()
        #expect(remaining == ["Vkeep01"])
    }
}
