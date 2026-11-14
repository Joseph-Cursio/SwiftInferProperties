import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

/// `documented-range` verify support (#701): `(L...U as ClosedRange<Double>).contains(Double(f(x)))`,
/// measured rather than only written by `accept`.
///
/// `accept` has written the law complete since commit 18f8eb2e, and on SwiftLintRuleStudioCore it
/// refuted the unclamped `AnalysisProgress.progress` and passed once clamped. Verify lacked only
/// the bounds: discover parsed them from the doc comment and the projection dropped them. They
/// are persisted now (`SemanticIndexEntry.documentedRange`), for this template only, and an entry
/// indexed before that declines as stale rather than guessing.
///
/// This suite covers the index and the call; `DocumentedRangeComposerTests` covers the emitted
/// pass, the gates and the phrasing. The build-and-run in both directions lives in
/// `VerifyPipelineDocumentedRangeTests` (batch 3).
@Suite("documented-range — verify support")
struct DocumentedRangeVerifySupportTests {

    /// An instance property, an instance method with a parameter, a static method with one, a
    /// free function, and the one shape verify must refuse: a static member with no parameters.
    private static let subjectSource = """
        public struct AnalysisProgress {
            public let filesProcessed: Int
            public let totalFiles: Int
            /// Fraction of files processed (0.0 to 1.0)
            public var progress: Double { 0 }
            /// A percentage, between 0 and 100
            public func percent(of total: Int) -> Int { 0 }
            /// Clamped to [-1, 1]
            public static func offset(at x: Double) -> Double { 0 }
            /// The default, in 0...1
            public static var standard: Double { 0.5 }
        }
        /// Scaled into -10...-1
        public func scaled(_ x: Int) -> Int { -1 }
        """

    private static func indexedEntry(_ name: String) throws -> SemanticIndexEntry {
        let corpus = FunctionScanner.scanCorpus(source: subjectSource, file: "Progress.swift")
        let summary = try #require(corpus.summaries.first { $0.name == name })
        let suggestion = try #require(DocumentedRangeTemplate.suggest(for: summary))
        return SwiftInferCommand.Index.buildEntry(
            from: suggestion,
            decisionsByHash: [:],
            now: "2026-11-13T00:00:00Z"
        )
    }

    static let progressShape = IndexedTypeShape(
        name: "AnalysisProgress",
        kind: .struct,
        inheritedTypes: [],
        hasUserGen: false,
        storedMembers: [
            IndexedTypeShape.StoredMember(name: "filesProcessed", typeName: "Int"),
            IndexedTypeShape.StoredMember(name: "totalFiles", typeName: "Int"),
        ]
    )

    /// The `staleIndexEntry` reason `resolveFunctionCalls` gives `entry`, or nil when it resolves.
    private static func staleReason(_ entry: SemanticIndexEntry) -> String? {
        do {
            _ = try SwiftInferCommand.Verify.resolveFunctionCalls(for: entry)
            return nil
        } catch let VerifyError.staleIndexEntry(template, _, reason) {
            #expect(template == "documented-range")
            return reason
        } catch {
            Issue.record("expected staleIndexEntry, got \(error)")
            return nil
        }
    }

    // MARK: - Projection

    /// The return type rides along so a `Float` subject's bounds can round the way it does
    /// (`DocumentedRange.checkedBounds`).
    @Test("the projection persists the two literals the doc comment states, verbatim, and the codomain")
    func projectionPersistsTheBounds() throws {
        let expected: [(String, DocumentedRange)] = [
            ("progress", DocumentedRange(lower: "0.0", upper: "1.0", resultTypeName: "Double")),
            ("percent", DocumentedRange(lower: "0", upper: "100", resultTypeName: "Int")),
            ("offset", DocumentedRange(lower: "-1", upper: "1", resultTypeName: "Double")),
            ("scaled", DocumentedRange(lower: "-10", upper: "-1", resultTypeName: "Int")),
        ]
        for (name, range) in expected {
            #expect(try Self.indexedEntry(name).documentedRange == range, "\(name)")
        }
    }

    /// Only `documented-range`'s match carries bounds, so no other row gains the column.
    @Test("no other template's row carries the column")
    func projectionDoesNotOverPersist() throws {
        let corpus = FunctionScanner.scanCorpus(
            source: "public func versions(from start: Int, to end: Int) -> [Int] { [] }",
            file: "Ranges.swift"
        )
        let summary = try #require(corpus.summaries.first)
        let suggestion = try #require(EmptyRangeTemplate.suggest(for: summary))
        let entry = SwiftInferCommand.Index.buildEntry(
            from: suggestion, decisionsByHash: [:], now: "2026-11-13T00:00:00Z"
        )
        #expect(entry.templateName == "empty-range")
        #expect(entry.documentedRange == nil)
    }

    @Test("the column survives Codable and a re-index merge")
    func columnSurvivesPersistence() throws {
        let entry = try Self.indexedEntry("progress")
        let decoded = try JSONDecoder().decode(SemanticIndexEntry.self, from: JSONEncoder().encode(entry))
        #expect(decoded.documentedRange == entry.documentedRange)
        var edited = entry
        edited.documentedRange = DocumentedRange(lower: "0", upper: "100")
        // An edited doc comment is an edited law, so the fresh scan's bounds win.
        #expect(entry.updated(from: edited).documentedRange == edited.documentedRange)
    }

    // MARK: - Call resolution

    @Test("an instance property resolves to the receiver access, with the range as the renderer's inverse")
    func instancePropertyResolves() throws {
        let calls = try SwiftInferCommand.Verify.resolveFunctionCalls(for: try Self.indexedEntry("progress"))
        #expect(calls.expressions == ["{ $0.progress }"])
        #expect(calls.rendererForwardName == "AnalysisProgress.progress")
        #expect(calls.rendererInverseName == "0.0...1.0")
    }

    @Test("instance, static and free subjects with parameters resolve as predicate's do")
    func parameterisedSubjectsResolve() throws {
        let percent = try SwiftInferCommand.Verify.resolveFunctionCalls(for: try Self.indexedEntry("percent"))
        #expect(percent.expressions == ["{ $0.percent(of: $1) }"])
        let offset = try SwiftInferCommand.Verify.resolveFunctionCalls(for: try Self.indexedEntry("offset"))
        #expect(offset.expressions == ["{ AnalysisProgress.offset(at: $0) }"])
        let scaled = try SwiftInferCommand.Verify.resolveFunctionCalls(for: try Self.indexedEntry("scaled"))
        #expect(scaled.expressions.first?.contains("scaled") == true)
        #expect(scaled.rendererInverseName == "-10...-1")
    }

    /// Nothing to generate: the single-carrier fallback would pass a drawn value to a call that
    /// takes none. `accept` declines the same shape.
    @Test("a static member with no parameters is refused as having no input, not built")
    func staticNullaryIsRefused() throws {
        let entry = try Self.indexedEntry("standard")
        #expect(entry.isInstanceMethod == false)
        #expect {
            _ = try SwiftInferCommand.Verify.resolveFunctionCalls(for: entry)
        } throws: { error in
            guard case let VerifyError.noInputToGenerate(template, primary) = error else { return false }
            return template == "documented-range" && primary.hasPrefix("standard")
                && String(describing: error).contains("nothing to generate")
        }
    }

    // MARK: - An index written before the column

    /// The JSON an earlier binary wrote has no `documentedRange` key at all; decoding it must
    /// give `nil`, and `nil` must decline rather than emit a check with invented bounds.
    @Test("an entry decoded from an index that predates the column declines as stale")
    func oldIndexDeclinesAsStale() throws {
        let data = try JSONEncoder().encode(try Self.indexedEntry("progress"))
        var object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "documentedRange")
        let old = try JSONDecoder().decode(
            SemanticIndexEntry.self, from: JSONSerialization.data(withJSONObject: object)
        )
        #expect(old.documentedRange == nil)
        #expect(Self.staleReason(old)?.contains("documentedRange") == true)
    }

    @Test("the whole dispatch reports a stale entry and says to re-index")
    func dispatchReportsStaleEntry() throws {
        var entry = try Self.indexedEntry("progress")
        entry.documentedRange = nil
        #expect {
            _ = try SwiftInferCommand.Verify.buildStubBundle(entry: entry, budget: .small)
        } throws: { error in
            guard case VerifyError.staleIndexEntry = error else { return false }
            return String(describing: error).contains("Re-run `swift-infer index`")
        }
    }

    // MARK: - The whole dispatch

    /// Through the real first gate, the resolver, the strategist and the composer at once.
    @Test("the whole dispatch builds a stub that checks a receiver's property against its range")
    func dispatchBuildsInstancePropertyStub() throws {
        var entry = try Self.indexedEntry("progress")
        entry.typeShape = Self.progressShape
        let bundle = try SwiftInferCommand.Verify.buildStubBundle(entry: entry, budget: .small)
        #expect(bundle.source.contains("Generator<AnalysisProgress, some SendableSequenceType>"))
        #expect(bundle.source.contains("let documentedRange = (0.0 ... 1.0 as ClosedRange<Double>)"))
        #expect(bundle.source.contains("let result = { $0.progress }(candidate)"))
        #expect(bundle.rendererContext.templateName == "documented-range")
        #expect(bundle.rendererContext.inverseName == "0.0...1.0")
    }

    /// The receiver and the parameter each get their own generator, through `totalityOperands`.
    @Test("an instance method with a parameter draws a receiver and an argument")
    func dispatchBuildsInstanceMethodStub() throws {
        let bundle = try SwiftInferCommand.Verify.buildStubBundle(
            entry: try Self.indexedEntry("percent"),
            budget: .small,
            allShapes: ["AnalysisProgress": Self.progressShape]
        )
        #expect(bundle.source.contains("let generator0: Generator<AnalysisProgress, some SendableSequenceType>"))
        #expect(bundle.source.contains("let generator1: Generator<Int, some SendableSequenceType>"))
        #expect(bundle.source.contains("let result = { $0.percent(of: $1) }(candidate0, candidate1)"))
        #expect(bundle.source.contains("(0 ... 100 as ClosedRange<Double>)"), "integer bounds must not infer Int")
    }
}
