import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

/// The text↔structure widening of `RoundTripTemplate.curatedInversePairs` —
/// `docs/measurements/parsing-catalog-gap.md` §3a.
///
/// Before it, the list held exactly one parse-ish entry (`parse`/`format`) and
/// every other spelling of the same law scored 35 — `Possible`, hidden on a
/// default run. Measured on identical type shapes: `parse`/`format` → 75
/// `Strong`, `parse`/`print` and `parse`/`render` → 35, invisible.
///
/// The suite pins both directions: the promotion these names now get, and the
/// two §3 causes the widening does **not** close, so a later reader does not
/// mistake this fix for having reached the swift-syntax fidelity law.
@Suite("RoundTripTemplate — parse/print inverse-name widening")
struct ParsePrintInverseNameTests {

    private func summary(
        _ name: String,
        param: String,
        returns: String,
        carrier: String?
    ) -> FunctionSummary {
        FunctionSummary(
            name: name,
            parameters: [Parameter(label: nil, internalName: "value", typeText: param, isInout: false)],
            returnTypeText: returns,
            isThrows: false, isAsync: false, isMutating: false, isStatic: true,
            location: SourceLocation(file: "Test.swift", line: 1, column: 1),
            containingTypeName: carrier,
            bodySignals: .empty
        )
    }

    private func pair(
        _ forwardName: String,
        _ reverseName: String,
        carrier: String? = "Codec",
        reverseCarrier: String? = nil
    ) -> FunctionPair {
        FunctionPair(
            forward: summary(forwardName, param: "String", returns: "Tree", carrier: carrier),
            reverse: summary(
                reverseName, param: "Tree", returns: "String",
                carrier: reverseCarrier ?? carrier
            )
        )
    }

    // MARK: - The promotion

    @Test("every text↔structure spelling now earns the same +40 the codec pairs do")
    func textStructurePairsAreCurated() throws {
        for (forward, reverse) in [
            ("parse", "format"),      // was already curated — the control
            ("parse", "print"),
            ("parse", "unparse"),
            ("parse", "render"),
            ("parse", "description"),
            ("tokenize", "join")
        ] {
            let suggestion = try #require(
                RoundTripTemplate.suggest(for: pair(forward, reverse)),
                "expected a suggestion for \(forward)/\(reverse)"
            )
            let nameSignal = try #require(
                suggestion.score.signals.first { $0.kind == .exactNameMatch },
                "expected a curated-name signal for \(forward)/\(reverse)"
            )
            #expect(nameSignal.weight == 40)
            // 30 type-symmetry + 40 curated name = 70 → Likely, which is
            // shown by default. These pairs scored 35 (Possible, hidden)
            // before the widening. A real `discover` run adds the +5
            // value-semantic carrier signal and lands them at 75 / Strong;
            // this unit context passes no `CarrierKindResolver`, so 70.
            #expect(suggestion.score.total == 70)
            #expect(suggestion.score.tier == .likely, "expected \(forward)/\(reverse) visible")
        }
    }

    @Test("orientation-insensitive: the printer may be the forward half")
    func matchIsOrientationInsensitive() {
        let reversed = FunctionPair(
            forward: summary("print", param: "Tree", returns: "String", carrier: "Codec"),
            reverse: summary("parse", param: "String", returns: "Tree", carrier: "Codec")
        )
        #expect(RoundTripTemplate.suggest(for: reversed)?.score.total == 70)
    }

    @Test("the widening is shared with InversePairTemplate, at its own weight")
    func inversePairTemplateSeesTheSameNames() throws {
        // The list is `RoundTripTemplate`'s but `InversePairTemplate` reads it
        // too (+10 there, not +40), so an addition widens both templates. That
        // is intended — an inverse pair is an inverse pair — and pinned here so
        // the coupling is visible rather than surprising.
        let suggestion = try #require(InversePairTemplate.suggest(for: pair("parse", "print")))
        #expect(suggestion.score.signals.contains { $0.kind == .exactNameMatch })
    }

    // MARK: - The persistence caveat

    @Test("read/write and load/save carry the store caveat; parse/print does not")
    func persistencePairsDiscloseTheirStore() throws {
        for (forward, reverse) in [("write", "read"), ("save", "load")] {
            let suggestion = try #require(RoundTripTemplate.suggest(for: pair(forward, reverse)))
            #expect(suggestion.score.total == 70)
            #expect(
                suggestion.explainability.whyMightBeWrong.contains { $0.contains("RUNS THROUGH A STORE") },
                "expected the store caveat on \(forward)/\(reverse)"
            )
        }
        let pure = try #require(RoundTripTemplate.suggest(for: pair("parse", "print")))
        #expect(!pure.explainability.whyMightBeWrong.contains { $0.contains("RUNS THROUGH A STORE") })
    }

    // MARK: - What this fix does NOT close

    @Test("cross-type parse/print is rescued from Suppressed to Likely, not to Strong")
    func crossTypePairIsOnlyPartlyRescued() {
        // §3b: parsers and printers are almost always in DIFFERENT types
        // (`Loader`/`Writer`, `Parser`/`Printer`), and the -25 cross-type
        // counter used to bury the pair entirely: 30 - 25 = 5, Suppressed.
        // The +40 now carries it to 30 + 40 - 25 = 45, which is visible. That
        // is a side effect of this fix, not a substitute for §3b — a pair
        // whose names are NOT curated is still suppressed outright.
        let crossType = pair("parse", "print", carrier: "Reader", reverseCarrier: "Printer")
        let suggestion = RoundTripTemplate.suggest(for: crossType)
        #expect(suggestion?.score.tier == .likely)

        let uncurated = pair("decodeTree", "renderTree", carrier: "Reader", reverseCarrier: "Printer")
        #expect(RoundTripTemplate.suggest(for: uncurated) == nil, "still suppressed — §3b is open")
    }

    @Test("a printer declared on a PROTOCOL EXTENSION never pairs — the swift-syntax blocker")
    func protocolExtensionPrinterStillCannotPair() {
        // §3c, measured precisely. `SyntaxProtocol.description` is declared
        // once on an extension of the protocol, so the scanner records its
        // domain as `SyntaxProtocol`, while `Parser.parse` produces
        // `String -> SourceFileSyntax`. The type texts never meet, so
        // `FunctionPairing` makes no pair and no name list can help.
        //
        // Note what IS reachable: the same printer on the CONCRETE type does
        // pair. The blocker is the protocol extension, not computed
        // properties as such.
        let protocolPrinter = FunctionSummary(
            name: "description",
            parameters: [],
            returnTypeText: "String",
            isThrows: false, isAsync: false, isMutating: false, isStatic: false,
            location: SourceLocation(file: "Test.swift", line: 1, column: 1),
            containingTypeName: "NodeProtocol",
            bodySignals: .empty
        )
        let parse = summary("parse", param: "String", returns: "SourceFile", carrier: "Parser")
        let candidates = FunctionPairing.candidates(in: [protocolPrinter, parse])
        #expect(candidates.isEmpty, "no pair forms: NodeProtocol -> String vs String -> SourceFile")
    }
}
