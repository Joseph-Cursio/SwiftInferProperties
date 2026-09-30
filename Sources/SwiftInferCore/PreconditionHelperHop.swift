import PropertyLawSyntaxSupport
import SwiftSyntax

/// A precondition one hop away, through a helper the initializer calls.
///
/// `InitializerPreconditionDetector` reads one initializer's body, so a check routed through a helper is
/// invisible to it. Harbeth's `Matrix3x3.init(values:)` calls `HarbethError.failed(…)` — a static function
/// on another type, in another file, that is `fatalError` in DEBUG — and the kit derived a generator
/// through it that drew 0–8 floats into an initializer requiring 9: 5 of 7 traps on that subject
/// (`docs/measurements/subject-harbeth.md`). `criterion-a-swift-system.md` §8.5 sized the same gap through a
/// same-type method (`SystemString._invariantCheck()`).
///
/// The scan records, in its one pass, which functions trap (`trappingKey`) and which functions each
/// initializer calls (`calleeKeys`); `TypeShapeBuilder` joins them, so an initializer calling a trapping
/// helper is declined by the kit's existing rule, exactly as if the check were written inline. **One hop,
/// by name**: a helper calling another helper is not followed, and an owner is its last path component.
enum PreconditionHelperHop {

    /// Whether `body` calls one of the kit's precondition functions anywhere — including inside `#if DEBUG`,
    /// as the kit's own detector counts it.
    static func traps(_ body: CodeBlockSyntax) -> Bool {
        let finder = PreconditionCallFinder(viewMode: .sourceAccurate)
        finder.walk(body)
        return finder.found
    }

    /// `Owner.name` for a method, `name` for a free function.
    static func trappingKey(name: String, owner: String?) -> String {
        owner.map { "\(lastComponent($0)).\(name)" } ?? name
    }

    /// The keys of the functions an initializer calls: `T.f(…)` as `T.f`; `f(…)` and `self.f(…)` as
    /// `Owner.f`, and `f(…)` also as `f` for a free function.
    static func calleeKeys(in initDecl: InitializerDeclSyntax, owner: String?) -> [String] {
        guard let body = initDecl.body else { return [] }
        let collector = CalleeCollector(owner: owner.map(lastComponent))
        collector.walk(body)
        return collector.keys
    }

    static func lastComponent(_ name: String) -> String {
        String(name.split(separator: ".").last ?? Substring(name)).components(separatedBy: "<")[0]
    }

    private final class PreconditionCallFinder: SyntaxVisitor {
        var found = false

        override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
            if let callee = node.calledExpression.as(DeclReferenceExprSyntax.self),
               InitializerPreconditionDetector.preconditionFunctions.contains(callee.baseName.text) {
                found = true
                return .skipChildren
            }
            return .visitChildren
        }
    }

    private final class CalleeCollector: SyntaxVisitor {
        let owner: String?
        var keys: [String] = []

        init(owner: String?) {
            self.owner = owner
            super.init(viewMode: .sourceAccurate)
        }
        private func add(_ key: String) {
            if !keys.contains(key) { keys.append(key) }
        }
        override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
            if let reference = node.calledExpression.as(DeclReferenceExprSyntax.self) {
                let name = reference.baseName.text
                add(name)
                if let owner { add("\(owner).\(name)") }
            } else if let member = node.calledExpression.as(MemberAccessExprSyntax.self),
                      let base = member.base?.as(DeclReferenceExprSyntax.self) {
                let name = member.declName.baseName.text
                guard name != "init" else { return .visitChildren }
                let baseName = base.baseName.text
                if baseName == "self" || baseName == "Self" {
                    if let owner { add("\(owner).\(name)") }
                } else if baseName.first?.isUppercase == true {
                    add("\(baseName).\(name)")
                }
            }
            return .visitChildren
        }
    }
}
