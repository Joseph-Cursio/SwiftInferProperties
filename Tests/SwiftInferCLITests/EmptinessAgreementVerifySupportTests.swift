import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

/// `emptiness-agreement` verify support (#701): `value.p == (value.m > 0)`, or `== 0` for
/// `isEmpty`, measured rather than only written by `accept`.
///
/// `accept` writes the whole law from the template's two evidence rows, and on
/// SwiftLintRuleStudioCore's `CompatibilityReport` it killed both `||` → `&&` mutants. Verify
/// lacked two things the index dropped: the measure's name, and whether it is a computed property
/// or a nullary method, which no name spells. Both are now persisted, for this template only, and
/// an entry indexed before them declines as stale rather than guessing.
///
/// The precedent is `DifferentialVerifySupportTests`. The build-and-run in both directions lives in
/// `VerifyPipelineEmptinessAgreementTests` (batch 3).
@Suite("emptiness-agreement — verify support")
struct EmptinessAgreementVerifySupportTests {

    /// All four property/method combinations, both polarities.
    private static let subjectSource = """
        public struct Report {
            let deprecated: Int
            let removed: Int
            public var hasIssues: Bool { deprecated > 0 || removed > 0 }
            public var totalIssueCount: Int { (deprecated > 0 ? 1 : 0) + (removed > 0 ? 1 : 0) }
        }
        public struct Queue {
            let size: Int
            public func isEmpty() -> Bool { size == 0 }
            public func count() -> Int { size }
        }
        public struct Bag {
            let size: Int
            public var isEmpty: Bool { size == 0 }
            public func count() -> Int { size }
        }
        public struct Search {
            let size: Int
            public func hasMatches() -> Bool { size > 0 }
            public var matchCount: Int { size }
        }
        """

    /// The entry the real pipeline builds: scan, the real pairing and template, the real projection.
    private static func indexedEntry(onType type: String) throws -> SemanticIndexEntry {
        let corpus = FunctionScanner.scanCorpus(source: subjectSource, file: "Agreement.swift")
        let pair = try #require(
            EmptinessAgreementPairing.candidates(in: corpus.summaries)
                .first { $0.predicate.containingTypeName == type }
        )
        let suggestion = try #require(EmptinessAgreementTemplate.suggest(for: pair))
        return SwiftInferCommand.Index.buildEntry(
            from: suggestion,
            decisionsByHash: [:],
            now: "2026-11-13T00:00:00Z"
        )
    }

    /// A hand-built two-evidence suggestion whose second row IS a computed property, so a
    /// projection that over-persisted the flag would show it on these rows.
    private static func twoHalfSuggestion(templateName: String) -> Suggestion {
        func evidence(_ name: String, isComputedProperty: Bool) -> Evidence {
            Evidence(
                displayName: name,
                signature: "() -> Int",
                location: SourceLocation(file: "/Pair.swift", line: 1, column: 1),
                isComputedProperty: isComputedProperty
            )
        }
        return Suggestion(
            templateName: templateName,
            evidence: [
                evidence("forward()", isComputedProperty: false),
                evidence("backward()", isComputedProperty: true),
            ],
            score: Score(signals: [Signal(kind: .exactNameMatch, weight: 35, detail: "pair")]),
            generator: GeneratorMetadata(source: .notYetComputed, confidence: nil, sampling: .notRun),
            explainability: ExplainabilityBlock(whySuggested: ["why"], whyMightBeWrong: ["caveat"]),
            identity: SuggestionIdentity(canonicalInput: "\(templateName)|pair"),
            carrier: "Pair"
        )
    }

    private static func staleReason(_ entry: SemanticIndexEntry) -> String? {
        do {
            _ = try SwiftInferCommand.Verify.resolveFunctionCalls(for: entry)
            return nil
        } catch let VerifyError.staleIndexEntry(template, _, reason) {
            #expect(template == "emptiness-agreement")
            return reason
        } catch {
            Issue.record("expected staleIndexEntry, got \(error)")
            return nil
        }
    }

    // MARK: - Projection

    @Test("the projection persists the measure's name and its property-or-method shape")
    func projectionPersistsNameAndFlag() throws {
        let report = try Self.indexedEntry(onType: "Report")
        #expect(report.templateName == "emptiness-agreement")
        #expect(report.primaryFunctionName == "hasIssues()")
        #expect(report.isComputedProperty == true)
        #expect(report.secondaryFunctionName == "totalIssueCount()")
        #expect(report.secondaryMemberShape == .computedProperty)

        let queue = try Self.indexedEntry(onType: "Queue")
        #expect(queue.isComputedProperty == false)
        #expect(queue.secondaryFunctionName == "count()")
        #expect(queue.secondaryMemberShape == .nullaryMethod, "a method must be recorded as one, not as nil")
    }

    /// The flag is written for the one template that reads it. Round-trip and differential apply
    /// their halves as functions, so their rows must stay as they were.
    @Test("no other template gains the flag, even when its second row is a property", arguments: [
        "round-trip", "differential-equivalence", "idempotence", "empty-range",
    ])
    func otherTemplatesKeepNilFlag(template: String) {
        let entry = SwiftInferCommand.Index.buildEntry(
            from: Self.twoHalfSuggestion(templateName: template),
            decisionsByHash: [:],
            now: "2026-11-13T00:00:00Z"
        )
        #expect(entry.secondaryMemberShape == nil)
    }

    @Test("the column survives an encode/decode round trip and a re-index merge")
    func columnRoundTrips() throws {
        let entry = try Self.indexedEntry(onType: "Search")
        let decoded = try JSONDecoder().decode(SemanticIndexEntry.self, from: JSONEncoder().encode(entry))
        #expect(decoded == entry)
        #expect(decoded.secondaryMemberShape == .computedProperty)
        var rescanned = entry
        rescanned.secondaryMemberShape = .nullaryMethod
        #expect(entry.updated(from: rescanned).secondaryMemberShape == .nullaryMethod, "a re-scan is authoritative")
    }

    // MARK: - Call resolution

    /// All four combinations: the spelling of each member comes from its own flag.
    @Test("each member is spelled from its own flag", arguments: [
        ("Report", ["hasIssues", "totalIssueCount"]),
        ("Queue", ["isEmpty()", "count()"]),
        ("Bag", ["isEmpty", "count()"]),
        ("Search", ["hasMatches()", "matchCount"]),
    ])
    func membersAreSpelledFromTheirFlags(type: String, expected: [String]) throws {
        let calls = try SwiftInferCommand.Verify.resolveFunctionCalls(for: try Self.indexedEntry(onType: type))
        #expect(calls.expressions == expected)
        #expect(calls.rendererForwardName == expected[0].replacingOccurrences(of: "()", with: ""))
        #expect(calls.rendererInverseName == expected[1].replacingOccurrences(of: "()", with: ""))
    }

    /// An index written before #701 has neither the measure's name nor the column. Decoded from
    /// JSON with both keys removed, as a real old `index.json` would read.
    @Test("an entry decoded from an index older than the column declines as stale")
    func oldIndexDeclinesAsStale() throws {
        let entry = try Self.indexedEntry(onType: "Report")
        var object = try #require(
            try JSONSerialization.jsonObject(with: JSONEncoder().encode(entry)) as? [String: Any]
        )
        object.removeValue(forKey: "secondaryMemberShape")
        let flagless = try JSONDecoder().decode(
            SemanticIndexEntry.self, from: JSONSerialization.data(withJSONObject: object)
        )
        #expect(flagless.secondaryMemberShape == nil)
        #expect(Self.staleReason(flagless)?.contains("secondaryMemberShape") == true)

        object.removeValue(forKey: "secondaryFunctionName")
        let nameless = try JSONDecoder().decode(
            SemanticIndexEntry.self, from: JSONSerialization.data(withJSONObject: object)
        )
        #expect(Self.staleReason(nameless)?.contains("secondaryFunctionName") == true)
    }

    @Test("names that no longer pair decline as stale rather than guessing a polarity")
    func unpairedNamesDeclineAsStale() throws {
        var entry = try Self.indexedEntry(onType: "Report")
        entry.secondaryFunctionName = "retryCount()"
        #expect(Self.staleReason(entry)?.contains("no longer pair") == true)
    }

    /// The stale refusal reaches `buildStubBundle`'s caller as itself, never as a build failure
    /// or an unsupported template, and its message tells the reader to re-index.
    @Test("the whole dispatch reports a stale entry and says to re-index")
    func dispatchReportsStaleEntry() throws {
        var entry = try Self.indexedEntry(onType: "Report")
        entry.secondaryMemberShape = nil
        #expect {
            _ = try SwiftInferCommand.Verify.buildStubBundle(entry: entry, budget: .small)
        } throws: { error in
            guard case VerifyError.staleIndexEntry = error else { return false }
            return String(describing: error).contains("Re-run `swift-infer index`")
        }
    }

    /// Through the real first gate, the resolver, the strategist and the composer at once.
    @Test("the whole dispatch builds a stub that reads both members off one value")
    func dispatchBuildsTheStub() throws {
        var entry = try Self.indexedEntry(onType: "Report")
        entry.typeShape = IndexedTypeShape(
            name: "Report",
            kind: .struct,
            inheritedTypes: [],
            hasUserGen: false,
            storedMembers: [
                IndexedTypeShape.StoredMember(name: "deprecated", typeName: "Int"),
                IndexedTypeShape.StoredMember(name: "removed", typeName: "Int"),
            ]
        )
        let bundle = try SwiftInferCommand.Verify.buildStubBundle(entry: entry, budget: .small)
        #expect(bundle.source.contains("Generator<Report, some SendableSequenceType>"))
        #expect(bundle.source.contains("let holds: Bool = value.hasIssues\n"))
        #expect(bundle.source.contains("let measured = value.totalIssueCount\n"))
        #expect(bundle.source.contains("if holds != (measured > 0) {"))
        #expect(bundle.rendererContext.forwardName == "hasIssues")
        #expect(bundle.rendererContext.inverseName == "totalIssueCount")
    }
}
