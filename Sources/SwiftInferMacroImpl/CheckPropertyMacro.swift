import ProtoLawCore
import SwiftDiagnostics
import SwiftInferCore
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
        case .roundTrip:
            // M5.3 deliverable. Diagnose explicitly so users tagging
            // `.roundTrip(pairedWith:)` against M5.2 see why nothing
            // expanded rather than a silent no-op.
            context.diagnose(Diagnostic(
                node: Syntax(node),
                message: SwiftInferMacroDiagnostic.roundTripNotYetShipped
            ))
            return []
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
    }

    private static func parseKind(from node: AttributeSyntax) -> ParsedKind? {
        guard case let .argumentList(arguments) = node.arguments,
              let firstArgument = arguments.first else {
            return nil
        }
        // The argument is a member-access expression like `.idempotent`
        // or `.roundTrip(pairedWith: "decode")`.
        if let memberAccess = firstArgument.expression.as(MemberAccessExprSyntax.self) {
            return parseSimpleCase(memberAccess: memberAccess)
        }
        if let functionCall = firstArgument.expression.as(FunctionCallExprSyntax.self) {
            return parseRoundTripCase(call: functionCall)
        }
        return nil
    }

    private static func parseSimpleCase(memberAccess: MemberAccessExprSyntax) -> ParsedKind? {
        switch memberAccess.declName.baseName.text {
        case "idempotent": return .idempotent
        default: return nil
        }
    }

    private static func parseRoundTripCase(call: FunctionCallExprSyntax) -> ParsedKind? {
        guard let memberAccess = call.calledExpression.as(MemberAccessExprSyntax.self),
              memberAccess.declName.baseName.text == "roundTrip" else {
            return nil
        }
        for argument in call.arguments where argument.label?.text == "pairedWith" {
            if let paired = stringLiteralValue(of: argument.expression) {
                return .roundTrip(pairedWith: paired)
            }
        }
        return nil
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
        let generatorExpression = generatorSource(for: paramTypeText)
        let testFunctionName = "\(funcName)_isIdempotent"

        let body = """

            @Test func \(raw: testFunctionName)() async {
                let backend = SwiftPropertyBasedBackend()
                let seed = Seed(
                    stateA: 0x\(raw: hex(seed.stateA)),
                    stateB: 0x\(raw: hex(seed.stateB)),
                    stateC: 0x\(raw: hex(seed.stateC)),
                    stateD: 0x\(raw: hex(seed.stateD))
                )
                let result = await backend.check(
                    trials: 100,
                    seed: seed,
                    sample: { rng in (\(raw: generatorExpression)).run(&rng) },
                    property: { value in \(raw: funcName)(\(raw: funcName)(value)) == \(raw: funcName)(value) }
                )
                if case let .failed(_, _, input, error) = result {
                    Issue.record(
                        "\(raw: funcName)(_:) failed idempotence at input \\(input)."
                            + " \\(error?.message ?? \\"\\")"
                    )
                }
            }
            """ as DeclSyntax
        return [body]
    }

    /// Pick the generator expression for `paramType`. If it matches a
    /// `ProtoLawCore.RawType` (stdlib `Int`, `String`, `Bool`, etc.),
    /// emit the canonical `RawType.generatorExpression` so the M4.2
    /// generator-selection convention is respected. Otherwise, emit
    /// `\(paramType).gen()` — same `.userGen` fallback the
    /// `DerivationStrategist` produces, requiring the user to provide
    /// `static func gen() -> Gen<T>` on the type.
    private static func generatorSource(for paramType: String) -> String {
        if let rawType = RawType(typeName: paramType) {
            return rawType.generatorExpression
        }
        return "\(paramType).gen()"
    }

    private static func hex(_ word: UInt64) -> String {
        let raw = String(word, radix: 16, uppercase: true)
        return String(repeating: "0", count: 16 - raw.count) + raw
    }
}
