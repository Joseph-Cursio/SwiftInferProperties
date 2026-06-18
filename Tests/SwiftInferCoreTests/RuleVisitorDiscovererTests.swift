import Foundation
import SwiftInferCore
import Testing

/// PROTOTYPE — the SwiftSyntax lint-rule visitor carrier recognizer (slice 1,
/// recognition only). Detects `SyntaxVisitor` subclasses by their structural
/// signal — a `visit(_:) -> SyntaxVisitorContinueKind` override — and captures
/// the node types they visit + the rule identifiers they emit. Fixtures are
/// modelled on the real `swiftprojectlint` `BasePatternVisitor` subclasses.
@Suite("RuleVisitorDiscoverer — SwiftSyntax visitor carrier recognizer (prototype)")
struct RuleVisitorDiscovererTests {

    /// A single-node rule visitor modelled verbatim on the real
    /// `ForceUnwrapVisitor`: one `visit(_:)` override + one `ruleName:` emit.
    private static let forceUnwrapSource = """
    import SwiftProjectLintModels
    import SwiftProjectLintVisitors
    import SwiftSyntax

    final class ForceUnwrapVisitor: BasePatternVisitor {
        required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
            super.init(pattern: pattern, viewMode: viewMode)
        }

        override func visit(_ node: ForceUnwrapExprSyntax) -> SyntaxVisitorContinueKind {
            addIssue(
                severity: .info,
                message: "Force unwrap (!) will crash on nil",
                filePath: getFilePath(for: Syntax(node)),
                lineNumber: getLineNumber(for: Syntax(node)),
                suggestion: "Use if-let / guard-let / ??.",
                ruleName: .forceUnwrap
            )
            return .visitChildren
        }
    }
    """

    @Test("recognizes a BasePatternVisitor subclass by its visit(_:) override")
    func recognizesForceUnwrapVisitor() throws {
        let candidates = RuleVisitorDiscoverer.discover(
            source: Self.forceUnwrapSource, file: "/test/ForceUnwrapVisitor.swift"
        )
        #expect(candidates.count == 1)
        let visitor = try #require(candidates.first)
        #expect(visitor.typeName == "ForceUnwrapVisitor")
        #expect(visitor.location == "/test/ForceUnwrapVisitor.swift:5")
        #expect(visitor.inheritedTypes == ["BasePatternVisitor"])
        #expect(visitor.visitedNodeTypes == ["ForceUnwrapExprSyntax"])
        #expect(visitor.emittedRuleNames == ["forceUnwrap"])
    }

    @Test("captures every visited node type + every emitted rule, sorted & deduped")
    func multiNodeVisitor() throws {
        let source = """
        import SwiftSyntax

        final class MultiVisitor: BasePatternVisitor {
            override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
                addIssue(message: "a", ruleName: .printStatement)
                return .visitChildren
            }
            override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
                addIssue(message: "b", ruleName: .forceCast)
                addIssue(message: "c", ruleName: .printStatement)
                return .visitChildren
            }
        }
        """
        let candidates = RuleVisitorDiscoverer.discover(source: source, file: "/test/Multi.swift")
        let visitor = try #require(candidates.first)
        #expect(visitor.visitedNodeTypes == ["ClassDeclSyntax", "FunctionCallExprSyntax"])
        #expect(visitor.emittedRuleNames == ["forceCast", "printStatement"])
    }

    @Test("recognizes a direct SyntaxVisitor subclass (no project base name)")
    func directSyntaxVisitorSubclass() throws {
        let source = """
        import SwiftSyntax

        final class RawVisitor: SyntaxVisitor {
            override func visit(_ node: TryExprSyntax) -> SyntaxVisitorContinueKind {
                return .visitChildren
            }
        }
        """
        let candidates = RuleVisitorDiscoverer.discover(source: source, file: "/test/Raw.swift")
        let visitor = try #require(candidates.first)
        #expect(visitor.typeName == "RawVisitor")
        #expect(visitor.inheritedTypes == ["SyntaxVisitor"])
        #expect(visitor.visitedNodeTypes == ["TryExprSyntax"])
        // No ruleName: emission in this fixture.
        #expect(visitor.emittedRuleNames.isEmpty)
    }

    @Test("merges visit(_:) overrides declared in an extension across the class")
    func extensionMergedOverrides() throws {
        let source = """
        import SwiftSyntax

        final class SplitVisitor: BasePatternVisitor {
            override func visit(_ node: ForceUnwrapExprSyntax) -> SyntaxVisitorContinueKind {
                return .visitChildren
            }
        }

        extension SplitVisitor {
            override func visit(_ node: ForceCastExprSyntax) -> SyntaxVisitorContinueKind {
                return .visitChildren
            }
        }
        """
        let candidates = RuleVisitorDiscoverer.discover(source: source, file: "/test/Split.swift")
        #expect(candidates.count == 1)
        let visitor = try #require(candidates.first)
        #expect(visitor.visitedNodeTypes == ["ForceCastExprSyntax", "ForceUnwrapExprSyntax"])
    }

    @Test("precision: a class with no visit(_:) override is not a carrier")
    func noVisitOverrideIsNotACarrier() {
        let source = """
        final class PlainService {
            func visit(_ thing: String) -> Bool { thing.isEmpty }
            func doWork() {}
        }

        struct Helper {
            func run() {}
        }
        """
        let candidates = RuleVisitorDiscoverer.discover(source: source, file: "/test/Plain.swift")
        // `visit(_:) -> Bool` is NOT the SwiftVisitor signal; nothing matches.
        #expect(candidates.isEmpty)
    }

    @Test("precision: an abstract base with no node-specific visit override is excluded")
    func abstractBaseExcluded() {
        let source = """
        import SwiftSyntax

        open class BasePatternVisitor: SyntaxVisitor {
            public var detectedIssues: [LintIssue] = []
            func addIssue(message: String) {}
        }
        """
        let candidates = RuleVisitorDiscoverer.discover(source: source, file: "/test/Base.swift")
        #expect(candidates.isEmpty)
    }
}
