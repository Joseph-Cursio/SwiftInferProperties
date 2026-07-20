@testable import SwiftInferCLI
import Testing

/// Fast checks on the shape of the emitted init-decode codec verifier — the
/// encode call, the decode form (failable vs not), and the `VERIFY_*` marker
/// contract — without paying for a `swift build`.
@Suite("InitDecodeStubEmitter — emitted verifier shape")
struct InitDecodeStubEmitterTests {

    private func emit(
        typeName: String = "Blob",
        encodeMethod: String = "base64EncodedString",
        encodeIsProperty: Bool = false,
        decodeLabel: String = "base64Encoded",
        isFailable: Bool = true,
        values: String = "[Blob(raw: 0), Blob(raw: 1)]"
    ) -> String {
        InitDecodeStubEmitter.emit(
            .init(
                typeName: typeName,
                encodeMethod: encodeMethod,
                encodeIsProperty: encodeIsProperty,
                decodeLabel: decodeLabel,
                isFailable: isFailable,
                valuesExpression: values
            )
        )
    }

    @Test("emits the VERIFY marker contract and the labelled init decode call")
    func markerContractAndDecodeCall() {
        let stub = emit()
        #expect(stub.contains("VERIFY_DEFAULT_RESULT: PASS"))
        #expect(stub.contains("VERIFY_EDGE_RESULT: PASS"))
        #expect(stub.contains("VERIFY_DEFAULT_RESULT: FAIL"))
        #expect(stub.contains("exit(0)"))
        #expect(stub.contains("exit(1)"))
        // The decode is the labelled initializer.
        #expect(stub.contains("Blob(base64Encoded: encoded)"))
        // The encode is a method call.
        #expect(stub.contains("original.base64EncodedString()"))
    }

    @Test("a failable init guards the nil case; a non-failable one does not")
    func failableVsNonFailable() {
        let failable = emit(isFailable: true)
        #expect(failable.contains("guard let decoded ="))
        #expect(failable.contains("returned nil for a freshly-encoded value"))

        let total = emit(isFailable: false)
        #expect(total.contains("let decoded = Blob(base64Encoded: encoded)"))
        #expect(!total.contains("guard let decoded ="))
    }

    @Test("a computed-property encode is accessed without parentheses")
    func computedPropertyEncode() {
        let stub = emit(encodeMethod: "base64", encodeIsProperty: true)
        #expect(stub.contains("original.base64"))
        #expect(!stub.contains("original.base64()"))
    }
}
