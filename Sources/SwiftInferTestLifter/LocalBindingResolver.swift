import SwiftSyntax

/// Substitutes a sliced body's local `let` bindings into an expression, so the shape matchers
/// see the law a human wrote rather than only the one-liner form they were built for.
///
/// **Why this exists.** Every negative detector in `AsymmetricAssertionDetector` matches on
/// syntax: `idempotenceNegativePair` requires both sides of the inequality to be
/// `FunctionCallExprSyntax`, so it recognises
///
/// ```swift
/// #expect(stem(stem(name)) != stem(name))
/// ```
///
/// and nothing else. Humans do not write that. The refutation this repo actually banked reads:
///
/// ```swift
/// let once = ViewModelNameHeuristics.booleanStem(name)
/// let twice = ViewModelNameHeuristics.booleanStem(once)
/// #expect(once != twice)
/// ```
///
/// Both sides are `DeclReferenceExprSyntax`, so the matcher returned nil and the counter-signal
/// never fired — with the consequence that `discover` kept promoting a law the repo's own test
/// suite refutes (road test §10.4). **That is §7.3's failure mode on the negative side**: a
/// detector keyed to the shape the tool imagines rather than the shape people write.
///
/// **Substituting rather than teaching each matcher about variables** is the point. There are
/// six negative detectors and each inspects nested argument structure; adding a
/// variable-aware branch to each would be six chances to get it wrong. Rewriting the
/// expression once, before matching, means every detector — including any added later —
/// benefits without knowing this file exists.
///
/// The slicer has already done the hard part: `propertyRegion` is the transitive backward
/// slice from the assertion through `let`/`var` bindings, so the bindings here are exactly the
/// ones the assertion depends on.
enum LocalBindingResolver {

    /// How many substitution rounds to run before giving up.
    ///
    /// A chain `let a = f(x); let b = f(a); let c = f(b)` needs one round per link. The cap is
    /// a **cycle guard, not a depth preference**: Swift forbids a `let` referring to itself,
    /// but the slice is a syntactic fragment and nothing here re-typechecks it, so a
    /// pathological or malformed body must not spin. Chains beyond this simply stay
    /// unsubstituted, which is the pre-existing behaviour.
    static let maximumRounds = 8

    /// Single-pattern `let`/`var` bindings whose initializer is a CALL, as `name -> call`.
    ///
    /// Tuple destructuring and bindings with no initializer are skipped — there is no single
    /// expression to substitute, and guessing one would be worse than leaving the reference
    /// alone.
    ///
    /// **Calls only, and the restriction is load-bearing rather than cautious.** The matchers
    /// require the innermost argument to be a bare `DeclReferenceExprSyntax` — that identifier
    /// is the value the law quantifies over. Substituting an INPUT binding
    /// (`let name = "isShowing"`) rewrites that identifier into a string literal and the match
    /// fails, so an over-eager resolver breaks the very shapes that worked before. The control
    /// arm caught exactly this: `#expect(f(f(name)) != f(name))`, which had always been
    /// detected, stopped being detected the moment literal bindings were substituted.
    ///
    /// What needs substituting is the *computed intermediate* — `let once = f(name)` — which
    /// is always a call. Inputs must stay symbolic.
    static func bindings(in region: [CodeBlockItemSyntax]) -> [String: ExprSyntax] {
        var result: [String: ExprSyntax] = [:]
        for item in region {
            guard let decl = item.item.as(VariableDeclSyntax.self) else { continue }
            for binding in decl.bindings {
                guard let pattern = binding.pattern.as(IdentifierPatternSyntax.self),
                      let value = binding.initializer?.value,
                      value.is(FunctionCallExprSyntax.self) else { continue }
                // First binding wins. A name rebound later in the slice is ambiguous at this
                // level of analysis, and the earlier one is the one the backward slice walked
                // to reach the assertion.
                if result[pattern.identifier.text] == nil {
                    result[pattern.identifier.text] = value
                }
            }
        }
        return result
    }

    /// Replace bound identifiers with their initializers, repeatedly, until nothing changes.
    ///
    /// Returns the expression unchanged when there is nothing to substitute, so a body that
    /// already used the nested form takes the identical path it did before.
    static func substituting(
        _ expression: ExprSyntax,
        bindings: [String: ExprSyntax]
    ) -> ExprSyntax {
        guard !bindings.isEmpty else { return expression }
        var current = expression
        for _ in 0 ..< maximumRounds {
            let rewriter = BindingRewriter(bindings: bindings)
            guard let rewritten = rewriter.visit(Syntax(current)).as(ExprSyntax.self) else {
                return current
            }
            if rewritten.description == current.description {
                return current
            }
            current = rewritten
        }
        return current
    }

    /// Rewrites every `DeclReferenceExprSyntax` naming a known binding into that binding's
    /// initializer. One pass; `substituting` iterates it.
    private final class BindingRewriter: SyntaxRewriter {

        private let bindings: [String: ExprSyntax]

        init(bindings: [String: ExprSyntax]) {
            self.bindings = bindings
            super.init()
        }

        override func visit(_ node: DeclReferenceExprSyntax) -> ExprSyntax {
            // A member's NAME is a `DeclReferenceExprSyntax` too — `ViewModelNameHeuristics
            // .booleanStem` holds `booleanStem` in `declName` — but it is a name, not a value
            // reference, and `MemberAccessExprSyntax.declName` is typed as a decl reference.
            // Substituting an arbitrary expression there produces a tree that violates the
            // grammar, and the first consumer to read `.declName` force-casts and TRAPS.
            //
            // Measured, and it is why this guard is here rather than a theory: without it
            // `swift-infer discover` died with `Unexpectedly found nil while unwrapping an
            // Optional value` inside `ExprSyntax.trailingIdentifierName`, reached from
            // `roundTripNegativePair` — a detector this change was not even aiming at.
            if let member = node.parent?.as(MemberAccessExprSyntax.self),
               member.declName.id == node.id {
                return super.visit(node)
            }
            guard node.argumentNames == nil,
                  let replacement = bindings[node.baseName.text] else {
                return super.visit(node)
            }
            // Trivia is dropped deliberately: the result is matched structurally and never
            // rendered, and carrying the original's spacing into a substituted subtree
            // produces expressions that read oddly in a debugger for no benefit.
            return ExprSyntax(replacement.trimmed)
        }
    }
}
