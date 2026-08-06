import Foundation
@testable import SwiftInferCore
import Testing

/// A `carrier` seed names a **type**, and the focus must join it as one.
///
/// The linter's domain-type rules print findings about types that owe laws a raw primitive cannot
/// state — `Percentage` can own `0...100`; `String` cannot. They did not seed at all, on a recorded
/// reason that assumed this tool's subject is always a function. It is not:
/// `CodableRoundTripTemplate`, `ModelLawTemplate` and `verify-value-semantics` all state laws over
/// a carrier type with no free function anywhere (SwiftProjectLint issue #76).
///
/// The producer now emits `kind: "carrier"` with a type name in `symbol`. This suite pins the half
/// that lives here: the join.
@Suite("SeedFocus — carrier seeds join by type name")
struct SeedFocusCarrierTests {

    private func makeSuggestion(
        templateName: String,
        evidenceName: String,
        file: String,
        carrierTypeName: String?
    ) -> Suggestion {
        Suggestion(
            templateName: templateName,
            evidence: [
                Evidence(
                    displayName: evidenceName,
                    signature: "() -> Void",
                    location: SourceLocation(file: file, line: 1, column: 1)
                )
            ],
            score: Score(signals: []),
            generator: GeneratorMetadata(
                source: .notYetComputed, confidence: nil, sampling: .notRun
            ),
            explainability: ExplainabilityBlock(whySuggested: [], whyMightBeWrong: []),
            identity: SuggestionIdentity(canonicalInput: "\(templateName)|\(carrierTypeName ?? "")"),
            carrierTypeName: carrierTypeName
        )
    }

    private func carrierSeed(symbol: String, file: String) -> SeedManifest.Seed {
        SeedManifest.Seed(
            file: file, line: 2, symbol: symbol, rule: "Primitive Named For Its Domain Type",
            kind: .carrier
        )
    }

    @Test("a carrier seed keeps a suggestion whose carrier type matches")
    func testCarrierSeedKeepsMatchingSuggestion() {
        let manifest = SeedManifest(seeds: [carrierSeed(symbol: "Percentage", file: "Report.swift")])
        let kept = makeSuggestion(
            templateName: "codable-round-trip",
            evidenceName: "encode(to:)",
            file: "Domain.swift",
            carrierTypeName: "Percentage"
        )

        #expect(SeedFocus.filter([kept], to: manifest).count == 1)
    }

    /// **The point of the whole change.** The seed points at the *use site* (`Report.swift`, where
    /// the raw primitive was found) while the type is declared elsewhere (`Domain.swift`). Reusing
    /// the function join — keyed on `(file basename, symbol)` — would miss here, and this is the
    /// normal case rather than a contrived one.
    @Test("the join ignores the file, because the two sides mean different files")
    func testCarrierJoinIsNotFileScoped() {
        let manifest = SeedManifest(seeds: [carrierSeed(symbol: "Percentage", file: "Report.swift")])
        let declaredElsewhere = makeSuggestion(
            templateName: "model-law",
            evidenceName: "validate()",
            file: "SomewhereEntirelyElse.swift",
            carrierTypeName: "Percentage"
        )

        #expect(SeedFocus.filter([declaredElsewhere], to: manifest).count == 1)
    }

    @Test("a carrier seed does not keep an unrelated suggestion")
    func testCarrierSeedFiltersNonMatching() {
        let manifest = SeedManifest(seeds: [carrierSeed(symbol: "Percentage", file: "Report.swift")])
        let unrelated = makeSuggestion(
            templateName: "codable-round-trip",
            evidenceName: "encode(to:)",
            file: "Other.swift",
            carrierTypeName: "Unrelated"
        )

        #expect(SeedFocus.filter([unrelated], to: manifest).contains(unrelated) == false)
    }

    /// A suggestion with no carrier at all must still be judged on its function evidence, so adding
    /// the carrier branch cannot quietly widen the focus.
    @Test("a function suggestion is unaffected by a carrier seed")
    func testFunctionSuggestionStillJoinsOnEvidence() {
        let manifest = SeedManifest(seeds: [
            carrierSeed(symbol: "Percentage", file: "Report.swift"),
            SeedManifest.Seed(
                file: "Math.swift", line: 3, symbol: "add", rule: "Pure Function", kind: .pureFunction
            )
        ])
        let seeded = makeSuggestion(
            templateName: "commutativity",
            evidenceName: "add(_:_:)",
            file: "Math.swift",
            carrierTypeName: nil
        )
        let unseeded = makeSuggestion(
            templateName: "commutativity",
            evidenceName: "subtract(_:_:)",
            file: "Math.swift",
            carrierTypeName: nil
        )

        let kept = SeedFocus.filter([seeded, unseeded], to: manifest)

        #expect(kept.count == 1)
        #expect(kept.first?.evidence.first?.displayName == "add(_:_:)")
    }

    @Test("carrier is analysable, so a carrier-only manifest still focuses")
    func testCarrierIsAnalysable() {
        let manifest = SeedManifest(seeds: [carrierSeed(symbol: "Percentage", file: "Report.swift")])

        #expect(SeedKind.carrier.isAnalysable)
        #expect(manifest.analysableSeeds.count == 1)
    }

    @Test("carrier decodes from the producer's manifest")
    func testCarrierDecodes() throws {
        let json = """
        {"version": 2, "seeds": [
          {"file": "Report.swift", "line": 2, "symbol": "Percentage",
           "rule": "Primitive Named For Its Domain Type", "kind": "carrier"}
        ]}
        """
        let manifest = try JSONDecoder().decode(SeedManifest.self, from: Data(json.utf8))

        let seed = try #require(manifest.seeds.first)
        #expect(seed.kind == .carrier)
        #expect(seed.kind.rawValue == "carrier")
        #expect(seed.symbol == "Percentage")
    }
}
