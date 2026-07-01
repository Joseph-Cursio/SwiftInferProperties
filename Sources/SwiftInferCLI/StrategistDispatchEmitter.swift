import Foundation
import PropertyLawCore
import SwiftInferCore

/// V1.47.E — verify-time stub emitter that consumes a SemanticIndexEntry's
/// `IndexedTypeShape` (V1.47.A) + carrier name, invokes
/// `DerivationStrategist.strategy(for:)`, and emits the per-strategy
/// generator code wired into the standard 4-template stub shape
/// (round-trip / idempotence / commutativity / associativity).
///
/// **Scope contract.** The strategist path handles carriers the v1.46
/// hardcoded path doesn't — Int (via the strategist's direct-raw map
/// instead of the v1.46 `CarrierKind`), String, Bool, fixed-width
/// integers, and `.caseIterable` / `.userGen` / `.rawRepresentable`
/// enums. `Complex<Double>` and `Double` stay on the v1.46 path
/// because their edge-pass intelligence (12-entry curated `Complex`
/// edges; inlined `doubleWithNaN`) lives outside the strategist's
/// raw-type surface — see the V1.47.F router for the carrier-name
/// split. The `.memberwiseArbitrary` and lifted-form
/// `.rawRepresentable` strategies fall through to `.error` in v1.47;
/// cycle-44 evidence will guide which (if any) lands in v1.48.
///
/// **Single-pass output.** Strategist-routed carriers are all
/// integral or `String` — there's no `NaN`/`Inf` semantic, so Pass 2
/// emits the V1.44.B/C zero-edge sentinel directly (matching the v1.46
/// Int path). The marker contract is preserved unchanged so
/// `VerifyResultParser` reads strategist-routed output identically.
public enum StrategistDispatchEmitter: SeededStubEmitter {

    /// Seed-hex format shared with the v1.46 emitters.
    public typealias SeedHex = RoundTripStubEmitter.SeedHex

    /// Trial budget shared with the v1.46 emitters.
    public typealias TrialBudget = RoundTripStubEmitter.TrialBudget

    /// Inputs to the emitter — carrier + typeShape + template +
    /// per-template function call expressions.
    public struct Inputs: Equatable, Sendable {
        /// Bound carrier name — already passed through
        /// `GenericBindingResolver.bound(_:)` so generic associated
        /// types are resolved before they reach the strategist.
        public let carrier: String

        /// JSON-encodable mirror of the kit's `TypeShape`, when the
        /// indexer captured one. `nil` when the carrier is a stdlib
        /// raw type the indexer doesn't record TypeShapes for
        /// (Int / String / Bool / …) — the emitter detects raw-type
        /// carriers by name and skips the strategist call.
        public let typeShape: IndexedTypeShape?

        /// WS-6 Slice 2 — the whole-module shape universe (every scanned type,
        /// keyed by bare name), from the persisted index root. When non-empty,
        /// `resolveRecipe` builds a `GeneratorResolver` over it and passes the
        /// recursive resolver to the strategist, so a carrier whose members /
        /// init-params are nested custom types derives instead of `.todo`.
        /// Empty (the default) preserves the pre-WS-6 single-shape behavior.
        public let allShapes: [String: IndexedTypeShape]

        /// One of `"round-trip"`, `"idempotence"`, `"commutativity"`,
        /// `"associativity"`. Each template selects a per-trial
        /// value-count + per-trial property-check shape.
        public let template: String

        /// Template-specific call expressions. For round-trip:
        /// `[forwardCall, inverseCall]`. For idempotence /
        /// commutativity / associativity: `[functionCall]` — one
        /// expression invoked 2× / 3× per trial respectively.
        public let functionCalls: [String]

        /// Extra imports beyond the carrier-derived defaults.
        public let extraImports: [String]

        /// Xoshiro seed components.
        public let seedHex: SeedHex

        /// Trial count for Pass 1.
        public let trialBudget: TrialBudget

        /// V1.49.A — verbatim Swift source rendered between the
        /// imports + the `var rng = ...` line. See
        /// `RoundTripStubEmitter.Inputs.preamble` for the load-bearing docstring.
        public let preamble: String

        public init(
            carrier: String,
            typeShape: IndexedTypeShape?,
            template: String,
            functionCalls: [String],
            extraImports: [String] = [],
            seedHex: SeedHex,
            trialBudget: TrialBudget,
            preamble: String = "",
            allShapes: [String: IndexedTypeShape] = [:]
        ) {
            self.carrier = carrier
            self.typeShape = typeShape
            self.template = template
            self.functionCalls = functionCalls
            self.extraImports = extraImports
            self.seedHex = seedHex
            self.trialBudget = trialBudget
            self.preamble = preamble
            self.allShapes = allShapes
        }
    }

    /// Emit a strategist-routed verify stub. Resolves the strategy,
    /// composes the generator expression, and wraps it in the
    /// template-specific stub shape.
    public static func emit(_ inputs: Inputs) throws -> String {
        // WS-6 Slice 2 — build the whole-module resolver once per emit when the
        // index carried the shape universe. Nil (empty universe) → the strategist
        // sees the pre-WS-6 default `{ _ in nil }` resolver.
        let resolver = inputs.allShapes.isEmpty
            ? nil
            : GeneratorResolver(types: inputs.allShapes.values.map { $0.toKitShape() })
        let recipe = try resolveRecipe(
            carrier: inputs.carrier,
            typeShape: inputs.typeShape,
            resolve: resolver?.customTypeGenerator ?? { _ in nil }
        )
        let trials = inputs.trialBudget.count
        let header = headerSection(inputs: inputs, recipe: recipe)
        let importsBlock = mergedImports(base: recipe.imports, extra: inputs.extraImports)
        let setup = setupSection(
            importsBlock: importsBlock,
            seed: inputs.seedHex,
            trials: trials,
            preamble: inputs.preamble
        )
        let defaultPass = try defaultPassSection(inputs: inputs, recipe: recipe)
        let edgeSentinel = edgeSentinelSection()
        return [header, setup, defaultPass, edgeSentinel].joined(separator: "\n\n")
    }

    // MARK: - Strategy resolution

    /// Per-strategy emission recipe — the generator expression the stub
    /// invokes per trial, plus any extra imports + the carrier's bound
    /// type name (the bound form after the binding resolver fires).
    struct GeneratorRecipe: Equatable {
        let expression: String
        let carrierTypeName: String
        let imports: [String]
    }

    /// Decide which strategy applies, build the recipe. Lookup order:
    ///   1. Carrier matches a stdlib `RawType` directly → emit that
    ///      raw type's generator expression. No strategist call —
    ///      `typeShape` may be nil (typical for raw-type carriers).
    ///   2. `typeShape` present → call the strategist and dispatch on
    ///      its result.
    ///   3. Neither → `.noStrategy`.
    static func resolveRecipe(
        carrier: String,
        typeShape: IndexedTypeShape?,
        resolve: DerivationStrategist.CustomTypeResolver = { _ in nil }
    ) throws -> GeneratorRecipe {
        if let rawType = RawType(typeName: carrier) {
            // V1.54.C — add `RealModule` for FP carriers so the static
            // `Double.log(_:)` / `Float.log(_:)` etc. forms declared
            // by `ElementaryFunctions` resolve. Cycle-51 measurement
            // (`docs/calibration-cycle-51-findings.md`) showed that
            // without this import, V1.54.A's free-function revert
            // breaks the 2 monotonicity-on-Double picks that were
            // `.bothPass` in cycle-50 (the v1.42 `Foundation` import
            // exposes Darwin's C `log(_:)` free function but not the
            // protocol's static methods).
            let imports = (carrier == "Double" || carrier == "Float")
                ? ["Foundation", "PropertyBased", "RealModule"]
                : ["Foundation", "PropertyBased"]
            // V1.150 — edge-bias the *top-level* String carrier. The kit's raw
            // `Gen<Character>.letterOrNumber.string` is alphanumeric-only, so it
            // never generates the whitespace / newline / punctuation inputs that
            // falsify string-structural logic (YAML markers, indentation, etc.) —
            // a determinism/idempotence check on such a function *false-passes*.
            // Mixing in curated structural edge strings makes those counterexamples
            // reachable. Struct *members* keep the plain generator (they resolve
            // via `member.generatorExpression`, not this path). Canonical home is
            // `PropertyLawCore.DerivationStrategist`; upstream when that lands.
            let expression = edgeBiasedStringExpression(for: carrier) ?? rawType.generatorExpression
            return GeneratorRecipe(
                expression: expression,
                carrierTypeName: carrier,
                imports: imports
            )
        }
        // V1.59.A — curated OC carrier recipes. Short-circuits before
        // the kit-side strategy call for carriers the strategist's
        // `DerivationStrategist.strategy(for:)` returns `.todo` on
        // (wrapper-around-Array types like `OrderedSet<Int>`). v1.59
        // ships with one entry; v1.60+ extends to `OrderedDictionary<Int, Int>`,
        // `_HashTable`, `ChunkedByCollection<Array<Int>>`, etc.
        // See `docs/calibration-cycle-55-findings.md`.
        if let curated = curatedOCRecipe(carrier: carrier) {
            return curated
        }
        if let typeShape {
            // WS-6 Slice 2 — `resolve` recurses through the whole-module shape
            // universe so nested custom-type members / init-params derive; the
            // default `{ _ in nil }` preserves single-shape behavior.
            let strategy = DerivationStrategist.strategy(for: typeShape.toKitShape(), resolve: resolve)
            return try recipe(for: strategy, carrier: carrier)
        }
        // WS-6 follow-up — top-level *composite* carrier. A carrier without its
        // own indexed TypeShape may still be a composite spelling (`[Rule]`,
        // `Rule?`, `[K: V]`) whose element/leaf types live in the resolver's
        // universe. The kit's `composedGenerator` (public since
        // SwiftPropertyLaws 3.3.0) recurses through Optional/Array/Set/Dictionary
        // and hands leaf custom types to `resolve` — the same whole-module
        // resolver WS-6 threaded in. Fires only when there's no TypeShape (shaped
        // carriers took the branch above); an unresolvable leaf returns nil and
        // falls through to the `gen()` guidance below. With an empty universe the
        // default `{ _ in nil }` resolver yields nil for custom leaves, so a
        // pre-v4 index behaves exactly as before.
        if let composed = DerivationStrategist.composedGenerator(forTypeName: carrier, resolve: resolve) {
            return GeneratorRecipe(
                expression: composed.expression,
                carrierTypeName: carrier,
                imports: Array(Set(["Foundation", "PropertyBased"]).union(composed.requiredImports)).sorted()
            )
        }
        // WS-4 — no RawType and no indexed shape (an external/opaque carrier).
        // Point the user at the `gen()` escape hatch with the exact signature; a
        // same-file `extension \(carrier) { static func gen() }` in the scanned
        // target is picked up (TypeShapeBuilder emits a synthetic hasUserGen shape).
        throw VerifyError.unsupportedCarrier(
            carrier: carrier,
            expected: [
                "a RawType or a carrier with an indexed TypeShape",
                "or provide `static func gen() -> Generator<\(carrier), some SendableSequenceType>` "
                    + "(a same-file extension works for external types)"
            ]
        )
    }

    /// Translate a `DerivationStrategy` result into an emission
    /// recipe. Cases v1.47 supports: `.userGen`, `.caseIterable`,
    /// `.rawRepresentable` (enum-lifted form). Cases v1.47 defers:
    /// `.memberwiseArbitrary` (needs zip-composition emission;
    /// v1.48 candidate) and `.todo` (no strategy — error out).
    private static func recipe(
        for strategy: DerivationStrategy,
        carrier: String
    ) throws -> GeneratorRecipe {
        switch strategy {
        case .userGen:
            return GeneratorRecipe(
                expression: "\(carrier).gen()",
                carrierTypeName: carrier,
                imports: ["Foundation", "PropertyBased"]
            )

        case .caseIterable:
            // `Gen.element(of:)` is `Generator<C.Element?, _>` (nil on an empty
            // collection), so force-unwrap — `allCases` is non-empty. (Latent
            // until the first enum-carrier survey: cycle27 has none.)
            return GeneratorRecipe(
                expression: "Gen.element(of: \(carrier).allCases).map { $0! }",
                carrierTypeName: carrier,
                imports: ["Foundation", "PropertyBased"]
            )

        case let .rawRepresentable(rawType):
            let lifted = "\(rawType.generatorExpression).compactMap { "
                + "\(carrier)(rawValue: $0) }"
            return GeneratorRecipe(
                expression: lifted,
                carrierTypeName: carrier,
                imports: ["Foundation", "PropertyBased"]
            )

        case let .memberwiseArbitrary(members):
            return try memberwiseRecipe(members: members, carrier: carrier)

        case .initializerBased, .enumCases:
            // Tier 6 (user-init) and Tier 4 (enum payloads), v3.0.0. Render via
            // PropertyLawCore's canonical emitter rather than re-implement the
            // init-lift / `Gen.oneOf` shapes here.
            return GeneratorRecipe(
                expression: GeneratorExpressionEmitter.expression(typeName: carrier, strategy: strategy),
                carrierTypeName: carrier,
                imports: ["Foundation", "PropertyBased"]
            )

        case let .todo(reason):
            throw VerifyError.unsupportedCarrier(
                carrier: carrier,
                expected: ["strategist returned .todo: \(reason)"]
            )
        }
    }

    // MARK: - Stub composition

    /// Header comment block — names the strategist source, the chosen
    /// strategy summary, and the template under test.
    private static func headerSection(inputs: Inputs, recipe: GeneratorRecipe) -> String {
        """
        // V1.47.E — strategist-routed verify stub.
        // Template: \(inputs.template)
        // Carrier:  \(inputs.carrier) (bound to \(recipe.carrierTypeName))
        // Generator expression: \(recipe.expression)
        // Single-pass — integral/string carriers have no NaN/Inf semantic.
        """
    }

    /// Pass 1 emit — template-aware. Routes to the right per-template
    /// composer (1/2/3 values per trial).
    private static func defaultPassSection(
        inputs: Inputs,
        recipe: GeneratorRecipe
    ) throws -> String {
        switch inputs.template {
        case "round-trip":
            return try composeRoundTripPass(inputs: inputs, recipe: recipe)

        case "idempotence":
            return composeIdempotencePass(inputs: inputs, recipe: recipe)

        case "commutativity":
            return composeCommutativityPass(inputs: inputs, recipe: recipe)

        case "associativity":
            return composeAssociativityPass(inputs: inputs, recipe: recipe)

        case "idempotence-lifted":
            return composeIdempotenceLiftedPass(inputs: inputs, recipe: recipe)

        case "dual-style-consistency":
            return try composeDualStyleConsistencyPass(inputs: inputs, recipe: recipe)

        case "monotonicity":
            return composeMonotonicityPass(inputs: inputs, recipe: recipe)

        default:
            throw VerifyError.unsupportedTemplate(
                template: inputs.template,
                expected: [
                    "round-trip", "idempotence", "commutativity", "associativity",
                    "idempotence-lifted", "dual-style-consistency", "monotonicity"
                ]
            )
        }
    }

    /// V1.44.B/C zero-edge sentinel. Strategist-routed carriers are
    /// integral or `String` — no NaN/Inf semantic, no edge pass needed.
    private static func edgeSentinelSection() -> String {
        """
        // --- Pass 2: edge-case-biased — n/a for strategist-routed carrier ---
        print("VERIFY_EDGE_RESULT: PASS")
        print("VERIFY_EDGE_TRIALS: 0")
        print("VERIFY_EDGE_SAMPLED: 0")
        exit(0)
        """
    }
}
