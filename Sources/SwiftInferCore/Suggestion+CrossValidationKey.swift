extension Suggestion {

    /// Derives the `CrossValidationKey` for this suggestion by stripping
    /// the parameter-label suffix from each `Evidence.displayName`
    /// (e.g. `"encode(_:)"` → `"encode"`) and constructing a key with
    /// the suggestion's template name and the sorted callee-name set.
    ///
    /// The TestLifter side computes the same key from a test body via
    /// `LiftedSuggestion.crossValidationKey`; the cross-validation
    /// pass in `TemplateRegistry.applyCrossValidation` matches on key
    /// equality.
    public var crossValidationKey: CrossValidationKey {
        let names = evidence.map { Self.calleeName(from: $0.displayName) }
        return CrossValidationKey(templateName: templateName, calleeNames: names)
    }

    private static func calleeName(from displayName: String) -> String {
        guard let parenStart = displayName.firstIndex(of: "(") else {
            return displayName
        }
        return String(displayName[..<parenStart])
    }
}
