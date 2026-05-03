import Testing
@testable import SwiftInferTemplates

@Suite("CodableRoundTripGeneratorRenderer — body-string shape (M5.4)")
struct CodableRoundTripGeneratorRendererTests {

    @Test
    func renderedBodyContainsTypeName() {
        let rendered = CodableRoundTripGeneratorRenderer.renderGenerator(for: "Money")
        #expect(rendered.contains("Gen<Money>"))
        #expect(rendered.contains("decode(Money.self"))
    }

    @Test
    func renderedBodyUsesJSONEncoderAndJSONDecoder() {
        let rendered = CodableRoundTripGeneratorRenderer.renderGenerator(for: "T")
        #expect(rendered.contains("JSONEncoder()"))
        #expect(rendered.contains("JSONDecoder()"))
    }

    @Test
    func renderedBodyDocumentsTheReplaceFixtureRequirement() {
        let rendered = CodableRoundTripGeneratorRenderer.renderGenerator(for: "T")
        #expect(rendered.contains("fixture"))
    }

    @Test
    func renderedBodyChainsEncodeThenDecode() {
        let rendered = CodableRoundTripGeneratorRenderer.renderGenerator(for: "T")
        #expect(rendered.contains("encoder.encode(value)"))
        #expect(rendered.contains("decoder.decode(T.self"))
    }
}
