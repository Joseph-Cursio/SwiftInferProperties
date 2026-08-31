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
    /// **Sample-coverage scope** (widened 2026-08-08 — see
    /// `fixtures/ordered-set-generator/README.md`): each recipe draws a
    /// variable-length collection of 1–6 elements from `-100 ... 100`.
    ///
    /// It previously produced a fixed 4-element `{n, n+1, n+2, n+3}` over
    /// n ∈ [0, 100] — **101 reachable values**, every one four consecutive
    /// ascending non-negative integers. Three properties therefore held across
    /// the *entire* domain (fixed arity, never negative, always an arithmetic
    /// progression), and a subject depending on any of them was untestable.
    /// Measured with three mutants, one per property: all three survive the
    /// old domain **exhaustively** (all 101 values, so unreachable rather than
    /// merely unlikely) and all three are caught by this one — 0 of 3 → 3 of 3,
    /// gained 3, lost 0, with a correct-subject control holding on both.
    ///
    /// **The arity floor is 1, not the kit's 0, deliberately.** These recipes
    /// serve `index(after:)` / `index(before:)` monotonicity picks, and an empty
    /// receiver has no valid index to advance from; the trap would be read as
    /// `.measuredDefaultFails` against the subject — the conflation
    /// `docs/measurements/interaction-trap-attribution-census.md` exists to
    /// separate. The kit's `smallIntOrderedSet()` uses `0 ... 8` and is right
    /// for the Equatable/Hashable laws it serves. The stated cost is that an
    /// empty-collection mutant stays unreachable here.
    ///
    /// **What this does NOT buy**: the `OrderedSet` order projection. That law
    /// can only fail on a pair colliding on its element set while differing in
    /// order, which independent draws essentially never produce — the
    /// collision-dependence rule, which binds the kit's generator just as hard.
    /// The lever there is a permuting *pair sampler* in the harness, not a wider
    /// element generator (falsifier: `Pairing.permuted` reaching an emitted
    /// stub).
    static func curatedOCRecipe(carrier: String) -> GeneratorRecipe? {
        curatedOCRecipes[carrier] ?? curatedOCRecipesByBareName[unspecialised(carrier)]
    }

    /// The same table keyed by the carrier's name with generic arguments stripped —
    /// `OrderedDictionary<Int, Int>.Elements` → `OrderedDictionary.Elements`.
    ///
    /// ⚠ **THE TABLE IS KEYED ON A SPELLING PRODUCTION NEVER PRODUCES, AND THAT MADE IT
    /// UNREACHABLE.** Discovery records a carrier as its declaring type's name, unspecialised.
    /// **Measured 2026-08-30 on `swift-collections`: of 34 distinct carriers in the
    /// `monotonicity` rows, ZERO contain `<`** — so every entry above could only ever be found
    /// by a caller that already knew the element type, which is what the emitter tests do and
    /// what discovery cannot. `docs/measurements/instance-method-shape-census.md` §7.
    ///
    /// The evidence was in the table's own comments before it was measured: the
    /// `OrderedDictionary<Int, Int>` entry was added because picks *"stalled at
    /// `unsupported-carrier: OrderedDictionary`"* — **the unspecialised spelling, named in the
    /// decline it was meant to fix** — and adding a specialised key could not answer an
    /// unspecialised lookup.
    ///
    /// **DERIVED, never written out.** Writing the bare forms by hand would let the two drift,
    /// which is the defect in mirror image. **Exact lookup is tried first**, so a caller that
    /// does supply `OrderedSet<Int>` is bit-identical to before.
    ///
    /// **Checked for collisions**: the 8 entries produce 8 distinct bare names.
    private static let curatedOCRecipesByBareName: [String: GeneratorRecipe] =
        Dictionary(curatedOCRecipes.map { (unspecialised($0.key), $0.value) }) { first, _ in first }

    /// A type name with its generic arguments removed, at any nesting depth.
    static func unspecialised(_ carrier: String) -> String {
        var result = ""
        var depth = 0
        for character in carrier {
            if character == "<" { depth += 1; continue }
            if character == ">" { depth = max(0, depth - 1); continue }
            if depth == 0 { result.append(character) }
        }
        return result
    }

    /// The carriers this table answers for, sorted.
    ///
    /// Exists so `CuratedRecipePremiseTests` can read the population **out of
    /// the table** rather than restate it — a guard that restates what it guards
    /// only checks that two copies agree. Adding a curated entry therefore
    /// enrols it in the premise check automatically.
    static var curatedOCRecipeCarriers: [String] {
        curatedOCRecipes.keys.sorted()
    }

    /// Shared import set for every curated OC recipe.
    private static let ocImports = ["Foundation", "OrderedCollections", "PropertyBased"]

    /// `Gen<Int>` source producing a fresh 1–6 element `OrderedSet<Int>`, with
    /// `viewSuffix` (`""`, `".unordered"`, `"[...]"`) projecting the view under
    /// test.
    ///
    /// Duplicates in the drawn array collapse on insert, so the realised count
    /// can fall below the drawn one — which is the point, since it is the only
    /// way this recipe reaches a 1- or 2-element `OrderedSet` at all often.
    private static func ocSetExpression(viewSuffix: String) -> String {
        "Gen<Int>.int(in: -100 ... 100).array(of: 1 ... 6).map { "
            + "OrderedSet($0)\(viewSuffix) }"
    }

    /// `Gen<Int>` source producing a fresh 4-key `OrderedDictionary<Int,
    /// Int>`, with `viewSuffix` (`".elements"`, `".values"`,
    /// `".elements[...]"`) projecting the view under test.
    ///
    /// The `OrderedDictionary<Int, Int>(...)` construction is bound to a
    /// concretely-typed local before the view is projected: the
    /// single-expression form with an inline tuple literal *plus* a
    /// `.elements[...]` slice overloads the Swift type-checker
    /// ("unable to type-check this expression in reasonable time").
    ///
    /// **The `OrderedSet` round-trip on the keys is load-bearing, not tidiness.**
    /// `uniqueKeysWithValues:` has a precondition that the keys are distinct and
    /// **traps** when they are not. The old recipe drew one seed and derived
    /// four distinct keys from it arithmetically, so uniqueness was free; a
    /// drawn array can repeat, so the keys are deduplicated before the pairs are
    /// built. Without this, widening the domain would convert a generator into a
    /// crash — and `InteractionVerifyOutcomeParser` maps any non-zero exit to
    /// `.measuredDefaultFails`, so it would have surfaced as the subject being
    /// refuted rather than as a broken harness.
    private static func ocDictExpression(viewSuffix: String) -> String {
        "Gen<Int>.int(in: -100 ... 100).array(of: 1 ... 6).map { seeds in "
            + "let keys = OrderedSet(seeds); "
            + "let dict = OrderedDictionary<Int, Int>("
            + "uniqueKeysWithValues: keys.map { ($0, $0 * 2) }); "
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
        ),
        // Collections/async workplan Phase 1 M4 — Deque<Int>, previously
        // the one swift-collections calibration type with no recipe (its
        // picks stalled at `unsupported-carrier: Deque`). Lives in
        // DequeModule, not OrderedCollections, hence its own import set;
        // the `.algebraic` workdir manifest declares the product.
        // Widened with the OC recipes 2026-08-08. `Deque` keeps duplicates —
        // it is a sequence, not a set — so the drawn array maps across
        // unchanged and the realised count always equals the drawn one.
        "Deque<Int>": GeneratorRecipe(
            expression: "Gen<Int>.int(in: -100 ... 100).array(of: 1 ... 6).map { "
                + "Deque($0) }",
            carrierTypeName: "Deque<Int>",
            imports: ["Foundation", "DequeModule", "PropertyBased"]
        )
    ]
}
