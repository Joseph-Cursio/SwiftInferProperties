import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

/// `structural-round-trip`: a parser with no printer gets a scaffold for `parse(render(v)) == v`,
/// with the printer and the values left to the author (SwiftInferProperties#646).
@Suite("Structural round trip — a scaffold for the printerless parser")
struct StructuralRoundTripTemplateTests {

    private static func function(
        _ name: String,
        on owner: String? = "RuleInfoParser",
        isStatic: Bool = true,
        parameter: String? = "String",
        returns: String?
    ) -> FunctionSummary {
        FunctionSummary(
            name: name,
            parameters: parameter.map {
                [Parameter(label: nil, internalName: "output", typeText: $0, isInout: false)]
            } ?? [],
            returnTypeText: returns,
            isThrows: false,
            isAsync: false,
            isMutating: false,
            isStatic: isStatic,
            location: SourceLocation(file: "RuleInfoParser.swift", line: 94, column: 5),
            containingTypeName: owner,
            bodySignals: .empty
        )
    }

    private static let parser = function("parse", returns: "ParsedRuleInfo")

    // MARK: - Proposed

    @Test func aParserWithNoPrinterIsProposed() throws {
        let subject = try #require(StructuralRoundTripSubject.candidates(in: [Self.parser]).first)
        #expect(subject.structure == "ParsedRuleInfo")
        let suggestion = try #require(StructuralRoundTripTemplate.suggest(for: subject))
        #expect(suggestion.templateName == "structural-round-trip")
        #expect(suggestion.carrier == "ParsedRuleInfo")
        #expect(suggestion.score.total == 35)
        // A scaffold, not a law: neither entailed nor read from the body.
        #expect(!Refutability.isRoleEntailed(suggestion))
        #expect(!Refutability.isCharacterisation(suggestion))
    }

    /// `parse(_:) -> Self` parses into its own declaring type.
    @Test func selfResolvesToTheDeclaringType() throws {
        let parser = Self.function("parse", on: "Netrc", returns: "Self")
        let subject = try #require(StructuralRoundTripSubject.candidates(in: [parser]).first)
        #expect(subject.structure == "Netrc")
    }

    // MARK: - Declined

    /// **A type something prints is `round-trip`'s and `normal-form`'s.** SwiftFormatRuleStudio's
    /// `SwiftFormatConfig.parse(_:) -> Self` has `serialized()`, and is not proposed.
    @Test func aTypeWithAPrinterIsLeftToTheRoundTripTemplates() {
        let parser = Self.function("parse", on: "SwiftFormatConfig", returns: "Self")
        let printer = Self.function(
            "serialized", on: "SwiftFormatConfig", isStatic: false, parameter: nil, returns: "String"
        )
        #expect(StructuralRoundTripSubject.candidates(in: [parser, printer]).isEmpty)
        #expect(StructuralRoundTripSubject.candidates(in: [parser]).count == 1)
    }

    @Test("a result with no layout of its own is declined", arguments: [
        "[FormatOption]", "ParsedRuleInfo?", "(json: String, prompt: String)", "Set<String>",
        "Bool", "Int", "String", "URL"
    ])
    func declinesResultsWithNoLayout(result: String) {
        #expect(StructuralRoundTripSubject.candidates(in: [Self.function("parse", returns: result)]).isEmpty)
    }

    /// **A dotted result counts only when its head is declared.** swift-foundation's
    /// `IntegerParseStrategy<Format>.parse(_:) -> Format.FormatInput` returns an associated type of a
    /// generic parameter — no layout of its own, and a printer the textual check cannot see.
    @Test func aMemberOfAnUndeclaredHeadIsDeclined() {
        let strategy = Self.function(
            "parse", on: "IntegerParseStrategy", isStatic: false, returns: "Format.FormatInput"
        )
        #expect(StructuralRoundTripSubject.candidates(in: [strategy]).isEmpty)

        let lut = Self.function("parse", on: "C7ColorCube", returns: "C7ColorCube.Resource")
        let lutOwner = FunctionSummary(
            name: "apply", parameters: [], returnTypeText: "Void", isThrows: false, isAsync: false,
            isMutating: false, isStatic: false,
            location: SourceLocation(file: "C7ColorCube.swift", line: 1, column: 1),
            containingTypeName: "C7ColorCube", bodySignals: .empty, qualifiedContainingTypeName: "C7ColorCube"
        )
        #expect(StructuralRoundTripSubject.candidates(in: [lut, lutOwner]).map(\.structure) == ["C7ColorCube.Resource"])
    }

    /// The population is `input-totality`'s: a function that reads its argument as a structure.
    @Test func aFunctionThatDoesNotInterpretItsInputIsDeclined() {
        let lookup = Self.function("rule", returns: "ParsedRuleInfo")
        #expect(StructuralRoundTripSubject.candidates(in: [lookup]).isEmpty)
    }

    // MARK: - Written

    /// Everything the author supplies is in comments; the only live statement is the recorded
    /// to-do, so the file compiles anywhere and the header labels it a scaffold.
    @Test func theScaffoldCompilesAsWrittenAndFailsUntilCompleted() throws {
        let subject = try #require(StructuralRoundTripSubject.candidates(in: [Self.parser]).first)
        let suggestion = try #require(StructuralRoundTripTemplate.suggest(for: subject))
        let stub = try #require(InteractiveTriage.entailedTemplateStub(for: suggestion, customGenerator: nil))
        #expect(stub.contains("@Test func parse_readsBackWhatItsLayoutPrints() throws {"))
        #expect(stub.contains("//   func render(_ value: ParsedRuleInfo) -> String { <#layout#> }"))
        #expect(stub.contains("//   #expect(RuleInfoParser.parse(render(value)) == value)"))
        #expect(stub.contains("Issue.record(\"TODO: complete the structure-first round-trip scaffold"))
        #expect(InteractiveTriage.isScaffold(stub))
        let live = stub.split(separator: "\n").filter {
            let line = $0.trimmingCharacters(in: .whitespaces)
            return !line.isEmpty && !line.hasPrefix("//")
        }
        #expect(live.count == 3, "the test's signature, the Issue.record, and the closing brace: \(live)")
    }

    /// **`discover`'s block must not call the scaffold a law.** It used to end with the conjecture
    /// caveat every non-entailed template gets — "THIS LAW IS A CONJECTURE … a `T -> T` need not be
    /// idempotent" — beneath its own "THIS IS A SCAFFOLD, NOT A LAW".
    @Test func theDiscoverBlockDoesNotCallTheScaffoldALaw() throws {
        let subject = try #require(StructuralRoundTripSubject.candidates(in: [Self.parser]).first)
        let suggestion = try #require(StructuralRoundTripTemplate.suggest(for: subject))
        #expect(Refutability.isScaffold(suggestion))
        let block = SuggestionRenderer.render(suggestion)
        #expect(block.contains("THIS IS A SCAFFOLD, NOT A LAW"))
        #expect(!block.contains("THIS LAW IS A CONJECTURE"))
    }
}
