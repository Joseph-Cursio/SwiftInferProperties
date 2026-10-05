import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

/// The reference oracle and the determinism law cannot drift apart: the oracle's property IS the
/// agreement property with the `_reference` twin on the right, and renaming that twin back gives
/// the determinism law's own property for the same draws.
extension ReferenceOracleCalleeEmitterTests {

    static let driftTable: [(LiftedTestEmitter.ReferenceOracleSubject, [String])] = [
        (.init(
            callee: CalleeReference(bareName: "correlation", qualifier: "BeadCorrelation", argumentLabels: ["for"]),
            owner: "BeadCorrelation", parameters: [parameter("for", "items", "[Item]")],
            returnTypeText: "Int", isAsync: false, isThrows: false
        ), ["[Item]"]),
        (.init(
            callee: CalleeReference(bareName: "relative", argumentLabels: [nil], isInstanceMethod: true),
            owner: "WorkspaceJail", parameters: [parameter(nil, "url", "URL")],
            returnTypeText: "String", isAsync: false, isThrows: true
        ), ["WorkspaceJail", "URL"]),
        (.init(
            callee: CalleeReference(
                bareName: "count", argumentLabels: ["of"],
                isolation: CalleeReference.actorReceiverIsolation, isInstanceMethod: true
            ),
            owner: "Ledger", parameters: [parameter("of", "entry", "String")],
            returnTypeText: "Int", isAsync: false, isThrows: true
        ), ["Ledger", "String"]),
        (.init(
            callee: CalleeReference(
                bareName: "title", qualifier: "Sidebar", argumentLabels: ["for"], isolation: "MainActor"
            ),
            owner: "Sidebar", parameters: [parameter("for", "count", "Int")],
            returnTypeText: "Double", isAsync: false, isThrows: false
        ), ["Int"]),
        (.init(
            callee: CalleeReference(bareName: "load", qualifier: "Loader", argumentLabels: [nil, "retries"]),
            owner: "Loader", parameters: [parameter(nil, "path", "String"), parameter("retries", "retries", "Int")],
            returnTypeText: "Int", isAsync: true, isThrows: true
        ), ["String", "Int"]),
        (.init(
            callee: CalleeReference(bareName: "canReach", argumentLabels: ["from", "to"]),
            owner: nil, parameters: [parameter("from", "origin", "Int"), parameter("to", "target", "Int")],
            returnTypeText: "Bool", isAsync: false, isThrows: false
        ), ["Int", "Int"]),
        (.init(
            callee: CalleeReference(bareName: "+", argumentLabels: ["lhs", "rhs"]),
            owner: "Money", parameters: [parameter("lhs", "lhs", "Money"), parameter("rhs", "rhs", "Money")],
            returnTypeText: "Money", isAsync: false, isThrows: false
        ), ["Money", "Money"])
    ]

    @Test(
        "the oracle's property is the agreement property, and renamed back it is determinism's",
        arguments: driftTable
    )
    func theOracleCannotDriftFromTheDeterminismLaw(
        subject: LiftedTestEmitter.ReferenceOracleSubject,
        argumentTypes: [String]
    ) {
        let kind: LiftedTestEmitter.EqualityKind = subject.returnTypeText == "Double" ? .approximate : .strict
        let scaffold = Self.emit(subject, argumentTypes, equalityKind: kind)
        let property = LiftedTestEmitter.agreementProperty(.init(
            subject: subject.callee,
            oracle: subject.reference,
            argumentTypes: argumentTypes,
            argumentCount: argumentTypes.count,
            equalityKind: kind,
            isAsync: subject.isAsync,
            isThrows: subject.isThrows
        ))
        #expect(scaffold.contains("property: \(property)\n"))
        // An operator's twin is a named function, so it has no infix spelling to rename back to.
        guard subject.callee.isOperator == false else { return }
        let determinism = LiftedTestEmitter.deterministic(
            callee: subject.callee,
            generators: argumentTypes.map { "\($0).gen()" },
            seed: Self.seed,
            equalityKind: kind,
            isAsync: subject.isAsync,
            isThrows: subject.isThrows,
            argumentTypes: argumentTypes
        )
        let identifier = subject.callee.identifierName
        let renamed = property.replacingOccurrences(of: "\(identifier)_reference(", with: "\(identifier)(")
        #expect(determinism.contains("property: \(renamed)\n"))
    }
}
