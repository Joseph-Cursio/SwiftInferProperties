import SwiftInferCore

/// The `marker-dispatch` arm: every marker of a keyword table dispatches to its row's case (#644).
///
/// Not a property test, for the reason `caseKeyInjectivity` is not: the table is finite and read
/// off the syntax, so the stub is a loop over every checkable name — no generator, no seed, and a
/// pass that means each marker was checked rather than that the ones drawn were.
extension LiftedTestEmitter {

    /// - Parameters:
    ///   - callee: the function the test calls — the chain, or the front that reaches it.
    ///   - front: the lookup the front consults first, when there is one; names it answers are
    ///     skipped, and the test fails if it answers all of them.
    public static func markerDispatch(
        callee: CalleeReference,
        match: MarkerDispatchMatch,
        front: CalleeReference?
    ) -> String {
        let rows = match.dispatch.probes().checkable
            .map { "        (\"\($0.name)\", \($0.result))," }
            .joined(separator: "\n")
        let actor = callee.isolation.map { "@\($0) " } ?? ""
        let skip = front.map { "        guard \($0.call("name")) == nil else { continue }\n" } ?? ""
        let label = escapedForLiteral(callee.displaySignature)
        return """
        @Test \(actor)func \(callee.identifierName)_dispatchesEachMarker() {
            let table: [(name: String, expected: \(match.resultType))] = [
        \(rows)
            ]
            var checked = 0
            for (name, expected) in table {
        \(skip)        checked += 1
                #expect(\(callee.call("name")) == expected, "\(label) dispatched \\"\\(name)\\" to the wrong case")
            }
            #expect(checked > 0, "every marker was answered before the table was reached — nothing was checked")
        }
        """
    }
}
