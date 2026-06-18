import Foundation

/// PROTOTYPE — emits a standalone verifier source that checks a no-arg
/// view-model action is idempotent at the State level: construct the view
/// model, apply the action once, snapshot every State field, apply it
/// again, and assert the snapshot is unchanged (`f(f(x)) == f(x)` on the
/// constructed initial state). The corpus source is co-compiled into the
/// verifier target (direct source inclusion), so the stub constructs the
/// view model directly — no import, internal access works.
///
/// **Scope (this slice):** no-argument actions on a zero-arg-constructible
/// view model (`ViewModelConstructibility.zeroArgument`) whose State
/// fields are `Equatable`. Parameterized actions need a value generator
/// (the strategist) and are deferred — the MVVM analog of the `.tca`
/// Phase A → Phase B progression. Emits the same `VERIFY_DEFAULT_*` /
/// `VERIFY_EDGE_*` marker contract as the algebraic stubs, so
/// `VerifyResultParser` consumes the output unchanged (deterministic →
/// single trial; the edge pass is a zero sentinel).
public enum ViewModelIdempotenceStubEmitter {

    public struct Inputs: Equatable, Sendable {
        /// The view-model type to construct (`SelectionModel`).
        public let typeName: String
        /// The no-arg action method to apply twice (`selectAll`).
        public let actionName: String
        /// The State field names to snapshot + compare (must be `Equatable`).
        public let stateFieldNames: [String]

        public init(typeName: String, actionName: String, stateFieldNames: [String]) {
            self.typeName = typeName
            self.actionName = actionName
            self.stateFieldNames = stateFieldNames
        }
    }

    public static func emit(_ inputs: Inputs) -> String {
        let snapshots = inputs.stateFieldNames
            .map { "    let snapshot_\($0) = probe.\($0)" }
            .joined(separator: "\n")
        let comparison = inputs.stateFieldNames.isEmpty
            ? "true"
            : inputs.stateFieldNames
                .map { "probe.\($0) == snapshot_\($0)" }
                .joined(separator: "\n        && ")
        return """
        // PROTOTYPE — auto-generated ViewModel idempotence verifier.
        // Type: \(inputs.typeName)  Action: \(inputs.actionName)()
        // Property: applying \(inputs.actionName)() twice == applying it once
        // (State-level f(f(x)) == f(x) on the constructed initial state).
        import Foundation

        func runIdempotenceCheck() -> Bool {
            let probe = \(inputs.typeName)()
            probe.\(inputs.actionName)()
        \(snapshots)
            probe.\(inputs.actionName)()
            return \(comparison)
        }

        if runIdempotenceCheck() {
            print("VERIFY_DEFAULT_RESULT: PASS")
            print("VERIFY_DEFAULT_TRIALS: 1")
            print("VERIFY_EDGE_RESULT: PASS")
            print("VERIFY_EDGE_TRIALS: 0")
            print("VERIFY_EDGE_SAMPLED: 0")
            exit(0)
        } else {
            print("VERIFY_DEFAULT_RESULT: FAIL")
            print("VERIFY_DEFAULT_TRIAL: 0")
            exit(1)
        }
        """
    }
}
