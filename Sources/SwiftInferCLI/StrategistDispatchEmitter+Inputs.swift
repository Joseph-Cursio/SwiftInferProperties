import Foundation
import SwiftInferCore

/// `StrategistDispatchEmitter.Inputs` — everything one verify-stub emission
/// needs. Split from the emitter itself so the emitter file stays under the
/// 400-line cap.
///
/// Most fields are callee-shape signals read off the SemanticIndex. They exist
/// because the same law needs a different *call* depending on what the callee
/// is: a free function is applied directly, a mutating method needs a `var`
/// copy, a self-returning method chains on the receiver. Getting this wrong
/// does not produce a wrong verdict — it produces a stub that will not compile.
extension StrategistDispatchEmitter {

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

        /// Callee-shape signals (from the SemanticIndex) that select the
        /// instance-method idempotence emit shape: `receiver.method()`
        /// (mutating) or `value.method().method()` (self-returning) instead
        /// of the static `Type.method(value)`. All default `false`.
        public let isInstanceMethod: Bool
        public let isMutatingMethod: Bool
        public let isNullary: Bool
        public let returnsSelfType: Bool
        /// Recall epic #1 — emit a property access (`value.name`) not a call.
        public let isComputedProperty: Bool

        /// How many parameters the callee declares. `isNullary` answers only
        /// "zero or not", which is enough to pick the *nullary* instance shapes
        /// but not enough to emit a call for the non-nullary ones: a receiver
        /// closure for a 1-parameter method (`{ $0.merge($1) }`) takes two
        /// operands, one for 2 parameters takes three, and the composer has to
        /// supply exactly that many generated values. Defaults to `0`, which
        /// keeps every pre-existing call site emitting exactly what it did.
        public let parameterCount: Int

        /// Each parameter's type as written, in declaration order.
        ///
        /// `parameterCount` says how many; this says what. A law over `f(_ a: A, _ b: B)` needs a
        /// generator per parameter, and until 2026-08-03 nothing carried `B` at all — 19 of 126
        /// `predicate` entries failed to compile as `missing argument for parameter #2`.
        ///
        /// Empty means *not recorded* (a pre-2026-08-03 index, or a hand-built `Inputs`), and
        /// every composer falls back to the single-carrier form it used before.
        public let parameterTypeNames: [String]

        /// The type an instance method is called ON, when the emitted call has a receiver — and
        /// `nil` otherwise, so the gate is decided once here rather than re-derived at each use.
        ///
        /// `receiverCallExpression` renders `{ $0.method($1) }`, making the receiver an implicit
        /// first argument. A composer that supplies one value per *declared* parameter is short
        /// by one for every such law. Set only when `isInstanceMethod && !isMutatingMethod`,
        /// matching that function's own condition — a mutating method takes the positional
        /// trampoline and has no receiver argument.
        public let receiverTypeName: String?

        public init(
            carrier: String,
            typeShape: IndexedTypeShape?,
            template: String,
            functionCalls: [String],
            extraImports: [String] = [],
            seedHex: SeedHex,
            trialBudget: TrialBudget,
            preamble: String = "",
            allShapes: [String: IndexedTypeShape] = [:],
            isInstanceMethod: Bool = false,
            isMutatingMethod: Bool = false,
            isNullary: Bool = false,
            returnsSelfType: Bool = false,
            isComputedProperty: Bool = false,
            parameterCount: Int = 0,
            parameterTypeNames: [String] = [],
            receiverTypeName: String? = nil
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
            self.isInstanceMethod = isInstanceMethod
            self.isMutatingMethod = isMutatingMethod
            self.isNullary = isNullary
            self.returnsSelfType = returnsSelfType
            self.isComputedProperty = isComputedProperty
            self.parameterCount = parameterCount
            self.parameterTypeNames = parameterTypeNames
            self.receiverTypeName = receiverTypeName
        }
    }
}
