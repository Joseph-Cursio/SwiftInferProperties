import SwiftDiagnostics
import SwiftInferCore
import SwiftInferTemplates
import SwiftSyntax
import SwiftSyntaxMacros

/// `@CheckProperty(...)` peer-macro implementation.
///
/// Expands a tagged function decl into a peer `@Test func` that runs
/// the named property under `SwiftPropertyBasedBackend` with a
/// PRD v0.4 §16 #6 sampling seed derived from the function's identity.
/// M5.2 ships the `.idempotent` arm; M5.3 will add `.roundTrip`.
public struct CheckPropertyMacro: PeerMacro {

    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let function = declaration.as(FunctionDeclSyntax.self) else {
            context.diagnose(Diagnostic(
                node: Syntax(declaration),
                message: SwiftInferMacroDiagnostic.notAFunctionDecl
            ))
            return []
        }
        guard let kind = parseKind(from: node) else {
            context.diagnose(Diagnostic(
                node: Syntax(node),
                message: SwiftInferMacroDiagnostic.unrecognizedKind
            ))
            return []
        }
        switch kind {
        case .idempotent:
            return expandIdempotent(function: function, in: context)
        case .roundTrip(let inverseName):
            return expandRoundTrip(
                function: function,
                inverseName: inverseName,
                in: context
            )
        case .preservesInvariant(let keyPath):
            return expandPreservesInvariant(
                function: function,
                keyPath: keyPath,
                in: context
            )
        }
    }

    // MARK: - Kind parsing

    /// Internal mirror of `SwiftInferMacro.CheckPropertyKind` — re-declared
    /// here because the macro impl runs as a separate compiler-plugin
    /// process and can't import the macro's declaration target. Shape
    /// must match the source-level enum 1:1.
    private enum ParsedKind {
        case idempotent
        case roundTrip(pairedWith: String)
        case preservesInvariant(keyPath: String)
    }

    private static func parseKind(from node: AttributeSyntax) -> ParsedKind? {
        guard case let .argumentList(arguments) = node.arguments,
              let firstArgument = arguments.first else {
            return nil
        }
        // The argument is a member-access expression like `.idempotent`
        // or a function call like `.roundTrip(pairedWith: "decode")` or
        // `.preservesInvariant(\.isValid)`.
        if let memberAccess = firstArgument.expression.as(MemberAccessExprSyntax.self) {
            return parseSimpleCase(memberAccess: memberAccess)
        }
        if let functionCall = firstArgument.expression.as(FunctionCallExprSyntax.self) {
            return parseFunctionCallCase(call: functionCall)
        }
        return nil
    }

    private static func parseSimpleCase(memberAccess: MemberAccessExprSyntax) -> ParsedKind? {
        switch memberAccess.declName.baseName.text {
        case "idempotent": return .idempotent
        default: return nil
        }
    }

    private static func parseFunctionCallCase(call: FunctionCallExprSyntax) -> ParsedKind? {
        guard let memberAccess = call.calledExpression.as(MemberAccessExprSyntax.self) else {
            return nil
        }
        switch memberAccess.declName.baseName.text {
        case "roundTrip":
            for argument in call.arguments where argument.label?.text == "pairedWith" {
                if let paired = stringLiteralValue(of: argument.expression) {
                    return .roundTrip(pairedWith: paired)
                }
            }
            return nil
        case "preservesInvariant":
            // First (unlabelled) argument is the keypath literal.
            guard let firstArgument = call.arguments.first else { return nil }
            guard let keyPath = firstArgument.expression.as(KeyPathExprSyntax.self) else {
                return nil
            }
            return .preservesInvariant(keyPath: keyPath.trimmedDescription)
        default:
            return nil
        }
    }

    private static func stringLiteralValue(of expression: ExprSyntax) -> String? {
        guard let literal = expression.as(StringLiteralExprSyntax.self) else { return nil }
        guard literal.segments.count == 1,
              let segment = literal.segments.first?.as(StringSegmentSyntax.self) else {
            return nil
        }
        return segment.content.text
    }

    // MARK: - Idempotent expansion

    private static func expandIdempotent(
        function: FunctionDeclSyntax,
        in context: some MacroExpansionContext
    ) -> [DeclSyntax] {
        guard function.signature.parameterClause.parameters.count == 1,
              let parameter = function.signature.parameterClause.parameters.first,
              let returnType = function.signature.returnClause?.type else {
            context.diagnose(Diagnostic(
                node: Syntax(function),
                message: SwiftInferMacroDiagnostic.idempotentRequiresUnaryShape
            ))
            return []
        }
        let paramTypeText = parameter.type.trimmedDescription
        let returnTypeText = returnType.trimmedDescription
        guard paramTypeText == returnTypeText else {
            context.diagnose(Diagnostic(
                node: Syntax(function),
                message: SwiftInferMacroDiagnostic.idempotentRequiresMatchingTypes
            ))
            return []
        }

        let funcName = function.name.text
        let canonicalSignature = "checkProperty.idempotent|\(funcName)|(\(paramTypeText))->\(returnTypeText)"
        let seed = SamplingSeed.derive(fromIdentityHash: canonicalSignature)
        let source = LiftedTestEmitter.idempotent(
            funcName: funcName,
            typeName: paramTypeText,
            seed: seed,
            generator: LiftedTestEmitter.defaultGenerator(for: paramTypeText)
        )
        return [DeclSyntax(stringLiteral: source)]
    }

    // MARK: - Round-trip expansion

    private static func expandRoundTrip(
        function: FunctionDeclSyntax,
        inverseName: String,
        in context: some MacroExpansionContext
    ) -> [DeclSyntax] {
        guard function.signature.parameterClause.parameters.count == 1,
              let parameter = function.signature.parameterClause.parameters.first,
              let returnType = function.signature.returnClause?.type else {
            context.diagnose(Diagnostic(
                node: Syntax(function),
                message: SwiftInferMacroDiagnostic.roundTripRequiresUnaryShape
            ))
            return []
        }
        let paramTypeText = parameter.type.trimmedDescription
        let returnTypeText = returnType.trimmedDescription
        guard paramTypeText != returnTypeText else {
            // T -> T is the .idempotent shape; round-trip is T -> U with
            // T != U. Prevent a confusing same-type round-trip stub
            // (where decode(encode(value)) == value collapses to
            // identity if both sides are no-ops on the same type).
            context.diagnose(Diagnostic(
                node: Syntax(function),
                message: SwiftInferMacroDiagnostic.roundTripRequiresDistinctTypes
            ))
            return []
        }
        let forwardName = function.name.text
        let canonicalSignature = roundTripCanonicalSignature(
            forwardName: forwardName,
            inverseName: inverseName,
            forwardParam: paramTypeText,
            forwardReturn: returnTypeText
        )
        let source = LiftedTestEmitter.roundTrip(
            forwardName: forwardName,
            inverseName: inverseName,
            seed: SamplingSeed.derive(fromIdentityHash: canonicalSignature),
            generator: LiftedTestEmitter.defaultGenerator(for: paramTypeText)
        )
        return [DeclSyntax(stringLiteral: source)]
    }

    /// Build the orientation-agnostic canonical signature used for the
    /// round-trip seed. Sorts the forward / reverse names lexically so
    /// attaching `@CheckProperty(.roundTrip(pairedWith: "decode"))` to
    /// `encode` and attaching `@CheckProperty(.roundTrip(pairedWith:
    /// "encode"))` to `decode` produce the same seed (mirrors how
    /// `RoundTripTemplate.makeIdentity` sorts its halves for the same
    /// reason — the property is symmetric so the identity should be too).
    /// The forward type signature appears alongside in the canonical
    /// form so e.g. `encode/decode` over `MyType` ↔ `Data` and
    /// `encode/decode` over `OtherType` ↔ `Data` get distinct seeds.
    private static func roundTripCanonicalSignature(
        forwardName: String,
        inverseName: String,
        forwardParam: String,
        forwardReturn: String
    ) -> String {
        let sorted = [forwardName, inverseName].sorted().joined(separator: "|")
        return "checkProperty.roundTrip|\(sorted)|(\(forwardParam))->\(forwardReturn)"
    }

    // MARK: - Invariant-preservation expansion (M7.2.a)

    /// Expand `@CheckProperty(.preservesInvariant(\.kp))` into a peer
    /// `@Test func` that asserts `kp(input) -> kp(f(input))` over a
    /// generated stream of inputs. Mirrors `expandIdempotent` /
    /// `expandRoundTrip`'s shape — wraps `LiftedTestEmitter.invariantPreserving`
    /// (M7.3) into a `DeclSyntax`. Same single-parameter / non-nil-
    /// return shape requirement as the other arms; `T -> U` is allowed
    /// (the keypath may apply to T and to U separately).
    private static func expandPreservesInvariant(
        function: FunctionDeclSyntax,
        keyPath: String,
        in context: some MacroExpansionContext
    ) -> [DeclSyntax] {
        guard function.signature.parameterClause.parameters.count == 1,
              let parameter = function.signature.parameterClause.parameters.first,
              let returnType = function.signature.returnClause?.type else {
            context.diagnose(Diagnostic(
                node: Syntax(function),
                message: SwiftInferMacroDiagnostic.preservesInvariantRequiresUnaryShape
            ))
            return []
        }
        let paramTypeText = parameter.type.trimmedDescription
        let returnTypeText = returnType.trimmedDescription
        let funcName = function.name.text
        let canonicalSignature = preservesInvariantCanonicalSignature(
            funcName: funcName,
            keyPath: keyPath,
            paramType: paramTypeText,
            returnType: returnTypeText
        )
        let source = LiftedTestEmitter.invariantPreserving(
            funcName: funcName,
            typeName: paramTypeText,
            invariantName: keyPath,
            seed: SamplingSeed.derive(fromIdentityHash: canonicalSignature),
            generator: LiftedTestEmitter.defaultGenerator(for: paramTypeText)
        )
        return [DeclSyntax(stringLiteral: source)]
    }

    /// Build the canonical signature used for the invariant-preservation
    /// seed. Includes the keypath text so the same function with two
    /// different `@CheckProperty(.preservesInvariant)` annotations
    /// (different keypaths on different test files) gets distinct seeds
    /// — keeps trial sequences distinct per claim.
    private static func preservesInvariantCanonicalSignature(
        funcName: String,
        keyPath: String,
        paramType: String,
        returnType: String
    ) -> String {
        "checkProperty.preservesInvariant|\(funcName)|\(keyPath)|(\(paramType))->\(returnType)"
    }

}
