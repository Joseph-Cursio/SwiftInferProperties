@testable import SwiftInferTestLifter
import SwiftSyntax
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

    /// ⚠ **The same trap, one node over.** A key-path component's name is a
    /// `DeclReferenceExprSyntax` in a slot typed as one, exactly like a member's, and the guard
    /// above did not cover it: `\.id` became `\.makeID()`, a `KeyPathPropertyComponentSyntax`
    /// whose `declName` holds a call. Nothing read it yet, so nothing trapped yet. The `[id]` is
    /// the control: a genuine read of the same binding is still substituted.
    @Test("a binding sharing a key-path component's name does not corrupt the key path")
    func bindingNamedLikeAKeyPathComponentIsNotSubstituted() throws {
        let slice = SlicerTestHelper.sliceFirstBody(in: #"""
        import Testing
        struct T {
            @Test
            func idsSurviveCanonicalisation() {
                let id = makeID()
                let once = canonical(rows)
                #expect(once.map(\.id) == [id])
            }
        }
        """#)
        let bindings = LocalBindingResolver.bindings(in: slice.propertyRegion)
        #expect(bindings.keys.sorted() == ["id", "once"])
        let argument = try #require(slice.assertion?.arguments.first)
        let resolved = LocalBindingResolver.substituting(argument, bindings: bindings)
        #expect(resolved.trimmedDescription == #"canonical(rows).map(\.id) == [makeID()]"#)

        let backslash = resolved.tokens(viewMode: .sourceAccurate).first { $0.tokenKind == .backslash }
        let keyPath = try #require(backslash?.parent?.as(KeyPathExprSyntax.self))
        guard case .property(let component)? = keyPath.components.first?.component else {
            Issue.record("expected a property component in \(keyPath)")
            return
        }
        // Asked of the slot without the force cast `declName` makes, so the broken tree fails
        // here rather than trapping the test process.
        let slot = component.children(viewMode: .sourceAccurate).first
        #expect(slot?.is(DeclReferenceExprSyntax.self) == true)
        if slot?.is(DeclReferenceExprSyntax.self) == true {
            #expect(component.declName.baseName.text == "id")
        }
    }

    /// A key-path SUBSCRIPT argument is a read, so the binding is substituted there; and a member
    /// of `self` is a member name like any other, never the local of the same name.
    @Test("a key-path subscript argument is substituted; a member of self is not")
    func subscriptArgumentSubstitutedSelfMemberNot() {
        let subscripted = Self.resolvedFirstArgument(#"""
        let id = makeID()
        let once = canonical(rows)
        #expect(once.map(\.[id]) == [])
        """#)
        #expect(subscripted == #"canonical(rows).map(\.[makeID()]) == []"#)

        let member = Self.resolvedFirstArgument("""
        let once = canonical(rows)
        #expect(self.once != once)
        """)
        #expect(member == "self.once != canonical(rows)")
    }

    /// `body` inside a `@Test` function, sliced, with its assertion's first argument resolved.
    private static func resolvedFirstArgument(_ body: String) -> String? {
        let slice = SlicerTestHelper.sliceFirstBody(in: """
        import Testing
        struct T {
            @Test
            func resolves() {
                \(body)
            }
        }
        """)
        guard let argument = slice.assertion?.arguments.first else { return nil }
        let bindings = LocalBindingResolver.bindings(in: slice.propertyRegion)
        return LocalBindingResolver.substituting(argument, bindings: bindings).trimmedDescription
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
