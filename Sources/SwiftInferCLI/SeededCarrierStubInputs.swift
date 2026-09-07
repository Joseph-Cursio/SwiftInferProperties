import Foundation

/// The input bundle shared by the seeded algebraic stub emitters.
///
/// `AssociativityStubEmitter`, `CommutativityStubEmitter` and
/// `IdempotenceStubEmitter` each declared their own `Inputs` struct with the
/// same six stored properties, the same types and the same defaulted
/// `preamble` — 69 lines repeated three times, differing only in the doc
/// comment on `functionCall`. Same reasoning as `importsForComplexDouble`:
/// three copies of one field list is three chances for a seventh field to be
/// added to two of them.
///
/// **What `functionCall` renders as is the emitter's business, not this
/// type's.** Associativity renders `f(f(a, b), c)` against `f(a, f(b, c))`;
/// commutativity renders `f(lhs, rhs)` against `f(rhs, lhs)`; idempotence
/// renders `f(f(x))` against `f(x)`. Each emitter's type documentation carries
/// its own marker-field semantics.
public struct SeededCarrierStubInputs: Equatable, Sendable, CarrierStubInputs {

    /// The function under test, written as a call expression — a member
    /// reference (`"Int.add"`) or a closure literal
    /// (`"{ (a: Int, b: Int) in a + b }"`). The owning emitter decides how it
    /// is applied.
    public let functionCall: String

    /// User modules to import beyond the carrier-specific mandatory set.
    /// Empty entries and duplicates are filtered.
    public let extraImports: [String]

    /// Carrier type. Must be in the owning emitter's `supportedCarriers`.
    public let carrierType: String

    public let seedHex: RoundTripStubEmitter.SeedHex

    public let trialBudget: RoundTripStubEmitter.TrialBudget

    /// V1.49.A — verbatim Swift source rendered between the imports and the
    /// `var rng = ...` line. See `RoundTripStubEmitter.Inputs.preamble` for the
    /// load-bearing docstring.
    public let preamble: String

    public init(
        functionCall: String,
        extraImports: [String],
        carrierType: String,
        seedHex: RoundTripStubEmitter.SeedHex,
        trialBudget: RoundTripStubEmitter.TrialBudget,
        preamble: String = ""
    ) {
        self.functionCall = functionCall
        self.extraImports = extraImports
        self.carrierType = carrierType
        self.seedHex = seedHex
        self.trialBudget = trialBudget
        self.preamble = preamble
    }
}
