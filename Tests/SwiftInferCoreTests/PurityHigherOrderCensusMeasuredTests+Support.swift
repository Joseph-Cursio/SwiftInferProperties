import Foundation
import SwiftEffectInference
import SwiftParser
import SwiftSyntax

@testable import SwiftInferCore

/// Type unwrapping and call-site collection for
/// `PurityHigherOrderCensusMeasuredTests`. Split out for the 400-line file cap
/// only; the reasoning that governs both lives in that suite's header.
extension PurityHigherOrderCensusMeasuredTests {

    typealias Subject = PurityRefutationCensusMeasuredTests.Subject

    /// A non-refuted function that takes at least one function-typed parameter,
    /// so its purity is **conditional on what the caller passes** — and is
    /// claimed unconditionally.
    struct ConditionalRow {
        let subject: Subject
        let verdict: PurityVerdict
        /// The parameters whose type is a function type, by name.
        let functionParameters: [String]
        /// Whether any of them is `@escaping` or `@autoclosure`, which is where
        /// the claim is loosest: the argument can outlive the call.
        let hasAttributedParameter: Bool
    }

    /// Whether `type` is a function type, through the wrappers Swift allows
    /// around one.
    ///
    /// `@escaping (Int) -> Int`, `((Int) -> Int)?`, `((Int) -> Int)!` and the
    /// redundantly-parenthesised `((Int) -> Int)` all denote a function and all
    /// carry the same conditional purity. Missing a wrapper here would
    /// under-count the population, which is the direction that flatters the
    /// tool, so each is unwrapped explicitly rather than by a token scan for
    /// `->` (which would also match a *return* type).
    static func isFunctionType(_ type: TypeSyntax) -> Bool {
        if type.is(FunctionTypeSyntax.self) { return true }
        if let attributed = type.as(AttributedTypeSyntax.self) {
            return isFunctionType(attributed.baseType)
        }
        if let optional = type.as(OptionalTypeSyntax.self) {
            return isFunctionType(optional.wrappedType)
        }
        if let unwrapped = type.as(ImplicitlyUnwrappedOptionalTypeSyntax.self) {
            return isFunctionType(unwrapped.wrappedType)
        }
        if let tuple = type.as(TupleTypeSyntax.self), tuple.elements.count == 1,
           let only = tuple.elements.first {
            return isFunctionType(only.type)
        }
        return false
    }

    /// Whether the parameter carries `@escaping` or `@autoclosure`.
    static func isAttributed(_ parameter: FunctionParameterSyntax) -> Bool {
        guard let attributed = parameter.type.as(AttributedTypeSyntax.self) else { return false }
        return !attributed.attributes.isEmpty
    }

    /// One call site passing a closure literal, with the verdict on that
    /// literal. This is the base-rate instrument: a conditionally-pure function
    /// is only *wrongly* claimed pure where some caller actually supplies an
    /// impure argument.
    struct ClosureArgument {
        let calleeName: String
        let file: String
        let isPure: Bool
    }

    /// Every closure literal passed at a call site, across `Sources/`.
    ///
    /// Uses SEI's **public** `isPure(_ closure:)` rather than a replicated copy.
    /// The item 29 census replicates because the function-level refuters are
    /// `private`; the closure oracle is published precisely so a caller can ask
    /// this, so replicating it here would invent a drift trap for nothing.
    static let closureArguments: [ClosureArgument] = {
        let inferrer = PurityInferrer()
        var found: [ClosureArgument] = []
        for file in SwiftSourceFiles.sorted(in: PurityRefutationCensusMeasuredTests.packageSourcesRoot) {
            guard let source = try? String(contentsOf: file, encoding: .utf8) else { continue }
            let collector = CensusClosureArgumentCollector(viewMode: .sourceAccurate)
            collector.walk(Parser.parse(source: source))
            let relative = file.lastPathComponent
            found.append(contentsOf: collector.passed.map {
                ClosureArgument(
                    calleeName: $0.calleeName,
                    file: relative,
                    isPure: inferrer.isPure($0.closure)
                )
            })
        }
        return found
    }()
}

// MARK: - Collection

/// Every closure literal handed to a call, keyed by the callee's bare name.
///
/// Trailing closures count — `xs.map { … }` is the ordinary spelling and
/// omitting it would measure almost nothing. Additional trailing closures count
/// too, since a two-closure call passes two arguments whose purity differs.
final class CensusClosureArgumentCollector: SyntaxVisitor {

    private(set) var passed: [(calleeName: String, closure: ClosureExprSyntax)] = []

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        guard let callee = CensusCalleeCollector.callee(of: node.calledExpression) else {
            return .visitChildren
        }
        for argument in node.arguments {
            if let closure = argument.expression.as(ClosureExprSyntax.self) {
                passed.append((callee.name, closure))
            }
        }
        if let trailing = node.trailingClosure {
            passed.append((callee.name, trailing))
        }
        for additional in node.additionalTrailingClosures {
            passed.append((callee.name, additional.closure))
        }
        return .visitChildren
    }
}
