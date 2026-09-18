import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import SwiftInferTemplates
import Testing

/// The scanner reads `nonisolated` and, until #482, threw it away.
///
/// **`globalActor == nil` was answering two different questions with one value**:
/// `resolvedGlobalActor` returns `nil` both for a declaration nobody isolated and for one that
/// explicitly opted OUT. Those are the same until something tries to supply a default — and a
/// target compiled under `.defaultIsolation(MainActor.self)` does exactly that, isolating the
/// first while it must not touch the second.
@Suite("FunctionScanner — the nonisolated keyword")
struct NonisolatedKeywordTests {

    @Test("the scanner records nonisolated, in both of its spellings")
    func scannerRecordsTheKeyword() {
        let source = """
        @MainActor
        public struct Formatter {
            public nonisolated func plain(_ text: String) -> String { text }
            public nonisolated(unsafe) func waived(_ text: String) -> String { text }
            public func isolated(_ text: String) -> String { text }
        }
        """
        let corpus = FunctionScanner.scanCorpus(source: source, file: "F.swift")
        func summary(_ name: String) -> FunctionSummary? {
            corpus.summaries.first { $0.name == name }
        }

        #expect(summary("plain")?.declaresNonisolated == true)
        #expect(summary("waived")?.declaresNonisolated == true)
        #expect(summary("isolated")?.declaresNonisolated == false)
        // And the existing reading is unchanged: an opted-out member resolves to no actor, an
        // ordinary member of a `@MainActor` type inherits one lexically.
        #expect(summary("plain")?.globalActor == nil)
        #expect(summary("isolated")?.globalActor == "MainActor")
    }

    @Test("the keyword reaches Evidence, so the post-pass can read it")
    func keywordReachesEvidence() {
        let source = """
        @MainActor
        public struct Formatter {
            public nonisolated func plain(_ text: String) -> String { text }
        }
        """
        let corpus = FunctionScanner.scanCorpus(source: source, file: "F.swift")
        let scanned = corpus.summaries.first { $0.name == "plain" }
        #expect(scanned?.inferenceEvidence.declaresNonisolated == true)
    }
}
