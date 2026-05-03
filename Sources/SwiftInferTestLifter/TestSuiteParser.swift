import Foundation
import SwiftInferCore
import SwiftParser
import SwiftSyntax

/// Static-analysis pipeline that walks Swift test source and emits one
/// `TestMethodSummary` per recognized test method. M1.1 surface — the
/// M1.2 slicer consumes the produced summaries directly via
/// `summary.body`.
///
/// **Recognition rules (PRD §7.9 M1):**
/// - **XCTest:** any function inside a `class` whose direct inheritance
///   clause names `XCTestCase`, where the function's name starts with
///   `test`. `setUp` / `tearDown` / helper methods don't match because
///   they don't start with `test`.
/// - **Swift Testing:** any function carrying the `@Test` attribute,
///   regardless of where it's declared. Works at file scope, inside
///   `@Suite` classes / structs, and inside arbitrary nesting.
///
/// **Skipped:**
/// - Protocol requirements (no body to slice).
/// - Nested function decls (rare in test bodies; would conflate slices).
/// - `@Test`-annotated computed properties (Swift Testing allows them
///   in some shapes; M1 only handles function decls).
public enum TestSuiteParser {

    /// Scan a single in-memory source string. `file` is the label
    /// attached to every emitted `SourceLocation` — pass the path you
    /// want shown to the user (e.g. `Tests/MyTests/FooTests.swift`).
    public static func scan(source: String, file: String) -> [TestMethodSummary] {
        let tree = Parser.parse(source: source)
        let converter = SourceLocationConverter(fileName: file, tree: tree)
        let visitor = TestSuiteParserVisitor(file: file, converter: converter)
        visitor.walk(tree)
        return visitor.summaries
    }

    /// Scan a single `.swift` file on disk. Reads the file as UTF-8.
    public static func scan(file: URL) throws -> [TestMethodSummary] {
        let source = try String(contentsOf: file, encoding: .utf8)
        return scan(source: source, file: file.path)
    }

    /// Recursively scan every `.swift` file under `directory`. Files
    /// are visited in deterministic (sorted-path) order so output is
    /// stable across runs — supports the byte-identical-reproducibility
    /// guarantee (PRD v0.4 §16 #6).
    ///
    /// **No directory filtering at this layer.** Callers pass a
    /// pre-filtered tests root (e.g. `<project>/Tests/`); the M1.5
    /// CLI wiring applies the `Tests` / `*Tests` heuristic before
    /// invoking this method.
    public static func scanTests(directory: URL) throws -> [TestMethodSummary] {
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
        var summaries: [TestMethodSummary] = []
        for fileURL in swiftFiles {
            try summaries.append(contentsOf: scan(file: fileURL))
        }
        return summaries
    }
}

// MARK: - Visitor

/// Single-pass AST walker emitting `TestMethodSummary` records. Type
/// stack tracks the innermost enclosing class / struct / actor so XCTest
/// recognition can check the direct superclass and so Swift Testing
/// recognition can attach the containing type name.
final class TestSuiteParserVisitor: SyntaxVisitor {

    struct EnclosingType {
        let name: String
        let isXCTestCaseSubclass: Bool
    }

    var summaries: [TestMethodSummary] = []
    let file: String
    let converter: SourceLocationConverter
    var typeStack: [EnclosingType] = []

    init(file: String, converter: SourceLocationConverter) {
        self.file = file
        self.converter = converter
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        let inherits = inheritsFromXCTestCase(node.inheritanceClause)
        typeStack.append(EnclosingType(name: node.name.text, isXCTestCaseSubclass: inherits))
        return .visitChildren
    }
    override func visitPost(_ node: ClassDeclSyntax) {
        typeStack.removeLast()
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        // Swift Testing suites are commonly structs. Push as
        // non-XCTestCase context so an XCTest-style `test*` method
        // inside a struct doesn't accidentally fire.
        typeStack.append(EnclosingType(name: node.name.text, isXCTestCaseSubclass: false))
        return .visitChildren
    }
    override func visitPost(_ node: StructDeclSyntax) {
        typeStack.removeLast()
    }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        typeStack.append(EnclosingType(name: node.name.text, isXCTestCaseSubclass: false))
        return .visitChildren
    }
    override func visitPost(_ node: ActorDeclSyntax) {
        typeStack.removeLast()
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        typeStack.append(EnclosingType(name: node.name.text, isXCTestCaseSubclass: false))
        return .visitChildren
    }
    override func visitPost(_ node: EnumDeclSyntax) {
        typeStack.removeLast()
    }

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        let extendedTypeText = node.extendedType.trimmedDescription
        // Extensions don't introduce a new class identity for XCTest
        // recognition — `extension MyTests: XCTestCase` doesn't compile;
        // XCTest inheritance must be on the original `class` decl. The
        // extension can still hold `@Test` funcs though, so push the
        // extended type name.
        typeStack.append(EnclosingType(name: extendedTypeText, isXCTestCaseSubclass: false))
        return .visitChildren
    }
    override func visitPost(_ node: ExtensionDeclSyntax) {
        typeStack.removeLast()
    }

    /// Protocol requirements have no body — skip the entire decl.
    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        .skipChildren
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        considerFunction(node)
        // Don't recurse into the body — nested function decls inside a
        // test body are skipped per the M1.1 contract.
        return .skipChildren
    }

    private func considerFunction(_ node: FunctionDeclSyntax) {
        guard let body = node.body else {
            return
        }
        let methodName = node.name.text
        let enclosing = typeStack.last
        let position = node.funcKeyword.positionAfterSkippingLeadingTrivia
        let raw = converter.location(for: position)
        let location = SwiftInferCore.SourceLocation(
            file: file,
            line: raw.line,
            column: raw.column
        )

        if hasTestAttribute(node.attributes) {
            summaries.append(TestMethodSummary(
                harness: .swiftTesting,
                className: enclosing?.name,
                methodName: methodName,
                body: body,
                location: location
            ))
            return
        }

        if let enclosing,
           enclosing.isXCTestCaseSubclass,
           methodName.hasPrefix("test") {
            summaries.append(TestMethodSummary(
                harness: .xctest,
                className: enclosing.name,
                methodName: methodName,
                body: body,
                location: location
            ))
        }
    }

    private func inheritsFromXCTestCase(_ clause: InheritanceClauseSyntax?) -> Bool {
        guard let clause else {
            return false
        }
        return clause.inheritedTypes.contains { inherited in
            inherited.type.trimmedDescription == "XCTestCase"
        }
    }

    private func hasTestAttribute(_ attributes: AttributeListSyntax) -> Bool {
        for element in attributes {
            guard case .attribute(let attribute) = element else {
                continue
            }
            if attribute.attributeName.trimmedDescription == "Test" {
                return true
            }
        }
        return false
    }
}
