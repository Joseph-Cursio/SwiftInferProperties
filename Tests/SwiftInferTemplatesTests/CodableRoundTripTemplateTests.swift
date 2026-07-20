import PropertyLawCore
import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

/// The codable-round-trip template — a type with a *hand-written* `Codable`
/// conformance (`encode(to: Encoder)` + `init(from: Decoder)`) owes
/// `decode(encode(x)) == x`. Motivated by the swift-asn1 signed-integer bug
/// (`docs/backtest-codable-roundtrip-pressuretest.md`).
@Suite("CodableRoundTripTemplate — custom Codable round-trip")
struct CodableRoundTripTemplateTests {

    private static let loc = SourceLocation(file: "Model.swift", line: 1, column: 1)

    private func encodeSummary(type: String) -> FunctionSummary {
        FunctionSummary(
            name: "encode",
            parameters: [Parameter(label: "to", internalName: "encoder", typeText: "Encoder", isInout: false)],
            returnTypeText: nil,
            isThrows: true,
            isAsync: false,
            isMutating: false,
            isStatic: false,
            location: Self.loc,
            containingTypeName: type,
            bodySignals: .empty
        )
    }

    private func decodeInitDecl(_ type: String, kind: TypeDecl.Kind = .struct) -> TypeDecl {
        TypeDecl(
            name: type,
            kind: kind,
            inheritedTypes: [],
            location: Self.loc,
            initializers: [
                InitializerSignature(
                    parameters: [InitializerParameter(label: "from", typeName: "Decoder")],
                    isThrowing: true
                )
            ]
        )
    }

    // MARK: - Unit level: pairing gate

    @Test("a type with BOTH custom encode(to:) and init(from:) surfaces at Likely 50")
    func customPairSurfaces() throws {
        let suggestions = CodableRoundTripTemplate.suggestions(
            typeDecls: [decodeInitDecl("Ratio")],
            summaries: [encodeSummary(type: "Ratio")]
        )
        let suggestion = try #require(suggestions.first)
        #expect(suggestions.count == 1)
        #expect(suggestion.templateName == "codable-round-trip")
        #expect(suggestion.score.tier == .likely)
        #expect(suggestion.carrier == "Ratio")
    }

    @Test("encode-only (no custom init(from:)) does NOT surface")
    func encodeOnlyGated() {
        let suggestions = CodableRoundTripTemplate.suggestions(
            typeDecls: [],
            summaries: [encodeSummary(type: "Ratio")]
        )
        #expect(suggestions.isEmpty)
    }

    @Test("decode-only (no custom encode(to:)) does NOT surface")
    func decodeOnlyGated() {
        let suggestions = CodableRoundTripTemplate.suggestions(
            typeDecls: [decodeInitDecl("Ratio")],
            summaries: []
        )
        #expect(suggestions.isEmpty)
    }

    @Test("a non-Encoder encode(to:) is not recognised (a same-named domain method)")
    func nonEncoderEncodeRejected() {
        let notCodec = FunctionSummary(
            name: "encode",
            parameters: [Parameter(label: "to", internalName: "buffer", typeText: "ByteBuffer", isInout: false)],
            returnTypeText: nil, isThrows: false, isAsync: false, isMutating: false, isStatic: false,
            location: Self.loc, containingTypeName: "Ratio", bodySignals: .empty
        )
        let suggestions = CodableRoundTripTemplate.suggestions(
            typeDecls: [decodeInitDecl("Ratio")],
            summaries: [notCodec]
        )
        #expect(suggestions.isEmpty)
    }

    // MARK: - End-to-end scan: synthesized silent, custom (body + extension) surfaces

    private func picks(_ source: String) -> [Suggestion] {
        let corpus = FunctionScanner.scanCorpus(source: source, file: "Model.swift")
        return CodableRoundTripTemplate.suggestions(
            typeDecls: corpus.typeDecls,
            summaries: corpus.summaries
        )
    }

    @Test("synthesized Codable (no source encode/decode) stays silent — the Daikon gate")
    func synthesizedSilent() {
        #expect(picks("public struct Point: Codable, Equatable { public var x: Int; public var y: Int }").isEmpty)
    }

    @Test("custom Codable in the primary body surfaces")
    func customInBodySurfaces() {
        let source = """
        public struct Ratio: Codable, Equatable {
            public var value: Double
            public init(from decoder: Decoder) throws {
                self.value = try decoder.singleValueContainer().decode(Double.self)
            }
            public func encode(to encoder: Encoder) throws {
                var c = encoder.singleValueContainer()
                try c.encode(value)
            }
        }
        """
        let result = picks(source)
        #expect(result.count == 1)
        #expect(result.first?.carrier == "Ratio")
    }

    @Test("custom Codable declared in EXTENSIONS surfaces (the idiomatic conditional-conformance shape)")
    func customInExtensionSurfaces() {
        // The swift-collections `OrderedDictionary+Codable.swift` shape: encode and
        // init(from:) each in their own conditional-conformance extension.
        let source = """
        public struct Bag<T>: Equatable { public var items: [T] }
        extension Bag: Encodable where T: Encodable {
            public func encode(to encoder: Encoder) throws {
                var c = encoder.unkeyedContainer()
                for item in items { try c.encode(item) }
            }
        }
        extension Bag: Decodable where T: Decodable {
            public init(from decoder: Decoder) throws {
                var c = try decoder.unkeyedContainer()
                var out: [T] = []
                while !c.isAtEnd { out.append(try c.decode(T.self)) }
                self.items = out
            }
        }
        """
        let result = picks(source)
        #expect(result.count == 1)
        #expect(result.first?.carrier == "Bag")
    }
}
