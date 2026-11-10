@testable import SwiftInferCLI
import Testing

@Suite("InteractiveTriage — parameter parsing (determinism stub, any arity)")
struct InteractiveTriageParameterParsingTests {

    @Test func parameterTypesSplitsTopLevelCommasOnly() {
        #expect(InteractiveTriage.parameterTypes(from: "(String) -> Int") == ["String"])
        #expect(InteractiveTriage.parameterTypes(from: "(Money, Money) -> Money") == ["Money", "Money"])
        #expect(InteractiveTriage.parameterTypes(from: "() -> Int").isEmpty)
        // Comma inside generic brackets stays one parameter.
        #expect(
            InteractiveTriage.parameterTypes(from: "(Dictionary<String, Int>, Bool) -> Int")
                == ["Dictionary<String, Int>", "Bool"]
        )
        #expect(InteractiveTriage.parameterTypes(from: "(any Backend) -> Env") == ["any Backend"])
    }

    @Test func parameterLabelsMapUnderscoreToNil() {
        #expect(InteractiveTriage.parameterLabels(from: "describe(_:)") == [nil])
        #expect(InteractiveTriage.parameterLabels(from: "memberGenerator(forTypeName:)") == ["forTypeName"])
        #expect(InteractiveTriage.parameterLabels(from: "combine(_:with:)") == [nil, "with"])
        #expect(InteractiveTriage.parameterLabels(from: "make()").isEmpty)
    }

    @Test func functionParametersZipsLabelsAndTypes() throws {
        let params = try #require(
            InteractiveTriage.functionParameters(displayName: "combine(_:with:)", signature: "(Int, String) -> Int")
        )
        #expect(params.count == 2)
        #expect(params[0].label == nil)
        #expect(params[0].type == "Int")
        #expect(params[1].label == "with")
        #expect(params[1].type == "String")
    }

    @Test func functionParametersReturnsNilForZeroParamsOrMismatch() {
        #expect(InteractiveTriage.functionParameters(displayName: "make()", signature: "() -> Int") == nil)
        // Label/type count disagree → untrusted parse.
        #expect(
            InteractiveTriage.functionParameters(displayName: "f(_:)", signature: "(Int, Int) -> Int") == nil
        )
    }
}
