import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// V1.142 — verified-only DocC generation. The gate (only
/// `measured-bothPass` rows become docs), jargon→behavior mapping,
/// container grouping, rendering, and file writing.
@Suite("DoccPageBuilder — V1.142 verified-only DocC")
struct DoccPageBuilderTests {

    // MARK: - Fixtures

    private static func algebraic(
        hash: String,
        template: String,
        type: String?,
        function: String,
        secondary: String? = nil
    ) -> SemanticIndexEntry {
        SemanticIndexEntry(
            identityHash: hash,
            templateName: template,
            typeName: type,
            score: 90,
            tier: "Strong",
            primaryFunctionName: function,
            location: "/x.swift:1",
            firstSeenAt: "2026-07-01T00:00:00Z",
            lastSeenAt: "2026-07-01T00:00:00Z",
            secondaryFunctionName: secondary
        )
    }

    private static func interaction(
        hash: String,
        family: String,
        reducer: String,
        predicate: String
    ) -> InteractionIndexEntry {
        InteractionIndexEntry(
            identityHash: hash,
            family: family,
            reducerQualifiedName: reducer,
            stateTypeName: "State",
            actionTypeName: "Action",
            predicate: predicate,
            location: "/r.swift:1",
            moduleName: nil,
            score: 80,
            tier: "Verified",
            firstSeenAt: "2026-07-01T00:00:00Z",
            lastSeenAt: "2026-07-01T00:00:00Z"
        )
    }

    private static func evidence(_ hash: String, _ outcome: VerifyEvidenceOutcome) -> VerifyEvidence {
        VerifyEvidence(
            identityHash: hash,
            template: "t",
            outcome: outcome,
            detail: nil,
            capturedAt: Date(timeIntervalSince1970: 1_780_000_000),
            swiftInferVersion: "1.142.0"
        )
    }

    // MARK: - The verified gate

    @Test("V1.142 — verifiedHashes keeps only measured-bothPass")
    func verifiedGate() {
        let log = VerifyEvidenceLog(records: [
            Self.evidence("AAAA000000000001", .measuredBothPass),
            Self.evidence("BBBB000000000002", .measuredDefaultFails),
            Self.evidence("CCCC000000000003", .measuredError),
            Self.evidence("DDDD000000000004", .measuredEdgeCaseAdvisory)
        ])
        let verified = DoccPageBuilder.verifiedHashes(in: log)
        #expect(verified == ["AAAA000000000001"])
    }

    @Test("V1.142 — only verified rows become properties; unverified are excluded")
    func onlyVerifiedRows() {
        let index = IndexStore.Index(
            updatedAt: "2026-07-01T00:00:00Z",
            entries: [
                Self.algebraic(
                    hash: "0xAAAA000000000001", template: "idempotence", type: "Text", function: "normalize(_:)"
                ),
                Self.algebraic(
                    hash: "0xBBBB000000000002", template: "idempotence", type: "Other", function: "sort()"
                )
            ],
            interactionEntries: [
                Self.interaction(
                    hash: "0xEEEE000000000005", family: "idempotence",
                    reducer: "NavFeature.reduce", predicate: "s == s"
                )
            ]
        )
        // Verify only the Text row + the interaction row.
        let verified: Set<String> = ["AAAA000000000001", "EEEE000000000005"]
        let props = DoccPageBuilder.verifiedProperties(in: index, verified: verified)
        #expect(props.count == 2)
        #expect(props.contains { $0.container == "Text" && $0.headline == "Idempotent" })
        #expect(props.contains { $0.container == "NavFeature" && $0.headline == "Idempotent action" })
        #expect(!props.contains { $0.container == "Other" })   // BBBB unverified → excluded
    }

    @Test("V1.142 — no verified evidence → no properties, no pages")
    func emptyWhenNothingVerified() {
        let index = IndexStore.Index(
            updatedAt: "2026-07-01T00:00:00Z",
            entries: [
                Self.algebraic(
                    hash: "0xAAAA000000000001", template: "idempotence", type: "Text", function: "normalize(_:)"
                )
            ]
        )
        let props = DoccPageBuilder.verifiedProperties(in: index, verified: [])
        #expect(props.isEmpty)
        #expect(DoccPageBuilder.pages(from: props).isEmpty)
    }

    // MARK: - Consequence mapping (jargon → behavior)

    @Test("V1.142 — algebraic mappings translate to plain-language consequences")
    func algebraicConsequences() {
        let index = IndexStore.Index(
            updatedAt: "2026-07-01T00:00:00Z",
            entries: [
                Self.algebraic(hash: "0x01", template: "idempotence", type: "Text", function: "normalize(_:)"),
                Self.algebraic(
                    hash: "0x02", template: "round-trip", type: "Codec",
                    function: "encode(_:)", secondary: "decode(_:)"
                ),
                Self.algebraic(hash: "0x03", template: "commutativity", type: "Money", function: "plus(_:_:)"),
                Self.algebraic(
                    hash: "0x04", template: "some-future-template", type: "Widget", function: "frobnicate()"
                )
            ]
        )
        let props = DoccPageBuilder.verifiedProperties(in: index, verified: ["01", "02", "03", "04"])
        let byType = Dictionary(uniqueKeysWithValues: props.map { ($0.container ?? "", $0) })
        #expect(byType["Text"]?.headline == "Idempotent")
        #expect(byType["Text"]?.consequence.contains("twice is the same as applying it once") == true)
        #expect(byType["Codec"]?.consequence.contains("decode(_:)") == true)   // secondary rendered
        #expect(byType["Money"]?.headline == "Commutative")
        // Unknown template → graceful generic fallback (still emitted, still true).
        #expect(byType["Widget"]?.headline == "Verified property")
        #expect(byType["Widget"]?.consequence.contains("frobnicate()") == true)
    }

    @Test("V1.142 — interaction mappings translate families to behavior + carry the predicate")
    func interactionConsequences() {
        let index = IndexStore.Index(
            updatedAt: "2026-07-01T00:00:00Z",
            entries: [],
            interactionEntries: [
                Self.interaction(
                    hash: "0x10", family: "referential-integrity",
                    reducer: "Lib.reduce", predicate: "sel ⊆ items"
                ),
                Self.interaction(
                    hash: "0x11", family: "cardinality", reducer: "Router.reduce", predicate: "≤1 modal"
                )
            ]
        )
        let props = DoccPageBuilder.verifiedProperties(in: index, verified: ["10", "11"])
        let refint = props.first { $0.container == "Lib" }
        #expect(refint?.headline == "Referential integrity")
        #expect(refint?.consequence.contains("never dangles") == true)
        #expect(refint?.consequence.contains("sel ⊆ items") == true)   // predicate carried
        #expect(props.first { $0.container == "Router" }?.headline == "Mutual exclusion")
    }

    // MARK: - Grouping + rendering

    @Test("V1.142 — pages: one per type (sorted), free-functions article last")
    func pagesGrouping() {
        let props = [
            DoccProperty(container: "Zebra", headline: "Idempotent", consequence: "z"),
            DoccProperty(container: "Alpha", headline: "Commutative", consequence: "a"),
            DoccProperty(container: nil, headline: "Monotonic", consequence: "free")
        ]
        let pages = DoccPageBuilder.pages(from: props)
        #expect(pages.map(\.fileName) == ["Alpha.md", "Zebra.md", "VerifiedProperties.md"])
    }

    @Test("V1.142 — generic-type container strips <...> in title + filename")
    func genericTypeBareName() {
        let props = [DoccProperty(container: "Complex<Double>", headline: "Commutative", consequence: "c")]
        let pages = DoccPageBuilder.pages(from: props)
        #expect(pages.first?.fileName == "Complex.md")
        #expect(pages.first?.markdown.contains("# ``Complex``") == true)
    }

    @Test("V1.142 — type page renders DocC extension header, bullets, and provenance note")
    func typePageRender() {
        let props = [
            DoccProperty(container: "Text", headline: "Idempotent", consequence: "Applying it twice equals once.")
        ]
        let markdown = DoccPageBuilder.pages(from: props).first?.markdown ?? ""
        #expect(markdown.contains("# ``Text``"))
        #expect(markdown.contains("@DocumentationExtension(mergeBehavior: append)"))
        #expect(markdown.contains("## Verified Properties"))
        #expect(markdown.contains("- **Idempotent** — Applying it twice equals once."))
        #expect(markdown.contains("backed by a passing property test"))
    }

    @Test("V1.142 — free-function article uses @PageKind(article), not a symbol title")
    func articleRender() {
        let props = [DoccProperty(container: nil, headline: "Monotonic", consequence: "preserves order")]
        let markdown = DoccPageBuilder.pages(from: props).first?.markdown ?? ""
        #expect(markdown.contains("# Verified Properties"))
        #expect(markdown.contains("@PageKind(article)"))
        #expect(!markdown.contains("``"))   // no symbol link in an article title
    }

    // MARK: - Writing

    @Test("V1.142 — write emits one file per page with the rendered markdown")
    func writePages() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("docc-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let pages = [
            DoccPage(fileName: "Text.md", markdown: "# ``Text``\n"),
            DoccPage(fileName: "VerifiedProperties.md", markdown: "# Verified Properties\n")
        ]
        let urls = try DoccPageBuilder.write(pages, to: tempDir)
        #expect(urls.count == 2)
        let textContents = try String(contentsOf: tempDir.appendingPathComponent("Text.md"), encoding: .utf8)
        #expect(textContents == "# ``Text``\n")
        #expect(FileManager.default.fileExists(atPath: tempDir.appendingPathComponent("VerifiedProperties.md").path))
    }
}
