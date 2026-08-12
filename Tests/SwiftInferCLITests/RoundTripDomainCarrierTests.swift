import SwiftInferCore
import Testing

@testable import SwiftInferCLI

private typealias VerifyCmd = SwiftInferCommand.Verify

/// The domain a `round-trip` law quantifies over (issue #235).
///
/// The composer emits `inverse(forward(value)) != value`, so `value` must have the
/// type `forward` accepts. That is the declaring type only when the forward half is
/// the receiver; for a parse/print pair — `static parse(String) -> Self` paired with
/// `serialized() -> String` — the round trip is anchored at `String`, and generating
/// the carrier instead produced `cannot convert value of type 'SwiftFormatConfig' to
/// expected argument type 'String'` before a single trial ran.
///
/// **The arms that matter are the ones that return `nil`.** A rule that answered
/// "the parameter type" for every entry would silently re-anchor the curated
/// `Complex`/`Double` pairs and every other template, and the resulting stubs would
/// fail somewhere else entirely. Each `nil` case below is a shape the rule must
/// decline, so the fallback stays bit-identical to the pre-fix behaviour.
@Suite("Round-trip domain carrier")
struct RoundTripDomainCarrierTests {

    private func entry(
        template: String = "round-trip",
        function: String,
        isInstanceMethod: Bool = false,
        parameterTypeNames: [String] = [],
        typeName: String? = "SwiftFormatConfig"
    ) -> SemanticIndexEntry {
        SemanticIndexEntry(
            identityHash: "0x1",
            templateName: template,
            typeName: typeName,
            score: 50,
            tier: "Likely",
            primaryFunctionName: function,
            location: "/Module.swift:1",
            firstSeenAt: "2026-08-12T00:00:00Z",
            lastSeenAt: "2026-08-12T00:00:00Z",
            secondaryFunctionName: "serialized()",
            isInstanceMethod: isInstanceMethod,
            parameterTypeNames: parameterTypeNames
        )
    }

    @Test("a static forward taking one parameter anchors at that parameter's type")
    func staticForwardAnchorsAtParameter() {
        let subject = entry(function: "parse(_:)", parameterTypeNames: ["String"])
        #expect(VerifyCmd.roundTripDomainCarrier(entry: subject) == "String")
    }

    @Test("an instance-method forward declines — the value IS the receiver")
    func instanceForwardDeclines() {
        // `value.encoded()` quantifies over the declaring type, which `typeName`
        // already reports. Re-anchoring here would generate the ENCODED type and
        // then call `encoded()` on it.
        let subject = entry(
            function: "encoded()", isInstanceMethod: true, parameterTypeNames: []
        )
        #expect(VerifyCmd.roundTripDomainCarrier(entry: subject) == nil)
    }

    @Test("a two-parameter forward declines — there is no single domain")
    func twoParameterForwardDeclines() {
        let subject = entry(
            function: "parse(_:options:)", parameterTypeNames: ["String", "Options"]
        )
        #expect(VerifyCmd.roundTripDomainCarrier(entry: subject) == nil)
    }

    @Test("an unrecorded parameter list declines rather than guessing")
    func unrecordedParametersDecline() {
        // Empty means *not recorded* — an index written before `parameterTypeNames`
        // existed. Guessing here would re-anchor entries whose types nobody read.
        let subject = entry(function: "parse(_:)", parameterTypeNames: [])
        #expect(VerifyCmd.roundTripDomainCarrier(entry: subject) == nil)
    }

    @Test("a non-round-trip template declines")
    func otherTemplatesDecline() {
        let subject = entry(
            template: "idempotence", function: "normalize(_:)", parameterTypeNames: ["String"]
        )
        #expect(VerifyCmd.roundTripDomainCarrier(entry: subject) == nil)
    }

    @Test("the curated Complex pair is unchanged — the parameter IS the carrier")
    func curatedPairIsBitIdentical() {
        // `Complex.exp(_ z: Complex<Double>) -> Complex<Double>`. The rule fires and
        // returns the same type the old `carrierTypeName ?? typeName` path produced,
        // which is why the cycle27 key does not move.
        let subject = entry(
            function: "exp(_:)",
            parameterTypeNames: ["Complex<Double>"],
            typeName: "Complex<Double>"
        )
        #expect(VerifyCmd.roundTripDomainCarrier(entry: subject) == "Complex<Double>")
    }
}
