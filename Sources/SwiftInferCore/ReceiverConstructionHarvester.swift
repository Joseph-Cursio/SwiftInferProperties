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
/// local. A type with several construction sites keeps the first self-contained one in file
/// order, so the choice is stable.
///
/// ## A local is followed to what it is bound to
///
/// `Visitor(pattern: pattern)` is the common shape, and refusing it outright cost the stubs it
/// was the only construction for. The binding is usually in the same block and is itself
/// self-contained:
///
/// ```swift
/// private func makeVisitor() -> TooManyEnvironmentObjectsVisitor {
///     let pattern = TooManyEnvironmentObjects().pattern
///     return TooManyEnvironmentObjectsVisitor(pattern: pattern)
/// }
/// ```
///
/// so the local is replaced by the expression it stands for and the result re-checked. A name
/// with no visible `let` is still refused, and so is one whose binding does not itself resolve
/// (`let pattern = makePattern()`) — the substitution moves the question, it does not answer it.
public enum ReceiverConstructionHarvester {

    /// Construction expressions by the type they build, for `wanted` types only.
    ///
    /// ⚠ **A construction the test wrote verbatim outranks one a substitution recovered**, across
    /// every file rather than within one. Following a local makes EARLIER sites eligible, and
    /// first-in-file-order then hands a type a worse expression than the one it already had —
    /// measured, one stub that compiled stopped compiling because its new construction named a
    /// type the stub does not import.
    public static func harvest(roots: [URL], wanted: Set<String>) -> [String: String] {
        harvestWithImports(roots: roots, wanted: wanted).mapValues(\.expression)
    }

    /// A construction together with the `import` lines of the test file it was copied from.
    public struct Harvested: Sendable, Equatable {
        public let expression: String
        /// Each import declaration as written, attributes included — `import SwiftParser`,
        /// `@testable import SwiftProjectLintRules`.
        public let imports: [String]

        public init(expression: String, imports: [String]) {
            self.expression = expression
            self.imports = imports
        }
    }

    /// `harvest`, keeping the imports of the file each construction came from.
    ///
    /// **The expression is copied; the file it compiled in is not.** A test's construction names
    /// whatever that test file imports — `Parser` from `SwiftParser`, `SyntaxPattern` from a nested
    /// package's module, a mock from a test-support target — and none of those are in the index the
    /// carrier-import resolver reads, because none of them is a scanned type. Measured on the
    /// 22 September census: 17 stubs failed `cannot find '…' in scope` on exactly these names.
    /// The test file already says where each one comes from.
    public static func harvestWithImports(roots: [URL], wanted: Set<String>) -> [String: Harvested] {
        var verbatim: [String: Harvested] = [:]
        var inlined: [String: Harvested] = [:]
        for file in swiftFiles(under: roots) {
            guard let source = try? String(contentsOf: file, encoding: .utf8) else { continue }
            let found = constructions(in: source, wanted: wanted)
            guard !found.isEmpty else { continue }
            let imports = importLines(in: source)
            for construction in found {
                let harvested = Harvested(expression: construction.expression, imports: imports)
                if construction.substituted {
                    if inlined[construction.type] == nil { inlined[construction.type] = harvested }
                } else if verbatim[construction.type] == nil {
                    verbatim[construction.type] = harvested
                }
            }
        }
        return inlined.merging(verbatim) { _, written in written }
    }

    /// The file's top-level import declarations, trimmed, in source order.
    static func importLines(in source: String) -> [String] {
        Parser.parse(source: source).statements.compactMap { item in
            item.item.as(ImportDeclSyntax.self)?.trimmedDescription
        }
    }

    /// A construction of a wanted type, and whether a test-local had to be followed to make it
    /// usable — the flag is what lets a verbatim site outrank a recovered one.
    struct Construction {
        let type: String
        let expression: String
        let substituted: Bool
    }

    /// Every usable construction of a `wanted` type in `source`, in source order.
    ///
    /// ⚠ **A type the file declares itself is never harvested.** A test's own `Collector` visitor
    /// shares only its NAME with a production `private struct Collector`, and constructions are
    /// keyed by bare name — so `Collector(viewMode: .sourceAccurate)`, copied from two test files
    /// that declare their own, was handed to 11 stubs whose `Collector` takes no arguments. A
    /// subject is always declared in `Sources/`, so a same-named type in a test file is always
    /// a different type.
    static func constructions(in source: String, wanted: Set<String>) -> [Construction] {
        let tree = Parser.parse(source: source)
        let collector = CallCollector(viewMode: .sourceAccurate)
        collector.wanted = wanted.subtracting(declaredTypeNames(in: tree))
        collector.walk(tree)
        return collector.found
    }

    /// Every nominal type the file declares, at any depth.
    static func declaredTypeNames(in tree: SourceFileSyntax) -> Set<String> {
        let finder = TypeDeclarationFinder(viewMode: .sourceAccurate)
        finder.walk(tree)
        return finder.names
    }

    private final class TypeDeclarationFinder: SyntaxVisitor {
        var names: Set<String> = []

        override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind { record(node.name) }
        override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind { record(node.name) }
        override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind { record(node.name) }
        override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind { record(node.name) }
        private func record(_ name: TokenSyntax) -> SyntaxVisitorContinueKind {
            names.insert(name.text)
            return .visitChildren
        }
    }

    /// Whether `expression` names only things a generated test file can see: literals, leading-dot
    /// members, and names beginning with a capital letter (types).
    static func isSelfContained(_ expression: ExprSyntax) -> Bool {
        let checker = FreeNameChecker(viewMode: .sourceAccurate)
        checker.walk(expression)
        return checker.isSelfContained
    }

    /// How many times a substitution pass is repeated before a chain of locals is given up on.
    private static let substitutionRounds = 3

    /// The `let` bindings visible at `node`, innermost first, as a name → expression map.
    ///
    /// Read out of the file's own syntax: a name is recorded only from a `let` in a block that
    /// encloses the call and is written before it, so the expression is the one the call saw.
    ///
    /// ⚠ **A name an enclosing parameter binds is dropped, not resolved.** `{ pattern in
    /// Visitor(pattern: pattern) }` means the closure's own `pattern`, and answering it with an
    /// outer `let` of the same name would copy a construction the test did not write. A parameter
    /// resolves nowhere in a generated file either way, so dropping it refuses the call.
    private static func visibleBindings(before node: some SyntaxProtocol) -> [String: ExprSyntax] {
        var bindings: [String: ExprSyntax] = [:]
        var shadowed: Set<String> = []
        var scope = node.parent
        while let current = scope {
            shadowed.formUnion(parameterNames(of: current))
            for item in current.as(CodeBlockItemListSyntax.self) ?? [] where item.position < node.position {
                guard let declaration = item.item.as(VariableDeclSyntax.self),
                      declaration.bindingSpecifier.tokenKind == .keyword(.let),
                      declaration.bindings.count == 1,
                      let binding = declaration.bindings.first,
                      binding.accessorBlock == nil,
                      let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
                      let value = binding.initializer?.value,
                      bindings[name] == nil
                else { continue }
                bindings[name] = value
            }
            scope = current.parent
        }
        return bindings.filter { !shadowed.contains($0.key) }
    }

    /// The names `scope` binds as parameters — a closure's, or a function's or initialiser's.
    private static func parameterNames(of scope: Syntax) -> [String] {
        if let closure = scope.as(ClosureExprSyntax.self) {
            switch closure.signature?.parameterClause {
            case .simpleInput(let names): return names.map(\.name.text)
            case .parameterClause(let clause): return clause.parameters.map { ($0.secondName ?? $0.firstName).text }
            case nil: return []
            }
        }
        if let function = scope.as(FunctionDeclSyntax.self) {
            return function.signature.parameterClause.parameters.map { ($0.secondName ?? $0.firstName).text }
        }
        if let initializer = scope.as(InitializerDeclSyntax.self) {
            return initializer.signature.parameterClause.parameters.map { ($0.secondName ?? $0.firstName).text }
        }
        return []
    }

    /// Whether `text` is still one complete expression. A substituted operand can need the
    /// parentheses its own context supplied, and a construction that does not parse is worth less
    /// than none: it is a syntax error in code the reader did not write.
    private static func parsesCleanly(_ text: String) -> Bool {
        !Parser.parse(source: text).hasError
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
        var found: [Construction] = []

        override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
            let callee = node.calledExpression.trimmedDescription
            guard wanted.contains(callee) || wanted.contains(callee.components(separatedBy: ".").last ?? "") else {
                return .visitChildren
            }
            guard node.trailingClosure == nil, node.additionalTrailingClosures.isEmpty,
                  let construction = resolved(node, type: callee)
            else { return .visitChildren }
            found.append(construction)
            return .visitChildren
        }

        /// The call's own text when every argument already resolves there; otherwise its text with
        /// each test-local replaced by what it is bound to, or `nil` when a name still does not.
        private func resolved(_ node: FunctionCallExprSyntax, type: String) -> Construction? {
            if node.arguments.allSatisfy({ isSelfContained($0.expression) }) {
                return Construction(type: type, expression: node.trimmedDescription, substituted: false)
            }
            let bindings = visibleBindings(before: node)
            guard !bindings.isEmpty else { return nil }
            var call = node
            // A binding can name another, so substitute to a fixed point rather than once —
            // bounded, because the search is over source text and a chain has no declared length.
            for _ in 0 ..< substitutionRounds {
                guard let next = LocalBindingInliner(bindings: bindings).rewrite(call).as(FunctionCallExprSyntax.self),
                      next.description != call.description
                else { return nil }
                call = next
                guard call.arguments.allSatisfy({ isSelfContained($0.expression) }) else { continue }
                let text = call.trimmedDescription
                return parsesCleanly(text) ? Construction(type: type, expression: text, substituted: true) : nil
            }
            return nil
        }
    }

    /// Replaces each name a test-local `let` binds with the expression it is bound to.
    private final class LocalBindingInliner: SyntaxRewriter {
        private let bindings: [String: ExprSyntax]

        init(bindings: [String: ExprSyntax]) {
            self.bindings = bindings
            super.init()
        }

        override func visit(_ node: DeclReferenceExprSyntax) -> ExprSyntax {
            guard let value = bindings[node.baseName.text] else { return super.visit(node) }
            return value.trimmed
                .with(\.leadingTrivia, node.leadingTrivia)
                .with(\.trailingTrivia, node.trailingTrivia)
        }

        /// Only the BASE of `rule.pattern` is a name of its own. The member half is visited by
        /// nobody, rather than by a check that has to recognise it — a local called `pattern`
        /// must not rewrite the `.pattern` in someone else's chain.
        override func visit(_ node: MemberAccessExprSyntax) -> ExprSyntax {
            guard let base = node.base else { return ExprSyntax(node) }
            return ExprSyntax(node.with(\.base, visit(base)))
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
