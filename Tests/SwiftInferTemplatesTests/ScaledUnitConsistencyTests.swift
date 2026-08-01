import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

/// **Scaled-unit consistency** — `Duration.seconds(n) == Duration.milliseconds(n * 1_000)`.
///
/// Rows 8–11 of `fixtures/swiftorg-study/loops-answer-key.json`. The witnesses check
/// `Duration.milliseconds(v).components` against `(v / 1000, v % 1000 * 1e15)` at four
/// scales; the template states the same defect between two *constructors*, which needs
/// only the ratio and nothing about how the carrier stores the value.
@Suite("Scaled-unit consistency — two spellings of one value must agree")
struct ScaledUnitConsistencyTests {

    private static let loc = SourceLocation(file: "Duration.swift", line: 178, column: 1)

    private func unit(
        _ name: String,
        on carrier: String = "Duration",
        returns: String? = nil,
        isStatic: Bool = true,
        parameterType: String = "Int64"
    ) -> FunctionSummary {
        FunctionSummary(
            name: name,
            parameters: [
                Parameter(
                    label: nil, internalName: "amount",
                    typeText: parameterType, isInout: false
                )
            ],
            returnTypeText: returns ?? carrier,
            isThrows: false,
            isAsync: false,
            isMutating: false,
            isStatic: isStatic,
            location: Self.loc,
            containingTypeName: carrier,
            bodySignals: .empty
        )
    }

    // MARK: - The witnesses

    /// `Duration`'s four units produce three ADJACENT pairs, not six.
    @Test("A four-unit family yields three adjacent pairs with exact ratios")
    func durationFamilyProducesAdjacentPairs() {
        let shapes = ScaledUnitPairing.candidates(in: [
            unit("seconds"), unit("milliseconds"), unit("microseconds"), unit("nanoseconds")
        ])
        #expect(shapes.count == 3)
        let pairs = shapes.map { "\($0.larger.name)/\($0.smaller.name)=\($0.ratio)" }.sorted()
        #expect(pairs == [
            "microseconds/nanoseconds=1000",
            "milliseconds/microseconds=1000",
            "seconds/milliseconds=1000"
        ])
    }

    /// swift-nio's `TimeAmount` spans hours to nanoseconds, so the ladder includes the
    /// non-decimal step 60.
    @Test("Minutes and hours give the non-decimal ratios")
    func nonDecimalRatios() {
        let shapes = ScaledUnitPairing.candidates(in: [
            unit("hours", on: "TimeAmount"),
            unit("minutes", on: "TimeAmount"),
            unit("seconds", on: "TimeAmount")
        ])
        let byPair = Dictionary(
            uniqueKeysWithValues: shapes.map { ("\($0.larger.name)/\($0.smaller.name)", $0.ratio) }
        )
        #expect(byPair["hours/minutes"] == 60)
        #expect(byPair["minutes/seconds"] == 60)
    }

    @Test("Three or more units reach Strong; two stay Likely")
    func clusterBonus() {
        let three = ScaledUnitPairing.candidates(in: [
            unit("seconds"), unit("milliseconds"), unit("microseconds")
        ])
        let strongest = three.first.flatMap(ScaledUnitConsistencyTemplate.suggest(for:))
        #expect(strongest?.score.tier == .strong)

        let two = ScaledUnitPairing.candidates(in: [unit("seconds"), unit("milliseconds")])
        let suggestion = two.first.flatMap(ScaledUnitConsistencyTemplate.suggest(for:))
        #expect(suggestion?.score.total == 70)
        #expect(suggestion?.score.tier == .likely)
    }

    @Test("The rendered law multiplies the finer unit")
    func lawText() {
        let shapes = ScaledUnitPairing.candidates(in: [unit("seconds"), unit("milliseconds")])
        #expect(shapes.first?.lawText == "Duration.seconds(n) == Duration.milliseconds(n * 1000)")
    }

    // MARK: - What it declines

    /// **The measured ambiguity that scopes this template to time.** `kilobytes` means
    /// 1000 in some types and 1024 in others, and both are defensible — swift-nio's
    /// `ByteCount` (a full four-unit family the population sweep found) uses `1000 *
    /// count`. Asserting either ratio would be flatly wrong for half the ecosystem.
    @Test("Byte units are not a unit family this template will touch")
    func byteUnitsExcluded() {
        let shapes = ScaledUnitPairing.candidates(in: [
            unit("bytes", on: "ByteCount"),
            unit("kilobytes", on: "ByteCount"),
            unit("megabytes", on: "ByteCount"),
            unit("gigabytes", on: "ByteCount")
        ])
        #expect(shapes.isEmpty)
        for name in ["bytes", "kilobytes", "megabytes", "gigabytes"] {
            #expect(ScaledUnitPairing.nanosecondsPerUnit[name] == nil)
        }
    }

    /// `days` and `weeks` are calendar units — a type modelling calendars may make a day
    /// something other than 86,400 seconds, which is exactly the reinterpretation the
    /// curated table must not permit.
    @Test("Calendar units are excluded from the ladder")
    func calendarUnitsExcluded() {
        #expect(ScaledUnitPairing.nanosecondsPerUnit["days"] == nil)
        #expect(ScaledUnitPairing.nanosecondsPerUnit["weeks"] == nil)
        #expect(ScaledUnitPairing.nanosecondsPerUnit["hours"] == 3_600_000_000_000)
    }

    /// A same-named *accessor* returning a scalar is the decomposition, not the
    /// construction — pairing it would state something about the wrong direction.
    @Test("An accessor that does not return the carrier is not a constructor")
    func accessorNotConstructor() {
        let shapes = ScaledUnitPairing.candidates(in: [
            unit("seconds", returns: "Int64"),
            unit("milliseconds", returns: "Int64")
        ])
        #expect(shapes.isEmpty)
    }

    @Test("An instance method is not a scaled constructor")
    func instanceMethodDeclined() {
        let shapes = ScaledUnitPairing.candidates(in: [
            unit("seconds", isStatic: false), unit("milliseconds", isStatic: false)
        ])
        #expect(shapes.isEmpty)
    }

    /// One unit is not a family — there is nothing to be consistent with.
    @Test("A lone unit produces nothing")
    func loneUnitDeclined() {
        #expect(ScaledUnitPairing.candidates(in: [unit("seconds")]).isEmpty)
    }

    // MARK: - Explainability (PRD §4.5)

    /// The overflow caveat is the one that stops a reader filing a false counterexample:
    /// the right-hand side multiplies, so an unbounded generator fails on the domain
    /// rather than on a conversion bug.
    @Test("The caveats name overflow, adjacency, and the byte exclusion")
    func caveatsCarryTheLimits() {
        let shapes = ScaledUnitPairing.candidates(in: [unit("seconds"), unit("milliseconds")])
        let caveats = shapes.first.map(ScaledUnitConsistencyTemplate.makeCaveats(for:)) ?? []
        #expect(caveats.contains { $0.contains("OVERFLOW BOUNDS THE DOMAIN") })
        #expect(caveats.contains { $0.contains("ONLY ADJACENT UNITS") })
        #expect(caveats.contains { $0.contains("BYTE UNITS ARE EXCLUDED") })
    }

    @Test("The generator recipe bounds the product but keeps its boundary")
    func generatorRationale() {
        let shapes = ScaledUnitPairing.candidates(in: [unit("seconds"), unit("milliseconds")])
        let recipes = shapes.first.map(ScaledUnitConsistencyTemplate.makeGenerators(for:)) ?? []
        #expect(recipes.first?.rationale.contains("BOUND IT SO THE PRODUCT IS") == true)
        #expect(recipes.first?.rationale.contains("largest `n`") == true)
    }

    @Test("Identity is stable across shapes and distinct across unit pairs")
    func identityIsStableAndScoped() {
        let shapes = ScaledUnitPairing.candidates(in: [
            unit("seconds"), unit("milliseconds"), unit("microseconds")
        ])
        let identities = shapes.map(ScaledUnitConsistencyTemplate.makeIdentity(for:))
        #expect(Set(identities).count == shapes.count, "one identity per unit pair")
        let rebuiltShapes = ScaledUnitPairing.candidates(in: [
            unit("seconds"), unit("milliseconds"), unit("microseconds")
        ])
        let rebuilt = rebuiltShapes.map(ScaledUnitConsistencyTemplate.makeIdentity(for:))
        #expect(identities == rebuilt)
    }
}
