import PropertyLawCore
import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

/// Stream-consumption veto on idempotence-lifted. Closes
/// `docs/measurements/parsing-catalog-gap.md` §2: `discover` on `swiftlang/swift-syntax`
/// @ `9d6e738` `Sources/SwiftParser` returned 98 default-tier suggestions, of
/// which 53 were lifted idempotence at `Likely` on cursor-consuming methods —
/// every one false, and none on a carrier conforming to `IteratorProtocol`.
///
/// The subject names below are verbatim from that run, not invented, so the
/// suite doubles as the regression record for the measurement.
@Suite("IdempotenceTemplate — stream-consumption veto on idempotence-lifted")
struct StreamConsumptionVetoTests {

    private func summary(
        _ name: String,
        carrier: String
    ) -> FunctionSummary {
        FunctionSummary(
            name: name,
            parameters: [],
            returnTypeText: "Void",
            isThrows: false, isAsync: false, isMutating: true, isStatic: false,
            location: SourceLocation(file: "Test.swift", line: 1, column: 1),
            containingTypeName: carrier,
            bodySignals: .empty
        )
    }

    private func valueSemanticResolver(carrier: String) -> CarrierKindResolver {
        CarrierKindResolver(typeDecls: [
            TypeDecl(
                name: carrier,
                kind: .struct,
                inheritedTypes: [],
                location: SourceLocation(file: "Test.swift", line: 1, column: 1),
                storedMembers: [StoredMember(name: "offset", typeName: "Int")]
            )
        ])
    }

    private func lifted(method: String, carrier: String) -> LiftedTransformation {
        LiftedTransformation.lift(
            summary(method, carrier: carrier),
            carrierKindResolver: valueSemanticResolver(carrier: carrier)
        )!
    }

    // MARK: - Tokenizer

    @Test("camelCaseTokens splits on word boundaries and acronym runs")
    func tokenizerSplitsCorrectly() {
        #expect(StreamConsumption.camelCaseTokens("lexNumber") == ["lex", "number"])
        #expect(StreamConsumption.camelCaseTokens("tryLexConflictMarker")
            == ["try", "lex", "conflict", "marker"])
        #expect(StreamConsumption.camelCaseTokens("advanceValidatingUTF8Character")
            == ["advance", "validating", "utf8", "character"])
        #expect(StreamConsumption.camelCaseTokens("parseXMLNode") == ["parse", "xml", "node"])
        #expect(StreamConsumption.camelCaseTokens("advance") == ["advance"])
        #expect(StreamConsumption.camelCaseTokens("").isEmpty)
    }

    @Test("token-exact matching is why this is not a prefix test (SwiftLexicalLookup control)")
    func tokenMatchingDoesNotFireOnLexicalNames() {
        // `"lexicographicallyPrecedes".hasPrefix("lex")` is TRUE, and
        // `SwiftLexicalLookup` is a real module in the measured corpus. A
        // prefix test cannot tell these from `lexNumber`; token-exact can.
        #expect(StreamConsumption.isConsumingVerb("lexNumber"))
        #expect(!StreamConsumption.isConsumingVerb("lexicographicallyPrecedes"))
        #expect(!StreamConsumption.isConsumingVerb("lexicalLookup"))
        #expect(!StreamConsumption.isConsumingVerb("lexemeCount"))
    }

    // MARK: - Tier 1 — consuming verb, any carrier

    @Test("tier 1: consuming verbs veto on a carrier with no stream noun at all")
    func consumingVerbsVetoOnNeutralCarrier() {
        for name in [
            "advance", "advanceToEndOfLine", "advanceIfOpeningRawStringDelimiter",
            "lexNumber", "lexUnknown", "tryLexEditorPlaceholder",
            "skipSingle", "skipUntilEndOfLine", "eatWhitespace", "munchDigits"
        ] {
            #expect(StreamConsumption.isConsumingVerb(name), "expected \(name) consuming")
            let signal = IdempotenceTemplate.streamConsumptionVeto(
                forLifted: lifted(method: name, carrier: "PlainStruct")
            )
            #expect(signal?.isVeto == true, "expected veto for \(name)")
        }
    }

    @Test("tier 1 precision: peek / take / scan are deliberately NOT consuming verbs")
    func deliberateOmissionsDoNotVeto() {
        // `peek` is the defining NON-consuming lookahead operation; `take` is
        // the `Option::take` idiom, which nils the storage and so IS
        // idempotent on the second call; `scan` reads both ways. All three
        // would be false vetoes on a neutral carrier.
        for name in [
            "peek", "peekToken", "take", "takeValue", "scan", "scanAll",
            // Measured out of tier 1: swift-nio's
            // `consumeAllowLocalEndpointReuse()` is `defer { flag = false }`,
            // so the second call leaves state where the first did and the
            // lifted shadow IS idempotent. Same for two nio siblings and
            // swift-collections' `consumeAll()` — four true laws tier 1 cost
            // before the demotion. Tier 2 still catches consume-on-a-cursor.
            "consumeAllowLocalEndpointReuse", "consumeAll", "consumeDisableAutoRead"
        ] {
            #expect(!StreamConsumption.isConsumingVerb(name), "expected \(name) NOT consuming")
            #expect(IdempotenceTemplate.streamConsumptionVeto(
                forLifted: lifted(method: name, carrier: "PlainStruct")
            ) == nil)
        }
    }

    // MARK: - Tier 2 — stream carrier, any move

    @Test("tier 2: query-SHAPED mutating methods veto on a stream carrier")
    func queryShapedMethodsVetoOnStreamCarrier() throws {
        // 20 of the 53 are named like predicates but declared `mutating` —
        // speculative consumption. Tier 1 cannot reach them; only the carrier
        // settles it. Subjects verbatim from the SwiftParser run.
        let cases: [(method: String, carrier: String)] = [
            ("canParseType", "Parser.Lookahead"),
            ("canParsePattern", "Parser.Lookahead"),
            ("canParseClosureSignature", "Parser.Lookahead"),
            ("atStartOfSwitchCase", "Parser.Lookahead"),
            ("atStartOfGetSetAccessor", "Parser.Lookahead"),
            ("atStartOfExpression", "TokenConsumer"),
            ("atBinaryOperatorArgument", "TokenConsumer"),
            ("isAtModuleSelector", "TokenConsumer")
        ]
        for (method, carrier) in cases {
            let signal = IdempotenceTemplate.streamConsumptionVeto(
                forLifted: lifted(method: method, carrier: carrier)
            )
            let veto = try #require(signal, "expected veto for \(carrier).\(method)")
            #expect(veto.isVeto)
            #expect(veto.detail.contains("position in a stream"))
        }
    }

    @Test("tier 2: carrier nouns match on any dotted component")
    func streamCarrierMatchesNestedComponents() {
        for carrier in [
            "Lexer.Cursor", "Lexer.Cursor.Position", "Parser.Lookahead",
            "TokenConsumer", "SourceReader", "ByteStream", "JSONTokenizer",
            "SimpleScanner", "BucketIterator"
        ] {
            #expect(StreamConsumption.isStreamCarrier(carrier), "expected \(carrier) stream-shaped")
        }
    }

    @Test("tier 2 precision: container and accumulator carriers are NOT stream-shaped")
    func nonStreamCarriersDoNotVeto() {
        // `Buffer` is a container, not a position; `Builder` is an
        // accumulator — a different non-idempotence family this veto must not
        // silently claim. `Parse` is not `Parser`.
        for carrier in [
            "RingBuffer", "FrameBuffer", "RequestBuilder", "OrderedDictionary",
            "ParseResult", "LexemeStore", "PlainStruct"
        ] {
            #expect(!StreamConsumption.isStreamCarrier(carrier), "expected \(carrier) NOT stream-shaped")
            #expect(IdempotenceTemplate.streamConsumptionVeto(
                forLifted: lifted(method: "normalize", carrier: carrier)
            ) == nil)
        }
    }

    @Test("restoring verbs keep their idempotence claim despite a stream carrier")
    func restoringVerbsAreExempt() {
        // `reset` / `rewind` move a position to a FIXED POINT, so
        // `f(f(s)) == f(s)` genuinely holds — the veto would cost a true law.
        for name in ["reset", "rewind", "restore", "seek", "rollback", "clear", "resetToStart"] {
            #expect(IdempotenceTemplate.streamConsumptionVeto(
                forLifted: lifted(method: name, carrier: "Lexer.Cursor")
            ) == nil, "expected \(name) exempt")
        }
        // Leading-token only: a compound that also consumes is NOT exempt.
        #expect(!StreamConsumption.isRestoring("advanceAndRewind"))
    }

    // MARK: - End to end through the template

    /// The 52 consuming picks from `discover --sources Sources/SwiftParser` on
    /// swift-syntax @ `9d6e738`, verbatim. Each scored Likely 45 before this
    /// veto. (The 53rd, `recordOpenSlash`, is the recorded residue below.)
    private static let swiftParserSubjects: [(method: String, carrier: String)] = [
        ("canParseCustomAttribute", "Parser.Lookahead"),
        ("advance", "Lexer.Cursor.Position"),
        ("advance", "Lexer.Cursor"),
        ("advanceToEndOfLine", "Lexer.Cursor"),
        ("advanceToEndOfSlashStarComment", "Lexer.Cursor"),
        ("advanceIfOpeningRawStringDelimiter", "Lexer.Cursor"),
        ("advanceValidatingUTF8Character", "Lexer.Cursor"),
        ("lexNumber", "Lexer.Cursor"),
        ("lexHexNumber", "Lexer.Cursor"),
        ("lexMagicPoundLiteral", "Lexer.Cursor"),
        ("lexIdentifier", "Lexer.Cursor"),
        ("lexEscapedIdentifier", "Lexer.Cursor"),
        ("lexPostfixOptionalChain", "Lexer.Cursor"),
        ("lexDollarIdentifier", "Lexer.Cursor"),
        ("tryLexEditorPlaceholder", "Lexer.Cursor"),
        ("lexUnknown", "Lexer.Cursor"),
        ("tryLexConflictMarker", "Lexer.Cursor"),
        ("lexRegexLiteral", "Lexer.Cursor"),
        ("atStartOfFreestandingMacroExpansion", "TokenConsumer"),
        ("atStartOfExpression", "TokenConsumer"),
        ("atBinaryOperatorArgument", "TokenConsumer"),
        ("isAtModuleSelector", "TokenConsumer"),
        ("consumeModuleSelectorTokensIfPresent", "TokenConsumer"),
        ("atStartOfLabelledTrailingClosure", "Parser.Lookahead"),
        ("consumeEffectsSpecifiers", "Parser.Lookahead"),
        ("canParseClosureSignature", "Parser.Lookahead"),
        ("consumeAnyToken", "Parser.Lookahead"),
        ("consumeAnyAttribute", "Parser.Lookahead"),
        ("consumeAttributeList", "Parser.Lookahead"),
        ("consumeIfConfigOfAttributes", "Parser.Lookahead"),
        ("atStartOfGetSetAccessor", "Parser.Lookahead"),
        ("skipUntilEndOfLine", "Parser.Lookahead"),
        ("skipSingle", "Parser.Lookahead"),
        ("canParsePattern", "Parser.Lookahead"),
        ("atStartOfSwitchCase", "Parser.Lookahead"),
        ("atStartOfConditionalSwitchCases", "Parser.Lookahead"),
        ("atStartOfConditionalStatementBody", "Parser.Lookahead"),
        ("canParseType", "Parser.Lookahead"),
        ("canParseValueGenericArgument", "Parser.Lookahead"),
        ("canParseTypeAttributeList", "Parser.Lookahead"),
        ("canParseTypeScalar", "Parser.Lookahead"),
        ("canParseSimpleOrCompositionType", "Parser.Lookahead"),
        ("canParseSimpleType", "Parser.Lookahead"),
        ("canParseStartOfInlineArrayTypeBody", "Parser.Lookahead"),
        ("canParseInlineArrayTypeBody", "Parser.Lookahead"),
        ("canParseCollectionTypeBody", "Parser.Lookahead"),
        ("canParseTupleBodyType", "Parser.Lookahead"),
        ("canParseFunctionTypeArrow", "Parser.Lookahead"),
        ("canParseAsGenericArgumentList", "Parser.Lookahead"),
        ("canParseIntegerLiteral", "Parser.Lookahead"),
        ("canParseGenericArgument", "Parser.Lookahead"),
        ("consumeGenericArguments", "Parser.Lookahead")
    ]

    @Test("all 52 consuming SwiftParser subjects are suppressed end to end")
    func swiftParserSubjectsAreSuppressed() {
        for (method, carrier) in Self.swiftParserSubjects {
            let suggestion = IdempotenceTemplate.suggest(
                forLifted: lifted(method: method, carrier: carrier),
                carrierKindResolver: valueSemanticResolver(carrier: carrier)
            )
            #expect(suggestion == nil, "expected \(carrier).\(method) suppressed")
        }
    }

    @Test("recorded residue: RegexLiteralLexemes.Builder.recordOpenSlash is NOT caught")
    func accumulatorResidueIsPinned() {
        // The 53rd subject. Non-idempotent because it APPENDS — the
        // accumulator family, not stream consumption. Pinned so the veto's
        // boundary is visible in the suite rather than discovered later, and
        // so a future accumulator veto has a named starting case.
        let residue = lifted(
            method: "recordOpenSlash",
            carrier: "RegexLiteralLexemes.Builder"
        )
        #expect(IdempotenceTemplate.streamConsumptionVeto(forLifted: residue) == nil)
    }

    @Test("a genuinely idempotent mutator on a neutral carrier still surfaces")
    func trueIdempotencePositiveSurvives() {
        // The control the whole veto has to not break: `normalize` on a
        // non-stream carrier is the curated-verb Strong case.
        let suggestion = IdempotenceTemplate.suggest(
            forLifted: lifted(method: "normalize", carrier: "PlainStruct"),
            carrierKindResolver: valueSemanticResolver(carrier: "PlainStruct")
        )
        #expect(suggestion != nil)
    }

    // MARK: - Chaining with the IteratorProtocol veto

    @Test("an IteratorProtocol carrier renders ONE veto bullet, not two")
    func vetoesChainRatherThanStack() {
        // `BucketIterator.advance()` satisfies both the V1.21.A name fallback
        // and this veto's carrier tier. `liftedCarrierVetoes` chains them, so
        // the reader sees one reason.
        let candidate = lifted(method: "advance", carrier: "BucketIterator")
        let signals = IdempotenceTemplate.liftedAccumulatedSignals(
            for: candidate,
            vocabulary: .empty,
            inheritedTypesByName: ["BucketIterator": ["IteratorProtocol"]],
            carrierKindResolver: valueSemanticResolver(carrier: "BucketIterator")
        )
        let vetoes = signals.filter(\.isVeto)
        #expect(vetoes.count == 1)
        #expect(vetoes.first?.detail.contains("IteratorProtocol") == true)
    }
}
