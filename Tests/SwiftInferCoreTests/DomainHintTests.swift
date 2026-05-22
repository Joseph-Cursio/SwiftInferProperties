@testable import SwiftInferCore
import Testing

@Suite("DomainHint — data model (M10.0)")
struct DomainHintTests {

    @Test
    func equatableConformanceMatchesByValue() {
        let hint1 = DomainHint(
            forwardName: "encode",
            reverseName: "decode",
            producerName: "encode",
            domainTypeName: "MyType",
            siteCount: 5,
            producerVeto: nil,
            suggestedGenerator: "Gen<MyType>.gen().map(encode)"
        )
        let hint2 = DomainHint(
            forwardName: "encode",
            reverseName: "decode",
            producerName: "encode",
            domainTypeName: "MyType",
            siteCount: 5,
            producerVeto: nil,
            suggestedGenerator: "Gen<MyType>.gen().map(encode)"
        )
        let hint3 = DomainHint(
            forwardName: "encode",
            reverseName: "decode",
            producerName: "encode",
            domainTypeName: "MyType",
            siteCount: 4,
            producerVeto: nil,
            suggestedGenerator: "Gen<MyType>.gen().map(encode)"
        )
        #expect(hint1 == hint2)
        #expect(hint1 != hint3)
    }

    @Test
    func producerVetoReasonEquatableDistinguishesCases() {
        let throwsReason = ProducerVetoReason.producerThrows
        #expect(throwsReason == ProducerVetoReason.producerThrows)
        #expect(ProducerVetoReason.producerThrows != ProducerVetoReason.producerAsync)
        #expect(ProducerVetoReason.producerMultiArg != ProducerVetoReason.producerArgNotGeneratable)
    }

    @Test
    func producerVetoFieldDistinguishesEqualOtherwiseHints() {
        let unvetoed = DomainHint(
            forwardName: "encode",
            reverseName: "decode",
            producerName: "encode",
            domainTypeName: "MyType",
            siteCount: 5,
            producerVeto: nil,
            suggestedGenerator: "Gen<MyType>.gen().map(encode)"
        )
        let vetoedThrows = DomainHint(
            forwardName: "encode",
            reverseName: "decode",
            producerName: "encode",
            domainTypeName: "MyType",
            siteCount: 5,
            producerVeto: .producerThrows,
            suggestedGenerator: "Gen<MyType>.gen().map(encode)"
        )
        let vetoedAsync = DomainHint(
            forwardName: "encode",
            reverseName: "decode",
            producerName: "encode",
            domainTypeName: "MyType",
            siteCount: 5,
            producerVeto: .producerAsync,
            suggestedGenerator: "Gen<MyType>.gen().map(encode)"
        )
        #expect(unvetoed != vetoedThrows)
        #expect(vetoedThrows != vetoedAsync)
    }

    @Test
    func mockGeneratorDomainHintDefaultsToNil() {
        let mock = MockGenerator(
            typeName: "Doc",
            argumentSpec: [],
            siteCount: 5
        )
        #expect(mock.domainHint == nil)
    }

    @Test
    func mockGeneratorAcceptsExplicitDomainHint() {
        let hint = DomainHint(
            forwardName: "encode",
            reverseName: "decode",
            producerName: "encode",
            domainTypeName: "Doc",
            siteCount: 5,
            producerVeto: nil,
            suggestedGenerator: "Gen<Doc>.gen().map(encode)"
        )
        let mock = MockGenerator(
            typeName: "Doc",
            argumentSpec: [],
            siteCount: 5,
            domainHint: hint
        )
        #expect(mock.domainHint == hint)
    }

    @Test
    func mockGeneratorEquatableComparesDomainHint() {
        let hint = DomainHint(
            forwardName: "encode",
            reverseName: "decode",
            producerName: "encode",
            domainTypeName: "Doc",
            siteCount: 3,
            producerVeto: nil,
            suggestedGenerator: "Gen<Doc>.gen().map(encode)"
        )
        let withHint = MockGenerator(
            typeName: "Doc", argumentSpec: [], siteCount: 3, domainHint: hint
        )
        let withoutHint = MockGenerator(typeName: "Doc", argumentSpec: [], siteCount: 3)
        #expect(withHint != withoutHint)
        let alsoWithHint = MockGenerator(
            typeName: "Doc", argumentSpec: [], siteCount: 3, domainHint: hint
        )
        #expect(withHint == alsoWithHint)
    }

    @Test
    func mockGeneratorPreconditionHintsAndDomainHintCoexist() {
        let domainHint = DomainHint(
            forwardName: "encode",
            reverseName: "decode",
            producerName: "encode",
            domainTypeName: "Doc",
            siteCount: 5,
            producerVeto: nil,
            suggestedGenerator: "Gen<Doc>.gen().map(encode)"
        )
        let preconditionHint = PreconditionHint(
            position: 0,
            argumentLabel: "count",
            pattern: .positiveInt,
            siteCount: 5,
            suggestedGenerator: "Gen.int(in: 1...)"
        )
        let mock = MockGenerator(
            typeName: "Doc",
            argumentSpec: [],
            siteCount: 5,
            preconditionHints: [preconditionHint],
            domainHint: domainHint
        )
        #expect(mock.preconditionHints == [preconditionHint])
        #expect(mock.domainHint == domainHint)
    }
}
