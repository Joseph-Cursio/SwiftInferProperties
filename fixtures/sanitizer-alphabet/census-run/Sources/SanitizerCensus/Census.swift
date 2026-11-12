import Foundation
import SwiftInferCore
import SwiftParser
import SwiftSyntax

/// One subject from `scripts/dedupe_count_law_census.py controls`.
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

/// One function the census records: every row `R` admits, and every refused shape-passing function in the recall
/// pool (§2.2).
struct Row: Codable {
    let key: String
    let repository: String
    let file: String
    let line: Int
    let name: String
    let enclosingKind: String
    let typeName: String?
    let isStatic: Bool
    let inPool: Bool
    let refusal: String?
    let reading: Reading?
    let admitted: Bool
    let law1: Bool
    let law2: Bool
    let inScan: Bool
    let restriction: String?
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

    static let poolTokens = ["CharacterSet", "isLetter", "isNumber", "isASCII", "alphanumerics"]

    struct Verdict {
        var reading: Reading?
        var refusal: String?
        var enclosing: Enclosing
        var isStatic: Bool
        var candidateRefusal: String?
        var admitted: Bool { reading != nil }
        var candidate: Bool { admitted && candidateRefusal == nil }
    }

    static func judge(_ function: FunctionDeclSyntax) -> Verdict {
        let enclosing = Enclosing.of(function)
        let isStatic = function.modifiers.contains { [.keyword(.static), .keyword(.class)].contains($0.name.tokenKind) }
        var verdict = Verdict(enclosing: enclosing, isStatic: isStatic)
        switch Reader.read(function) {
        case .success(let reading): verdict.reading = reading
        case .failure(let refusal): verdict.refusal = refusal.reason
        }
        // §2.4.
        if enclosing.restricted {
            verdict.candidateRefusal = "private"
        } else if enclosing.kind == "actor" {
            verdict.candidateRefusal = "actor member"
        } else if enclosing.kind == "nested" {
            verdict.candidateRefusal = "nested function"
        } else if !isStatic, enclosing.kind != "file" {
            verdict.candidateRefusal = "instance method"
        }
        return verdict
    }

    /// Reads one file into `record`.
    static func read(source: String, path: String, repository: String, repositoryRoot: String,
                     into record: inout CensusRecord) -> Int {
        let tree = Parser.parse(source: source)
        let converter = SourceLocationConverter(fileName: path, tree: tree)
        let scanned = FunctionScanner.scanCorpus(source: source, file: path)
        let summaries = Dictionary(scanned.summaries.map { ($0.location.line, $0) }) { first, _ in first }
        let restricted = Dictionary(scanned.restricted.map { ($0.summary.location.line, $0) }) { first, _ in first }
        let collector = FunctionCollector(viewMode: .sourceAccurate)
        collector.walk(tree)
        let relative = path.hasPrefix(repositoryRoot + "/") ? String(path.dropFirst(repositoryRoot.count + 1)) : path
        for function in collector.functions where Reader.shapeRefusal(function) == nil {
            let name = function.name.text
            let verdict = judge(function)
            let text = function.body?.description ?? ""
            let inPool = poolTokens.contains { text.contains($0) }
            guard verdict.admitted || inPool else { continue }
            let line = converter.location(for: function.funcKeyword.positionAfterSkippingLeadingTrivia).line
            record.rows.append(Row(
                key: "\(repository):\(relative):\(line) \(name)",
                repository: repository, file: relative, line: line, name: name,
                enclosingKind: verdict.enclosing.kind, typeName: verdict.enclosing.typeName, isStatic: verdict.isStatic,
                inPool: inPool, refusal: verdict.refusal, reading: verdict.reading,
                admitted: verdict.admitted, law1: verdict.reading?.law1 ?? false, law2: verdict.admitted,
                inScan: summaries[line] != nil, restriction: restricted[line]?.restriction.rawValue,
                candidate: verdict.candidate, candidateRefusal: verdict.admitted ? verdict.candidateRefusal : nil
            ))
        }
        return collector.functions.count
    }
}
