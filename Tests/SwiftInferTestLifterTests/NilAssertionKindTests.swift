import SwiftInferCore
@testable import SwiftInferTestLifter
import Testing

/// `.xctAssertNil` — the negative-polarity nil assertion.
///
/// Until this kind existed, `StdlibUnittest.expectNil` (809 call sites in the
/// swift.org stdlib tests) had to be dropped, because the only near-fit was
/// `.xctAssertNotNil` and mapping it there would **invert** the assertion — a
/// detector would read "asserted non-nil" from `expectNil(x)` and infer the
/// opposite law.
///
/// Measured over `test/stdlib` + `validation-test/stdlib` @ `swift`
/// `408632e5`: test bodies slicing to an assertion anchor went **2,263 →
/// 2,677**, and `xctAssertNil` is now the second-largest anchor kind at 452.
@Suite("Slicer — the nil assertion kind")
struct NilAssertionKindTests {

    private func kind(of call: String) -> AssertionInvocation.Kind? {
        let source = "suite.test(\"c\") { \(call) }"
        guard let summary = TestSuiteParser.scan(source: source, file: "T.swift").first else {
            return nil
        }
        return Slicer.slice(summary.body).assertion?.kind
    }

    @Test("both spellings map to the nil kind")
    func bothSpellingsMap() {
        #expect(kind(of: "expectNil(value)") == .xctAssertNil)
        #expect(kind(of: "XCTAssertNil(value)") == .xctAssertNil)
    }

    /// The whole reason the kind exists. If these ever collapse to one case,
    /// every detector reading polarity silently inverts for 809 corpus sites.
    @Test("nil and not-nil stay distinct kinds")
    func polarityIsPreserved() {
        #expect(kind(of: "expectNil(value)") == .xctAssertNil)
        #expect(kind(of: "expectNotNil(value)") == .xctAssertNotNil)
        #expect(kind(of: "expectNil(value)") != kind(of: "expectNotNil(value)"))
    }

    /// The slicer anchors on the *terminal* assertion. While `expectNil` was
    /// unrecognized, a body ending in one anchored on an earlier assertion
    /// instead — so recognizing it does not only add anchors, it **corrects**
    /// the anchor for bodies that were pointing at the wrong conclusion.
    @Test("a terminal expectNil becomes the anchor instead of an earlier assertion")
    func terminalNilWinsTheAnchor() throws {
        let source = """
        suite.test("case") {
            expectEqual(a, b)
            expectNil(lookup(key))
        }
        """
        let summary = try #require(TestSuiteParser.scan(source: source, file: "T.swift").first)
        let assertion = try #require(Slicer.slice(summary.body).assertion)
        #expect(assertion.kind == .xctAssertNil)
    }

    @Test("the nil assertion carries its single argument")
    func carriesItsArgument() throws {
        let source = "suite.test(\"c\") { expectNil(lookup(key)) }"
        let summary = try #require(TestSuiteParser.scan(source: source, file: "T.swift").first)
        let assertion = try #require(Slicer.slice(summary.body).assertion)
        #expect(assertion.arguments.count == 1)
    }

    /// No detector reads a nil assertion as an equality, ordering or boolean
    /// shape, so every one must decline it rather than misread it.
    @Test("the shape-reading detectors all decline the nil kind")
    func detectorsDeclineTheNilKind() {
        let assertion = AssertionInvocation(
            kind: .xctAssertNil,
            arguments: [],
            location: SourceLocation(file: "T.swift", line: 1, column: 1)
        )
        #expect(EquivalenceClassMarkerExtractor.extractPredicate(from: assertion) == nil)
        #expect(EquivalenceClassMarkerExtractor.extractNClassPredicateAndCase(from: assertion) == nil)
    }
}
