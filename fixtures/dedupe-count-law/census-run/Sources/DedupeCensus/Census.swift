import Foundation
import SwiftInferCore
import SwiftInferTemplates
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

/// One function the census records: a name-family member (§2.1), or, unscored, a function outside it whose
/// body and shape pass (§9's observation).
struct Row: Codable {
    let key: String
    let repository: String
    let file: String
    let line: Int
    let name: String
    let enclosingKind: String
    let typeName: String?
    let inNameFamily: Bool
    let nameRefusal: String?
    let shapeRefusal: String?
    let bodyRefusal: String?
    let form: String?
    let element: String?
    let route: String?
    let keepFirst: Bool?
    let admitted: Bool
    let recognisedToday: Bool
    /// `IdempotenceTemplate.suggest` fires on the shipped scan's summary (restricted summaries included).
    let idempotenceToday: Bool
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

    /// The gates' verdicts for one function, without the scan join. Used by the run and by the controls.
    struct Verdict {
        var nameRefusal: String?
        var shapeRefusal: String?
        var bodyRefusal: String?
        var shape: ShapeGate.Reading?
        var body: BodyGate.Reading?
        var enclosing: Enclosing
        var candidateRefusal: String?

        var admitted: Bool { nameRefusal == nil && shapeRefusal == nil && bodyRefusal == nil }
        var candidate: Bool { admitted && candidateRefusal == nil }
    }

    static func judge(_ function: FunctionDeclSyntax) -> Verdict {
        let enclosing = Enclosing.of(function)
        var verdict = Verdict(enclosing: enclosing)
        verdict.nameRefusal = NameGate.refusal(function.name.text)
        switch ShapeGate.read(function, extendedType: enclosing.kind == "extension" ? enclosing.extendedType : nil) {
        case .success(let shape): verdict.shape = shape
        case .failure(let refusal): verdict.shapeRefusal = refusal.reason
        }
        if let body = function.body {
            switch BodyGate.read(body, input: verdict.shape?.input ?? "") {
            case .success(let reading): verdict.body = reading
            case .failure(let refusal): verdict.bodyRefusal = refusal.reason
            }
        }
        // §2.5.
        if enclosing.restricted {
            verdict.candidateRefusal = "private"
        } else if enclosing.kind == "actor" {
            verdict.candidateRefusal = "actor member"
        } else if enclosing.kind == "nested" {
            verdict.candidateRefusal = "nested function"
        } else if verdict.shape?.form == .receiver {
            verdict.candidateRefusal = "receiver form (generic element)"
        } else if let element = verdict.shape?.element,
                  let base = element.split(whereSeparator: { "<.?[ ".contains($0) }).first.map(String.init),
                  enclosing.genericNames.contains(base) {
            verdict.candidateRefusal = "generic element"
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
        for function in collector.functions {
            let name = function.name.text
            let inFamily = NameFamily.contains(name)
            let verdict = judge(function)
            // Outside the family, record only what passes shape and body (the unscored observation).
            guard inFamily || (verdict.shapeRefusal == nil && verdict.bodyRefusal == nil) else { continue }
            let line = converter.location(for: function.funcKeyword.positionAfterSkippingLeadingTrivia).line
            let summary = summaries[line] ?? restricted[line]?.summary
            record.rows.append(Row(
                key: "\(repository):\(relative):\(line) \(name)",
                repository: repository, file: relative, line: line, name: name,
                enclosingKind: verdict.enclosing.kind, typeName: verdict.enclosing.typeName,
                inNameFamily: inFamily,
                nameRefusal: verdict.nameRefusal, shapeRefusal: verdict.shapeRefusal, bodyRefusal: verdict.bodyRefusal,
                form: verdict.shape?.form.rawValue, element: verdict.shape?.element,
                route: verdict.body?.route.rawValue, keepFirst: verdict.body?.keepFirst,
                admitted: verdict.admitted,
                recognisedToday: NameGate.recognisedToday.contains(name),
                idempotenceToday: summary.map { IdempotenceTemplate.suggest(for: $0) != nil } ?? false,
                inScan: summaries[line] != nil,
                restriction: restricted[line]?.restriction.rawValue,
                candidate: verdict.candidate,
                candidateRefusal: verdict.admitted ? verdict.candidateRefusal : nil
            ))
        }
        return collector.functions.count
    }
}
