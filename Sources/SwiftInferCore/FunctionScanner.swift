import Foundation
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
        let tree = Parser.parse(source: source)
        let converter = SourceLocationConverter(fileName: file, tree: tree)
        let visitor = FunctionScannerVisitor(file: file, converter: converter)
        visitor.walk(tree)
        return visitor.summaries
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
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        var swiftFiles: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            swiftFiles.append(url)
        }
        swiftFiles.sort { $0.path < $1.path }
        var summaries: [FunctionSummary] = []
        for fileURL in swiftFiles {
            summaries.append(contentsOf: try scan(file: fileURL))
        }
        return summaries
    }
}

// MARK: - Visitor

private final class FunctionScannerVisitor: SyntaxVisitor {

    var summaries: [FunctionSummary] = []
    private let file: String
    private let converter: SourceLocationConverter
    private var typeStack: [String] = []

    init(file: String, converter: SourceLocationConverter) {
        self.file = file
        self.converter = converter
        super.init(viewMode: .sourceAccurate)
    }

    // Function decl — capture and skip its children (we body-scan separately).
    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        summaries.append(makeSummary(from: node))
        return .skipChildren
    }

    // Type-bearing decls — push/pop the innermost type name.
    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        typeStack.append(node.name.text)
        return .visitChildren
    }
    override func visitPost(_ node: ClassDeclSyntax) {
        typeStack.removeLast()
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        typeStack.append(node.name.text)
        return .visitChildren
    }
    override func visitPost(_ node: StructDeclSyntax) {
        typeStack.removeLast()
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        typeStack.append(node.name.text)
        return .visitChildren
    }
    override func visitPost(_ node: EnumDeclSyntax) {
        typeStack.removeLast()
    }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        typeStack.append(node.name.text)
        return .visitChildren
    }
    override func visitPost(_ node: ActorDeclSyntax) {
        typeStack.removeLast()
    }

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        typeStack.append(node.extendedType.trimmedDescription)
        return .visitChildren
    }
    override func visitPost(_ node: ExtensionDeclSyntax) {
        typeStack.removeLast()
    }

    // Protocol decls — skip body entirely (requirements have no body).
    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        .skipChildren
    }

    // MARK: Summary construction

    private func makeSummary(from node: FunctionDeclSyntax) -> FunctionSummary {
        let name = node.name.text
        let parameters = node.signature.parameterClause.parameters.map(makeParameter(from:))
        let returnTypeText = node.signature.returnClause?.type.trimmedDescription
        let effects = node.signature.effectSpecifiers
        let isThrows = effects?.throwsClause != nil
        let isAsync = effects?.asyncSpecifier != nil
        let modifiers = node.modifiers.map { $0.name.text }
        let isMutating = modifiers.contains("mutating")
        let isStatic = modifiers.contains("static") || modifiers.contains("class")

        let position = node.funcKeyword.positionAfterSkippingLeadingTrivia
        let sourceLocation = converter.location(for: position)
        let location = SourceLocation(
            file: file,
            line: sourceLocation.line,
            column: sourceLocation.column
        )

        let containingTypeName = typeStack.last
        let bodySignals = scanBody(of: node)

        return FunctionSummary(
            name: name,
            parameters: parameters,
            returnTypeText: returnTypeText,
            isThrows: isThrows,
            isAsync: isAsync,
            isMutating: isMutating,
            isStatic: isStatic,
            location: location,
            containingTypeName: containingTypeName,
            bodySignals: bodySignals
        )
    }

    private func makeParameter(from syntax: FunctionParameterSyntax) -> Parameter {
        // Swift parameter shapes:
        //   `func f(a: Int)`       → firstName=a, secondName=nil → label=a, name=a
        //   `func f(_ a: Int)`     → firstName=_, secondName=a   → label=nil, name=a
        //   `func f(label a: Int)` → firstName=label, secondName=a → label=label, name=a
        let firstName = syntax.firstName.text
        let secondName = syntax.secondName?.text

        let label: String?
        let internalName: String
        if let secondName {
            label = (firstName == "_") ? nil : firstName
            internalName = secondName
        } else {
            label = firstName
            internalName = firstName
        }

        let rawType = syntax.type.trimmedDescription
        let isInout = rawType.hasPrefix("inout ")
        let typeText = isInout ? String(rawType.dropFirst("inout ".count)) : rawType

        return Parameter(
            label: label,
            internalName: internalName,
            typeText: typeText,
            isInout: isInout
        )
    }

    private func scanBody(of node: FunctionDeclSyntax) -> BodySignals {
        guard let body = node.body else {
            return .empty
        }
        let scanner = BodySignalVisitor(funcName: node.name.text)
        scanner.walk(body)
        return BodySignals(
            hasNonDeterministicCall: !scanner.detectedAPIs.isEmpty,
            hasSelfComposition: scanner.foundSelfComposition,
            nonDeterministicAPIsDetected: scanner.detectedAPIs.sorted(),
            reducerOpsReferenced: scanner.reducerOps.sorted()
        )
    }
}

// MARK: - Body signal visitor

private final class BodySignalVisitor: SyntaxVisitor {

    let funcName: String
    var detectedAPIs: Set<String> = []
    var foundSelfComposition = false
    var reducerOps: Set<String> = []

    init(funcName: String) {
        self.funcName = funcName
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        let calleeText = node.calledExpression.trimmedDescription
        if NonDeterministicAPIs.matches(calleeText) {
            detectedAPIs.insert(calleeText)
        }
        if calleeText == funcName {
            for arg in node.arguments
            where arg.expression.as(FunctionCallExprSyntax.self)?
                .calledExpression
                .trimmedDescription == funcName {
                foundSelfComposition = true
            }
        }
        recordReducerOp(in: node)
        return .visitChildren
    }

    /// Detect `<expr>.reduce(<seed>, <op>)` and `<expr>.reduce(into: <seed>, <op>)`
    /// where `<op>` is a function reference (bare identifier or member-access
    /// `Type.method`). Trailing closures and explicit closure literals are
    /// intentionally skipped — the M2.4 detector only resolves named-function
    /// references, mirroring the conservative-precision posture of §3.5.
    private func recordReducerOp(in node: FunctionCallExprSyntax) {
        guard let member = node.calledExpression.as(MemberAccessExprSyntax.self),
              member.declName.baseName.text == "reduce",
              node.arguments.count == 2 else {
            return
        }
        let opArg = node.arguments[node.arguments.index(node.arguments.startIndex, offsetBy: 1)]
        if let ref = opArg.expression.as(DeclReferenceExprSyntax.self) {
            reducerOps.insert(ref.baseName.text)
            return
        }
        if let memberRef = opArg.expression.as(MemberAccessExprSyntax.self) {
            reducerOps.insert(memberRef.declName.baseName.text)
        }
    }
}

// MARK: - Non-deterministic API list

private enum NonDeterministicAPIs {

    /// Curated callee-text matches. Kept small and explicit for M1.2;
    /// expansion happens as templates encounter false negatives.
    private static let exactMatches: Set<String> = [
        "Date",
        "Date.now",
        "UUID",
        "URLSession.shared",
        "arc4random",
        "arc4random_uniform",
        "drand48",
        "rand",
        "random"
    ]

    /// Callee texts ending in `.random` or `.random(in:)` cover the
    /// `Int.random`, `Double.random(in:)`, `Bool.random()` family without
    /// enumerating every numeric type.
    private static let suffixMatches: [String] = [
        ".random",
        ".random(in:)"
    ]

    static func matches(_ calleeText: String) -> Bool {
        if exactMatches.contains(calleeText) {
            return true
        }
        return suffixMatches.contains { calleeText.hasSuffix($0) }
    }
}
