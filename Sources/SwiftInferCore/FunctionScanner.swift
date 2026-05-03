import Foundation
import ProtoLawCore
import SwiftParser
import SwiftSyntax

/// Static-analysis pipeline that walks Swift source and emits one
/// `FunctionSummary` per function declaration. M1.2 surface — the M1.3+
/// scoring engine consumes the produced summaries without further parsing.
///
/// Coverage:
/// - Top-level functions and functions inside `class`, `struct`, `enum`,
///   `actor`, and `extension` decls. Containing-type stack tracks the
///   innermost enclosing type by source name; extensions contribute the
///   `extendedType` text (e.g. `"Array"`).
/// - Protocol *requirements* (function decls inside `protocol` bodies) are
///   intentionally skipped — they have no body to score against and the
///   templates fire on implementations.
/// - Nested function decls (functions declared inside another function's
///   body) are skipped — rare in idiomatic Swift, and including them would
///   conflate the body-signal scan with the outer function's signals.
public enum FunctionScanner {

    /// Scan a single in-memory source string. `file` is the label attached
    /// to every emitted `SourceLocation` — pass the path you want shown to
    /// the user (e.g. `Sources/MyTarget/MyFile.swift`).
    public static func scan(source: String, file: String) -> [FunctionSummary] {
        scanCorpus(source: source, file: file).summaries
    }

    /// Scan a single `.swift` file on disk. Reads the file as UTF-8.
    public static func scan(file: URL) throws -> [FunctionSummary] {
        let source = try String(contentsOf: file, encoding: .utf8)
        return scan(source: source, file: file.path)
    }

    /// Recursively scan every `.swift` file under `directory`. Files are
    /// visited in deterministic (sorted-path) order so output is stable
    /// across runs — supports the byte-identical-reproducibility guarantee
    /// (PRD v0.3 §16 #6).
    public static func scan(directory: URL) throws -> [FunctionSummary] {
        try scanCorpus(directory: directory).summaries
    }

    /// One-pass scan that emits `FunctionSummary`, `IdentityCandidate`,
    /// and `TypeDecl` records from a single AST walk. Started in M2.5 for
    /// the identity-element template; M3.2 extended the same walk to
    /// emit `TypeDecl` records for M3.3's `EquatableResolver`. Keeps
    /// the §13 perf budget intact by avoiding a second pass over the
    /// source tree.
    public static func scanCorpus(source: String, file: String) -> ScannedCorpus {
        let tree = Parser.parse(source: source)
        let converter = SourceLocationConverter(fileName: file, tree: tree)
        let visitor = FunctionScannerVisitor(file: file, converter: converter)
        visitor.walk(tree)
        return ScannedCorpus(
            summaries: visitor.summaries,
            identities: visitor.identities,
            typeDecls: visitor.typeDecls
        )
    }

    /// Scan a single `.swift` file on disk. Reads the file as UTF-8.
    public static func scanCorpus(file: URL) throws -> ScannedCorpus {
        let source = try String(contentsOf: file, encoding: .utf8)
        return scanCorpus(source: source, file: file.path)
    }

    /// Recursively scan every `.swift` file under `directory`. Files are
    /// visited in deterministic (sorted-path) order so the merged output
    /// is stable across runs.
    public static func scanCorpus(directory: URL) throws -> ScannedCorpus {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return .empty
        }
        var swiftFiles: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            swiftFiles.append(url)
        }
        swiftFiles.sort { $0.path < $1.path }
        var summaries: [FunctionSummary] = []
        var identities: [IdentityCandidate] = []
        var typeDecls: [TypeDecl] = []
        for fileURL in swiftFiles {
            let corpus = try scanCorpus(file: fileURL)
            summaries.append(contentsOf: corpus.summaries)
            identities.append(contentsOf: corpus.identities)
            typeDecls.append(contentsOf: corpus.typeDecls)
        }
        return ScannedCorpus(summaries: summaries, identities: identities, typeDecls: typeDecls)
    }
}

// MARK: - Visitor

/// Single-pass AST walker emitting function summaries, identity
/// candidates, and type-decl records. Helpers split across
/// `FunctionScannerVisitor+Summary.swift`,
/// `FunctionScannerVisitor+TypeDecls.swift`, and
/// `FunctionScannerVisitor+Identities.swift`.
final class FunctionScannerVisitor: SyntaxVisitor {

    var summaries: [FunctionSummary] = []
    var identities: [IdentityCandidate] = []
    var typeDecls: [TypeDecl] = []
    let file: String
    let converter: SourceLocationConverter
    var typeStack: [String] = []

    init(file: String, converter: SourceLocationConverter) {
        self.file = file
        self.converter = converter
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        summaries.append(makeSummary(from: node))
        return .skipChildren
    }

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        captureIdentityCandidates(from: node)
        return .visitChildren
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        typeDecls.append(makeTypeDecl(
            name: node.name.text,
            kind: .class,
            inheritanceClause: node.inheritanceClause,
            keywordToken: node.classKeyword,
            memberBlock: node.memberBlock
        ))
        typeStack.append(node.name.text)
        return .visitChildren
    }
    override func visitPost(_ node: ClassDeclSyntax) {
        typeStack.removeLast()
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        typeDecls.append(makeTypeDecl(
            name: node.name.text,
            kind: .struct,
            inheritanceClause: node.inheritanceClause,
            keywordToken: node.structKeyword,
            memberBlock: node.memberBlock
        ))
        typeStack.append(node.name.text)
        return .visitChildren
    }
    override func visitPost(_ node: StructDeclSyntax) {
        typeStack.removeLast()
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        typeDecls.append(makeTypeDecl(
            name: node.name.text,
            kind: .enum,
            inheritanceClause: node.inheritanceClause,
            keywordToken: node.enumKeyword,
            memberBlock: node.memberBlock
        ))
        typeStack.append(node.name.text)
        return .visitChildren
    }
    override func visitPost(_ node: EnumDeclSyntax) {
        typeStack.removeLast()
    }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        typeDecls.append(makeTypeDecl(
            name: node.name.text,
            kind: .actor,
            inheritanceClause: node.inheritanceClause,
            keywordToken: node.actorKeyword,
            memberBlock: node.memberBlock
        ))
        typeStack.append(node.name.text)
        return .visitChildren
    }
    override func visitPost(_ node: ActorDeclSyntax) {
        typeStack.removeLast()
    }

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        let extendedTypeText = node.extendedType.trimmedDescription
        typeDecls.append(makeTypeDecl(
            name: extendedTypeText,
            kind: .extension,
            inheritanceClause: node.inheritanceClause,
            keywordToken: node.extensionKeyword,
            memberBlock: node.memberBlock
        ))
        typeStack.append(extendedTypeText)
        return .visitChildren
    }
    override func visitPost(_ node: ExtensionDeclSyntax) {
        typeStack.removeLast()
    }

    /// Protocol decls — skip body entirely (requirements have no body).
    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        .skipChildren
    }
}
