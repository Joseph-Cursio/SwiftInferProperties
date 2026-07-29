import PropertyLawCore

// Recursive-carrier support, split out of `StrategistDispatchEmitter` to keep
// that file under the 400-line gate.
//
// A recursive type is the one shape the generator resolver cannot inline: its
// expression would have to contain itself. The kit answers with a
// depth-budgeted helper `func` (`RecursiveGeneratorEmitter`); this side decides
// when to reach for it and makes sure the declaration lands above its use.
extension StrategistDispatchEmitter {

    /// Wrap a recursive carrier's expression into its depth-budgeted helper.
    ///
    /// `GeneratorResolver` does this for *nested* types, but the top-level
    /// carrier does not go through `derive` — it goes through
    /// `DerivationStrategist.strategy(for:resolve:)`, whose members resolve via
    /// the closure and therefore come back already carrying the recursion
    /// point. Without this the stub would emit `__genNode(budget - 1)` with no
    /// `__genNode` in scope and no `budget` either: a compile error that
    /// surfaces downstream as `measured-error: build-failed`, which reads as an
    /// architectural limit rather than a codegen bug.
    static func liftingRecursion(
        _ recipe: GeneratorRecipe,
        carrier: String
    ) -> GeneratorRecipe {
        guard RecursiveGeneratorEmitter.isRecursive(
            expression: recipe.expression,
            typeName: carrier
        ) else {
            return recipe
        }
        guard let declaration = RecursiveGeneratorEmitter.declaration(
            typeName: carrier,
            expression: recipe.expression
        ) else {
            return recipe   // no wrapper to terminate on — left to fail loudly
        }
        return GeneratorRecipe(
            expression: "\(RecursiveGeneratorEmitter.helperName(for: carrier))"
                + "(\(GeneratorPlan.defaultDepthBudget))",
            carrierTypeName: recipe.carrierTypeName,
            imports: recipe.imports,
            declarations: [declaration]
        )
    }

    /// Attach any recursive helper `func`s the resolver built while deriving
    /// this carrier.
    ///
    /// The declaration is produced deep inside resolution, and the plan tree
    /// carrying it does **not** survive the strategy layer — a nested type's
    /// declaration is flattened away the moment it becomes a
    /// `MemberSpec.generatorExpression` string. So ask the resolver what it
    /// built rather than trying to recover it from the rendered expression.
    static func withRecursiveHelpers(
        _ recipe: GeneratorRecipe,
        resolver: GeneratorResolver?,
        carrier: String
    ) -> GeneratorRecipe {
        guard let resolver, !resolver.supportingDeclarations.isEmpty else { return recipe }
        // When the CARRIER itself is recursive, call its helper directly.
        // Composing it memberwise instead would work, but nests one level
        // deeper than the budget says and reads as an off-by-one.
        let expression = resolver.isRecursive(carrier)
            ? "\(RecursiveGeneratorEmitter.helperName(for: carrier))"
                + "(\(GeneratorPlan.defaultDepthBudget))"
            : recipe.expression
        return GeneratorRecipe(
            expression: expression,
            carrierTypeName: recipe.carrierTypeName,
            imports: recipe.imports,
            declarations: resolver.supportingDeclarations
        )
    }
}
