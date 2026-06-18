import Foundation

/// PROTOTYPE — emits a standalone verifier that checks a view-model action
/// is idempotent at the State level. Construct the view model, apply the
/// action, snapshot every State field, apply it *again with the same
/// argument*, and assert the snapshot is unchanged:
///
///   - **No-arg action**: `f(f(x)) == f(x)` on the constructed state.
///   - **Single-arg action**: x-curried `f(f(s, a), a) == f(s, a)` for
///     every candidate value `a` (the property must hold for all of them).
///
/// The corpus is co-compiled into the verifier target (direct source
/// inclusion), so the stub constructs the view model directly — no import.
///
/// **Scope (this slice):** no-arg + single-argument actions whose
/// parameter type is generatable (`ViewModelArgumentGenerator`) on a
/// zero-arg-constructible view model with `Equatable` State fields.
/// Multi-argument / non-generatable-payload actions are gated out by the
/// caller — the MVVM analog of the `.tca` constructible-action subset.
/// Emits the same `VERIFY_*` marker contract as the algebraic stubs
/// (`exit(1)` on FAIL) so `VerifyResultParser` consumes it unchanged.
public enum ViewModelIdempotenceStubEmitter {

    /// A single generated argument for a parameterized action.
    public struct Argument: Equatable, Sendable {
        /// Parameter type as written (`"Bool"`, `"UUID?"`).
        public let typeText: String
        /// External label (`nil` for an unlabelled `_ x:` param).
        public let label: String?
        /// A Swift expression of type `[typeText]` — the candidate values
        /// to apply the action with (from `ViewModelArgumentGenerator`).
        public let valuesExpression: String

        public init(typeText: String, label: String?, valuesExpression: String) {
            self.typeText = typeText
            self.label = label
            self.valuesExpression = valuesExpression
        }
    }

    public struct Inputs: Equatable, Sendable {
        public let typeName: String
        public let actionName: String
        public let stateFieldNames: [String]
        /// `nil` for a no-arg action; otherwise the generated argument.
        public let argument: Argument?
        /// Fake `struct` definitions for injected dependencies, emitted
        /// before the verifier function (`ViewModelDependencyConstructor`).
        public let preamble: String
        /// How to construct the view model — defaults to `Type()`; a
        /// dependency-injected model passes synthesized fakes.
        public let construction: String?

        public init(
            typeName: String,
            actionName: String,
            stateFieldNames: [String],
            argument: Argument? = nil,
            preamble: String = "",
            construction: String? = nil
        ) {
            self.typeName = typeName
            self.actionName = actionName
            self.stateFieldNames = stateFieldNames
            self.argument = argument
            self.preamble = preamble
            self.construction = construction
        }
    }

    public static func emit(_ inputs: Inputs) -> String {
        let preamble = inputs.preamble.isEmpty ? "" : "\n\(inputs.preamble)\n"
        return """
        // PROTOTYPE — auto-generated ViewModel idempotence verifier.
        // Type: \(inputs.typeName)  Action: \(callExpression(inputs, argument: "…"))
        import Foundation
        \(preamble)
        \(checkFunction(inputs))

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

    // MARK: - Body

    private static func checkFunction(_ inputs: Inputs) -> String {
        guard let argument = inputs.argument else {
            // No-arg: single construction, apply twice, compare.
            return """
            func runIdempotenceCheck() -> Bool {
                let probe = \(inputs.construction ?? "\(inputs.typeName)()")
                \(callExpression(inputs, argument: nil))
            \(snapshotBlock(inputs))
                \(callExpression(inputs, argument: nil))
                return \(comparison(inputs))
            }
            """
        }
        // Single-arg: x-curried — fresh state per candidate value.
        return """
        func runIdempotenceCheck() -> Bool {
            for arg in \(argument.valuesExpression) {
                let probe = \(inputs.construction ?? "\(inputs.typeName)()")
                \(callExpression(inputs, argument: "arg"))
            \(snapshotBlock(inputs))
                \(callExpression(inputs, argument: "arg"))
                if !(\(comparison(inputs))) { return false }
            }
            return true
        }
        """
    }

    /// `probe.action()` / `probe.action(arg)` / `probe.action(label: arg)`.
    private static func callExpression(_ inputs: Inputs, argument: String?) -> String {
        guard let value = argument, inputs.argument != nil else {
            return "probe.\(inputs.actionName)()"
        }
        if let label = inputs.argument?.label {
            return "probe.\(inputs.actionName)(\(label): \(value))"
        }
        return "probe.\(inputs.actionName)(\(value))"
    }

    private static func snapshotBlock(_ inputs: Inputs) -> String {
        inputs.stateFieldNames
            .map { "        let snapshot_\($0) = probe.\($0)" }
            .joined(separator: "\n")
    }

    private static func comparison(_ inputs: Inputs) -> String {
        inputs.stateFieldNames.isEmpty
            ? "true"
            : inputs.stateFieldNames
                .map { "probe.\($0) == snapshot_\($0)" }
                .joined(separator: "\n        && ")
    }
}
