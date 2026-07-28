import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

/// The protocol-mediated printer half — `docs/parsing-catalog-gap.md` §3c, and
/// the last of the three blockers on swift-syntax's fidelity law.
///
/// ```swift
/// extension SyntaxProtocol { public var description: String }
/// public static func parse(source: String) -> SourceFileSyntax
/// ```
///
/// `Parser.parse(source).description == source` is asserted in swift-syntax's
/// own suite (`Tests/SwiftParserTest/Parser+EntryTests.swift:22`) and was the
/// survey's headline miss. §3a curated the `parse`/`description` name pair and
/// §3b relieved the cross-type counter, but the pair still never *formed*: the
/// printer is declared once on the protocol, so the scanner records its domain
/// as `SyntaxProtocol`, which never meets `String -> SourceFileSyntax` under
/// the strict type filter.
///
/// The relaxation is exactly that the concrete codomain may **conform to** the
/// printer's declaring protocol rather than equal it — the same admissibility
/// idea as the erased self-form.
@Suite("FunctionPairing — protocol-mediated printer half")
struct ProtocolPrinterPairingTests {

    private func parseFn(returns: String, carrier: String = "Parser") -> FunctionSummary {
        FunctionSummary(
            name: "parse",
            parameters: [
                Parameter(label: "source", internalName: "source", typeText: "String", isInout: false)
            ],
            returnTypeText: returns,
            isThrows: false, isAsync: false, isMutating: false, isStatic: true,
            location: SourceLocation(file: "Parse.swift", line: 1, column: 1),
            containingTypeName: carrier,
            bodySignals: .empty
        )
    }

    private func printer(
        _ name: String = "description",
        on carrier: String,
        returns: String = "String"
    ) -> FunctionSummary {
        FunctionSummary(
            name: name,
            parameters: [],
            returnTypeText: returns,
            isThrows: false, isAsync: false, isMutating: false, isStatic: false,
            location: SourceLocation(file: "Print.swift", line: 1, column: 1),
            containingTypeName: carrier,
            bodySignals: .empty
        )
    }

    /// `SourceFileSyntax: SyntaxProtocol`, as the corpus index records it.
    private let conformances = [
        "SourceFileSyntax": Set(["SyntaxProtocol", "SyntaxHashable"])
    ]

    // MARK: - The law

    @Test("the swift-syntax fidelity pair now forms")
    func fidelityPairForms() throws {
        let pairs = FunctionPairing.candidates(
            in: [parseFn(returns: "SourceFileSyntax"), printer(on: "SyntaxProtocol")],
            conformances: conformances
        )
        #expect(pairs.count == 1, "parse × description should pair through the conformance")
        let pair = try #require(pairs.first)
        #expect([pair.forward.name, pair.reverse.name].sorted() == ["description", "parse"])
    }

    @Test("without the conformance index the pair does not form — the scoping limit")
    func unresolvedConformanceDoesNotPair() {
        // `SourceFileSyntax` is declared in SwiftSyntax while `parse` lives in
        // SwiftParser, so a single-module scan resolves nothing. Silence rather
        // than a guessed pair.
        #expect(FunctionPairing.candidates(
            in: [parseFn(returns: "SourceFileSyntax"), printer(on: "SyntaxProtocol")]
        ).isEmpty)
    }

    @Test("the strict shape still pairs, unchanged")
    func concretePrinterUnaffected() {
        // `Doc.description` against `parse -> Doc` paired before this change and
        // must still.
        let pairs = FunctionPairing.candidates(
            in: [parseFn(returns: "Doc", carrier: "Parse2"), printer(on: "Doc")]
        )
        #expect(pairs.count == 1)
    }

    // MARK: - The gate that keeps it from multiplying

    @Test("only printer-shaped halves get the relaxation")
    func nonPrinterHalvesDoNotRelax() {
        // Relaxing "codomain conforms to the other half's domain" in general
        // would pair every `X -> Concrete` against every `Protocol -> X` in the
        // corpus. Scoped to printers, one extra shape is admitted and no more.
        for name in ["render", "serialize", "toString", "text", "formatted"] {
            let notAPrinter = printer(name, on: "SyntaxProtocol")
            #expect(
                FunctionPairing.candidates(
                    in: [parseFn(returns: "SourceFileSyntax"), notAPrinter],
                    conformances: conformances
                ).isEmpty,
                "\(name) is not a CustomStringConvertible printer — must not relax"
            )
        }
    }

    @Test("isPrinterHalf accepts exactly the two CustomStringConvertible names")
    func printerHalfRecognition() {
        #expect(FunctionPairing.isPrinterHalf(printer("description", on: "P")))
        #expect(FunctionPairing.isPrinterHalf(printer("debugDescription", on: "P")))
        // Not printers: wrong name, wrong return, static, parameterised.
        #expect(!FunctionPairing.isPrinterHalf(printer("summary", on: "P")))
        #expect(!FunctionPairing.isPrinterHalf(printer("description", on: "P", returns: "Data")))
        #expect(!FunctionPairing.isPrinterHalf(parseFn(returns: "String")))
    }

    @Test("a type that does NOT conform is not paired")
    func nonConformingCodomainNotPaired() {
        #expect(FunctionPairing.candidates(
            in: [parseFn(returns: "UnrelatedNode"), printer(on: "SyntaxProtocol")],
            conformances: ["UnrelatedNode": Set(["Equatable"])]
        ).isEmpty)
    }

    @Test("the relaxation never fires on an identity conformance")
    func identityConformanceDoesNotRelax() {
        // A parser returning the protocol itself pairs with the protocol's own
        // printer under the STRICT rule already — `String -> SyntaxProtocol`
        // against `SyntaxProtocol -> String` matches exactly — so this pair
        // exists with or without the relaxation. That is the point: a
        // self-referential entry in the conformance index
        // (`SyntaxProtocol: SyntaxProtocol`) must not make the relaxation fire
        // a SECOND time, which is what the `type != protocolName` guard in
        // `conforms` is for.
        let summaries = [
            parseFn(returns: "SyntaxProtocol", carrier: "SyntaxProtocol"),
            printer(on: "SyntaxProtocol")
        ]
        let strict = FunctionPairing.candidates(in: summaries)
        let withIdentityConformance = FunctionPairing.candidates(
            in: summaries,
            conformances: ["SyntaxProtocol": Set(["SyntaxProtocol"])]
        )
        #expect(strict.count == 1, "the strict rule already pairs these")
        #expect(withIdentityConformance.count == strict.count, "no extra pair from the relaxation")
    }

    // MARK: - The direction caveat

    @Test("a printer-half pair discloses which direction is actually being claimed")
    func printerPairCarriesDirectionCaveat() throws {
        // The law the tool now proposes on swift-syntax is TRUE there, because
        // that printer is full-fidelity — and FALSE for any lossy parser. A
        // Likely-tier claim that ships without saying so is the failure mode
        // this whole survey is about.
        let pairs = FunctionPairing.candidates(
            in: [parseFn(returns: "SourceFileSyntax"), printer(on: "SyntaxProtocol")],
            conformances: conformances
        )
        let pair = try #require(pairs.first)
        let suggestion = try #require(
            RoundTripTemplate.suggest(for: pair, inheritedTypesByName: conformances)
        )
        let caveat = try #require(
            suggestion.explainability.whyMightBeWrong
                .first { $0.contains("TEXT DOMAIN") }
        )
        // It has to name all three readings, not just wave at the ambiguity.
        #expect(caveat.contains("parse(print(x)) == x"))
        #expect(caveat.contains("print(parse(s)) == s"))
        #expect(caveat.contains("print ∘ parse"))
    }
}
