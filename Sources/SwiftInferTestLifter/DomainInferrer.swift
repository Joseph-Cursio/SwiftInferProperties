import SwiftInferCore

/// TestLifter M10.2 — pure-function inferrer that decides whether a
/// round-trip pair's reverse-side argument was uniformly the forward-
/// side function's output across the test corpus, and (when so) returns
/// the `DomainHint` the M10.3 accept-flow renderer surfaces.
///
/// Inputs:
/// - `pair`: the round-trip pair from M5's detector — `forwardName` is
///   the producer (e.g. `encode`), `reverseName` is the consumer
///   (e.g. `decode`), `domainTypeName` is the `T` the override
///   generator wraps as `Gen<T>.map(forward)`.
/// - `forwardSummary`: the producer's `FunctionSummary` — drives the
///   four hard-veto checks (throws / async / multi-arg / non-
///   generatable arg type).
/// - `sites`: the `[DomainCallSite]` produced by M10.1's extractor for
///   `pair.reverseName` across one or more `SlicedTestBody` slices.
/// - `setupBindings`: name → classification map for the slices' setup-
///   region `let <name> = <expr>` bindings, used to resolve
///   `.identifier(name:)` sites before applying homogeneity.
///   Resolution is transitive (with a 5-hop depth limit; cycles
///   degrade to `.other` and kill the hint).
/// - `producerArgGeneratable`: whether the forward function's single
///   argument type is auto-generatable per the M3+ `DerivationStrategist`
///   strategy table. Decoupled into a parameter so M10.2 unit tests
///   don't need to invoke the full strategist; the M10.3 pipeline
///   computes this via the existing `DerivationStrategist` lookup.
///
/// Returns a `DomainHint` when:
/// 1. `sites.count >= 3` (M4.3 / M9 threshold).
/// 2. Every site, post-resolution, classifies as
///    `.callOutput(producerName: pair.forwardName)` (homogeneity —
///    one outlier kills, per PRD §3.5 conservative bias).
///
/// The hint's `producerVeto` field is populated when one of the four
/// hard-veto checks fires, in priority order: throws > async > multi-
/// arg > non-generatable. The `suggestedGenerator` string is always
/// populated (rendered as advisory text even when vetoed).
///
/// Returns `nil` otherwise.
public enum DomainInferrer {

    public static func infer(
        pair: RoundTripPair,
        forwardSummary: FunctionSummary,
        sites: [DomainCallSite],
        setupBindings: [String: ArgumentClassification],
        producerArgGeneratable: Bool
    ) -> DomainHint? {
        guard sites.count >= 3 else { return nil }
        let resolvedSites = sites.map { site in
            resolve(site.argument, in: setupBindings)
        }
        let homogeneous = resolvedSites.allSatisfy { classification in
            classification == .callOutput(producerName: pair.forwardName)
        }
        guard homogeneous else { return nil }
        let veto = computeVeto(
            forwardSummary: forwardSummary,
            producerArgGeneratable: producerArgGeneratable
        )
        return DomainHint(
            forwardName: pair.forwardName,
            reverseName: pair.reverseName,
            producerName: pair.forwardName,
            domainTypeName: pair.domainTypeName,
            siteCount: sites.count,
            producerVeto: veto,
            suggestedGenerator: "Gen<\(pair.domainTypeName)>.map(\(pair.forwardName))"
        )
    }

    private static func resolve(
        _ classification: ArgumentClassification,
        in setupBindings: [String: ArgumentClassification],
        depth: Int = 0
    ) -> ArgumentClassification {
        guard depth < 5 else { return .other }
        guard case let .identifier(name) = classification else { return classification }
        guard let resolved = setupBindings[name] else { return .other }
        return resolve(resolved, in: setupBindings, depth: depth + 1)
    }

    /// Apply the four hard-veto checks in M10's documented priority
    /// order (throws > async > multi-arg > non-generatable arg). The
    /// helper is `internal` so the M16 `ConsumerProducerChainDetector`
    /// can reuse it verbatim per its plan ("M10's `computeVeto(...)`
    /// helper is reused as-is" — M16 plan §"M16 ships" item 2).
    static func computeVeto(
        forwardSummary: FunctionSummary,
        producerArgGeneratable: Bool
    ) -> ProducerVetoReason? {
        if forwardSummary.isThrows { return .producerThrows }
        if forwardSummary.isAsync { return .producerAsync }
        if forwardSummary.parameters.count != 1 { return .producerMultiArg }
        if !producerArgGeneratable { return .producerArgNotGeneratable }
        return nil
    }
}

/// The round-trip pair input for `DomainInferrer.infer(...)`. Carries
/// the M5 detector's `(forward, reverse)` names plus the carrier type
/// `T` the override generator wraps as `Gen<T>.map(forward)`. M10.3
/// pipeline wiring constructs one of these per round-trip suggestion
/// before invoking the inferrer.
public struct RoundTripPair: Sendable, Equatable {

    /// The producer function name (e.g. `encode`).
    public let forwardName: String

    /// The consumer function name (e.g. `decode`).
    public let reverseName: String

    /// The carrier type the override generator wraps. The PRD §7.8
    /// example `Gen<MyType>.map(encode)` puts `MyType` here. The M10.3
    /// pipeline derives this from the round-trip suggestion's
    /// `MockGenerator.typeName` or the source-side type-flow analysis.
    public let domainTypeName: String

    public init(forwardName: String, reverseName: String, domainTypeName: String) {
        self.forwardName = forwardName
        self.reverseName = reverseName
        self.domainTypeName = domainTypeName
    }
}
