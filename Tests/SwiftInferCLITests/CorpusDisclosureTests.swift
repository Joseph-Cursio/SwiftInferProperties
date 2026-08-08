import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// #174 — a survey that substitutes a local checkout for a pinned dependency has
/// to say so.
///
/// The substitution itself is #172 and is correct. What must not happen is a
/// `measured-bothPass` that reads as a verdict about the pinned release when it is
/// a verdict about whatever is checked out next door.
@Suite("Corpus disclosure — the substitution is announced before any verdict")
struct CorpusDisclosureTests {

    private static func member(
        corpusDirectory: String,
        mode: WorkdirMode = .algebraic
    ) -> SharedVerifierPackage.Member {
        SharedVerifierPackage.Member(
            entry: SemanticIndexEntry(
                identityHash: "0xAAAA00000000000\(abs(corpusDirectory.hashValue) % 10)",
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
                packagePath: URL(fileURLWithPath: "/tmp/\(corpusDirectory)"),
                productNames: ["Whatever"]
            ),
            mode: mode
        )
    }

    private static func warnings(
        for members: [SharedVerifierPackage.Member]
    ) -> [String] {
        var captured: [String] = []
        SwiftInferCommand.Verify.discloseSupersededDependencies(for: members) {
            captured.append($0)
        }
        return captured
    }

    /// **Silence is the normal case and must stay silent.** A warning on every
    /// ordinary survey trains the reader to skip it, which costs exactly the
    /// runs where it matters.
    @Test("an ordinary corpus produces no warning")
    func ordinaryCorpusIsSilent() {
        #expect(Self.warnings(for: [Self.member(corpusDirectory: "MyApp")]).isEmpty)
    }

    @Test("a superseding corpus is named, with what it displaced")
    func supersedingCorpusIsAnnounced() {
        let lines = Self.warnings(for: [Self.member(corpusDirectory: "swift-collections")])
        #expect(lines.count == 1)
        let line = lines.first ?? ""
        #expect(line.contains("swift-collections"))
        #expect(line.contains("/tmp/swift-collections"))
        // The reader has to learn that the verdict is about the checkout, or the
        // line is trivia rather than a caveat.
        #expect(line.contains("pinned"))
    }

    /// One line per corpus, not one per entry. A 98-entry survey that repeats the
    /// same caveat 98 times has buried it.
    @Test("many members over one corpus produce one warning")
    func disclosureIsRunLevelNotPerEntry() {
        let members = (0..<25).map { _ in Self.member(corpusDirectory: "swift-numerics") }
        #expect(Self.warnings(for: members).count == 1)
    }

    /// A member with no corpus cannot supersede anything.
    @Test("a member with no corpus is not announced")
    func noCorpusMemberIsSilent() {
        let bare = SharedVerifierPackage.Member(
            entry: SemanticIndexEntry(
                identityHash: "0xBBBB000000000001",
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
        #expect(Self.warnings(for: [bare]).isEmpty)
    }

    /// **Provenance must not invent a version.** A directory that is not a git
    /// checkout has no revision, and saying so is the honest answer — a bare path
    /// would read as though it pinned something.
    @Test("a non-git corpus says it has no revision rather than implying one")
    func nonGitCorpusSaysSo() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("provenance-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let described = CorpusProvenance.describe(root)
        #expect(described.contains(root.path))
        #expect(described.contains("not a git checkout"))
    }

    /// And a git checkout does resolve one — otherwise the honest-fallback branch
    /// above would be the only branch, and the feature would be a no-op that reads
    /// as caution.
    @Test("a git corpus resolves a revision")
    func gitCorpusResolvesRevision() {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let described = CorpusProvenance.describe(repository)
        #expect(described.contains(" @ "))
        #expect(!described.contains("not a git checkout"))
    }
}
