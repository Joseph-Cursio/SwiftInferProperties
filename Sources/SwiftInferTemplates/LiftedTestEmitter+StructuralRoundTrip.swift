import SwiftInferCore

extension LiftedTestEmitter {

    /// A scaffold for `structural-round-trip` (#646): the parser, named and spelled, and an
    /// `Issue.record` until a person writes the printer and the values.
    ///
    /// Built like `stateMachineScaffold`: everything the reader supplies is in **comments** and the
    /// only live statement is the `Issue.record`, so the file builds in any test target, fails by
    /// design until completed, and `isScaffold` labels it SCAFFOLD rather than a law.
    ///
    /// - Parameters:
    ///   - parser: the parse function, as a test spells a call to it.
    ///   - structure: the type it returns.
    ///   - isThrowing: whether the call needs `try`.
    public static func structuralRoundTripScaffold(
        parser: CalleeReference,
        structure: String,
        isThrowing: Bool
    ) -> String {
        let call = (isThrowing ? "try " : "") + parser.call(["render(value)"])
        let todo = "TODO: complete the structure-first round-trip scaffold for "
            + "\(parser.displaySignature) — write render(_:), build values the parser can produce, "
            + "then compare"
        return """

        // Structure-first round-trip scaffold for `\(parser.displaySignature)`: nothing in the code
        // prints a `\(structure)` back to text, so `parse(render(value)) == value` needs a printer
        // you write. swift-infer cannot know the layout or which values the parser can produce, so
        // this is a scaffold, not a runnable test — it fails (via Issue.record) until you complete it.
        @Test func \(parser.identifierName)_readsBackWhatItsLayoutPrints() throws {
            // TODO 1: write the printer — lay a value out the way the text's producer does, and draw
            //         every optional separator (blank lines, indentation, a trailing newline) at random:
            //   func render(_ value: \(structure)) -> String { <#layout#> }
            // TODO 2: build only values the parser can produce — from the format's own vocabulary, with
            //         no field holding a separator and no two fields that must agree drawn apart:
            //   let value = <#\(structure)(…)#>
            // TODO 3: print, parse back, compare (`\(structure)` must be Equatable):
            //   #expect(\(call) == value)
            Issue.record("\(escapedForLiteral(todo))")
        }
        """
    }
}
