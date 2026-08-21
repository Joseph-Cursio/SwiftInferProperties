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
    /// V1.48.B — pair of expressions: `[nonMutCall, mutMethodName]`. The resolver fires its
    /// own validation (carrier-agnostic; curated pair-list check), and the renderer surfaces
    /// both halves as forward / inverse names. Split out of `resolveFunctionCalls` only for
    /// the 50-line body cap, which admitting `role-postcondition` tipped.
    static func dualStyleCalls(entry: SemanticIndexEntry) throws -> ResolvedCalls {
        let pair = try DualStyleConsistencyPairResolver.resolve(entry)
        return ResolvedCalls(
            expressions: [pair.nonMutCall, pair.mutMethodName],
            rendererForwardName: pair.nonMutCall,
            rendererInverseName: pair.mutMethodName
        )
    }

    /// **A template needs admitting in TWO places, and missing either reports the same
    /// error.** `TemplateName.verifiable` gates the template check; this switch gates call
    /// resolution. `role-postcondition` was added to the first and still reported
    /// `unsupported-template` from the survey path, which consults this one — measured on a
    /// planted subject before the omission reached a corpus.
    static func resolveFunctionCalls(for entry: SemanticIndexEntry) throws -> ResolvedCalls {
        let carrier = entry.typeName ?? "(none)"
        // The name the stub must WRITE, which is not always the name the index
        // KEYS on. A type declared lexically inside another records its carrier as
        // the innermost frame (`Scaffold`), and `Scaffold.defaultOutputURL(…)`
        // fails to compile with *cannot find 'Scaffold' in scope*. The qualified
        // path (`SwiftInferCommand.Scaffold`) resolves. Falls back to the carrier
        // for an index written before the field existed — the behaviour every
        // entry had until 2026-08-05.
        let qualifier = entry.qualifiedTypeName ?? carrier
        let typeQualifier = RoundTripPairResolver.bareTypeName(from: qualifier)
        let funcName = RoundTripPairResolver.stripParameterLabels(entry.primaryFunctionName)
        switch entry.templateName {
        // The two-function laws. Both resolve a pair and render each half with
        // `roundTripHalfCall`; they differ only in how the second half is found
        // (curated-then-entry vs entry-only), so they share one arm here rather
        // than each costing the switch a branch against its complexity cap.
        case "round-trip", "differential-equivalence":
            return try resolveTwoFunctionCalls(entry: entry, typeQualifier: typeQualifier)

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

        case "involution", "homomorphism", "multiplicative-homomorphism", "measure-non-negativity",
             "role-postcondition":
            // Single-function laws. Involution's self-returning instance form and
            // measure's 0-param instance form both emit the receiver shape from
            // `inputs` flags in the composer; the free/static call resolves the
            // same way idempotence's non-receiver shape does.
            // `role-postcondition` joins them: same shape as measure — one function, one
            // generated value, a predicate on the RESULT.
            return singleCallResolved(
                entry: entry, typeQualifier: typeQualifier, funcName: funcName, receiverShape: false
            )

        case "dual-style-consistency":
            return try dualStyleCalls(entry: entry)

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

    /// Route a two-function law to its resolver. Keeps the dispatch switch at
    /// one branch for both.
    static func resolveTwoFunctionCalls(
        entry: SemanticIndexEntry,
        typeQualifier: String
    ) throws -> ResolvedCalls {
        if entry.templateName == "differential-equivalence" {
            return try resolveDifferentialCalls(entry: entry, typeQualifier: typeQualifier)
        }
        return try resolveRoundTripCalls(entry: entry, typeQualifier: typeQualifier)
    }

    /// Resolve the two halves of `reference(x) == variant(x)`.
    ///
    /// **No curated table, deliberately.** `round-trip` tries
    /// `RoundTripPairResolver.curated` before falling back to the entry, and
    /// `dual-style-consistency` has only the curated route. Neither applies
    /// here: a differential pair is discovered by NAME MARKER (`fooSlow`,
    /// `appendUnchecked`) over the user's own corpus, so there is no fixed list
    /// to curate — any table would be a list of names this repo happened to
    /// have seen. The entry carries the pair, so the entry is the source.
    ///
    /// Both halves render through `roundTripHalfCall`, which gives each one the
    /// receiver shape when it is the entry's signalled instance method and the
    /// static/free shape otherwise. That matters more here than for round-trip:
    /// a variant pair is frequently one instance method and one free function
    /// (`x.sortedFast()` against `referenceSort(x)`), so assuming a single shape
    /// for both halves would emit a call that does not compile.
    static func resolveDifferentialCalls(
        entry: SemanticIndexEntry,
        typeQualifier: String
    ) throws -> ResolvedCalls {
        let referenceBare = entry.primaryFunctionName
        guard let variantBare = entry.secondaryFunctionName else {
            throw VerifyError.missingPairedFunction(
                template: "differential-equivalence",
                primary: referenceBare
            )
        }
        let referenceCall = roundTripHalfCall(
            entry: entry, typeQualifier: typeQualifier, bareName: referenceBare
        )
        let variantCall = roundTripHalfCall(
            entry: entry, typeQualifier: typeQualifier, bareName: variantBare
        )
        return ResolvedCalls(
            expressions: [referenceCall, variantCall],
            rendererForwardName: referenceCall,
            rendererInverseName: variantCall
        )
    }
}
