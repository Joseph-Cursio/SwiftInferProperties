import Foundation
import PropertyLawCore
import SwiftInferCore

/// **Totality over an n-ary predicate** — one generated value per parameter.
///
/// Split from `+Templates` because the n-ary form needs a generator *per parameter*, which means
/// resolving a recipe per parameter, which means the composer can now fail. That is a different
/// shape from every other composer in that file, all of which are handed the one recipe they need.
///
/// Measured 2026-08-03: **19 of 126** `predicate` entries failed to compile with
/// `missing argument for parameter #2`. The composer had one type and emitted one argument for a
/// function that takes two — not a bug in the emission, but the index having recorded a carrier
/// where the law needed a signature.
extension StrategistDispatchEmitter {

    /// Generator declarations and the argument list for a totality call.
    ///
    /// `arity <= 1` returns the single-carrier form verbatim, so a unary law emits byte-identical
    /// source to what it did before this existed — the n-ary path cannot regress the 54 laws that
    /// already run.
    struct TotalityOperands {
        let declarations: String
        let drawStatements: String
        /// What gets printed as `VERIFY_TRIAL_INPUT`, and what is passed to the call.
        let inputExpression: String
        let argumentList: String
    }

    /// The types a totality call actually needs a value for — **including the receiver**.
    ///
    /// `receiverCallExpression` renders an instance method as `{ $0.method($1) }`: the receiver is
    /// `$0` and the declared parameters start at `$1`. So the closure's arity is
    /// `parameters + 1`, and the composer supplying one value per *declared* parameter is short by
    /// exactly one — a guaranteed compile error (`missing argument for parameter #2`) for every
    /// such entry. Measured 2026-08-03: **7 of 126**, and all 7 survived the import fix because
    /// each had been failing on a missing type first.
    ///
    /// Gated on `isInstanceMethod && !isMutatingMethod` to match `receiverCallExpression`'s own
    /// condition exactly — a mutating method falls back to the positional trampoline and has no
    /// receiver argument, so widening this to `isInstanceMethod` alone would break the shape it
    /// was meant to fix.
    ///
    /// The receiver's type is `typeName` (the type the method is declared on), NOT
    /// `carrierTypeName` — which is the first *parameter's* type. On
    /// `ReducerPin.matches(_ c: ReducerCandidate)` those are `ReducerPin` and `ReducerCandidate`,
    /// and using the carrier would generate two candidates of the wrong type.
    static func effectiveParameterTypes(of inputs: Inputs) -> [String] {
        guard let receiver = inputs.receiverTypeName else { return inputs.parameterTypeNames }
        return [receiver] + inputs.parameterTypeNames
    }

    /// Declared parameters plus the implicit receiver, for the agreement check.
    static func expectedArity(of inputs: Inputs) -> Int {
        inputs.parameterCount + (inputs.receiverTypeName == nil ? 0 : 1)
    }

    /// Resolve one generator per parameter type.
    ///
    /// **Falls back to the single-carrier form whenever the signature is not fully recorded.**
    /// An empty `parameterTypeNames` is a pre-2026-08-03 index, and a count that disagrees with
    /// `parameterCount` means labels and types were derived from different places — in either
    /// case the honest move is the old behaviour, which fails to compile with a message naming the
    /// missing argument, rather than a guessed generator that fails somewhere less legible.
    static func totalityOperands(
        inputs: Inputs,
        recipe: GeneratorRecipe
    ) throws -> TotalityOperands {
        let types = effectiveParameterTypes(of: inputs)
        // The SAME whole-module resolver `emit` builds for the carrier. Omitting it was a real
        // cost, measured the day this shipped: five n-ary laws over `FunctionSummary` declined
        // with `unsupported-carrier` for a type that is in `typeShapes` and derives fine on the
        // unary path — which is handed an already-resolved recipe and so never noticed. Anything
        // that re-resolves must re-resolve with the same resolver.
        let resolver = inputs.allShapes.isEmpty
            ? nil
            : GeneratorResolver(types: inputs.allShapes.values.map { $0.toKitShape() })
        let resolve = resolver?.customTypeGenerator ?? { _ in nil }
        guard types.count > 1, types.count == expectedArity(of: inputs) else {
            return TotalityOperands(
                declarations: """
                let defaultGenerator: Generator<\(recipe.carrierTypeName), some SendableSequenceType> =
                    \(recipe.expression)
                """,
                drawStatements: "    let candidate = defaultGenerator.run(using: &rng)",
                inputExpression: "candidate",
                argumentList: "candidate"
            )
        }

        var declarations: [String] = []
        var draws: [String] = []
        var names: [String] = []
        for (offset, typeText) in types.enumerated() {
            // Each parameter is resolved on its own, through the same path the carrier took.
            // A parameter the strategist cannot derive throws here and the whole entry declines —
            // which is right: a law that can only generate half its arguments is not a law.
            // A PARAMETER type needs the same nested-carrier qualification the generator
            // carrier gets. `e5731a9` fixed the carrier and stopped there, and the gap was
            // invisible until a nested type turned up in the parameter position rather than
            // the carrier position: the strategist qualifies the VALUES it composes
            // (`Gen.always(RefutedExpectation.Coverage.notApplicable)`) from the shape it was
            // handed, while the type ANNOTATION is written from `carrierTypeName` — so the
            // stub read `Generator<Coverage, …>` and failed with *cannot find type 'Coverage'
            // in scope*. Measured as 1 of the 3 `build-failed` picks in
            // `roadtest-self-dogfood-2026-08-08.md` §9.2.
            let qualifiedTypeText = SwiftInferCommand.Verify.qualifyingNestedCarrier(
                typeText,
                in: inputs.allShapes
            )
            // Prefer the qualified key: `TypeShapeBuilder` groups `allShapes` by
            // `TypeDecl.qualifiedName`, so a bare lookup MISSES every nested type and the
            // strategist then derives without a shape. The bare fallback keeps the previous
            // behaviour for everything the qualifier leaves alone.
            let parameterRecipe = try resolveRecipe(
                carrier: qualifiedTypeText,
                typeShape: inputs.allShapes[qualifiedTypeText]
                    ?? inputs.allShapes[RoundTripPairResolver.bareTypeName(from: typeText)],
                resolve: resolve
            )
            let name = "candidate\(offset)"
            names.append(name)
            declarations.append("""
            let generator\(offset): Generator<\(parameterRecipe.carrierTypeName), some SendableSequenceType> =
                \(parameterRecipe.expression)
            """)
            draws.append("    let \(name) = generator\(offset).run(using: &rng)")
        }
        return TotalityOperands(
            declarations: declarations.joined(separator: "\n"),
            drawStatements: draws.joined(separator: "\n"),
            // Printed as a tuple so one marker still names the whole counterexample — the parser
            // reads one `VERIFY_TRIAL_INPUT` line and must not have to know the arity.
            inputExpression: "(\(names.joined(separator: ", ")))",
            argumentList: names.joined(separator: ", ")
        )
    }
}
