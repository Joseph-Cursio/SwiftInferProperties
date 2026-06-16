import Foundation

// V1.59.A / V1.69.B — curated generator recipes for OrderedCollections
// carriers the kit's `DerivationStrategist` returns `.todo` on.
// Extracted from `StrategistDispatchEmitter.swift` in V1.69.B when the
// three nested-OC scaffold entries pushed `curatedOCRecipe`'s switch
// over SwiftLint's function-body cap; reshaped as a lookup table over
// two shared expression builders.
extension StrategistDispatchEmitter {

    /// V1.59.A — curated recipe for an OC wrapper-around-Array carrier
    /// the kit's strategist doesn't recognize, or `nil` if the carrier
    /// has no curated entry. Each recipe returns a `Generator<Carrier,
    /// some SendableSequenceType>`-typed expression the V1.47.E composers
    /// drop into the stub's `defaultGenerator` slot.
    ///
    /// **Generator determinism**: each expression runs inside
    /// `Gen<Int>.int(...).map { ... }`, so the outer `Gen` is the only
    /// randomness and the `.map` closure must be pure — this keeps the
    /// v1.42 Xoshiro seed → outcome chain deterministic.
    ///
    /// **Sample-coverage scope**: each recipe produces a fixed 4-element
    /// collection `{n, n+1, n+2, n+3}` (or a view of one). Modest
    /// variety per trial, but the 100-trial budget covers n ∈ [0, 100],
    /// i.e. 100 distinct collections.
    static func curatedOCRecipe(carrier: String) -> GeneratorRecipe? {
        curatedOCRecipes[carrier]
    }

    /// Shared import set for every curated OC recipe.
    private static let ocImports = ["Foundation", "OrderedCollections", "PropertyBased"]

    /// `Gen<Int>` source producing a fresh 4-element `OrderedSet<Int>`,
    /// with `viewSuffix` (`""`, `".unordered"`, `"[...]"`) projecting the
    /// view under test.
    private static func ocSetExpression(viewSuffix: String) -> String {
        "Gen<Int>.int(in: 0 ... 100).map { "
            + "OrderedSet([$0, $0 + 1, $0 + 2, $0 + 3])\(viewSuffix) }"
    }

    /// `Gen<Int>` source producing a fresh 4-key `OrderedDictionary<Int,
    /// Int>`, with `viewSuffix` (`".elements"`, `".values"`,
    /// `".elements[...]"`) projecting the view under test.
    ///
    /// The `OrderedDictionary<Int, Int>(...)` construction is bound to a
    /// concretely-typed local before the view is projected: the
    /// single-expression form with an inline 4-tuple literal *plus* a
    /// `.elements[...]` slice overloads the Swift type-checker
    /// ("unable to type-check this expression in reasonable time").
    private static func ocDictExpression(viewSuffix: String) -> String {
        "Gen<Int>.int(in: 0 ... 100).map { seed in "
            + "let dict = OrderedDictionary<Int, Int>(uniqueKeysWithValues: ["
            + "(seed, seed * 2), (seed + 1, (seed + 1) * 2), "
            + "(seed + 2, (seed + 2) * 2), (seed + 3, (seed + 3) * 2)]); "
            + "return dict\(viewSuffix) }"
    }

    /// The curated OC recipe table, keyed by bound carrier name.
    /// V1.69.B added the three nested-OC view carriers (`.SubSequence` /
    /// `.Values` / `.Elements.SubSequence`) so their `index(after:)` /
    /// `index(before:)` monotonicity picks resolve a receiver generator.
    private static let curatedOCRecipes: [String: GeneratorRecipe] = [
        // V1.59.A — first OC carrier.
        "OrderedSet<Int>": GeneratorRecipe(
            expression: ocSetExpression(viewSuffix: ""),
            carrierTypeName: "OrderedSet<Int>",
            imports: ocImports
        ),
        // V1.62.A — UnorderedView, reached via `.unordered` on a base
        // OrderedSet.
        "OrderedSet<Int>.UnorderedView": GeneratorRecipe(
            expression: ocSetExpression(viewSuffix: ".unordered"),
            carrierTypeName: "OrderedSet<Int>.UnorderedView",
            imports: ocImports
        ),
        // V1.69.B — full-range slice; `OrderedSet` is a
        // RandomAccessCollection so `[...]` projects its `SubSequence`.
        "OrderedSet<Int>.SubSequence": GeneratorRecipe(
            expression: ocSetExpression(viewSuffix: "[...]"),
            carrierTypeName: "OrderedSet<Int>.SubSequence",
            imports: ocImports
        ),
        // Cycle 149 (Lever C-1) — the bare OrderedDictionary carrier. The
        // `.Elements` / `.Values` / `.SubSequence` views were registered
        // first (V1.63.A / V1.69.B), but the dictionary itself had no
        // recipe, so its `merge(_:uniquingKeysWith:)` dual-style and
        // `sort()` idempotence picks stalled at `unsupported-carrier:
        // OrderedDictionary`. `viewSuffix: ""` returns the whole `dict`.
        "OrderedDictionary<Int, Int>": GeneratorRecipe(
            expression: ocDictExpression(viewSuffix: ""),
            carrierTypeName: "OrderedDictionary<Int, Int>",
            imports: ocImports
        ),
        // V1.63.A — OrderedDictionary's `.elements` key-value-pair view.
        "OrderedDictionary<Int, Int>.Elements": GeneratorRecipe(
            expression: ocDictExpression(viewSuffix: ".elements"),
            carrierTypeName: "OrderedDictionary<Int, Int>.Elements",
            imports: ocImports
        ),
        // V1.69.B — the `.values` view; a RandomAccessCollection with
        // `Index == Int`.
        "OrderedDictionary<Int, Int>.Values": GeneratorRecipe(
            expression: ocDictExpression(viewSuffix: ".values"),
            carrierTypeName: "OrderedDictionary<Int, Int>.Values",
            imports: ocImports
        ),
        // V1.69.B — full-range slice of the `.elements` view.
        "OrderedDictionary<Int, Int>.Elements.SubSequence": GeneratorRecipe(
            expression: ocDictExpression(viewSuffix: ".elements[...]"),
            carrierTypeName: "OrderedDictionary<Int, Int>.Elements.SubSequence",
            imports: ocImports
        )
    ]
}
