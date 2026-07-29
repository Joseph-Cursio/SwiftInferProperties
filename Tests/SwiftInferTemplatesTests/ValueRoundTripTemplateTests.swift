import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

/// The **value-reader** role and its law — round-trip, `read(write(v)) == v`, for a
/// `(Representation) -> Value?` that decodes a value out of the thing denoting it.
///
/// The template exists because a hand-written property found a real bug the catalog
/// was silent on: three SwiftProjectLint security visitors each had an
/// `extractStringValue`, and two returned the *source text* of a string literal
/// rather than its value (`literal.description.dropFirst().dropLast()`), so `"a\"b"`
/// read back as `a\"b`. Nothing reports that — a URL-scheme check simply stops
/// recognising the value.
///
/// Two things are load-bearing and each has its own test below: the law needs a
/// `write` the reader must supply (which is why no pair-matching template could
/// propose it), and it is refutable only by values whose *written form differs from
/// the value*.
@Suite("Value reader — round-trip through the notation")
struct ValueRoundTripTemplateTests {

    private static let loc = SourceLocation(file: "Visitors.swift", line: 1, column: 1)

    private func readerFn(
        _ name: String,
        params: [Parameter],
        returns: String?,
        on type: String? = "SecurityVisitor",
        mutating: Bool = false,
        async: Bool = false,
        initializer: Bool = false
    ) -> FunctionSummary {
        FunctionSummary(
            name: name,
            parameters: params,
            returnTypeText: returns,
            isThrows: false,
            isAsync: async,
            isMutating: mutating,
            isStatic: false,
            location: Self.loc,
            containingTypeName: type,
            bodySignals: .empty,
            isInitializer: initializer
        )
    }

    private func param(_ label: String?, _ type: String) -> Parameter {
        Parameter(label: label, internalName: label ?? "value", typeText: type, isInout: false)
    }

    /// The motivating shape, as it appeared in the bug.
    private func extractStringValue() -> FunctionSummary {
        readerFn(
            "extractStringValue",
            params: [param("from", "StringLiteralExprSyntax")],
            returns: "String?"
        )
    }

    // MARK: - Fires

    @Test("the motivating shape fires at Possible, scoring exactly 20 + 15")
    func motivatingShapeFires() throws {
        let summary = extractStringValue()
        #expect(ValueRoundTripTemplate.isValueReader(summary))

        let suggestion = try #require(ValueRoundTripTemplate.suggest(for: summary))
        #expect(suggestion.templateName == "value-round-trip")
        // The arithmetic is the calibration claim in the template's own docs — a
        // name-conjecture sits below the confidence cut, like `filter-subset`.
        #expect(suggestion.score.total == 35)
        #expect(suggestion.score.tier == .possible)
        #expect(suggestion.score.tier.isVisibleByDefault == false)
    }

    @Test("all four reader-verb families fire", arguments: [
        ("extractStringValue", "StringLiteralExprSyntax", "String?"),
        ("decodedValue", "Data", "Widget?"),
        ("parsedScheme", "URL", "Scheme?"),
        ("literalContent", "TokenSyntax", "String?")
    ])
    func readerVerbFamiliesFire(name: String, representation: String, value: String) {
        let summary = readerFn(name, params: [param("from", representation)], returns: value)
        #expect(
            ValueRoundTripTemplate.suggest(for: summary) != nil,
            "\(name): (\(representation)) -> \(value) should be a value reader"
        )
    }

    // MARK: - The generator obligation

    @Test("the generator type is the VALUE, not the representation")
    func generatorTypeIsTheValue() throws {
        // The law quantifies over values: `v` is generated and the representation is
        // derived from it by `write`. Generating representations instead would be a
        // weaker property — most arbitrary ones denote nothing, so the reader returns
        // `nil` and the comparison never happens.
        let value = try #require(ValueRoundTripTemplate.valueType(of: extractStringValue()))
        #expect(value == "String")
        #expect(value != "StringLiteralExprSyntax")
    }

    @Test("valueType declines a summary that is not a value reader")
    func generatorTypeDeclinesNonReaders() {
        let notAReader = readerFn("count", params: [param(nil, "String")], returns: "Int")
        #expect(ValueRoundTripTemplate.valueType(of: notAReader) == nil)
    }

    // MARK: - Shape gate — rejections

    @Test("a non-optional return is not a reader: it has nowhere to say `denotes nothing`")
    func nonOptionalReturnRejected() {
        let summary = readerFn(
            "extractStringValue",
            params: [param("from", "StringLiteralExprSyntax")],
            returns: "String"
        )
        #expect(!ValueRoundTripTemplate.isValueReader(summary))
    }

    @Test("`Bool?` is a predicate's answer, not a decoded value")
    func boolOptionalRejected() {
        let summary = readerFn(
            "extractedFlag",
            params: [param("from", "TokenSyntax")],
            returns: "Bool?"
        )
        #expect(!ValueRoundTripTemplate.isValueReader(summary))
    }

    @Test("reading a T out of a T is a normaliser, not a reader")
    func sameTypeRejected() {
        // `LayerStrippingTemplate` owns this shape. Admitting it here would propose a
        // round-trip for a function with no separate notation to round-trip through.
        let summary = readerFn(
            "unquotedString",
            params: [param(nil, "String")],
            returns: "String?"
        )
        #expect(!ValueRoundTripTemplate.isValueReader(summary))
    }

    @Test("a non-representation parameter is rejected: nothing to write back to")
    func nonRepresentationRejected() {
        let summary = readerFn(
            "extractValue",
            params: [param("from", "Configuration")],
            returns: "String?"
        )
        #expect(!ValueRoundTripTemplate.isValueReader(summary))
    }

    @Test("a reader verb is REQUIRED — the shape alone owes nothing")
    func shapeWithoutVerbRejected() {
        // `(R) -> V?` is also the shape of a lookup or a search, which owe no
        // round-trip. This is why the template is name-conjectured, and why the
        // caveats say so.
        for name in ["firstIndex", "lookup", "search", "match"] {
            let summary = readerFn(
                name,
                params: [param("of", "StringLiteralExprSyntax")],
                returns: "Int?"
            )
            #expect(!ValueRoundTripTemplate.isValueReader(summary), "\(name) should not fire")
        }
    }

    @Test("mutating, async, initializer, and multi-parameter forms are out of scope")
    func structuralRejections() {
        let representation = [param("from", "StringLiteralExprSyntax")]
        #expect(
            !ValueRoundTripTemplate.isValueReader(
                readerFn("extractValue", params: representation, returns: "String?", mutating: true)
            )
        )
        #expect(
            !ValueRoundTripTemplate.isValueReader(
                readerFn("extractValue", params: representation, returns: "String?", async: true)
            )
        )
        #expect(
            !ValueRoundTripTemplate.isValueReader(
                readerFn(
                    "extractValue",
                    params: representation,
                    returns: "String?",
                    initializer: true
                )
            )
        )
        #expect(
            !ValueRoundTripTemplate.isValueReader(
                readerFn(
                    "extractValue",
                    params: representation + [param("in", "SourceFileSyntax")],
                    returns: "String?"
                )
            )
        )
    }

    // MARK: - Caveats: the two that carry the finding

    @Test("the caveats state the write obligation, naming the representation")
    func caveatNamesTheWriteObligation() throws {
        // Only the reader knows `write` — it may live in the language, another
        // module, or a test helper. That is the whole cost of this property and the
        // reason no pair-matcher could propose it.
        let suggestion = try #require(ValueRoundTripTemplate.suggest(for: extractStringValue()))
        let caveats = suggestion.explainability.whyMightBeWrong.joined(separator: "\n")
        #expect(caveats.contains("read(write(v)) == v"))
        #expect(caveats.contains("You "))
        #expect(caveats.contains("must supply `write`"))
        #expect(caveats.contains("StringLiteralExprSyntax"))
    }

    @Test("the caveats say a plain-alphanumeric generator passes against a broken reader")
    func caveatNamesTheGeneratorTrap() throws {
        // This is the repo's collision lesson in another costume: the law is refutable
        // only by values whose WRITTEN FORM differs from the value — an embedded
        // quote, a backslash, an escape. A generator drawing plain alphanumerics
        // reports bothPass against a reader that returns source text.
        let suggestion = try #require(ValueRoundTripTemplate.suggest(for: extractStringValue()))
        let caveats = suggestion.explainability.whyMightBeWrong.joined(separator: "\n")
        #expect(caveats.contains("GENERATE THE NOTATION"))
        #expect(caveats.contains("plain alphanumerics"))
        #expect(caveats.contains("silent under-detection"))
    }

    @Test("the round-trip is disclosed as name-conjectured, not entailed")
    func caveatDisclosesConjecture() throws {
        let suggestion = try #require(ValueRoundTripTemplate.suggest(for: extractStringValue()))
        let caveats = suggestion.explainability.whyMightBeWrong.joined(separator: "\n")
        #expect(caveats.contains("NAME-CONJECTURED"))
    }

    // MARK: - Registration

    @Test("it is NOT role-entailed: a differently-intended function of this shape is correct")
    func notRoleEntailed() {
        // `(R) -> V?` owes nothing on its own, so this template must stay below the
        // confidence cut rather than joining the role-entailed set that may be shown
        // beneath it. A tool that proposes a false law is worse than one that
        // proposes nothing.
        #expect(!Refutability.roleEntailedTemplates.contains("value-round-trip"))
    }

    @Test("it is wired into the single-function app-shape registry")
    func isRegistered() throws {
        // The registry list is what `ApplicationShapeRegistryTests` iterates, so
        // membership here is what proves the template fires through `discover` —
        // the coverage gap that let `filter-subset` ship unit-tested-but-unwired.
        let entry = try #require(
            TemplateRegistry.singleFunctionAppShapes.first { $0.name == "value-round-trip" }
        )
        #expect(entry.exclusionGroup == nil, "a reader owes this AND whatever else its shape says")
        #expect(entry.suggest(entry.referenceFixture) != nil)
    }

    @Test("it fires end-to-end through discover, and stays hidden without --include-possible")
    func firesThroughDiscover() {
        let suggestions = TemplateRegistry.discover(in: [extractStringValue()])
        let mine = suggestions.filter { $0.templateName == "value-round-trip" }
        #expect(mine.count == 1)
        #expect(mine.first?.score.tier == .possible)
    }
}
