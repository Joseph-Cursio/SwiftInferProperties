import Foundation
import SwiftParser
import SwiftSyntax

// The walker, `Enclosing` and file selection are copied from #672's harness
// (`fixtures/sanitizer-alphabet/census-run/`); the reader and the two-pass, per-repository helper index are new.

/// One subject from `scripts/emitter_presence_census.py controls`.
struct Subject: Codable {
    let group: String
    let name: String
    let repository: String
    let repositoryRoot: String
    let roots: [String]
    let sourcesComponentOnly: Bool
    let revision: String?
    let dirty: Bool
}

/// One function the census records: every row `R` admits, every W1/W2/W3 row, and every refused shape-passing
/// function in the recall pool (§2.9).
struct Row: Codable {
    let key: String
    let repository: String
    let file: String
    let line: Int
    let name: String
    let signature: String
    let enclosingKind: String
    let typeName: String?
    let isStatic: Bool
    let inPool: Bool
    let reading: Reading
    let admitted: Bool
    let candidate: Bool
    let candidateRefusal: String?
}

struct SubjectCount: Codable {
    let name: String
    let repository: String
    let revision: String?
    let dirty: Bool
    var files = 0
    var functions = 0
}

struct CensusRecord: Codable {
    var functions = 0
    var files = 0
    var subjects: [SubjectCount] = []
    var rows: [Row] = []
}

/// Every `func` with a body, nested ones included.
final class FunctionCollector: SyntaxVisitor {
    var functions: [FunctionDeclSyntax] = []

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        if node.body != nil { functions.append(node) }
        return .visitChildren
    }
}

/// What encloses a function: the innermost declaration's kind, its type name, the extended type's base name,
/// the generic parameters in scope, and whether anything up the chain is `private` / `fileprivate`.
struct Enclosing {
    var kind = "file"
    var typeName: String?
    var extendedType: String?
    var genericNames: Set<String> = []
    var restricted = false

    static func isRestricted(_ modifiers: DeclModifierListSyntax) -> Bool {
        modifiers.contains { [.keyword(.private), .keyword(.fileprivate)].contains($0.name.tokenKind) }
    }

    static func of(_ function: FunctionDeclSyntax) -> Enclosing {
        var result = Enclosing()
        result.restricted = isRestricted(function.modifiers)
        for parameter in function.genericParameterClause?.parameters ?? [] { result.genericNames.insert(parameter.name.text) }
        var node = function.parent
        var innermost = true
        while let current = node {
            var kind: String?
            var name: String?
            var modifiers: DeclModifierListSyntax?
            var generics: GenericParameterClauseSyntax?
            if let decl = current.as(StructDeclSyntax.self) {
                (kind, name, modifiers, generics) = ("struct", decl.name.text, decl.modifiers, decl.genericParameterClause)
            } else if let decl = current.as(ClassDeclSyntax.self) {
                (kind, name, modifiers, generics) = ("class", decl.name.text, decl.modifiers, decl.genericParameterClause)
            } else if let decl = current.as(EnumDeclSyntax.self) {
                (kind, name, modifiers, generics) = ("enum", decl.name.text, decl.modifiers, decl.genericParameterClause)
            } else if let decl = current.as(ActorDeclSyntax.self) {
                (kind, name, modifiers, generics) = ("actor", decl.name.text, decl.modifiers, decl.genericParameterClause)
            } else if let decl = current.as(ProtocolDeclSyntax.self) {
                (kind, name, modifiers) = ("protocol", decl.name.text, decl.modifiers)
            } else if let decl = current.as(ExtensionDeclSyntax.self) {
                let base = decl.extendedType.trimmedDescription.split(separator: "<").first.map(String.init)
                (kind, name, modifiers) = ("extension", base, decl.modifiers)
                if innermost { result.extendedType = base }
            } else if current.is(FunctionDeclSyntax.self) || current.is(ClosureExprSyntax.self)
                        || current.is(AccessorDeclSyntax.self) || current.is(InitializerDeclSyntax.self) {
                kind = "nested"
            }
            if let kind {
                if innermost {
                    result.kind = kind
                    result.typeName = name
                    innermost = false
                }
                if let modifiers, isRestricted(modifiers) { result.restricted = true }
                for parameter in generics?.parameters ?? [] { result.genericNames.insert(parameter.name.text) }
            }
            node = current.parent
        }
        return result
    }
}

enum Census {
    static let skippedNames: Set<String> = [".build", "build", "DerivedData", "checkouts", "Pods", "Carthage", ".swiftinfer"]

    static func isSkipped(_ component: String) -> Bool {
        component.hasPrefix(".") || skippedNames.contains(component) || component == "Tests" || component == "tests"
            || component.hasSuffix("Tests") || component.lowercased() == "fixtures"
    }

    /// `.swift` files under `root`, skipping §3's directories below the root (never the root's own path).
    static func swiftFiles(under root: URL, sourcesComponentOnly: Bool) -> [URL] {
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey]) else {
            return []
        }
        var found: [URL] = []
        for case let url as URL in walker {
            if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                if isSkipped(url.lastPathComponent) { walker.skipDescendants() }
            } else if url.pathExtension == "swift" {
                let relative = url.path.dropFirst(root.path.count).split(separator: "/")
                if !sourcesComponentOnly || relative.dropLast().contains("Sources") { found.append(url) }
            }
        }
        return found.sorted { $0.path < $1.path }
    }

    /// One parsed file of a repository.
    struct Parsed {
        let path: String
        let relative: String
        let tree: SourceFileSyntax
        let converter: SourceLocationConverter
        let functions: [FunctionDeclSyntax]
    }

    static func parse(source: String, path: String, repositoryRoot: String) -> Parsed {
        let tree = Parser.parse(source: source)
        let converter = SourceLocationConverter(fileName: path, tree: tree)
        let collector = FunctionCollector(viewMode: .sourceAccurate)
        collector.walk(tree)
        let relative = path.hasPrefix(repositoryRoot + "/") ? String(path.dropFirst(repositoryRoot.count + 1)) : path
        return Parsed(path: path, relative: relative, tree: tree, converter: converter, functions: collector.functions)
    }

    static func index(_ files: [Parsed]) -> FunctionIndex {
        var index = FunctionIndex()
        for file in files { for function in file.functions { index.add(function, file: file.relative) } }
        return index
    }

    /// §2.8's syntactic half.
    static func candidateRefusal(_ enclosing: Enclosing) -> String? {
        if enclosing.restricted { return "private" }
        if enclosing.kind == "actor" { return "actor member" }
        if enclosing.kind == "nested" { return "nested function" }
        return nil
    }

    /// §2.9: a `for` loop and an `append` or `+=` in the body.
    static func inPool(_ function: FunctionDeclSyntax) -> Bool {
        let text = function.body?.description ?? ""
        return text.contains("for ") && (text.contains(".append(") || text.contains("+="))
    }

    /// Reads every function of one parsed file into `record`, resolving helpers against `index`.
    static func read(_ file: Parsed, repository: String, index: FunctionIndex, into record: inout CensusRecord) {
        for function in file.functions where Reader.shapeRefusal(function) == nil {
            let reading = Reader.read(function, index: index, converter: file.converter)
            let pool = inPool(function)
            guard reading.admitted || !reading.widenings.isEmpty || pool else { continue }
            let enclosing = Enclosing.of(function)
            let isStatic = function.modifiers.contains { [.keyword(.static), .keyword(.class)].contains($0.name.tokenKind) }
            let line = file.converter.location(for: function.funcKeyword.positionAfterSkippingLeadingTrivia).line
            let refusal = candidateRefusal(enclosing)
            record.rows.append(Row(
                key: "\(repository):\(file.relative):\(line) \(function.name.text)",
                repository: repository, file: file.relative, line: line, name: function.name.text,
                signature: function.signature.trimmedDescription,
                enclosingKind: enclosing.kind, typeName: enclosing.typeName, isStatic: isStatic,
                inPool: pool, reading: reading, admitted: reading.admitted,
                candidate: reading.admitted && refusal == nil, candidateRefusal: reading.admitted ? refusal : nil
            ))
        }
    }
}
