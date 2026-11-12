import Foundation
import SwiftInferCore
import SwiftParser
import SwiftSyntax

/// The A/B for the shipped syntax-level gate (`docs/measurements/guard-domain-syntax-gate.md`): the shipped
/// `GuardDomainReader.read` against `ReplicaReader` with today's text gate, which is the reader before the change,
/// on every function in the universe.
struct GateChangeRow: Codable {
    let key: String
    let condition: String
    let returned: String
    let templateEligible: Bool
    /// Names the old text gate read as free.
    let textFree: [String]
    /// Names guard-domain's writer could not bind: parameters, `self` (instance methods), `Self`, and the types
    /// the signature names, as `InteractiveTriage.guardDomainBindings` binds them.
    let writerUnbound: [String]
}

struct GateABRecord: Codable {
    var functions = 0
    var oldRows = 0
    var newRows = 0
    var gained: [GateChangeRow] = []
    var lost: [GateChangeRow] = []
    /// Functions both readers admit but read differently: must be empty, because only the gate changed.
    var changedReading: [String] = []
}

enum GateABRun {
    static func read(source: String, path: String, repository: String, repositoryRoot: String,
                     into record: inout GateABRecord) -> Int {
        let tree = Parser.parse(source: source)
        let converter = SourceLocationConverter(fileName: path, tree: tree)
        let scanned = FunctionScanner.scanCorpus(source: source, file: path)
        let summaries = Dictionary(scanned.summaries.map { ($0.location.line, $0) }) { first, _ in first }
        let collector = FunctionCollector(viewMode: .sourceAccurate)
        collector.walk(tree)
        let relative = path.hasPrefix(repositoryRoot + "/") ? String(path.dropFirst(repositoryRoot.count + 1)) : path
        for function in collector.functions {
            let line = converter.location(for: function.funcKeyword.positionAfterSkippingLeadingTrivia).line
            let key = "\(repository):\(relative):\(line) \(function.name.text)"
            let new = GuardDomainReader.read(function)
            let old = ReplicaReader.read(function, gate: .text)
            if new != nil { record.newRows += 1 }
            if old != nil { record.oldRows += 1 }
            let summary = summaries[line]
            let eligible = summary.map { summary in
                !summary.isMutating && !summary.isAsync && !summary.isThrows
                    && summary.returnTypeText.map { $0 != "Void" && $0 != "()" } == true
            } ?? false
            func row(_ condition: String, _ returned: String, _ parameter: String) -> GateChangeRow {
                let allowed: Set<String> = [parameter]
                let free = TextGate.freeNames(in: condition, allowed: allowed, allowingTypeNames: false)
                    .union(TextGate.freeNames(in: returned, allowed: allowed, allowingTypeNames: true))
                return GateChangeRow(
                    key: key, condition: condition, returned: returned, templateEligible: eligible,
                    textFree: free.sorted(),
                    writerUnbound: GuardDomainRebinding.unboundNames(
                        in: condition + " " + returned, bindings: bindings(function, parameter: parameter)
                    )
                )
            }
            switch (old, new) {
            case (nil, let new?):
                record.gained.append(row(new.condition, new.returnedExpression, new.parameterName))
            case (let old?, nil):
                record.lost.append(row(old.condition, old.returnedExpression, old.parameterName))
            case (let old?, let new?):
                if old.condition != new.condition || old.returnedExpression != new.returnedExpression
                    || old.firesWhenConditionHolds != new.firesWhenConditionHolds {
                    record.changedReading.append(key)
                }
            case (nil, nil):
                break
            }
        }
        return collector.functions.count
    }

    /// The names guard-domain's writer binds for `function`.
    static func bindings(_ function: FunctionDeclSyntax, parameter: String) -> [String: String] {
        var bindings = [parameter: "arg1"]
        let enclosing = Enclosing.of(Syntax(function))
        let isStatic = function.modifiers.contains { [.keyword(.static), .keyword(.class)].contains($0.name.tokenKind) }
        if enclosing.typeName != nil, !isStatic { bindings["self"] = "arg0" }
        if let typeName = enclosing.typeName { bindings["Self"] = typeName }
        let signature = function.signature.trimmedDescription
        var current = ""
        for character in signature + " " {
            if character.isLetter || character.isNumber || character == "_" {
                current.append(character)
                continue
            }
            if current.first?.isUppercase == true, current != "Self", bindings[current] == nil {
                bindings[current] = current
            }
            current = ""
        }
        return bindings
    }
}
