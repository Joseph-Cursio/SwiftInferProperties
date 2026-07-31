@testable import SwiftInferTestLifter
import Testing

/// The `StdlibUnittest` `expect*` family, mapped onto the existing assertion
/// kinds.
///
/// `AssertionInvocation.Kind` discriminates assertion *shape*, not harness —
/// the `xctAssert` case-name prefix is historical. Mapping onto the existing
/// cases rather than adding parallel ones is what lets every downstream
/// detector read the swift.org corpus without being touched.
@Suite("Slicer — StdlibUnittest expect* assertion table")
struct StdlibUnittestAssertionTableTests {

    private func kind(of call: String) -> AssertionInvocation.Kind? {
        let source = "suite.test(\"c\") { \(call) }"
        guard let summary = TestSuiteParser.scan(source: source, file: "T.swift").first else {
            return nil
        }
        return Slicer.slice(summary.body).assertion?.kind
    }

    @Test("equality and inequality")
    func equality() {
        #expect(kind(of: "expectEqual(a, b)") == .xctAssertEqual)
        #expect(kind(of: "expectNotEqual(a, b)") == .xctAssertNotEqual)
    }

    /// `expectEqualSequence` asserts element-wise equality rather than `==`.
    /// It maps to the equality shape because that is what the detectors read —
    /// two expressions claimed equal — but the distinction is real and is why
    /// this test names it separately.
    @Test("expectEqualSequence maps to the equality shape")
    func equalSequence() {
        #expect(kind(of: "expectEqualSequence(a, b)") == .xctAssertEqual)
    }

    @Test("boolean polarity is preserved")
    func booleans() {
        #expect(kind(of: "expectTrue(flag)") == .xctAssertTrue)
        #expect(kind(of: "expectFalse(flag)") == .xctAssertFalse)
    }

    @Test("ordering comparisons map to their matching kinds")
    func ordering() {
        #expect(kind(of: "expectGE(a, b)") == .xctAssertGreaterThanOrEqual)
        #expect(kind(of: "expectGT(a, b)") == .xctAssertGreaterThan)
        #expect(kind(of: "expectLE(a, b)") == .xctAssertLessThanOrEqual)
        #expect(kind(of: "expectLT(a, b)") == .xctAssertLessThan)
    }

    @Test("expectNotNil maps to the not-nil kind")
    func notNil() {
        #expect(kind(of: "expectNotNil(value)") == .xctAssertNotNil)
    }

    /// `expectNil` (809 sites) was unmapped until `.xctAssertNil` existed —
    /// mapping it onto `.xctAssertNotNil` would have inverted the assertion, so
    /// a detector would read "asserted non-nil" from `expectNil(x)` and infer
    /// the opposite law. Silence was the safe answer; the kind is the correct
    /// one. See `NilAssertionKindTests` for the polarity guard.
    @Test("expectNil maps at its true polarity")
    func nilMapsAtTruePolarity() {
        #expect(kind(of: "expectNil(value)") == .xctAssertNil)
        #expect(kind(of: "expectNil(value)") != kind(of: "expectNotNil(value)"))
    }

    /// These anchor process death, parse success, static typing and rendering.
    /// None is a shape any detector reads.
    @Test("non-comparison expect* names are not assertions")
    func nonComparisonNamesAreIgnored() {
        #expect(kind(of: "expectCrashLater()") == nil)
        #expect(kind(of: "expectType(Int.self, &value)") == nil)
        #expect(kind(of: "expectPrinted(\"1\", value)") == nil)
    }

    /// The XCTest names must keep working — this table is shared.
    @Test("the pre-existing XCTest names are unaffected")
    func xctestNamesStillWork() {
        #expect(kind(of: "XCTAssertEqual(a, b)") == .xctAssertEqual)
        #expect(kind(of: "XCTAssertTrue(flag)") == .xctAssertTrue)
    }
}
