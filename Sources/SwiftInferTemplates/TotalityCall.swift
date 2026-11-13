import SwiftInferCore

/// The one call a totality stub makes, written once for `_isTotal` and the reach test beside it
/// (#665's commit 4a, `docs/plans/predicate-outcome-reach-scope.md` §7).
///
/// The reach test (`LiftedTestEmitter.reachesBothOutcomes`) records which answers the law's own
/// draws got, so it must make the law's call: the same receiver, the same argument order, the same
/// `inout` copies and the same isolation. Two spellings of the call would let one drift from the
/// other, and the reach test would then describe a call the law never makes. So both read it here.
struct TotalityCall {

    /// What each drawn value is called in the call: `value` for one draw, `args.0`, `args.1`, …
    /// for a tuple, in argument order with the receiver first.
    let drawn: [String]

    /// `var inoutN = …; ` for each argument the subject takes `inout`: a drawn value is a `let`,
    /// and `f(value)` does not compile against an `inout` parameter.
    let copies: String

    /// The call, `&inoutN` in each `inout` position, with `await` and `try?` as the subject
    /// needs them.
    let invocation: String

    /// - Parameter inoutArguments: positions, in argument order (receiver included), of the
    ///   arguments the subject takes `inout`.
    init(callee: CalleeReference, drawCount: Int, isThrowing: Bool, isAsync: Bool, inoutArguments: Set<Int>) {
        let names = drawCount > 1 ? (0 ..< drawCount).map { "args.\($0)" } : ["value"]
        drawn = names
        copies = names.indices.filter(inoutArguments.contains).map { "var inout\($0) = \(names[$0]); " }.joined()
        var spelled = callee.call(names.indices.map { inoutArguments.contains($0) ? "&inout\($0)" : names[$0] })
        if isAsync { spelled = "await \(spelled)" }
        if isThrowing { spelled = "try? \(spelled)" }
        invocation = spelled
    }
}

extension LiftedTestEmitter {

    /// Trials per generated stub: every template's budget, and the reach test's, which re-draws
    /// exactly the law's inputs. One name, so a budget raise moves the law and its reach test
    /// together (#665 §7: the stub-budget follow-up must say whether it raises this for every
    /// template or adds a predicate-only budget).
    static let stubTrialCount = 100
}
