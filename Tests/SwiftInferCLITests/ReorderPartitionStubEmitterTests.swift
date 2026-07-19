@testable import SwiftInferCLI
import Testing

/// Fast checks on the shape of the emitted reorder-partition verifier — the
/// call site, the per-shape law, and the `VERIFY_*` marker contract — without
/// paying for a `swift build` (that is the measured corpus test's job).
@Suite("ReorderPartitionStubEmitter — emitted verifier shape")
struct ReorderPartitionStubEmitterTests {

    private func emit(
        _ method: String,
        hasSubrange: Bool,
        isStable: Bool,
        extraImports: [String] = []
    ) -> String {
        ReorderPartitionStubEmitter.emit(
            .init(
                methodName: method,
                hasSubrange: hasSubrange,
                isStable: isStable,
                extraImports: extraImports
            )
        )
    }

    @Test("every stub emits the VERIFY marker contract and a deterministic RNG")
    func markerContractAndDeterminism() {
        let stub = emit("partition", hasSubrange: false, isStable: false)
        #expect(stub.contains("VERIFY_DEFAULT_RESULT: PASS"))
        #expect(stub.contains("VERIFY_EDGE_RESULT: PASS"))
        #expect(stub.contains("VERIFY_DEFAULT_RESULT: FAIL"))
        #expect(stub.contains("exit(0)"))
        #expect(stub.contains("exit(1)"))
        // Fixed-seed RNG → byte-reproducible run.
        #expect(stub.contains("StubXoshiro(seed: 0xA5A5_5A5A_C3C3_3C3C)"))
    }

    @Test("a whole-collection call has no subrange argument")
    func wholeCall() {
        let stub = emit("stablePartitionWhole", hasSubrange: false, isStable: true)
        #expect(stub.contains("arr.stablePartitionWhole(by: pred)"))
        #expect(!stub.contains("subrange:"))
    }

    @Test("a stable check asserts the order-preserving filter; a non-stable one asserts split + sorted")
    func stableVsNonStableChecks() {
        let stable = emit("p", hasSubrange: false, isStable: true)
        #expect(stable.contains("original.filter({ !pred($0) })"))
        #expect(stable.contains("stable law violated"))

        let plain = emit("p", hasSubrange: false, isStable: false)
        #expect(plain.contains("arr.sorted() != original.sorted()"))
        #expect(plain.contains("permutation violated"))
        #expect(!plain.contains("stable law violated"))
    }

    @Test("a subrange stub calls with subrange:, checks the fence, and pins the pivot inside it")
    func subrangeShape() {
        let stub = emit("stablePartitionSubrange", hasSubrange: true, isStable: true)
        #expect(stub.contains("arr.stablePartitionSubrange(subrange: subrange, by: pred)"))
        #expect(stub.contains("fence violated"))
        #expect(stub.contains("pivot >= subrange.lowerBound, pivot <= subrange.upperBound"))
    }

    @Test("extraImports are rendered alongside Foundation")
    func extraImportsRendered() {
        let stub = emit("partition", hasSubrange: false, isStable: false, extraImports: ["MyCorpus"])
        #expect(stub.contains("import Foundation"))
        #expect(stub.contains("import MyCorpus"))
    }
}
