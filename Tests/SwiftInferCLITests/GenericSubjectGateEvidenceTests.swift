import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// The evidence form of `GenericSubjectGate`, which the docstring advisory's reference oracle
/// calls with a function's own row, answers exactly as the suggestion form does — over every
/// fixture `GenericSubjectGateTests` holds, declined and written alike: the hand-built rows in
/// `rows`, and the three it scans from source in `scannedRows`.
///
/// The row form is given the declaring type the FIXTURE states (`owner`, else `carrier`), which is
/// what a caller holding a function's own row passes — not the suggestion's, which would restate
/// the forwarding under test.
@Suite("Generic subjects — the row form answers as the suggestion form does")
struct GenericSubjectGateEvidenceTests {

    struct Row: Sendable {
        let display: String
        let parameterTypes: [String]
        var owner: String?
        var carrier: String?
        var generics: [String] = []
        var map: [String: [String]] = [:]
        let declines: Bool
    }

    static let rows: [Row] = [
        Row(
            display: "contains(_:)", parameterTypes: ["Key"], owner: "KeyedDecoding",
            map: ["KeyedDecoding": ["Key"]], declines: true
        ),
        Row(display: "isEmpty", parameterTypes: [], owner: "Deque", map: ["Deque": ["Element"]], declines: true),
        Row(
            display: "isValid(_:)", parameterTypes: ["String"], owner: "Checker",
            map: ["Deque": ["Element"]], declines: false
        ),
        Row(display: "contains(_:)", parameterTypes: ["Key"], owner: "KeyedDecoding", declines: false),
        Row(display: "isTopLevel(_:)", parameterTypes: ["some SyntaxProtocol"], owner: "Visitor", declines: true),
        Row(display: "accepts(_:)", parameterTypes: ["any SyntaxProtocol"], owner: "Checker", declines: false),
        Row(display: "check(_:)", parameterTypes: ["HandsomeValue"], owner: "Checker", declines: false),
        Row(display: "union(_:)", parameterTypes: ["Set<T>"], generics: ["T"], declines: true),
        Row(display: "make()", parameterTypes: [], generics: ["T"], declines: true),
        // No recorded declaring type: the suggestion form falls back to its carrier.
        Row(display: "isEmpty", parameterTypes: [], carrier: "Deque", map: ["Deque": ["Element"]], declines: true)
    ]

    @Test("the evidence overload equals the suggestion overload", arguments: rows.indices)
    func theRowFormAnswersAsTheSuggestionFormDoes(index: Int) {
        let row = Self.rows[index]
        let evidence = Evidence(
            displayName: row.display,
            signature: "\(row.display) -> Bool",
            location: SourceLocation(file: "Gate.swift", line: 1, column: 1),
            parameterTypeNames: row.parameterTypes,
            qualifiedTypeName: row.owner,
            genericParameters: row.generics.map { TypeDecl.GenericParameter(name: $0, constraint: nil) }
        )
        var suggestion = SubjectCallPlanBothSidesTests.suggestion(for: evidence)
        suggestion.carrier = row.carrier ?? row.owner
        let map = row.map.mapValues { names in names.map { TypeDecl.GenericParameter(name: $0, constraint: nil) } }
        let bySuggestion = GenericSubjectGate.declineReason(for: suggestion, genericParametersByName: map)
        let byRow = GenericSubjectGate.declineReason(
            for: evidence, owner: row.owner ?? row.carrier, genericParametersByName: map
        )
        #expect(byRow == bySuggestion)
        #expect((byRow != nil) == row.declines)
    }

    /// `GenericSubjectGateTests`' scanner-built fixtures, so the `Evidence` projection is covered
    /// as well as the gate: a top-level generic function, a non-generic free function, and a
    /// generic method on a non-generic type beside an unrelated map.
    struct ScannedRow: Sendable {
        let source: String
        let carrier: String?
        var map: [String: [String]] = [:]
        let declines: Bool
    }

    static let scannedRows: [ScannedRow] = [
        ScannedRow(
            source: "func swapAtInvolutionCounterexample<C: MutableCollection>(for sample: C) -> String? { nil }",
            carrier: nil,
            declines: true
        ),
        ScannedRow(source: "func isValid(_ name: String) -> Bool { true }", carrier: nil, declines: false),
        ScannedRow(
            source: """
                struct Sorter {
                    func sorted<S: Sequence>(_ values: S) -> [S.Element] where S.Element: Comparable { [] }
                }
                """,
            carrier: "Sorter",
            map: ["Deque": ["Element"]],
            declines: true
        )
    ]

    @Test("the evidence overload equals the suggestion overload on a scanned row", arguments: scannedRows.indices)
    func theRowFormAnswersAsTheSuggestionFormDoesOnAScannedRow(index: Int) throws {
        let row = Self.scannedRows[index]
        let summary = try #require(FunctionScanner.scan(source: row.source, file: "Gate.swift").first)
        let evidence = summary.inferenceEvidence
        var suggestion = SubjectCallPlanBothSidesTests.suggestion(for: evidence)
        suggestion.carrier = row.carrier
        let map = row.map.mapValues { names in names.map { TypeDecl.GenericParameter(name: $0, constraint: nil) } }
        let bySuggestion = GenericSubjectGate.declineReason(for: suggestion, genericParametersByName: map)
        let byRow = GenericSubjectGate.declineReason(
            for: evidence, owner: summary.qualifiedContainingTypeName ?? row.carrier, genericParametersByName: map
        )
        #expect(byRow == bySuggestion)
        #expect((byRow != nil) == row.declines)
    }
}
