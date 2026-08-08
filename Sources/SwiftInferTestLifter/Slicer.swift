import SwiftInferCore
import SwiftSyntax

/// PRD §7.2 four-rule slicing pass over a test method body. Anchors on
/// the terminal assertion, backward-slices contributing statements,
/// classifies the remainder as setup, and identifies parameterized
/// values inside the slice.
///
/// **Hard contract (PRD §15):** never throws. Bodies with no
/// recognized terminal assertion produce an empty property region;
/// the entire body falls through to setup.
///
/// **Backward-slice semantics:** name-based SSA-like walk. Starting
/// from the identifier names referenced in the assertion's arguments,
/// walk the body in reverse. A `let`/`var` binding whose pattern's
/// bound name appears in the live set is pulled into the slice and
/// its initializer's identifier references are added to the live set.
/// Mutating assignments (`encoder.outputFormatting = .pretty`) and
/// `let` bindings whose names are never in the live set fall through
/// to setup. Side-effecting expression statements (other than the
/// terminal assertion) likewise stay in setup. This is conservative:
/// statements ARE pulled in transitively even if they're "config-y"
/// (e.g. `let encoder = JSONEncoder()` gets pulled in if `let
/// encoded = encoder.encode(x)` is in the slice).
public enum Slicer {

    /// A test body that is **one repetition loop** is sliced as its loop body.
    ///
    /// This is the hand-rolled property test:
    ///
    /// ```swift
    /// func testSortMatchesReferenceOnRandomArrays() {
    ///     for _ in 0..<10_000 {
    ///         let input = (0..<50).map { _ in Int.random(in: -1000...1000) }
    ///         XCTAssertEqual(mySort(input), input.sorted())
    ///     }
    /// }
    /// ```
    ///
    /// The loop IS the quantifier. A human decided the assertion holds for all
    /// inputs, drew 10,000 of them, and wrote the law executably — evidence
    /// strictly better than any signature heuristic. Every detector was blind
    /// to it for a purely mechanical reason: `AssertionAnchor` scans top-level
    /// statements, and here the only top-level statement is the `for`.
    ///
    /// Measured on the differential detector: the same assertion scores a
    /// finding when flat and nothing when wrapped, with no other difference.
    ///
    /// **The loop must be LAST, and everything before it must be a binding.**
    ///
    /// The first cut of this required the loop to be the body's *only*
    /// statement. Measured against the real swift-foundation test suite, that
    /// fired on **zero** of the ten random-driven tests there — because a real
    /// property-style test sets up its generator or fixture first:
    ///
    /// ```swift
    /// @Test func randomVersionAndVariant() {
    ///     var generator = SystemRandomNumberGenerator()   // ← setup
    ///     for _ in 0..<10000 {
    ///         let uuid = UUID.random(using: &generator)
    ///         #expect(uuid.versionNumber == 0b0100)
    ///     }
    /// }
    /// ```
    ///
    /// The synthetic probe the first cut was validated against had a bare loop,
    /// so it confirmed a shape that does not occur in the wild. Leading
    /// bindings are now carried through and land in the slice's setup region,
    /// which is exactly what that region is for — the backward slice already
    /// pulls in whichever of them the assertion depends on.
    ///
    /// Still deliberately narrow in three ways. The loop must be the LAST
    /// statement, so a loop that merely builds a fixture before a later
    /// assertion is untouched — there the top-level assertion is the right
    /// anchor. Everything before it must be a `let`/`var` binding, so a body
    /// that *does* work (calls, mutations, its own assertions) before looping
    /// is not reinterpreted as a quantifier over just the tail. And it is
    /// applied once, not recursively: a doubly-nested loop is a table-driven
    /// test rather than a quantifier, and its inner body usually depends on the
    /// outer binding.
    static func unwrappingRepetition(_ items: [CodeBlockItemSyntax]) -> [CodeBlockItemSyntax] {
        guard let last = items.last, let loopBody = repetitionBody(of: last) else {
            return items
        }
        let leading = items.dropLast()
        guard leading.allSatisfy(isBinding) else { return items }
        return Array(leading) + loopBody
    }

    /// A `for`/`while`/`repeat` body, or a quantifier's closure (`Slicer+Quantifier.swift`).
    private static func repetitionBody(
        of item: CodeBlockItemSyntax
    ) -> [CodeBlockItemSyntax]? {
        if let forStatement = item.item.as(ForStmtSyntax.self) {
            return Array(forStatement.body.statements)
        }
        if let whileStatement = item.item.as(WhileStmtSyntax.self) {
            return Array(whileStatement.body.statements)
        }
        if let repeatStatement = item.item.as(RepeatStmtSyntax.self) {
            return Array(repeatStatement.body.statements)
        }
        return quantifierClosureBody(of: item)
    }

    /// A plain `let`/`var` declaration — the only thing allowed to precede the
    /// loop, because setup is all the tail-quantifier reading can tolerate.
    private static func isBinding(_ item: CodeBlockItemSyntax) -> Bool {
        guard case .decl(let decl) = item.item else { return false }
        return decl.is(VariableDeclSyntax.self)
    }

    public static func slice(_ body: CodeBlockSyntax) -> SlicedTestBody {
        let items = unwrappingRepetition(Array(body.statements))
        guard let anchored = AssertionAnchor.locate(in: items) else {
            return .emptySlice(setup: items)
        }
        let liveSeed = identifierNames(in: anchored.assertion.arguments)
        let backslice = backwardSlice(items: items, anchorIndex: anchored.index, seed: liveSeed)
        let parameterized = parameterizedValues(in: backslice.propertyRegion)
        return SlicedTestBody(
            setup: backslice.setup,
            propertyRegion: backslice.propertyRegion,
            parameterizedValues: parameterized,
            assertion: anchored.assertion
        )
    }

    // MARK: - Backward slice

    private struct SliceResult {
        let setup: [CodeBlockItemSyntax]
        let propertyRegion: [CodeBlockItemSyntax]
    }

    private static func backwardSlice(
        items: [CodeBlockItemSyntax],
        anchorIndex: Int,
        seed: Set<String>
    ) -> SliceResult {
        var live = seed
        var inSlice: Set<Int> = [anchorIndex]
        // Walk items strictly before the anchor in reverse — the
        // anchor itself is already in the slice; statements after the
        // anchor (rare, but possible if the assertion isn't last)
        // fall through to setup.
        for index in (0..<anchorIndex).reversed() {
            let item = items[index]
            guard let binding = boundName(of: item) else {
                continue
            }
            if live.contains(binding.name) {
                inSlice.insert(index)
                if let initializer = binding.initializer {
                    live.formUnion(identifierNames(in: [initializer]))
                }
            }
        }
        var setup: [CodeBlockItemSyntax] = []
        var propertyRegion: [CodeBlockItemSyntax] = []
        for (index, item) in items.enumerated() {
            if inSlice.contains(index) {
                propertyRegion.append(item)
            } else {
                setup.append(item)
            }
        }
        return SliceResult(setup: setup, propertyRegion: propertyRegion)
    }

    private struct BoundName {
        let name: String
        let initializer: ExprSyntax?
    }

    /// Extracts the bound name + initializer from a `let x = ...` /
    /// `var x = ...` statement. Multi-pattern bindings (`let (a, b) =
    /// ...`) and tuple patterns are not handled in M1 — the binding
    /// falls through to setup, which means the slicer will conservatively
    /// drop a statement that should arguably be in the slice. Acceptable
    /// for M1's round-trip target which never produces tuple bindings.
    private static func boundName(of item: CodeBlockItemSyntax) -> BoundName? {
        guard case .decl(let decl) = item.item,
              let varDecl = decl.as(VariableDeclSyntax.self),
              let firstBinding = varDecl.bindings.first,
              let identifierPattern = firstBinding.pattern.as(IdentifierPatternSyntax.self) else {
            return nil
        }
        return BoundName(
            name: identifierPattern.identifier.text,
            initializer: firstBinding.initializer?.value
        )
    }

    // MARK: - Identifier collection

    /// Walks a sequence of expressions and returns the bare identifier
    /// names referenced inside (via `DeclReferenceExprSyntax`). Member
    /// accesses contribute their *base* — `encoder.encode(x)` adds
    /// `encoder` (not `encode`) and `x`.
    private static func identifierNames(in expressions: [ExprSyntax]) -> Set<String> {
        let collector = IdentifierCollector(viewMode: .sourceAccurate)
        for expression in expressions {
            collector.walk(expression)
        }
        return collector.names
    }

    private final class IdentifierCollector: SyntaxVisitor {
        var names: Set<String> = []

        override func visit(_ node: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
            names.insert(node.baseName.text)
            return .visitChildren
        }
    }

    // MARK: - Parameterized values

    private static func parameterizedValues(in items: [CodeBlockItemSyntax]) -> [ParameterizedValue] {
        var results: [ParameterizedValue] = []
        for item in items {
            // `let x = <literal>` shape
            if case .decl(let decl) = item.item,
               let varDecl = decl.as(VariableDeclSyntax.self),
               let firstBinding = varDecl.bindings.first,
               let identifierPattern = firstBinding.pattern.as(IdentifierPatternSyntax.self),
               let initializerExpr = firstBinding.initializer?.value,
               let kind = literalKind(of: initializerExpr) {
                results.append(ParameterizedValue(
                    bindingName: identifierPattern.identifier.text,
                    literalText: initializerExpr.trimmedDescription,
                    kind: kind
                ))
                continue
            }
            // Inline literal expressions used as bare exprs / assertion
            // args are picked up via the assertion-walking path in M1.3
            // when needed; the slicer's parameterized list covers
            // bound literals only.
        }
        return results
    }

    private static func literalKind(of expression: ExprSyntax) -> ParameterizedValue.Kind? {
        if expression.is(IntegerLiteralExprSyntax.self) {
            return .integer
        }
        if expression.is(StringLiteralExprSyntax.self) {
            return .string
        }
        if expression.is(BooleanLiteralExprSyntax.self) {
            return .boolean
        }
        if expression.is(FloatLiteralExprSyntax.self) {
            return .float
        }
        return nil
    }
}

// MARK: - AssertionAnchor

/// Locates the *terminal* assertion call inside a body — the one the
/// slicer anchors on. "Terminal" = the *last* assertion in source order
/// among the body's top-level statements. Tests with multiple
/// assertions get sliced against the final one; M1's round-trip
/// detector is happy with that posture (it asks "what does the final
/// assertion claim?").
enum AssertionAnchor {

    struct Located {
        let index: Int
        let assertion: AssertionInvocation
    }

    static func locate(in items: [CodeBlockItemSyntax]) -> Located? {
        var lastFound: Located?
        for (index, item) in items.enumerated() {
            guard case .expr(let expr) = item.item else {
                continue
            }
            if let invocation = parseInvocation(from: expr) {
                lastFound = Located(index: index, assertion: invocation)
            }
        }
        return lastFound
    }

    private static func parseInvocation(from expr: ExprSyntax) -> AssertionInvocation? {
        if let call = expr.as(FunctionCallExprSyntax.self),
           let kind = xctAssertKind(of: call) {
            let args = call.arguments.map(\.expression)
            return AssertionInvocation(
                kind: kind,
                arguments: args,
                location: location(of: Syntax(call))
            )
        }
        if let macro = expr.as(MacroExpansionExprSyntax.self),
           let kind = swiftTestingMacroKind(of: macro) {
            let args = macro.arguments.map(\.expression)
            return AssertionInvocation(
                kind: kind,
                arguments: args,
                location: location(of: Syntax(macro))
            )
        }
        return nil
    }

    /// Assertion-callee → kind dispatch table. Centralizing the
    /// mapping in a static dictionary keeps `xctAssertKind` under
    /// SwiftLint's cyclomatic-complexity cap as the kind list grows
    /// (M5.1 added two; M7.0 adds three more).
    ///
    /// **`Kind` discriminates assertion SHAPE, not harness.** The case names
    /// carry an `xctAssert` prefix for historical reasons, but what every
    /// downstream detector switches on is the shape — "two expressions asserted
    /// equal", "one expression asserted true". `StdlibUnittest`'s `expect*`
    /// family has exactly those shapes, so it maps onto the existing cases
    /// rather than adding parallel ones. That is what makes the whole detector
    /// suite (round-trip, symmetry, idempotence, count-change, …) work on the
    /// swift.org corpus without touching any of them.
    private static let xctAssertKindByCallee: [String: AssertionInvocation.Kind] = [
        "XCTAssertEqual": .xctAssertEqual,
        "XCTAssertTrue": .xctAssertTrue,
        "XCTAssert": .xctAssert,
        "XCTAssertNotNil": .xctAssertNotNil,
        "XCTAssertNil": .xctAssertNil,
        "XCTAssertLessThan": .xctAssertLessThan,
        "XCTAssertLessThanOrEqual": .xctAssertLessThanOrEqual,
        "XCTAssertNotEqual": .xctAssertNotEqual,
        "XCTAssertGreaterThan": .xctAssertGreaterThan,
        "XCTAssertGreaterThanOrEqual": .xctAssertGreaterThanOrEqual,
        "XCTAssertFalse": .xctAssertFalse,
        // `StdlibUnittest` — the swift.org stdlib test harness. Counts are
        // call sites across `test/stdlib` + `validation-test/stdlib` at
        // `swift` @ `408632e5`, and they are why this table entry exists:
        // every one of these was invisible to the lifter.
        "expectEqual": .xctAssertEqual,                       // 8,665
        "expectTrue": .xctAssertTrue,                         // 2,342
        "expectFalse": .xctAssertFalse,                       // 1,016
        "expectNotNil": .xctAssertNotNil,                     //   341
        "expectNil": .xctAssertNil,                           //   809
        "expectEqualSequence": .xctAssertEqual,               //   269
        "expectNotEqual": .xctAssertNotEqual,                 //   235
        "expectGE": .xctAssertGreaterThanOrEqual,             //    56
        "expectGT": .xctAssertGreaterThan,                    //    21
        "expectLE": .xctAssertLessThanOrEqual,                //    14
        "expectLT": .xctAssertLessThan                        //    14
        //
        // `expectNil` was deliberately absent until `.xctAssertNil` existed:
        // mapping it onto `.xctAssertNotNil` would have INVERTED the
        // assertion, so a detector would read "asserted non-nil" from
        // `expectNil(x)` and infer the opposite law. The kind now exists, so
        // the 809 sites map at their true polarity.
        //
        // STILL ABSENT, and not equality or ordering assertions at all:
        //   `expectCrashLater` (810), `expectParse` (441), `expectType` (227),
        //   `expectPrinted` (191). They anchor process death, parse success,
        //   static typing and rendering; none is a shape any detector reads.
    ]

    private static func xctAssertKind(of call: FunctionCallExprSyntax) -> AssertionInvocation.Kind? {
        guard let ref = call.calledExpression.as(DeclReferenceExprSyntax.self) else {
            return nil
        }
        return xctAssertKindByCallee[ref.baseName.text]
    }

    private static func swiftTestingMacroKind(of macro: MacroExpansionExprSyntax) -> AssertionInvocation.Kind? {
        switch macro.macroName.text {
        case "expect":
            return .expectMacro

        case "require":
            return .requireMacro

        default:
            return nil
        }
    }

    private static func location(of _: Syntax) -> SwiftInferCore.SourceLocation {
        // The slicer doesn't carry a SourceLocationConverter, and M1.3's
        // round-trip detector consumes the assertion's argument shape, not its
        // absolute location. We surface a placeholder here; M1.5's CLI wiring was
        // to thread a converter through when the location actually fed rendering.
        //
        // **It never did, and the placeholder reached users for the whole of that
        // gap** — every lifted row rendered `Lifted from <test-body>:0`. Rather
        // than thread a converter (which would move an assertion-precise location
        // through six detectors), `makeExplainability` now falls back to
        // `LiftedOrigin`, which already carries the enclosing test METHOD's real
        // file and line. Less precise than the assertion line, and auditable,
        // which the placeholder was not.
        SwiftInferCore.SourceLocation.testBodyPlaceholder
    }
}
