import SwiftSyntax

/// What a replica of `GuardDomainReader.read` read, with the syntax its condition came from.
struct ReplicaDomain: Equatable {
    let condition: String
    let returnedExpression: String
    let parameterName: String
    let firesWhenConditionHolds: Bool
    /// The condition's syntax: each condition element, or the ternary's elements before the `?`.
    let conditionNodes: [ExprSyntax]
    /// Whether the nodes are a ternary's sequence elements rather than condition elements.
    let fromTernary: Bool

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.condition == rhs.condition && lhs.returnedExpression == rhs.returnedExpression
            && lhs.parameterName == rhs.parameterName && lhs.firesWhenConditionHolds == rhs.firesWhenConditionHolds
    }
}

enum Gate {
    case text
    case labelAware
}

/// `GuardDomainReader.read` (Sources/SwiftInferCore/GuardDomainReader.swift), rule for rule, with its
/// free-identifier gate swappable (§2.4.2). With `.text` it must agree with the shipped reader on every function;
/// that agreement is the replica guard.
enum ReplicaReader {
    static func read(_ function: FunctionDeclSyntax, gate: Gate) -> ReplicaDomain? {
        let parameters = function.signature.parameterClause.parameters
        guard parameters.count == 1, let parameter = parameters.first else { return nil }
        let name = (parameter.secondName ?? parameter.firstName).text
        guard name != "_" else { return nil }
        guard let first = function.body?.statements.first?.item else { return nil }
        if let guardStmt = first.as(GuardStmtSyntax.self) {
            return domain(conditions: guardStmt.conditions, body: guardStmt.body, parameter: name, fires: false, gate: gate)
        }
        if let expression = first.as(ExpressionStmtSyntax.self),
           let ifExpr = expression.expression.as(IfExprSyntax.self), ifExpr.elseBody == nil {
            return domain(conditions: ifExpr.conditions, body: ifExpr.body, parameter: name, fires: true, gate: gate)
        }
        if function.body?.statements.count == 1 {
            return ternaryDomain(first, parameter: name, gate: gate)
        }
        return nil
    }

    static func admits(
        _ parameter: String,
        text: String,
        nodes: [Syntax],
        allowingTypeNames: Bool = false,
        gate: Gate
    ) -> Bool {
        switch gate {
        case .text: TextGate.mentionsOnly(parameter, in: text, allowingTypeNames: allowingTypeNames)
        case .labelAware: LabelAwareGate.mentionsOnly(parameter, in: nodes, allowingTypeNames: allowingTypeNames)
        }
    }

    private static func ternaryDomain(_ item: CodeBlockItemSyntax.Item, parameter: String, gate: Gate) -> ReplicaDomain? {
        let expression = item.as(ReturnStmtSyntax.self)?.expression
            ?? item.as(ExpressionStmtSyntax.self)?.expression
            ?? item.as(ExprSyntax.self)
        guard let sequence = expression?.as(SequenceExprSyntax.self) else { return nil }
        let elements = Array(sequence.elements)
        let ternaries = elements.indices.filter { elements[$0].is(UnresolvedTernaryExprSyntax.self) }
        guard ternaries.count == 1, let index = ternaries.first, index > 0, index < elements.count - 1,
              let ternary = elements[index].as(UnresolvedTernaryExprSyntax.self) else { return nil }
        let conditionNodes = Array(elements[..<index])
        let elseNodes = Array(elements[(index + 1)...])
        let condition = conditionNodes.map(\.trimmedDescription).joined(separator: " ")
        let thenBranch = ternary.thenExpression.trimmedDescription
        let elseBranch = elseNodes.map(\.trimmedDescription).joined(separator: " ")
        guard admits(parameter, text: condition, nodes: conditionNodes.map(Syntax.init), gate: gate) else { return nil }
        let thenIsParameter = thenBranch == parameter
        let (returned, fires) = thenIsParameter ? (elseBranch, false) : (thenBranch, true)
        let returnedNodes = thenIsParameter ? elseNodes.map(Syntax.init) : [Syntax(ternary.thenExpression)]
        guard returned != parameter, !returned.isEmpty,
              admits(parameter, text: returned, nodes: returnedNodes, allowingTypeNames: true, gate: gate) else {
            return nil
        }
        return ReplicaDomain(
            condition: condition,
            returnedExpression: returned,
            parameterName: parameter,
            firesWhenConditionHolds: fires,
            conditionNodes: conditionNodes,
            fromTernary: true
        )
    }

    private static func domain(
        conditions: ConditionElementListSyntax,
        body: CodeBlockSyntax,
        parameter: String,
        fires: Bool,
        gate: Gate
    ) -> ReplicaDomain? {
        var nodes: [ExprSyntax] = []
        for element in conditions {
            guard case .expression(let expression) = element.condition else { return nil }
            nodes.append(expression)
        }
        guard !nodes.isEmpty else { return nil }
        let condition = nodes.map(\.trimmedDescription).joined(separator: " && ")
        guard admits(parameter, text: condition, nodes: nodes.map(Syntax.init), gate: gate) else { return nil }
        guard body.statements.count == 1,
              let returnStmt = body.statements.first?.item.as(ReturnStmtSyntax.self),
              let returnedNode = returnStmt.expression else { return nil }
        let returned = returnedNode.trimmedDescription
        guard !returned.isEmpty,
              admits(parameter, text: returned, nodes: [Syntax(returnedNode)], allowingTypeNames: true, gate: gate) else {
            return nil
        }
        return ReplicaDomain(
            condition: condition,
            returnedExpression: returned,
            parameterName: parameter,
            firesWhenConditionHolds: fires,
            conditionNodes: nodes,
            fromTernary: false
        )
    }
}
