import Foundation
import SwiftInferCore
import SwiftParser
import SwiftSyntax

/// One parameter of an Action enum case — its (optional) argument label and
/// type text. Used by the trace-mining selector to emit a *labeled*,
/// type-correct generated argument when generalizing a payload-bearing mined
/// action (Slice 3b).
struct ActionParam: Equatable, Sendable {
    let label: String?
    let type: String
}

/// One case of an Action enum — its name plus ordered parameters. The
/// trace-mining alphabet: `payloadFree` cases replay verbatim; payload-bearing
/// cases are generalized to `.case(label: <generated>, …)` when every
/// parameter type is cheaply defaultable, else the trace is dropped.
struct ActionCaseSpec: Equatable, Sendable {
    let name: String
    let parameters: [ActionParam]
    var isPayloadFree: Bool { parameters.isEmpty }
}

/// TestStore Trace Mining (Slice 3a) — resolves an Action enum's cases +
/// parameter labels/types by scanning the target's sources, for *any* carrier
/// (`.tca`, `.elmStyle`, `.generic`). Discovery only captures `actionCases`
/// (name + payload types, no labels) for `.tca` nested Action enums, so this
/// scanner is the single alphabet source the selector uses — it works for a
/// top-level `enum AppAction` (generic/Elm) AND a nested `Feature.Action`
/// (`.tca`), and it carries the argument labels payload generalization needs.
///
/// Matching:
///   - bare name (`"AppAction"`) → any enum whose name matches;
///   - dotted name (`"Feature.Action"`) → an enum named `Action` whose
///     enclosing type stack ends with `Feature`.
///
/// Best-effort + never throws: an unreadable / missing directory yields `[]`
/// (→ the selector mines nothing → byte-identical un-mined path).
enum ActionAlphabetScanner {

    static func scan(directory: URL, actionTypeName: String) -> [ActionCaseSpec] {
        let components = actionTypeName.split(separator: ".").map(String.init)
        guard let enumName = components.last else { return [] }
        let enclosing = components.dropLast().last  // nil for a bare name
        for fileURL in SwiftSourceFiles.sorted(in: directory) {
            guard let source = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            let visitor = ActionEnumVisitor(enumName: enumName, enclosing: enclosing)
            visitor.walk(Parser.parse(source: source))
            if let found = visitor.cases {
                return found
            }
        }
        return []
    }
}

/// Finds the target Action enum (by name, optionally qualified by an enclosing
/// type) and reads its cases. Stops at the first match per file.
private final class ActionEnumVisitor: SyntaxVisitor {

    private let enumName: String
    private let enclosing: String?
    private var typeStack: [String] = []
    private(set) var cases: [ActionCaseSpec]?

    init(enumName: String, enclosing: String?) {
        self.enumName = enumName
        self.enclosing = enclosing
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        typeStack.append(node.name.text)
        return .visitChildren
    }
    override func visitPost(_: StructDeclSyntax) { typeStack.removeLast() }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        if cases == nil, matches(node) {
            cases = readCases(node)
        }
        typeStack.append(node.name.text)
        return .visitChildren
    }
    override func visitPost(_: EnumDeclSyntax) { typeStack.removeLast() }

    private func matches(_ node: EnumDeclSyntax) -> Bool {
        guard node.name.text == enumName else { return false }
        guard let enclosing else { return true }  // bare name: any match
        return typeStack.last == enclosing        // dotted: enclosing type must match
    }

    private func readCases(_ node: EnumDeclSyntax) -> [ActionCaseSpec] {
        var specs: [ActionCaseSpec] = []
        for member in node.memberBlock.members {
            guard let caseDecl = member.decl.as(EnumCaseDeclSyntax.self) else { continue }
            for element in caseDecl.elements {
                let params = element.parameterClause?.parameters.map { param in
                    ActionParam(
                        label: param.firstName?.text,
                        type: param.type.trimmedDescription
                    )
                } ?? []
                specs.append(ActionCaseSpec(name: element.name.text, parameters: params))
            }
        }
        return specs
    }
}
