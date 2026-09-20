import Foundation
import SwiftParser
import SwiftSyntax

/// How a package's own tests construct a type the tool cannot derive — copied verbatim, rather
/// than derived.
///
/// ## Why copy rather than derive
///
/// Memberwise derivation is structs-only by design, so a law whose RECEIVER is a class has no
/// generator: 314 stubs across the corpus, 269 of them SwiftProjectLint visitors. Those visitors
/// take a `SyntaxPattern`, which holds a metatype (`visitor: PatternVisitorProtocol.Type`) — a
/// member no memberwise derivation can synthesise at all. The tests build them anyway:
///
/// ```swift
/// LawOfDemeterVisitor(patternCategory: .architecture)
/// RetroactiveConformanceVisitor(pattern: RetroactiveConformance().pattern)
/// ```
///
/// That expression is the answer, and it is already written down. `MockGeneratorSynthesizer`
/// mines values a test binds to a `let`; this mines the *initializer call* itself, which is what
/// a receiver is built by.
///
/// ## Self-contained, or not at all
///
/// An expression is only usable in a generated file if every name in it resolves there. So an
/// argument may be a literal, a leading-dot enum case, a member chain rooted at a TYPE, or a
/// nested call of the same kind — and never a lowercase identifier, which in a test body is a
/// local (`Visitor(pattern: pattern)` is the common shape and is rejected). A type with several
/// construction sites keeps the first self-contained one in file order, so the choice is stable.
public enum ReceiverConstructionHarvester {

    /// Construction expressions by the type they build, for `wanted` types only.
    public static func harvest(roots: [URL], wanted: Set<String>) -> [String: String] {
        var found: [String: String] = [:]
        for file in swiftFiles(under: roots) {
            guard let source = try? String(contentsOf: file, encoding: .utf8) else { continue }
            for (name, expression) in constructions(in: source, wanted: wanted) where found[name] == nil {
                found[name] = expression
            }
        }
        return found
    }

    /// Every self-contained construction of a `wanted` type in `source`, in source order.
    static func constructions(in source: String, wanted: Set<String>) -> [(String, String)] {
        let collector = CallCollector(viewMode: .sourceAccurate)
        collector.wanted = wanted
        collector.walk(Parser.parse(source: source))
        return collector.found
    }

    /// Whether `expression` names only things a generated test file can see: literals, leading-dot
    /// members, and names beginning with a capital letter (types).
    static func isSelfContained(_ expression: ExprSyntax) -> Bool {
        let checker = FreeNameChecker(viewMode: .sourceAccurate)
        checker.walk(expression)
        return checker.isSelfContained
    }

    private static func swiftFiles(under roots: [URL]) -> [URL] {
        let skipped: Set<String> = [".build", ".git", "Generated", "checkouts", ".swiftinfer"]
        var files: [URL] = []
        for root in roots {
            guard let walker = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
            ) else { continue }
            for case let url as URL in walker {
                if skipped.contains(url.lastPathComponent) {
                    walker.skipDescendants()
                    continue
                }
                if url.pathExtension == "swift" { files.append(url) }
            }
        }
        return files.sorted { $0.path < $1.path }
    }

    private final class CallCollector: SyntaxVisitor {
        var wanted: Set<String> = []
        var found: [(String, String)] = []

        override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
            let callee = node.calledExpression.trimmedDescription
            guard wanted.contains(callee) || wanted.contains(callee.components(separatedBy: ".").last ?? "") else {
                return .visitChildren
            }
            guard node.trailingClosure == nil, node.additionalTrailingClosures.isEmpty,
                  node.arguments.allSatisfy({ isSelfContained($0.expression) })
            else { return .visitChildren }
            found.append((callee, node.trimmedDescription))
            return .visitChildren
        }
    }

    /// Fails the expression on any identifier that is not a type, a member, or a labelled argument.
    private final class FreeNameChecker: SyntaxVisitor {
        var isSelfContained = true

        override func visit(_ node: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
            // A member (`.pattern`, `Rule().pattern`) is spelled by its base, which is checked on
            // its own; a bare lowercase name is a local the generated file has no binding for.
            // ⚠ Only the MEMBER half is spelled that way. A base is a name in its own right, and
            // both halves are children of the same `MemberAccessExprSyntax`, so asking whether the
            // parent is one waved `pattern.category` through as if it were `Rule().pattern`.
            if node.parent?.as(MemberAccessExprSyntax.self)?.declName.id == node.id { return .skipChildren }
            let text = node.baseName.text
            if let first = text.first, first.isLowercase { isSelfContained = false }
            return .visitChildren
        }
    }
}
