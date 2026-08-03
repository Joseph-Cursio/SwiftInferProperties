import Foundation
import SwiftInferCore

/// Call-expression resolution for the strategist path: given a SemanticIndex
/// entry, decide what the stub should actually *call*. Split out of
/// `VerifyCommand+TemplateDispatch.swift` when the operand-idempotence shape
/// pushed that file past the 400-line cap.
///
/// The distinction this layer owns is receiver-shape vs static-reference. A
/// static reference (`Decisions.merge`) is what an unapplied *free* function
/// looks like; for an instance method it is a curried
/// `(Self) -> (Args) -> Result` and will not coerce to the function type the
/// composers annotate. `receiverCallExpression` renders the closure form
/// (`{ $0.merge($1) }`) that does.
extension SwiftInferCommand.Verify {

    /// The `a.merge(b)` idempotence shape: a non-mutating instance method that
    /// returns its own type and takes **exactly one** operand of that type.
    ///
    /// The law is *idempotence in the operand* — merging the same `b` a second
    /// time changes nothing: `a.merge(b).merge(b) == a.merge(b)`. That is the
    /// standard reading for merge / union / update shapes, and it is refutable:
    /// a merge that appends rather than absorbs fails it at the first trial.
    ///
    /// **Exactly one** parameter, not "at least one". The receiver closure
    /// `receiverCallExpression` renders takes one operand per parameter, and
    /// the composer supplies exactly two values (receiver + operand). A
    /// 2-parameter method would need a third, drawn from where? — there is no
    /// principled answer, so it keeps its previous static-reference rendering
    /// and its previous `build-failed`, rather than acquiring a wrong law.
    static func takesOperandIdempotenceShape(_ entry: SemanticIndexEntry) -> Bool {
        entry.isInstanceMethod
            && !entry.isMutatingMethod
            && !entry.isNullary
            && entry.returnsSelfType
            && argumentLabels(from: entry.primaryFunctionName).count == 1
    }

    /// Pair / single-function resolution layer shared across templates
    /// when the strategist path emits. Round-trip resolves the curated
    /// forward+inverse pair; idempotence / commutativity / associativity
    /// resolve the single function call.
    struct ResolvedCalls {
        let expressions: [String]
        let rendererForwardName: String
        let rendererInverseName: String
    }

    /// Build call expressions for the strategist path, inlining the
    /// resolvers' call-construction logic to sidestep their v1.46
    /// `supportedCarriers` validation (which would reject `String` /
    /// `Bool` / enum / `.userGen` carriers that the strategist emits
    /// fine). Round-trip still looks up the curated pair list to
    /// discover the inverse half — strategist routing doesn't change
    /// that piece of the design.
    static func resolveFunctionCalls(for entry: SemanticIndexEntry) throws -> ResolvedCalls {
        let carrier = entry.typeName ?? "(none)"
        let typeQualifier = RoundTripPairResolver.bareTypeName(from: carrier)
        let funcName = RoundTripPairResolver.stripParameterLabels(entry.primaryFunctionName)
        switch entry.templateName {
        case "round-trip":
            return try resolveRoundTripCalls(entry: entry, typeQualifier: typeQualifier)

        case "codable-round-trip":
            return try resolveCodableRoundTripCalls(entry: entry, carrier: carrier)

        case "idempotence":
            // Static/free shape; idempotence's own composer emits the receiver
            // form for mutating / self-returning NULLARY instance methods —
            // those composers build `value.method()` from the method name
            // themselves, so they need the plain reference, not a closure.
            //
            // The one shape they cannot build is a self-returning instance
            // method that TAKES an operand (`a.merge(b)`): the composer has no
            // argument labels, so the plain reference renders as the static
            // `Decisions.merge`, which is a curried
            // `(Decisions) -> (Decisions) -> Decisions` and fails to compile
            // against the `(Decisions) -> Decisions` annotation. That shape gets
            // the label-carrying receiver closure instead.
            return singleCallResolved(
                entry: entry,
                typeQualifier: typeQualifier,
                funcName: funcName,
                receiverShape: takesOperandIdempotenceShape(entry)
            )

        case "predicate":
            // Totality takes ONE call and applies it to one generated value, so the plain
            // static/free reference is all it needs — no pairing, no receiver closure.
            //
            // **This case is the second gate, and shipping the composer without it was a
            // no-op.** `TemplateName.verifiable` clears `dispatch`'s check; this switch is a
            // separate enumeration of the same vocabulary, and its `default:` throws the very
            // `unsupportedTemplate` the composer exists to stop. All 49 indexed `predicate`
            // entries declined here — measured before this line existed, which is the only
            // reason it was found.
            return singleCallResolved(
                entry: entry,
                typeQualifier: typeQualifier,
                funcName: funcName,
                receiverShape: entry.isInstanceMethod
            )

        case "commutativity", "associativity":
            // Binary instance ops emit the receiver shape here.
            return singleCallResolved(
                entry: entry, typeQualifier: typeQualifier, funcName: funcName, receiverShape: true
            )

        case "idempotence-lifted", "monotonicity":
            return liftedOrMonotonicityCalls(entry: entry, typeQualifier: typeQualifier, funcName: funcName)

        case "binary-idempotence":
            // A binary operator — receiver shape so an INSTANCE op emits
            // `x.union(x)` (via the closure trampoline); a free/static op falls
            // back to `union(x, x)` (receiverCallExpression's non-instance path).
            return singleCallResolved(
                entry: entry, typeQualifier: typeQualifier, funcName: funcName, receiverShape: true
            )

        case "involution", "homomorphism", "multiplicative-homomorphism", "measure-non-negativity":
            // Single-function laws. Involution's self-returning instance form and
            // measure's 0-param instance form both emit the receiver shape from
            // `inputs` flags in the composer; the free/static call resolves the
            // same way idempotence's non-receiver shape does.
            return singleCallResolved(
                entry: entry, typeQualifier: typeQualifier, funcName: funcName, receiverShape: false
            )

        case "dual-style-consistency":
            // V1.48.B — pair of expressions: [nonMutCall, mutMethodName].
            // Resolver fires its own validation (carrier-agnostic;
            // curated pair list check). Renderer surfaces both halves
            // as forward / inverse names.
            let pair = try DualStyleConsistencyPairResolver.resolve(entry)
            return ResolvedCalls(
                expressions: [pair.nonMutCall, pair.mutMethodName],
                rendererForwardName: pair.nonMutCall,
                rendererInverseName: pair.mutMethodName
            )

        default:
            throw VerifyError.unsupportedTemplate(
                template: entry.templateName,
                expected: supportedTemplates
            )
        }
    }

    /// V1.89 lint pass — extracted from `resolveFunctionCalls` so the
    /// switch body stays under SwiftLint's 50-line cap. Mirrors
    /// `RoundTripPairResolver.resolve`'s curated-first /
    /// `secondaryFunctionName`-fallback chain; skips the carrier check
    /// because the strategist owns carrier validation at this layer.
    static func resolveRoundTripCalls(
        entry: SemanticIndexEntry,
        typeQualifier: String
    ) throws -> ResolvedCalls {
        let forwardBare = entry.primaryFunctionName
        let inverseBare: String
        if let pair = RoundTripPairResolver.curated.first(where: { $0.forwardName == forwardBare }) {
            inverseBare = pair.inverseName
        } else if let secondary = entry.secondaryFunctionName {
            inverseBare = secondary
        } else {
            throw VerifyError.unsupportedPair(
                forward: forwardBare,
                supported: RoundTripPairResolver.curated.map(\.forwardName)
            )
        }
        // Each half renders static/free by default; a half that IS the entry's
        // signalled instance method emits the receiver shape (self-inverse
        // instance-method round-trips like `value.negated().negated() == value`).
        let forwardCall = roundTripHalfCall(entry: entry, typeQualifier: typeQualifier, bareName: forwardBare)
        let inverseCall = roundTripHalfCall(entry: entry, typeQualifier: typeQualifier, bareName: inverseBare)
        return ResolvedCalls(
            expressions: [forwardCall, inverseCall],
            rendererForwardName: forwardCall,
            rendererInverseName: inverseCall
        )
    }
}
