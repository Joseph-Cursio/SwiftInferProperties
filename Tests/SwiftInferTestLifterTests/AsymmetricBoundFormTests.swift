@testable import SwiftInferTestLifter
import Testing

private func detectAsymmetric(in source: String) -> [DetectedAsymmetricAssertion] {
    let slice = SlicerTestHelper.sliceFirstBody(in: source)
    return AsymmetricAssertionDetector.detect(in: slice)
}

/// Negative assertions written the way people actually write them: with intermediate `let`
/// bindings instead of one nested expression.
///
/// **Why this matters (road test §10.4).** Every matcher in `AsymmetricAssertionDetector` keys
/// on syntax — `idempotenceNegativePair` requires both sides of the inequality to be
/// `FunctionCallExprSyntax`. So it saw `#expect(f(f(x)) != f(x))` and nothing else, while the
/// refutation this repo actually banked reads `let once = …; let twice = …; #expect(once !=
/// twice)`. The counter-signal never fired, and `discover` went on promoting a law the repo's
/// own test suite refutes. That is §7.3's failure mode on the negative side: a detector keyed
/// to the shape the tool imagines rather than the shape people write.
@Suite("AsymmetricAssertionDetector — bindings resolved before matching")
struct AsymmetricBoundFormTests {

    /// The banked `booleanStem` refutation, reduced to its shape.
    @Test("let-bound idempotence negative is detected")
    func boundIdempotenceNegative() {
        let source = """
        import Testing
        struct T {
            @Test
            func stemIsNotIdempotent() {
                let name = "isShowing"
                let once = Heuristics.booleanStem(name)
                let twice = Heuristics.booleanStem(once)
                #expect(once != twice)
            }
        }
        """
        let detections = detectAsymmetric(in: source)
        if case let .idempotence(callee) = detections.first {
            #expect(callee == "booleanStem")
        } else {
            Issue.record("expected .idempotence detection, got \(detections)")
        }
    }

    @Test("let-bound round-trip negative is detected")
    func boundRoundTripNegative() {
        let source = """
        import Testing
        struct T {
            @Test
            func roundTripBroken() {
                let value = 42
                let encoded = encode(value)
                let decoded = decode(encoded)
                #expect(decoded != value)
            }
        }
        """
        if case let .roundTrip(forward, backward) = detectAsymmetric(in: source).first {
            #expect(forward == "encode")
            #expect(backward == "decode")
        } else {
            Issue.record("expected .roundTrip detection")
        }
    }

    /// **The regression that motivated the guard, not a hypothetical.** A member's NAME is a
    /// `DeclReferenceExprSyntax` too, so an unguarded rewriter replaced `booleanStem` inside
    /// `Heuristics.booleanStem` and produced a tree violating the grammar. The first consumer
    /// to read `.declName` force-cast and TRAPPED: `swift-infer discover` died with
    /// `Unexpectedly found nil while unwrapping an Optional value`, on this repo, in a
    /// detector the change was not aiming at.
    @Test("a binding sharing a member's name does not corrupt the member access")
    func bindingNamedLikeAMemberDoesNotTrap() {
        let source = """
        import Testing
        struct T {
            @Test
            func shadowed() {
                let booleanStem = "isShowing"
                let once = Heuristics.booleanStem(booleanStem)
                let twice = Heuristics.booleanStem(once)
                #expect(once != twice)
            }
        }
        """
        // The assertion is that this returns AT ALL — the pre-guard build crashed here.
        let detections = detectAsymmetric(in: source)
        #expect(detections.count <= 1, "must not trap, whatever it decides")
    }

    /// **The control.** The nested form must keep working exactly as before — substitution is
    /// a widening, and a widening that broke the original shape would trade one blindness for
    /// another.
    @Test("the nested form still matches, unchanged")
    func nestedFormStillMatches() {
        let source = """
        import Testing
        struct T {
            @Test
            func stemIsNotIdempotent() {
                let name = "isShowing"
                #expect(booleanStem(booleanStem(name)) != booleanStem(name))
            }
        }
        """
        if case let .idempotence(callee) = detectAsymmetric(in: source).first {
            #expect(callee == "booleanStem")
        } else {
            Issue.record("the pre-existing shape must still be detected")
        }
    }

    /// A body with no bindings must take the identical path it always did.
    @Test("no bindings means no substitution")
    func noBindingsIsUnchanged() {
        let source = """
        import Testing
        struct T {
            @Test
            func nothingToResolve() {
                #expect(encode(7) != 7)
            }
        }
        """
        #expect(detectAsymmetric(in: source).isEmpty)
    }
}
