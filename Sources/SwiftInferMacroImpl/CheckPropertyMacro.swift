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
        case .roundTrip(let inverseName):
            return expandRoundTrip(
                function: function,
                inverseName: inverseName,
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
        return [emitRoundTripPeer(
            forwardName: forwardName,
            inverseName: inverseName,
            seed: SamplingSeed.derive(fromIdentityHash: canonicalSignature),
            generator: generatorSource(for: paramTypeText)
        )]
    }

    private static func emitRoundTripPeer(
        forwardName: String,
        inverseName: String,
        seed: SamplingSeed.Value,
        generator: String
    ) -> DeclSyntax {
        let testFunctionName = "\(forwardName)_\(inverseName)_roundTrip"
        return """

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
                    sample: { rng in (\(raw: generator)).run(&rng) },
                    property: { value in \(raw: inverseName)(\(raw: forwardName)(value)) == value }
                )
                if case let .failed(_, _, input, error) = result {
                    Issue.record(
                        "\(raw: forwardName)/\(raw: inverseName) round-trip failed at input \\(input)."
                            + " \\(error?.message ?? \\"\\")"
                    )
                }
            }
            """ as DeclSyntax
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

    // MARK: - Shared helpers

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
