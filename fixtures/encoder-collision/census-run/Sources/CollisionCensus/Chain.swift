import Foundation
import SwiftSyntax

/// §1.2: a shortest pair `s ≠ t` with `f(s) == f(t)` over the classifier's own domain, breadth-first.
struct Witness: Codable, Equatable {
    let first: String
    let second: String
    let image: String
}

enum Collision {
    /// The classifier's domain (its alphabet rule and caps), searched for two strings with one image. The empty
    /// string is length 0 of the same domain and is seen first.
    static func witness(_ steps: [ReplacementChainClassifier.Step]) -> Witness? {
        var alphabet = Set(steps.flatMap { Array($0.pattern) + Array($0.replacement) })
        alphabet.insert("x")
        let letters = Array(alphabet).sorted().prefix(ReplacementChainClassifier.alphabetCap)
        var seen: [String: String] = [ReplacementChainClassifier.apply(steps, to: ""): ""]
        var frontier: [String] = [""]
        for _ in 0..<ReplacementChainClassifier.searchLength {
            var next: [String] = []
            for prefix in frontier {
                for letter in letters {
                    let candidate = prefix + String(letter)
                    let image = ReplacementChainClassifier.apply(steps, to: candidate)
                    if let earlier = seen[image] { return Witness(first: earlier, second: candidate, image: image) }
                    seen[image] = candidate
                    next.append(candidate)
                }
            }
            frontier = next
        }
        return nil
    }

    /// §1.3: for each step `(p, r)`, `Ab{p}Cd` against `Ab{r}Cd`, kept when the two differ and collide.
    static func identifierWitnesses(_ steps: [ReplacementChainClassifier.Step]) -> [Witness] {
        var found: [Witness] = []
        for step in steps {
            let first = "Ab" + step.pattern + "Cd"
            let second = "Ab" + step.replacement + "Cd"
            let image = ReplacementChainClassifier.apply(steps, to: first)
            if first != second, image == ReplacementChainClassifier.apply(steps, to: second),
               !found.contains(where: { $0.first == first && $0.second == second }) {
                found.append(Witness(first: first, second: second, image: image))
            }
        }
        return found
    }

    /// §4's Foundation check: the chain as Foundation runs it.
    static func foundation(_ steps: [ReplacementChainClassifier.Step], _ text: String) -> String {
        steps.reduce(text) { $0.replacingOccurrences(of: $1.pattern, with: $1.replacement) }
    }

    static func agreesWithFoundation(_ steps: [ReplacementChainClassifier.Step], _ witness: Witness) -> Bool {
        foundation(steps, witness.first) == foundation(steps, witness.second)
            && foundation(steps, witness.first) == witness.image
    }
}

/// §1.1 and §2.3: every function or getter with the candidate signature in one repository, chain or not, plus
/// every declared function name by type, so a call that resolves to a non-candidate method is not misread.
struct Candidate: Codable {
    let name: String
    let typeName: String?
    let isStringGetter: Bool
    let file: String
    let line: Int
    let steps: [ReplacementChainClassifier.Step]?
    let witness: Witness?
    let identifierWitnesses: [Witness]

    var isChain: Bool { steps != nil }
}

struct CandidateIndex {
    var byName: [String: [Candidate]] = [:]
    /// Every `func` name by enclosing type (nil for file scope), whatever its signature.
    var declared: [String: Set<String>] = [:]

    mutating func add(_ candidate: Candidate) { byName[candidate.name, default: []].append(candidate) }

    mutating func declare(_ name: String, in type: String?) { declared[type ?? "", default: []].insert(name) }

    enum Resolution {
        case candidate(Candidate)
        case ambiguous([Candidate])
        case none(String)
    }

    /// §2.3. `qualifier` is `T` for `T.F(n)`; `member` is true for `n.F`.
    func resolve(_ name: String, enclosingType: String?, qualifier: String?, member: Bool) -> Resolution {
        var pool = byName[name] ?? []
        if member { pool = pool.filter(\.isStringGetter) } else { pool = pool.filter { !$0.isStringGetter } }
        let preferredType = qualifier ?? enclosingType
        if !member, let preferredType {
            let local = pool.filter { $0.typeName == preferredType }
            if local.count == 1 { return .candidate(local[0]) }
            if local.count > 1 { return .ambiguous(local) }
            if declared[preferredType]?.contains(name) == true {
                return .none("resolves to a non-candidate member of \(preferredType)")
            }
        }
        if pool.count == 1 { return .candidate(pool[0]) }
        if pool.count > 1 { return .ambiguous(pool) }
        return .none("no declaration in the repository")
    }
}

enum CandidateReader {
    static func isString(_ type: TypeSyntax?) -> Bool { type?.trimmedDescription == "String" }

    /// The single expression of a body: one item that is an expression, or a `return` of one.
    static func singleExpression(_ items: CodeBlockItemListSyntax) -> ExprSyntax? {
        guard items.count == 1, let item = items.first?.item else { return nil }
        if let expr = item.as(ExprSyntax.self) { return expr }
        if let stmt = item.as(ExpressionStmtSyntax.self) { return stmt.expression }
        if let ret = item.as(ReturnStmtSyntax.self) { return ret.expression }
        return nil
    }

    static func candidate(name: String, typeName: String?, getter: Bool, file: String, line: Int,
                          body: ExprSyntax?, root: String?) -> Candidate {
        let steps = body.flatMap { ReplacementChainClassifier.steps(of: $0, root: root) }
        return Candidate(name: name, typeName: typeName, isStringGetter: getter, file: file, line: line, steps: steps,
                         witness: steps.flatMap(Collision.witness),
                         identifierWitnesses: steps.map(Collision.identifierWitnesses) ?? [])
    }

    /// Adds one file's candidates and declared names to `index`.
    static func read(_ tree: SourceFileSyntax, file: String, converter: SourceLocationConverter,
                     into index: inout CandidateIndex) {
        final class Visitor: SyntaxVisitor {
            var functions: [FunctionDeclSyntax] = []
            var variables: [VariableDeclSyntax] = []
            override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind { functions.append(node); return .visitChildren }
            override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind { variables.append(node); return .visitChildren }
        }
        let visitor = Visitor(viewMode: .sourceAccurate)
        visitor.walk(tree)
        for function in visitor.functions {
            let type = TypeContext.enclosingType(Syntax(function))
            index.declare(function.name.text, in: type)
            let parameters = Array(function.signature.parameterClause.parameters)
            guard parameters.count == 1, isString(parameters[0].type), parameters[0].ellipsis == nil,
                  isString(function.signature.returnClause?.type), let body = function.body else { continue }
            let root = (parameters[0].secondName ?? parameters[0].firstName).text
            let line = converter.location(for: function.funcKeyword.positionAfterSkippingLeadingTrivia).line
            index.add(candidate(name: function.name.text, typeName: type, getter: false, file: file, line: line,
                                body: singleExpression(body.statements), root: root))
        }
        for variable in visitor.variables {
            guard TypeContext.innermostExtension(Syntax(variable)) == "String", variable.bindings.count == 1,
                  let binding = variable.bindings.first,
                  let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
                  isString(binding.typeAnnotation?.type), let block = binding.accessorBlock else { continue }
            var items: CodeBlockItemListSyntax?
            switch block.accessors {
            case .getter(let list): items = list
            case .accessors(let accessors):
                if accessors.count == 1, let get = accessors.first, get.accessorSpecifier.tokenKind == .keyword(.get) {
                    items = get.body?.statements
                }
            }
            guard let items else { continue }
            let line = converter.location(for: variable.bindingSpecifier.positionAfterSkippingLeadingTrivia).line
            index.add(candidate(name: name, typeName: "String", getter: true, file: file, line: line,
                                body: singleExpression(items), root: nil))
        }
    }
}

/// The type a declaration sits in: the innermost struct, class, enum, actor or protocol name, or an extension's
/// base name.
enum TypeContext {
    static func enclosingType(_ node: Syntax) -> String? {
        var current = node.parent
        while let node = current {
            if let decl = node.as(StructDeclSyntax.self) { return decl.name.text }
            if let decl = node.as(ClassDeclSyntax.self) { return decl.name.text }
            if let decl = node.as(EnumDeclSyntax.self) { return decl.name.text }
            if let decl = node.as(ActorDeclSyntax.self) { return decl.name.text }
            if let decl = node.as(ProtocolDeclSyntax.self) { return decl.name.text }
            if let decl = node.as(ExtensionDeclSyntax.self) { return base(decl) }
            current = node.parent
        }
        return nil
    }

    static func innermostExtension(_ node: Syntax) -> String? {
        var current = node.parent
        while let node = current {
            if let decl = node.as(ExtensionDeclSyntax.self) { return base(decl) }
            if node.is(StructDeclSyntax.self) || node.is(ClassDeclSyntax.self) || node.is(EnumDeclSyntax.self)
                || node.is(ActorDeclSyntax.self) || node.is(ProtocolDeclSyntax.self) { return nil }
            current = node.parent
        }
        return nil
    }

    static func base(_ decl: ExtensionDeclSyntax) -> String? {
        let text = decl.extendedType.trimmedDescription
        return text.split(separator: "<").first.map(String.init)?.split(separator: ".").last.map(String.init)
    }
}
