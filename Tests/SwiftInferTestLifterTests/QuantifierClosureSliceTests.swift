import Foundation
import SwiftInferCore
@testable import SwiftInferTestLifter
import Testing

/// A property test's law lives inside a **quantifier's trailing closure**, and the slicer
/// must see through it.
///
/// `Slicer.unwrappingRepetition` already models exactly this idea for the *statement* form —
/// a trailing `for`/`while`/`repeat` whose body holds the assertion, preceded only by
/// bindings. A property-based test is the same shape written as a **call**:
///
/// ```swift
/// let gen = Gen.element(of: names)          // binding
/// await propertyCheck(input: gen) { name in // the quantifier
///     #expect(strip(strip(name)) == strip(name))
/// }
/// ```
///
/// Before this, the closure form was invisible: `AssertionAnchor.locate` searches top-level
/// statements, the assertion is not one, and the method sliced to `.emptySlice`. So TestLifter
/// read **nothing** from a property test.
///
/// **That gap covered the tests this toolchain's own workflow produces.** `discover` proposes
/// a law, a human writes the property test, and `discover` could not read it back — measured
/// on this repo as four landed suites and 15 laws yielding **zero** lifted rows
/// (`docs/measurements/roadtest-self-dogfood-2026-08-08.md` §7.3). The `+20` cross-validation
/// signal exists to reward a codebase that already states its laws, and it was unavailable to
/// exactly the codebases that had taken the tool's advice.
@Suite("Slicer — a quantifier's trailing closure is unwrapped like a loop body")
struct QuantifierClosureSliceTests {

    private static func slice(body: String) -> SlicedTestBody {
        let summaries = TestSuiteParser.scan(
            source: """
            import Testing
            @Suite struct T {
                @Test func law() async {
                    \(body)
                }
            }
            """,
            file: "T.swift"
        )
        return Slicer.slice(summaries[0].body)
    }

    /// The statement form, which already worked. Pinned here so the closure arm below is
    /// measured against a known-good baseline rather than an assumption.
    @Test("the loop form anchors, as it always did")
    func loopFormAnchors() {
        let slice = Self.slice(body: """
        for name in names {
            #expect(normalize(normalize(name)) == normalize(name))
        }
        """)
        #expect(slice.assertion != nil, "the `for` form is the baseline and must anchor")
    }

    /// **The fix.** The same law, written the way property tests actually write it.
    @Test("a propertyCheck trailing closure anchors")
    func propertyCheckClosureAnchors() {
        let slice = Self.slice(body: """
        await propertyCheck(input: nameGen) { name in
            #expect(normalize(normalize(name)) == normalize(name))
        }
        """)
        #expect(slice.assertion != nil, "the law inside a propertyCheck closure must be found")
    }

    /// Bindings may precede the quantifier — the same tolerance the loop form has, and the
    /// shape every real property test takes (a generator is bound, then quantified over).
    @Test("bindings before the quantifier are kept as setup")
    func bindingsBeforeQuantifierSurvive() {
        let slice = Self.slice(body: """
        let seed = 7
        await propertyCheck(input: nameGen) { name in
            #expect(normalize(normalize(name)) == normalize(name))
        }
        """)
        #expect(slice.assertion != nil)
    }

    /// Multi-parameter quantifiers are the two-generator form (`propertyCheck(input: a, b)`),
    /// which is how commutativity and associativity laws are written.
    @Test("a two-parameter quantifier closure anchors")
    func twoParameterClosureAnchors() {
        let slice = Self.slice(body: """
        await propertyCheck(input: genA, genB) { a, b in
            #expect(merge(a, b) == merge(b, a))
        }
        """)
        #expect(slice.assertion != nil)
    }

    /// The `perform:` label is the declared parameter name; a caller who does not use trailing
    /// syntax must not be treated differently, since the two spellings are the same call.
    @Test("the explicit perform: label is equivalent to the trailing closure")
    func explicitPerformLabelAnchors() {
        let slice = Self.slice(body: """
        await propertyCheck(input: nameGen, perform: { name in
            #expect(normalize(normalize(name)) == normalize(name))
        })
        """)
        #expect(slice.assertion != nil)
    }

    // MARK: - The precision half
    //
    // Unwrapping ANY trailing closure would be the Daikon trap: `measure { }`,
    // `withThrowingTaskGroup { }` and `#expect(throws:) { }` all have assertion-shaped
    // interiors that are not quantified laws. The gate is a curated callee name, the same
    // shape `VariantMarkers` and `MarkerTable` use.

    /// A non-quantifier trailing closure must NOT be unwrapped. Without this, the rule is
    /// "any call with a closure", which is not a rule.
    @Test("an unrelated trailing closure is not unwrapped")
    func unrelatedClosureIsNotUnwrapped() {
        let slice = Self.slice(body: """
        measure {
            #expect(normalize(normalize(name)) == normalize(name))
        }
        """)
        #expect(
            slice.assertion == nil,
            Comment(rawValue:
                "`measure { }` is a benchmark harness, not a quantifier — unwrapping it "
                + "would lift a law the test never stated over any domain")
        )
    }

    /// `withThrowingTaskGroup` is the concurrency shape whose interior looks assertion-like
    /// and quantifies over nothing.
    @Test("a task-group closure is not unwrapped")
    func taskGroupClosureIsNotUnwrapped() {
        let slice = Self.slice(body: """
        await withThrowingTaskGroup(of: Void.self) { group in
            #expect(normalize(normalize(name)) == normalize(name))
        }
        """)
        #expect(slice.assertion == nil)
    }

    /// The quantifier must be the LAST statement, exactly as the loop form requires. A call
    /// followed by more work is not a tail quantifier, and the trailing statements would be
    /// silently dropped from the slice.
    @Test("a quantifier that is not the last statement is not unwrapped")
    func nonTailQuantifierIsNotUnwrapped() {
        let slice = Self.slice(body: """
        await propertyCheck(input: nameGen) { name in
            #expect(normalize(normalize(name)) == normalize(name))
        }
        cleanUp()
        """)
        #expect(slice.assertion == nil)
    }
}
