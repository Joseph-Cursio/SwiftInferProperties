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
public enum StrategistDispatchEmitter {

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
            preamble: String = ""
        ) {
            self.carrier = carrier
            self.typeShape = typeShape
            self.template = template
            self.functionCalls = functionCalls
            self.extraImports = extraImports
            self.seedHex = seedHex
            self.trialBudget = trialBudget
            self.preamble = preamble
        }
    }

    /// Emit a strategist-routed verify stub. Resolves the strategy,
    /// composes the generator expression, and wraps it in the
    /// template-specific stub shape.
    public static func emit(_ inputs: Inputs) throws -> String {
        let recipe = try resolveRecipe(carrier: inputs.carrier, typeShape: inputs.typeShape)
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
        typeShape: IndexedTypeShape?
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
            return GeneratorRecipe(
                expression: rawType.generatorExpression,
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
            let strategy = DerivationStrategist.strategy(for: typeShape.toKitShape())
            return try recipe(for: strategy, carrier: carrier)
        }
        throw VerifyError.unsupportedCarrier(
            carrier: carrier,
            expected: ["any RawType, or any carrier with an indexed TypeShape"]
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
            return GeneratorRecipe(
                expression: "Gen<\(carrier)>.element(of: \(carrier).allCases)",
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
        case let .todo(reason):
            throw VerifyError.unsupportedCarrier(
                carrier: carrier,
                expected: ["strategist returned .todo: \(reason)"]
            )
        }
    }

    /// V1.49.B — emit recipe for the strategist's `.memberwiseArbitrary`
    /// case. For 1-member structs, emits `<rawTypeExpr>.map { T(name: $0) }`
    /// (no zip — `Gen` already has `.map` directly). For 2-N member
    /// structs (2 ≤ N ≤ 10), emits `zip(g1, g2, ..., gN).map { (m1, ..., mN) in
    /// T(name1: m1, name2: m2, ..., nameN: mN) }` — swift-property-based
    /// ships `zip` overloads for arities 2–10 per the kit's
    /// `Generator+Zip.swift`. Arity ≥ 11 throws — but the strategist's
    /// `memberwiseStrategy(for:)` already filters those into `.todo`,
    /// so v1.49.B's guard is defensive.
    private static func memberwiseRecipe(
        members: [MemberSpec],
        carrier: String
    ) throws -> GeneratorRecipe {
        guard !members.isEmpty else {
            throw VerifyError.unsupportedCarrier(
                carrier: carrier,
                expected: [
                    ".memberwiseArbitrary with empty members "
                        + "(strategist's memberwiseStrategy should never return this; "
                        + "v1.49.B defensive guard)"
                ]
            )
        }
        guard members.count <= DerivationStrategist.memberwiseArityLimit else {
            throw VerifyError.unsupportedCarrier(
                carrier: carrier,
                expected: [
                    ".memberwiseArbitrary arity \(members.count) > "
                        + "memberwiseArityLimit \(DerivationStrategist.memberwiseArityLimit) "
                        + "(strategist should have filtered to .todo; "
                        + "v1.49.B defensive guard)"
                ]
            )
        }
        if members.count == 1 {
            return memberwiseRecipeSingle(member: members[0], carrier: carrier)
        }
        return memberwiseRecipeMulti(members: members, carrier: carrier)
    }

    /// 1-member memberwise emit. Uses `.map` directly (no zip needed).
    private static func memberwiseRecipeSingle(
        member: MemberSpec,
        carrier: String
    ) -> GeneratorRecipe {
        let expression = "\(member.rawType.generatorExpression).map { "
            + "\(carrier)(\(member.name): $0) }"
        return GeneratorRecipe(
            expression: expression,
            carrierTypeName: carrier,
            imports: ["Foundation", "PropertyBased"]
        )
    }

    /// 2–10 member memberwise emit. Uses `zip(...)` from
    /// swift-property-based + a tuple-destructuring `.map`.
    private static func memberwiseRecipeMulti(
        members: [MemberSpec],
        carrier: String
    ) -> GeneratorRecipe {
        let generators = members
            .map { $0.rawType.generatorExpression }
            .joined(separator: ", ")
        let bindings = (0 ..< members.count)
            .map { "m\($0)" }
            .joined(separator: ", ")
        let constructorArgs = members
            .enumerated()
            .map { offset, spec in "\(spec.name): m\(offset)" }
            .joined(separator: ", ")
        let expression = "zip(\(generators)).map { (\(bindings)) in "
            + "\(carrier)(\(constructorArgs)) }"
        return GeneratorRecipe(
            expression: expression,
            carrierTypeName: carrier,
            imports: ["Foundation", "PropertyBased"]
        )
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

    /// Imports + optional V1.49.A preamble + Xoshiro RNG seeded from
    /// the V1.7.5 identity hash + trial count.
    private static func setupSection(
        importsBlock: String,
        seed: SeedHex,
        trials: Int,
        preamble: String = ""
    ) -> String {
        let preambleBlock = preamble.isEmpty ? "" : "\n\(preamble)\n"
        return """
        \(importsBlock)
        \(preambleBlock)
        var rng: any SeededRandomNumberGenerator = Xoshiro(seed: (
            0x\(hex(seed.stateA)),
            0x\(hex(seed.stateB)),
            0x\(hex(seed.stateC)),
            0x\(hex(seed.stateD))
        ))

        let trials = \(trials)
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

    // MARK: - Helpers

    static func mergedImports(base: [String], extra: [String]) -> String {
        let extraTrimmed = extra
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let combined = Set(base + extraTrimmed).sorted()
        return combined.map { "import \($0)" }.joined(separator: "\n")
    }

    static func hex(_ word: UInt64) -> String {
        String(word, radix: 16, uppercase: true)
    }
}
