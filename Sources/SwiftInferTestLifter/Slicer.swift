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

    public static func slice(_ body: CodeBlockSyntax) -> SlicedTestBody {
        let items = Array(body.statements)
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

    private static func xctAssertKind(of call: FunctionCallExprSyntax) -> AssertionInvocation.Kind? {
        let calleeName: String
        if let ref = call.calledExpression.as(DeclReferenceExprSyntax.self) {
            calleeName = ref.baseName.text
        } else {
            return nil
        }
        switch calleeName {
        case "XCTAssertEqual":
            return .xctAssertEqual
        case "XCTAssertTrue":
            return .xctAssertTrue
        case "XCTAssert":
            return .xctAssert
        case "XCTAssertNotNil":
            return .xctAssertNotNil
        default:
            return nil
        }
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

    private static func location(of node: Syntax) -> SwiftInferCore.SourceLocation {
        // The slicer doesn't carry a SourceLocationConverter, and
        // M1.3's round-trip detector consumes the assertion's argument
        // shape, not its absolute location. We surface a placeholder
        // here; M1.5's CLI wiring threads a converter through when the
        // location actually feeds rendering.
        SwiftInferCore.SourceLocation(file: "<test-body>", line: 0, column: 0)
    }
}
