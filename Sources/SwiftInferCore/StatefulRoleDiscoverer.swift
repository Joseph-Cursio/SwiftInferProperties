import SwiftSyntax

/// The generic discovery engine: walks a parsed file, and for each declaration
/// offers it to an ordered list of `RolePolicy` (specific → generic). The first
/// policy to claim a declaration builds the `StatefulRole`.
///
/// Phase 0 of `docs/stateful-role-discoverer-design.md`. The engine owns the
/// walk and the import/location plumbing; everything architecture-specific lives
/// in the policies. Phase 0 ships the engine with no production policies wired —
/// it is exercised by a stub policy in tests — so it changes no existing
/// behavior. Phase 1 registers `TCAReducerPolicy` / `MVVMPolicy`.
public struct StatefulRoleDiscoverer {

    /// Ordered policies. Order is the recognition-precedence tie-break: place
    /// macro/signature policies before convention policies so a `@Reducer`
    /// never gets claimed by a name-suffix convention.
    public let policies: [RolePolicy]

    public init(policies: [RolePolicy]) {
        self.policies = policies
    }

    /// Discover every role in a parsed source file.
    public func discover(in tree: SourceFileSyntax, file: String) -> [StatefulRole] {
        let converter = SourceLocationConverter(fileName: file, tree: tree)
        let context = FileContext(
            file: file,
            imports: Self.imports(in: tree),
            converter: converter
        )
        let collector = StatefulRoleCollector(policies: policies, context: context)
        collector.walk(tree)
        return collector.roles
    }

    /// Module names imported by the file — gates framework-specific recognition.
    static func imports(in tree: SourceFileSyntax) -> Set<String> {
        var names: Set<String> = []
        for statement in tree.statements {
            if let importDecl = statement.item.as(ImportDeclSyntax.self) {
                names.insert(importDecl.path.trimmedDescription)
            }
        }
        return names
    }
}

/// Walks a file's declarations and offers each to the policy list. First match
/// wins; sibling and nested declarations are still visited (a reducer can nest
/// inside a feature type that is itself a role).
final class StatefulRoleCollector: SyntaxVisitor {

    private let policies: [RolePolicy]
    private let context: FileContext
    private(set) var roles: [StatefulRole] = []

    init(policies: [RolePolicy], context: FileContext) {
        self.policies = policies
        self.context = context
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        offer(DeclSyntax(node))
        return .visitChildren
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        offer(DeclSyntax(node))
        return .visitChildren
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        offer(DeclSyntax(node))
        return .visitChildren
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        offer(DeclSyntax(node))
        return .visitChildren
    }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        offer(DeclSyntax(node))
        return .visitChildren
    }

    private func offer(_ decl: DeclSyntax) {
        for policy in policies {
            if let match = policy.recognize(decl, in: context) {
                roles.append(policy.buildRole(from: match, in: context))
                return
            }
        }
    }
}
