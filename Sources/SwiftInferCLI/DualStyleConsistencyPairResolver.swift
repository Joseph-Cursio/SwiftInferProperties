import Foundation
import SwiftInferCore

/// V1.48.B — resolves the verifier call expressions for a
/// dual-style-consistency `SemanticIndexEntry`. The template asserts
/// equivalence between a non-mutating function and its mutating
/// counterpart: `nonMut(x) == { var c = x; c.mut(); c }`.
///
/// **Curated pair table.** Like `RoundTripPairResolver.curated` but
/// pairs the non-mutating + mutating spelling pair (`sorted` ↔
/// `sort`, `reversed` ↔ `reverse`, `shuffled` ↔ `shuffle`).
/// `SemanticIndexEntry.primaryFunctionName` carries the *non-mutating*
/// half by convention; the resolver looks up the mutating spelling
/// in the curated list. Expand the table in v1.49+ if cycle-45
/// surfaces additional pairs.
///
/// **Output.** `functionCalls` carries `[nonMutCall, mutMethodName]`:
///   - `nonMutCall` — a full call expression like `Array.sorted` the
///     V1.48.A composer applies as `nonMutCall(original)`.
///   - `mutMethodName` — a bare instance-method name like `"sort"`
///     the composer applies via `copy.sort()` on a `var` binding.
public enum DualStyleConsistencyPairResolver {

    /// Curated `(nonMutating, mutating)` spellings the resolver knows
    /// how to pair. Both halves are bare function names without
    /// parameter labels — labels are added at use site if the entry
    /// carries them (`stripParameterLabels` handles either form).
    public struct Pair: Sendable, Equatable {
        public let nonMutating: String
        public let mutating: String

        public init(nonMutating: String, mutating: String) {
            self.nonMutating = nonMutating
            self.mutating = mutating
        }
    }

    public static let curated: [Pair] = [
        Pair(nonMutating: "sorted()", mutating: "sort"),
        Pair(nonMutating: "reversed()", mutating: "reverse"),
        Pair(nonMutating: "shuffled()", mutating: "shuffle")
    ]

    /// Resolution result. Carries the pair of expressions the V1.48.A
    /// dual-style-consistency composer consumes.
    public struct Resolved: Equatable, Sendable {
        public let nonMutCall: String
        public let mutMethodName: String

        public init(nonMutCall: String, mutMethodName: String) {
            self.nonMutCall = nonMutCall
            self.mutMethodName = mutMethodName
        }
    }

    /// Resolve the pair for a dual-style-consistency entry. Errors:
    ///   - `.unsupportedTemplate` if `templateName != "dual-style-consistency"`.
    ///   - `.unsupportedPair` if `primaryFunctionName` doesn't match
    ///     any curated `nonMutating` entry.
    public static func resolve(_ entry: SemanticIndexEntry) throws -> Resolved {
        guard entry.templateName == "dual-style-consistency" else {
            throw VerifyError.unsupportedTemplate(
                template: entry.templateName,
                expected: ["dual-style-consistency"]
            )
        }
        let nonMutBare = entry.primaryFunctionName
        guard let pair = curated.first(where: { $0.nonMutating == nonMutBare }) else {
            throw VerifyError.unsupportedPair(
                forward: nonMutBare,
                supported: curated.map(\.nonMutating)
            )
        }
        let carrier = entry.typeName ?? "(none)"
        let typeQualifier = RoundTripPairResolver.bareTypeName(from: carrier)
        let nonMutCall = "\(typeQualifier).\(RoundTripPairResolver.stripParameterLabels(pair.nonMutating))"
        return Resolved(
            nonMutCall: nonMutCall,
            mutMethodName: pair.mutating
        )
    }
}
