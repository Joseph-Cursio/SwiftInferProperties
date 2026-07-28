import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

/// Exemption 4 on `RoundTripTemplate`'s cross-type counter —
/// `docs/parsing-catalog-gap.md` §3b.
///
/// The counter subtracts 25 from any pair whose halves live in different
/// types, and it earns that: re-measured across the reference corpora it
/// suppresses **1,380 cross-type pairs**, of which 1,310 have the degenerate
/// `T -> T` shape and nearly all the rest are accidents. But it also
/// suppressed the shape a serializer round trip actually takes — a
/// `Loader`/`Writer` split — so a package built around a config serializer
/// got no proposal for it at any tier.
///
/// The negative cases below are taken verbatim from that measurement, not
/// invented, because the two obvious discriminators both fail against them
/// and the suite is where that stays visible.
@Suite("RoundTripTemplate — codec-carrier exemption on the cross-type counter")
struct CodecCarrierPairingTests {

    private func summary(
        _ name: String,
        param: String,
        returns: String,
        carrier: String?
    ) -> FunctionSummary {
        FunctionSummary(
            name: name,
            parameters: [Parameter(label: nil, internalName: "v", typeText: param, isInout: false)],
            returnTypeText: returns,
            isThrows: false, isAsync: false, isMutating: false, isStatic: true,
            location: SourceLocation(file: "Test.swift", line: 1, column: 1),
            containingTypeName: carrier,
            bodySignals: .empty
        )
    }

    // MARK: - The gate itself

    @Test("mutually inverse role nouns are complementary, stem or no stem")
    func inverseRolesAreComplementary() {
        for (lhs, rhs) in [
            ("LintConfigurationLoader", "LintConfigurationWriter"),  // the motivating case
            ("Loader", "Writer"),                                    // bare, no shared stem
            ("JSONEncoder", "PlistDecoder"),                         // different stems
            ("SwiftParser", "SwiftPrinter"),
            ("MessagePacker", "MessageUnpacker"),
            ("CSVImporter", "CSVExporter"),
            ("Foo.Bar.ConfigReader", "Baz.ConfigWriter")             // nested, leaf wins
        ] {
            #expect(CodecCarrierPairing.areComplementary(lhs, rhs), "expected \(lhs)/\(rhs)")
            #expect(CodecCarrierPairing.areComplementary(rhs, lhs), "expected order-insensitive")
        }
    }

    @Test("the measured noise carriers are NOT complementary — including the stem-sharers")
    func measuredNoiseIsRejected() {
        // Every pair here is from the 1,380 the counter suppresses. The top
        // offenders SHARE A STEM, which is why the obvious "shared stem means
        // one codec" rule was rejected: it would have re-admitted the flood.
        for (lhs, rhs) in [
            ("BigString", "BigString.UTF8View"),
            ("BigString", "BigSubstring.UTF16View"),
            ("BigString._Chunk", "BigString"),
            ("BigSubstring.UTF8View", "BigSubstring.UnicodeScalarView"),
            ("BitSet", "BitSet.Counted"),
            ("ByteBufferAllocator", "ByteBuffer"),
            ("Syntax", "SyntaxRewriter"),
            ("FileHandle", "SystemFileHandle"),
            ("RigidSet", "UniqueSet"),
            ("AbsolutePosition", "SourceLineTable")
        ] {
            #expect(!CodecCarrierPairing.areComplementary(lhs, rhs), "expected \(lhs)/\(rhs) rejected")
        }
    }

    @Test("the same role noun on both sides is not a pair")
    func identicalRolesAreNotComplementary() {
        // `FileHandle` × `SystemFileHandle` both end in `handle`; two writers
        // are two writers, not a codec.
        #expect(!CodecCarrierPairing.areComplementary("FileWriter", "AtomicFileWriter"))
        #expect(!CodecCarrierPairing.areComplementary("FileHandle", "SystemFileHandle"))
    }

    @Test("roleNoun takes the last camelCase token of the last dotted component")
    func roleNounExtraction() {
        #expect(CodecCarrierPairing.roleNoun(of: "LintConfigurationLoader") == "loader")
        #expect(CodecCarrierPairing.roleNoun(of: "BigSubstring.UTF8View") == "view")
        #expect(CodecCarrierPairing.roleNoun(of: "BigString._Chunk") == "chunk")
        #expect(CodecCarrierPairing.roleNoun(of: "Writer") == "writer")
    }

    @Test("'persistence' is deliberately absent, and it costs a real pair")
    func persistenceIsNotARole() {
        // SwiftProjectLint's `YAMLConfigurationPersistence.load` ×
        // `LintConfigurationWriter.render` stays suppressed. "Persistence"
        // names a concern, not a direction — a `FooPersistence` is as likely
        // to hold BOTH halves as one — so admitting it would admit any
        // type ending that way against any other. Recorded, not widened.
        #expect(!CodecCarrierPairing.areComplementary(
            "YAMLConfigurationPersistence", "LintConfigurationWriter"
        ))
    }

    // MARK: - End to end through the template

    @Test("the Loader/Writer codec pair is no longer suppressed")
    func codecPairSurvivesTheCounter() throws {
        // The motivating case, at its measured signature.
        let pair = FunctionPair(
            forward: summary(
                "load", param: "String", returns: "LintConfiguration",
                carrier: "LintConfigurationLoader"
            ),
            reverse: summary(
                "render", param: "LintConfiguration", returns: "String",
                carrier: "LintConfigurationWriter"
            )
        )
        let suggestion = try #require(
            RoundTripTemplate.suggest(for: pair),
            "the codec pair should survive the cross-type counter"
        )
        #expect(!suggestion.score.signals.contains { $0.kind == .crossTypeRoundTripPair })
        #expect(suggestion.score.total == 30)
    }

    @Test("the degenerate Index flood is still suppressed — the counter keeps its job")
    func indexFloodStaysSuppressed() {
        // `BigString._characterIndex(after:)` × `BigSubstring.index(after:)`,
        // the shape behind 1,310 of the 1,380. Nothing about this fix may
        // let it back in.
        let flood = FunctionPair(
            forward: summary("_characterIndex", param: "Index", returns: "Index", carrier: "BigString"),
            reverse: summary("index", param: "Index", returns: "Index", carrier: "BigSubstring.UTF8View")
        )
        #expect(RoundTripTemplate.suggest(for: flood) == nil)
    }

    @Test("exemption 4 overlaps exemption 3, and wins where they disagree")
    func codecCarriersExemptEvenWithMismatchedDiscoverableGroups() throws {
        // Worth pinning because it CHANGED existing behaviour. Exemption 3
        // says a mismatched `@Discoverable(group:)` does not exempt — the
        // user grouped these into different scopes, so their pairing is not
        // user-endorsed. On `Encoder`/`Decoder` carriers, exemption 4 now
        // exempts anyway, because the carriers' names are structural evidence
        // that does not depend on the user having annotated anything.
        //
        // That is the intended precedence: the annotation is one source of
        // evidence, not the only one. `CrossTypeRoundTripTests` was rewritten
        // to use neutral carrier names so it still tests exemption 3's own
        // boundary rather than this overlap.
        let pair = FunctionPair(
            forward: FunctionSummary(
                name: "transform",
                parameters: [Parameter(label: nil, internalName: "v", typeText: "Doc", isInout: false)],
                returnTypeText: "Data",
                isThrows: false, isAsync: false, isMutating: false, isStatic: true,
                location: SourceLocation(file: "Test.swift", line: 1, column: 1),
                containingTypeName: "Encoder",
                bodySignals: .empty,
                discoverableGroup: "codec"
            ),
            reverse: FunctionSummary(
                name: "untransform",
                parameters: [Parameter(label: nil, internalName: "v", typeText: "Data", isInout: false)],
                returnTypeText: "Doc",
                isThrows: false, isAsync: false, isMutating: false, isStatic: true,
                location: SourceLocation(file: "Test.swift", line: 1, column: 1),
                containingTypeName: "Decoder",
                bodySignals: .empty,
                discoverableGroup: "queue"
            )
        )
        let suggestion = try #require(RoundTripTemplate.suggest(for: pair))
        #expect(!suggestion.score.signals.contains { $0.kind == .crossTypeRoundTripPair })
    }

    @Test("a cross-type pair with no role nouns at all is still suppressed")
    func plainCrossTypePairStaysSuppressed() {
        let plain = FunctionPair(
            forward: summary("buffer", param: "Int", returns: "ByteBuffer", carrier: "ByteBufferAllocator"),
            reverse: summary("readerIndex", param: "ByteBuffer", returns: "Int", carrier: "ByteBuffer")
        )
        #expect(RoundTripTemplate.suggest(for: plain) == nil)
    }
}
