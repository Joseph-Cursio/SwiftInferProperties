@testable import SwiftInferCLI
import Testing

/// Unit tests for the shared curated real-axis `Double` edge-case set that the
/// two-pass algebraic verifier stubs (round-trip / idempotence / commutativity
/// / associativity) inline into their edge pass.
struct DoubleEdgeCaseStubTests {

    @Test("curated set covers the distinct IEEE-754 real-axis edge classes")
    func curatedSetShape() {
        let literals = DoubleEdgeCaseStub.entries.map(\.literal)
        // NaN + both infinities + both zeros + both overflow boundaries +
        // both underflow/subnormal boundaries.
        #expect(literals.contains("Double.nan"))
        #expect(literals.contains("Double.infinity"))
        #expect(literals.contains("-Double.infinity"))
        #expect(literals.contains("0.0"))
        #expect(literals.contains("-0.0"))
        #expect(literals.contains("Double.greatestFiniteMagnitude"))
        #expect(literals.contains("-Double.greatestFiniteMagnitude"))
        #expect(literals.contains("Double.leastNonzeroMagnitude"))
        #expect(literals.contains("Double.leastNormalMagnitude"))
        #expect(DoubleEdgeCaseStub.curatedCount == 9)
        #expect(DoubleEdgeCaseStub.labels.count == DoubleEdgeCaseStub.entries.count)
    }

    @Test("match function is column-0 and returns the index of every curated entry")
    func matchFunctionSource() {
        let source = DoubleEdgeCaseStub.matchFunctionSource
        #expect(source.hasPrefix("func matchEdgeCaseIndex(_ value: Double) -> Int {"))
        // NaN → 0 (its own predicate, not a plain ==).
        #expect(source.contains("if value.isNaN { return 0 }"))
        // Signed zero is disambiguated by sign, not ==.
        #expect(source.contains("value.sign == .plus"))
        #expect(source.contains("value.sign == .minus"))
        // Non-curated (finite-slice) values resolve to -1.
        #expect(source.contains("return -1"))
        // One arm per entry.
        for index in DoubleEdgeCaseStub.entries.indices {
            #expect(source.contains("return \(index) }"))
        }
    }

    @Test("generator emits a 10% edge bias band (entries × 10) with one tag per entry")
    func generatorSource() {
        let source = DoubleEdgeCaseStub.generatorSource
        // 9 entries → 90-tag band (9 / 90 = 10%).
        #expect(source.contains("Gen<Int>.int(in: 0 ..< 90)"))
        // Each curated literal appears as a switch arm.
        for (index, entry) in DoubleEdgeCaseStub.entries.enumerated() {
            #expect(source.contains("case \(index): return \(entry.literal)"))
        }
        // The finite-slice fall-through.
        #expect(source.contains("default: return Double.random(in: -1_000_000.0 ... 1_000_000.0)"))
    }

    @Test("index order is stable — NaN at 0, infinities at 1/2 (the persisted-evidence contract)")
    func indexStability() {
        #expect(DoubleEdgeCaseStub.entries[0].literal == "Double.nan")
        #expect(DoubleEdgeCaseStub.entries[1].literal == "Double.infinity")
        #expect(DoubleEdgeCaseStub.entries[2].literal == "-Double.infinity")
        #expect(DoubleEdgeCaseStub.labels[0] == "NaN")
        #expect(DoubleEdgeCaseStub.labels[1] == "+Infinity")
    }
}
