// Split out of `FunctionSummary.swift` when `FunctionSummary.soleTrap` took that file past
// SwiftLint's 400-line cap. Moved unchanged.

/// One parameter of a `FunctionSummary`. Captures the label/name distinction
/// Swift parameters carry: an external label (or no-label `_`) and an
/// internal binding name.
public struct Parameter: Sendable, Equatable {

    /// External argument label as the caller writes it. `nil` when the
    /// declaration uses `_` to suppress the label.
    public let label: String?

    /// Internal binding name used inside the function body.
    public let internalName: String

    /// Trimmed source representation of the parameter's type, with any
    /// `inout` specifier stripped. `inout` is captured separately in
    /// `isInout`.
    public let typeText: String

    /// `true` when the parameter is declared `inout`.
    public let isInout: Bool

    /// `true` when the declaration supplies a default value
    /// (`func formatted(using format: BasicFormat = BasicFormat())`).
    ///
    /// The distinction this records is **operand vs configuration**. A
    /// defaulted parameter is one the caller may omit, so `x.formatted()` is a
    /// legal call and the method reads as a unary transform of `self` that
    /// happens to be configurable. A required parameter is part of the
    /// operation's arity and cannot be elided.
    ///
    /// Added for the erased-self-form arm of `IdempotenceTemplate`
    /// (`docs/measurements/parsing-catalog-gap.md` §4/§5): `SyntaxProtocol.formatted(using:)`
    /// was rejected partly because the self-form gate required
    /// `parameters.isEmpty`, which a *configuration* parameter should not
    /// trip. Defaults to `false` so every existing call site — including the
    /// hand-built `Parameter`s across the test suites — compiles unchanged.
    public let hasDefault: Bool

    public init(
        label: String?,
        internalName: String,
        typeText: String,
        isInout: Bool,
        hasDefault: Bool = false
    ) {
        self.label = label
        self.internalName = internalName
        self.typeText = typeText
        self.isInout = isInout
        self.hasDefault = hasDefault
    }
}
