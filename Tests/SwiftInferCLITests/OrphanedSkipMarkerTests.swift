import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

/// **A skip marker that matches nothing is invisible, so `drift` says so** (#490).
///
/// Changing six templates' identities to carry argument labels changed their hashes on one
/// commit. Every `// swiftinfer: skip <hash>` written against a `comparator`,
/// `input-totality`, `equivalence-relation`, `functor-identity`, `state-machine` or
/// `differential-equivalence` row stopped matching — and nothing said so, because a marker that
/// suppresses nothing looks exactly like a suggestion that was never suppressed.
@Suite("Orphaned skip markers")
struct OrphanedSkipMarkerTests {

    private func scan(_ source: String) throws -> TemplateRegistry.DiscoverArtifacts {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("skip-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data(source.utf8).write(to: root.appendingPathComponent("Subject.swift"))
        return try TemplateRegistry.discoverArtifacts(in: root)
    }

    @Test("a marker matching no proposed suggestion is reported as unmatched")
    func orphanedMarkerIsReported() throws {
        let artifacts = try scan("""
        // swiftinfer: skip 0xDEADBEEFDEADBEEF
        public struct Subject {
            public func normalized(_ text: String) -> String { text.trimmingCharacters(in: .whitespaces) }
        }
        """)
        #expect(artifacts.unmatchedSkipHashes.contains("DEADBEEFDEADBEEF"))
    }

    /// The load-bearing half: a marker that DOES suppress something must not be reported.
    /// The filter removes its suggestion, so a naive check against the surviving rows would
    /// call every working marker orphaned — which is the trap this is written against.
    @Test("a marker that suppresses a real suggestion is NOT reported")
    func workingMarkerIsNotReported() throws {
        let source = """
        public struct Subject {
            public func normalized(_ text: String) -> String { text.trimmingCharacters(in: .whitespaces) }
        }
        """
        let unsuppressed = try scan(source)
        let target = try #require(unsuppressed.suggestions.first)

        let suppressed = try scan("// swiftinfer: skip 0x\(target.identity.normalized)\n" + source)
        #expect(!suppressed.suggestions.contains { $0.identity == target.identity })
        #expect(
            !suppressed.unmatchedSkipHashes.contains(target.identity.normalized),
            "a marker that fired must not be called orphaned"
        )
    }

    @Test("no markers means nothing to report")
    func noMarkersIsQuiet() throws {
        let artifacts = try scan("public struct Subject { public func f(_ x: Int) -> Int { x } }")
        #expect(artifacts.unmatchedSkipHashes.isEmpty)
    }
}
