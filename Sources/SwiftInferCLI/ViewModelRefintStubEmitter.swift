import Foundation

/// PROTOTYPE — emits a verifier that checks a view-model's referential-
/// integrity invariant is *maintained* by its actions: construct the view
/// model, assert the predicate on the initial state, then drive each
/// generatable action (no-arg, or single-arg over its candidate values)
/// and re-assert the predicate after every application. A violation at any
/// step → defaultFails (an action drove the selection out of the
/// collection); holding throughout → bothPass.
///
/// **Scope (this slice):** a single deterministic pass over the
/// constructible / generatable action alphabet (the MVVM analog of the
/// reducer action-sequence verifier). Non-generatable / multi-arg actions
/// are skipped — disclosed in the header comment, the `.tca`
/// partial-exploration posture. Multi-step random sequences + shrinking
/// are a future widening (delegate to the kit's `actionSequence`).
public enum ViewModelRefintStubEmitter {

    /// One action to drive. `valuesExpression` is `nil` for a no-arg
    /// action; otherwise the `[T]` candidate expression.
    public struct Driver: Equatable, Sendable {
        public let name: String
        public let label: String?
        public let valuesExpression: String?

        public init(name: String, label: String?, valuesExpression: String?) {
            self.name = name
            self.label = label
            self.valuesExpression = valuesExpression
        }
    }

    public struct Inputs: Equatable, Sendable {
        public let typeName: String
        /// The invariant predicate over a `probe` instance
        /// (`ViewModelRefintResolver.Resolved.predicate`).
        public let predicate: String
        public let drivers: [Driver]
        /// Actions excluded from the drive (non-generatable / multi-arg) —
        /// disclosed in the emitted header for explainability.
        public let excludedActions: [String]

        public init(
            typeName: String,
            predicate: String,
            drivers: [Driver],
            excludedActions: [String] = []
        ) {
            self.typeName = typeName
            self.predicate = predicate
            self.drivers = drivers
            self.excludedActions = excludedActions
        }
    }

    public static func emit(_ inputs: Inputs) -> String {
        let excluded = inputs.excludedActions.isEmpty
            ? ""
            : "\n// Excluded (non-generatable / multi-arg): "
                + inputs.excludedActions.joined(separator: ", ")
        return """
        // PROTOTYPE — auto-generated ViewModel referential-integrity verifier.
        // Type: \(inputs.typeName)
        // Invariant (after every action): \(inputs.predicate)\(excluded)
        import Foundation

        func runRefintCheck() -> Bool {
            let probe = \(inputs.typeName)()
            if !(\(inputs.predicate)) { return false }
        \(driverBlock(inputs))
            return true
        }

        if runRefintCheck() {
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

    private static func driverBlock(_ inputs: Inputs) -> String {
        inputs.drivers.map { driver in
            let call = callExpression(driver, argument: driver.valuesExpression == nil ? nil : "arg")
            let check = "        if !(\(inputs.predicate)) { return false }"
            guard let values = driver.valuesExpression else {
                return "    \(call)\n\(check)"
            }
            return """
                for arg in \(values) {
                    \(call)
            \(check)
                }
            """
        }
        .joined(separator: "\n")
    }

    private static func callExpression(_ driver: Driver, argument: String?) -> String {
        guard let value = argument else {
            return "probe.\(driver.name)()"
        }
        if let label = driver.label {
            return "probe.\(driver.name)(\(label): \(value))"
        }
        return "probe.\(driver.name)(\(value))"
    }
}
