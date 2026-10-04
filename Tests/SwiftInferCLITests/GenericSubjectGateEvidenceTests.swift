import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// The evidence form of `GenericSubjectGate`, which the docstring advisory's reference oracle
/// calls with a function's own row, answers exactly as the suggestion form does — over every
/// fixture `GenericSubjectGateTests` holds, declined and written alike.
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
            for: evidence, owner: row.owner ?? suggestion.carrier, genericParametersByName: map
        )
        #expect(byRow == bySuggestion)
        #expect((byRow != nil) == row.declines)
    }
}
